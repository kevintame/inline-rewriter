import Cocoa
import SwiftUI
import os.log

/// Creates the menubar status item and drives the rewrite flow:
/// hotkey → capture selection → pick transformation → preview → replace.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let container: AppContainer

    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "App")

    private var statusItem: NSStatusItem!

    private let transformationPopover = NSPopover()
    private let previewPopover = NSPopover()

    private let textPositionService = TextPositionService()
    private var anchorWindow: PopoverAnchorWindow?

    /// One rewrite, from hotkey press to replace or cancel.
    private final class RewriteSession {
        let input: String
        let backup: PasteboardService.PasteboardBackup?
        let targetApp: NSRunningApplication?
        let textBounds: CGRect?
        let pickerViewModel: TransformationPickerViewModel

        /// The popover this session expects to be on screen. When a popover closes and is
        /// still the active one, the user dismissed it (click outside, app switch) rather
        /// than the app moving to the next step.
        weak var activePopover: NSPopover?

        init(input: String,
             backup: PasteboardService.PasteboardBackup?,
             targetApp: NSRunningApplication?,
             textBounds: CGRect?,
             pickerViewModel: TransformationPickerViewModel) {
            self.input = input
            self.backup = backup
            self.targetApp = targetApp
            self.textBounds = textBounds
            self.pickerViewModel = pickerViewModel
        }
    }

    private var session: RewriteSession?
    /// True while capturing the selection or pasting the result, when no popover is up
    /// but a second hotkey press must still be ignored.
    private var isBusy = false

    override init() {
        container = AppContainer()
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()

        setUpStatusItem()
        setUpPopovers()
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

    private func setUpPopovers() {
        for popover in [transformationPopover, previewPopover] {
            popover.behavior = .transient
            popover.delegate = self
        }
    }

    private func configureWindows() {
        let settingsView = SettingsRootView(
            settings: container.settingsStore,
            keychain: container.keychain,
            hotkeyManager: container.hotkeyManager,
            launchAtLogin: container.launchAtLogin,
            permission: container.accessibilityPermission
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

        // Pressing the shortcut while a popover is up dismisses it.
        if session != nil {
            endSession(restoreClipboard: true)
            return
        }

        // Capture the frontmost app before anything else so our own activation later
        // does not change the paste target.
        let targetApp = NSWorkspace.shared.frontmostApplication
        isBusy = true

        Task { @MainActor in
            defer { isBusy = false }
            do {
                let capture = try await container.pasteboardService.captureSelection()
                let bounds = textPositionService.getSelectedTextBounds(in: targetApp)
                startSession(input: capture.text, backup: capture.backup, targetApp: targetApp, textBounds: bounds)
            } catch {
                presentError(error, fallbackTitle: "Couldn't read selection")
            }
        }
    }

    private func startSession(input: String,
                              backup: PasteboardService.PasteboardBackup?,
                              targetApp: NSRunningApplication?,
                              textBounds: CGRect?) {
        let viewModel = TransformationPickerViewModel(
            inputText: input,
            settings: container.settingsStore,
            transformer: container.textTransformer
        )
        let session = RewriteSession(
            input: input,
            backup: backup,
            targetApp: targetApp,
            textBounds: textBounds,
            pickerViewModel: viewModel
        )
        self.session = session

        viewModel.onCancel = { [weak self] in
            self?.endSession(restoreClipboard: true)
        }
        viewModel.onDidTransform = { [weak self, weak session] output, transformation in
            guard let self, let session, self.session === session else { return }
            self.showPreview(output: output, transformation: transformation, session: session)
        }

        showPicker(for: session)
    }

    private func showPicker(for session: RewriteSession) {
        transformationPopover.contentViewController = NSHostingController(
            rootView: TransformationPickerView(viewModel: session.pickerViewModel)
        )
        session.activePopover = transformationPopover
        present(transformationPopover, for: session)
    }

    private func showPreview(output: String, transformation: TextTransformation, session: RewriteSession) {
        let viewModel = PreviewViewModel(outputText: output)

        viewModel.onCancel = { [weak self] in
            self?.endSession(restoreClipboard: true)
        }
        viewModel.onRetry = { [weak self, weak session] in
            guard let self, let session, self.session === session else { return }
            // Bring the picker back so the spinner and any error are visible, then re-run.
            session.activePopover = self.transformationPopover
            self.previewPopover.performClose(nil)
            self.showPicker(for: session)
            session.pickerViewModel.run(transformation)
        }
        viewModel.onReplace = { [weak self, weak session] in
            guard let self, let session, self.session === session else { return }
            self.replace(output: output, session: session)
        }

        previewPopover.contentViewController = NSHostingController(rootView: PreviewView(viewModel: viewModel))

        // Mark the preview active before closing the picker so the picker's close is
        // treated as a step, not a cancel.
        session.activePopover = previewPopover
        transformationPopover.performClose(nil)
        present(previewPopover, for: session)
    }

    private func replace(output: String, session: RewriteSession) {
        // The session is over from the flow's point of view; clearing it first means the
        // preview's close callback does not restore the clipboard under us.
        self.session = nil
        isBusy = true
        previewPopover.performClose(nil)
        anchorWindow?.orderOut(nil)

        Task { @MainActor in
            defer { isBusy = false }
            // Give macOS a moment to finish dismissing the popover and hand focus back.
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

        session.pickerViewModel.cancelInFlight()
        transformationPopover.performClose(nil)
        previewPopover.performClose(nil)
        anchorWindow?.orderOut(nil)

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

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        popover.contentViewController = nil

        if let session, session.activePopover === popover {
            // Closed by the user rather than by the flow moving on.
            endSession(restoreClipboard: true)
        }
    }

    // MARK: - Presentation

    private func present(_ popover: NSPopover, for session: RewriteSession) {
        if let bounds = session.textBounds {
            presentAtTextLocation(popover, bounds: bounds)
        } else {
            presentAtMenuBar(popover)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentAtTextLocation(_ popover: NSPopover, bounds: CGRect) {
        if anchorWindow == nil {
            anchorWindow = PopoverAnchorWindow()
        }
        guard let anchor = anchorWindow else { return }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(bounds.origin) }) ?? NSScreen.main else {
            presentAtMenuBar(popover)
            return
        }

        // Text in the upper half of the screen gets the popover below it, and vice versa.
        let relativeY = (bounds.midY - screen.frame.minY) / screen.frame.height
        let showBelow = relativeY > 0.5

        let anchorSize = CGSize(width: 20, height: 20)
        let anchorPoint = CGPoint(
            x: bounds.midX - anchorSize.width / 2,
            y: (showBelow ? bounds.minY : bounds.maxY) - anchorSize.height / 2
        )

        anchor.positionAt(anchorPoint, size: anchorSize)
        anchor.orderFront(nil)

        guard let contentView = anchor.contentView else { return }
        let anchorRect = CGRect(x: anchorSize.width / 2, y: anchorSize.height / 2, width: 1, height: 1)
        popover.show(relativeTo: anchorRect, of: contentView, preferredEdge: showBelow ? .minY : .maxY)
    }

    private func presentAtMenuBar(_ popover: NSPopover) {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
