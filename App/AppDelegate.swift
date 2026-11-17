import Cocoa
import Combine
import SwiftUI
import os.log

/// Creates the menubar status item and drives the rewrite flow:
/// hotkey → capture selection → pick transformation → preview → replace.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: AppContainer

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "App")

    private var statusItem: NSStatusItem!

    /// The one window the picker and the preview are shown in.
    private let panelController = RewritePanelController()

    /// One rewrite, from hotkey press to replace or cancel.
    private final class RewriteSession {
        let input: String
        let target: PasteboardService.Target?
        /// The display that was active when the shortcut was pressed.
        let screen: NSScreen?
        let pickerViewModel: TransformationPickerViewModel

        var busyObservation: AnyCancellable?

        init(input: String,
             target: PasteboardService.Target?,
             screen: NSScreen?,
             pickerViewModel: TransformationPickerViewModel) {
            self.input = input
            self.target = target
            self.screen = screen
            self.pickerViewModel = pickerViewModel
        }
    }

    private var session: RewriteSession?
    /// True while capturing the selection or pasting the result, when the panel is not up
    /// but a second hotkey press must still be ignored.
    private var isBusy = false {
        didSet { refreshStatusItemBusy() }
    }
    /// Mirrors the picker's in-flight request so the menu bar icon can show progress.
    private var requestInFlight = false {
        didSet { refreshStatusItemBusy() }
    }

    override init() {
        container = AppContainer()
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()

        setUpStatusItem()
        // Losing focus (click elsewhere, app switch) dismisses the panel like a popover.
        panelController.onDismiss = { [weak self] in
            self?.endSession(restoreClipboard: true)
        }
        configureWindows()

        container.hotkeyManager.onHotkey = { [weak self] in
            self?.handleHotkey()
        }
        startHotkey()

        showWelcomeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting mid-rewrite must not leave the captured selection on the clipboard.
        // The service call also covers a capture or paste that is still in flight.
        endSession(restoreClipboard: true)
        container.pasteboardService.restoreClipboard()
        container.hotkeyManager.stop()
    }

    // MARK: - Setup

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusImage = NSImage(named: "StatusIcon")
            ?? NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Inline Rewriter")
        statusImage?.size = NSSize(width: 18, height: 18)
        statusImage?.isTemplate = true
        statusItem.button?.image = statusImage
        statusItem.button?.setAccessibilityLabel("Inline Rewriter")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Welcome & Permissions…", action: #selector(openWelcome), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Inline Rewriter", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func configureWindows() {
        let settingsView = SettingsRootView(
            settings: container.settingsStore,
            keychain: container.keychain,
            hotkeyManager: container.hotkeyManager,
            launchAtLogin: container.launchAtLogin,
            permission: container.accessibilityPermission,
            testConnection: container.openAIClient.testConnection
        )
        SettingsWindowController.shared.configure(with: settingsView)

        let welcomeView = WelcomeView(
            permission: container.accessibilityPermission,
            settings: container.settingsStore,
            keychain: container.keychain,
            onOpenSettings: { [weak self] in
                WelcomeWindowController.shared.close()
                self?.openSettings()
            },
            onFinish: {
                WelcomeWindowController.shared.close()
            }
        )
        WelcomeWindowController.shared.configure(with: welcomeView) { [weak self] in
            self?.container.settingsStore.hasCompletedOnboarding = true
        }
    }

    private func startHotkey() {
        do {
            try container.hotkeyManager.start()
        } catch {
            container.alertPresenter.showError(title: "Shortcut unavailable", message: error.localizedDescription)
        }
    }

    private func showWelcomeIfNeeded() {
        let settings = container.settingsStore
        if !settings.hasCompletedOnboarding || !container.accessibilityPermission.isTrusted {
            WelcomeWindowController.shared.showWelcome()
        }
    }

    // MARK: - Menu actions

    @objc func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func openWelcome() {
        WelcomeWindowController.shared.showWelcome()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Flow

    private func handleHotkey() {
        guard !isBusy else { return }

        // Pressing the shortcut while the panel is up dismisses it.
        if session != nil {
            endSession(restoreClipboard: true)
            return
        }

        // Capture the frontmost app before anything else so our own activation later
        // does not change the paste target.
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let target = frontmostApp.map(PasteboardService.Target.init)
        // Likewise the display the user is working on, before this app takes focus.
        let screen = RewritePanelController.activeScreen(forProcess: frontmostApp?.processIdentifier)
        isBusy = true

        Task { @MainActor in
            defer { isBusy = false }
            do {
                let input = try await container.pasteboardService.captureSelection(from: target)
                startSession(input: input, target: target, screen: screen)
            } catch {
                presentError(error, fallbackTitle: "Couldn't read selection")
            }
        }
    }

    private func startSession(input: String,
                              target: PasteboardService.Target?,
                              screen: NSScreen?) {
        let viewModel = TransformationPickerViewModel(
            inputText: input,
            settings: container.settingsStore,
            transformer: container.textTransformer
        )
        let session = RewriteSession(
            input: input,
            target: target,
            screen: screen,
            pickerViewModel: viewModel
        )
        self.session = session

        viewModel.onCancel = { [weak self] in
            self?.endSession(restoreClipboard: true)
        }
        viewModel.onOpenSettings = { [weak self] in
            self?.endSession(restoreClipboard: true)
            self?.openSettings()
        }
        viewModel.onDidTransform = { [weak self, weak session] output, transformation in
            guard let self, let session, self.session === session else { return }
            self.showPreview(output: output, transformation: transformation, session: session)
        }
        session.busyObservation = viewModel.$isBusy.sink { [weak self] busy in
            self?.requestInFlight = busy
        }

        showPicker(for: session)
    }

    private func showPicker(for session: RewriteSession) {
        let viewModel = session.pickerViewModel
        present(TransformationPickerView(viewModel: viewModel), for: session) { [weak viewModel] event in
            viewModel?.handleKeyDown(event) ?? false
        }
    }

    private func showPreview(output: String, transformation: TextTransformation, session: RewriteSession) {
        let viewModel = PreviewViewModel(
            inputText: session.input,
            outputText: output,
            transformationName: transformation.name
        )

        viewModel.onCancel = { [weak self] in
            self?.endSession(restoreClipboard: true)
        }
        viewModel.onRetry = { [weak self, weak session] in
            guard let self, let session, self.session === session else { return }
            // Bring the picker back so the spinner and any error are visible, then re-run.
            self.showPicker(for: session)
            session.pickerViewModel.run(transformation)
        }
        viewModel.onReplace = { [weak self, weak session, weak viewModel] text in
            guard let self, let session, let viewModel, self.session === session else { return }
            self.replace(output: text, session: session, preview: viewModel)
        }
        viewModel.onCopy = { [weak self, weak session] text in
            guard let self, let session, self.session === session else { return }
            // The result becomes the clipboard, so the backup is deliberately not restored.
            self.endSession(restoreClipboard: false)
            self.container.pasteboardService.keepOnClipboard(text)
        }

        showPreview(viewModel, for: session)
    }

    private func showPreview(_ viewModel: PreviewViewModel, for session: RewriteSession) {
        present(PreviewView(viewModel: viewModel), for: session) { [weak viewModel] event in
            viewModel?.handleKeyDown(event) ?? false
        }
    }

    private func replace(output: String, session: RewriteSession, preview: PreviewViewModel) {
        // The panel has to go so the target app can take focus. The session stays, so a
        // failed paste can bring the preview back with the result still in it; `isBusy`
        // keeps the shortcut from starting anything in the meantime.
        requestInFlight = false
        isBusy = true
        panelController.close()

        Task { @MainActor in
            defer { isBusy = false }
            // Give macOS a moment to finish dismissing the panel and hand focus back.
            try? await Task.sleep(nanoseconds: 200_000_000)
            do {
                // Hands the clipboard back itself once the paste is posted.
                try await container.pasteboardService.replaceSelection(with: output, in: session.target)
                if self.session === session {
                    endSession(restoreClipboard: false)
                }
            } catch {
                // The session is gone if the app is quitting; nothing to show then.
                guard self.session === session else { return }
                logger.error("Replace failed: \(error.localizedDescription)")
                // The service left the result on the clipboard instead of restoring the
                // old contents. Reopen the preview with the text as the user left it.
                preview.errorMessage = PasteboardService.replaceFailureMessage(for: error)
                showPreview(preview, for: session)
            }
        }
    }

    private func endSession(restoreClipboard: Bool) {
        guard let session else { return }
        self.session = nil
        requestInFlight = false

        session.pickerViewModel.cancelInFlight()
        panelController.close()

        if restoreClipboard {
            container.pasteboardService.restoreClipboard()
        }
    }

    private func presentError(_ error: Error, fallbackTitle: String) {
        if case PasteboardService.PasteboardError.accessibilityPermissionRequired = error {
            // The Welcome window has the grant button and live status; more useful than an alert.
            WelcomeWindowController.shared.showWelcome()
            return
        }
        logger.error("\(fallbackTitle): \(error.localizedDescription)")
        container.alertPresenter.showError(title: fallbackTitle, message: error.localizedDescription)
    }

    /// Dims the menu bar icon while the app is reading, waiting on the model, or pasting.
    private func refreshStatusItemBusy() {
        statusItem?.button?.appearsDisabled = isBusy || requestInFlight
    }

    // MARK: - Presentation

    /// Shows `content` in the panel on the session's display. A panel that cannot be shown
    /// must not leave a session behind: the shortcut would only cancel it on the next press.
    private func present<Content: View>(_ content: Content,
                                        for session: RewriteSession,
                                        onKeyDown: @escaping (NSEvent) -> Bool) {
        guard panelController.show(content, on: session.screen, onKeyDown: onKeyDown) else {
            logger.error("Could not show the rewriter panel")
            endSession(restoreClipboard: true)
            return
        }
    }
}
