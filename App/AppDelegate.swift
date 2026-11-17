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
        let backup: PasteboardService.PasteboardBackup?
        let targetApp: NSRunningApplication?
        /// The display that was active when the shortcut was pressed.
        let screen: NSScreen?
        let pickerViewModel: TransformationPickerViewModel

        var busyObservation: AnyCancellable?

        init(input: String,
             backup: PasteboardService.PasteboardBackup?,
             targetApp: NSRunningApplication?,
             screen: NSScreen?,
             pickerViewModel: TransformationPickerViewModel) {
            self.input = input
            self.backup = backup
            self.targetApp = targetApp
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
        container.hotkeyManager.stop()
    }

    // MARK: - Setup

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.circle.fill", accessibilityDescription: "Inline Rewriter")

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
        let targetApp = NSWorkspace.shared.frontmostApplication
        // Likewise the active display, before this app takes focus.
        let screen = NSScreen.main
        isBusy = true

        Task { @MainActor in
            defer { isBusy = false }
            do {
                let capture = try await container.pasteboardService.captureSelection()
                startSession(input: capture.text, backup: capture.backup, targetApp: targetApp, screen: screen)
            } catch {
                presentError(error, fallbackTitle: "Couldn't read selection")
            }
        }
    }

    private func startSession(input: String,
                              backup: PasteboardService.PasteboardBackup?,
                              targetApp: NSRunningApplication?,
                              screen: NSScreen?) {
        let viewModel = TransformationPickerViewModel(
            inputText: input,
            settings: container.settingsStore,
            transformer: container.textTransformer
        )
        let session = RewriteSession(
            input: input,
            backup: backup,
            targetApp: targetApp,
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
        present(TransformationPickerView(viewModel: session.pickerViewModel), for: session)
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
        viewModel.onReplace = { [weak self, weak session] text in
            guard let self, let session, self.session === session else { return }
            self.replace(output: text, session: session)
        }
        viewModel.onCopy = { [weak self, weak session] text in
            guard let self, let session, self.session === session else { return }
            // The result becomes the clipboard, so the backup is deliberately not restored.
            self.endSession(restoreClipboard: false)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        present(PreviewView(viewModel: viewModel), for: session)
    }

    private func replace(output: String, session: RewriteSession) {
        // The session is over from the flow's point of view; clearing it first means
        // closing the panel does not restore the clipboard under us.
        self.session = nil
        requestInFlight = false
        isBusy = true
        panelController.close()

        Task { @MainActor in
            defer { isBusy = false }
            // Give macOS a moment to finish dismissing the panel and hand focus back.
            try? await Task.sleep(nanoseconds: 200_000_000)
            do {
                try await container.pasteboardService.replaceSelection(
                    with: output,
                    restoring: session.backup,
                    targetApp: session.targetApp
                )
            } catch {
                presentError(error, fallbackTitle: "Replace failed")
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
            container.pasteboardService.restore(session.backup)
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
    private func present<Content: View>(_ content: Content, for session: RewriteSession) {
        guard panelController.show(content, on: session.screen) else {
            logger.error("Could not show the rewriter panel")
            endSession(restoreClipboard: true)
            return
        }
    }
}
