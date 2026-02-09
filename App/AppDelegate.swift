import Cocoa
import SwiftUI

/// Creates the menubar status item and coordinates popovers.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer()

    private var statusItem: NSStatusItem!

    private let transformationPopover = NSPopover()
    private let previewPopover = NSPopover()

    private let textPositionService = TextPositionService()
    private var anchorWindow: PopoverAnchorWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPopovers()

        // Configure settings window
        let settingsView = SettingsRootView(
            settings: container.settingsStore,
            keychain: container.keychain,
            hotkeyManager: container.hotkeyManager,
            alertPresenter: container.alertPresenter
        )
        SettingsWindowController.shared.configure(with: settingsView)

        // Start listening for the global hotkey.
        container.hotkeyManager.onHotkey = { [weak self] in
            self?.handleHotkey()
        }
        if !container.hotkeyManager.start() {
            container.alertPresenter.showError(
                title: "Hotkey unavailable",
                message: "Unable to register the global hotkey.\n\nRequired permissions:\n• Accessibility (for text selection)\n• Input Monitoring (for hotkey detection)\n\nEnable both in System Settings → Privacy & Security."
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.hotkeyManager.stop()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Inline Rewriter")
            button.action = #selector(didClickStatusItem)
            button.target = self
        }

        // Optional right-click menu.
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Inline Rewriter Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // If you want left-click to open popover rather than menu, you’d remove `statusItem.menu`
        // and handle clicks manually. Keeping this minimal for review.
    }

    private func setUpPopovers() {
        transformationPopover.behavior = .transient
        previewPopover.behavior = .transient
    }

    @objc private func didClickStatusItem() {
        // If using menu, this may not fire. Kept for future UX tweaks.
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func handleHotkey() {
        Task { @MainActor in
            // Capture the frontmost app BEFORE showing popover
            let targetApp = NSWorkspace.shared.frontmostApplication

            do {
                // 1) Try to copy selection (simulates ⌘C) and backup original clipboard
                let backup = try container.pasteboardService.copySelectionToPasteboard()

                // 2) Read plain text from pasteboard
                guard let input = container.pasteboardService.readStringFromPasteboard(), !input.isEmpty else {
                    container.alertPresenter.showError(title: "No text", message: "Could not read selected text from the clipboard.")
                    return
                }

                showTransformationPicker(for: input, backup: backup, targetApp: targetApp)
            } catch {
                container.alertPresenter.showError(title: "Permission required", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func showTransformationPicker(for input: String, backup: PasteboardService.PasteboardBackup?, targetApp: NSRunningApplication?) {
        let viewModel = TransformationPickerViewModel(
            inputText: input,
            settings: container.settingsStore,
            transformer: container.textTransformer,
            pasteboardBackup: backup
        )

        viewModel.onCancel = { [weak self] in
            self?.transformationPopover.performClose(nil)
        }

        viewModel.onDidTransform = { [weak self] result, retry in
            self?.transformationPopover.performClose(nil)
            self?.showPreview(input: input, output: result, backup: viewModel.pasteboardBackup, retry: retry, targetApp: targetApp)
        }

        transformationPopover.contentViewController = NSHostingController(
            rootView: TransformationPickerView(viewModel: viewModel)
        )

        present(popover: transformationPopover, targetApp: targetApp)
    }

    @MainActor
    private func showPreview(input: String, output: String, backup: PasteboardService.PasteboardBackup?, retry: @escaping () -> Void, targetApp: NSRunningApplication?) {
        let viewModel = PreviewViewModel(
            inputText: input,
            outputText: output,
            pasteboardService: container.pasteboardService,
            alertPresenter: container.alertPresenter,
            pasteboardBackup: backup,
            targetApp: targetApp
        )

        viewModel.onCancel = { [weak self] in
            self?.previewPopover.performClose(nil)
        }

        viewModel.onRetry = { [weak self] in
            self?.previewPopover.performClose(nil)
            retry()
        }

        previewPopover.contentViewController = NSHostingController(
            rootView: PreviewView(viewModel: viewModel)
        )

        present(popover: previewPopover, targetApp: targetApp)
    }

    @MainActor
    private func present(popover: NSPopover, targetApp: NSRunningApplication?) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // Try to get selected text position
        if let bounds = textPositionService.getSelectedTextBounds(in: targetApp) {
            presentAtTextLocation(popover: popover, bounds: bounds)
        } else {
            // Fallback to menu bar positioning
            presentAtMenuBar(popover: popover)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentAtTextLocation(popover: NSPopover, bounds: CGRect) {
        NSLog("📍 presentAtTextLocation - bounds: \(bounds)")

        // Create or reuse anchor window
        if anchorWindow == nil {
            anchorWindow = PopoverAnchorWindow()
        }

        guard let anchor = anchorWindow else { return }

        // Determine which screen contains the selected text
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(bounds.origin) })
              ?? NSScreen.main else { return }

        // Calculate vertical position relative to screen (0.0 = bottom, 1.0 = top)
        let screenFrame = screen.frame
        let textCenterY = bounds.midY
        let relativeY = (textCenterY - screenFrame.minY) / screenFrame.height

        // Text in upper half → show popup BELOW; text in lower half → show popup ABOVE
        let showBelow = relativeY > 0.5

        NSLog("📍 Text position - relativeY: \(relativeY), showBelow: \(showBelow)")

        // Position anchor at the appropriate edge of text selection
        let anchorSize = CGSize(width: 20, height: 20)
        let anchorPoint: CGPoint

        if showBelow {
            // Anchor at bottom edge of text, centered horizontally
            anchorPoint = CGPoint(
                x: bounds.midX - anchorSize.width / 2,
                y: bounds.minY - anchorSize.height / 2
            )
        } else {
            // Anchor at top edge of text, centered horizontally
            anchorPoint = CGPoint(
                x: bounds.midX - anchorSize.width / 2,
                y: bounds.maxY - anchorSize.height / 2
            )
        }

        NSLog("📍 Anchor positioned at: \(anchorPoint)")
        anchor.positionAt(anchorPoint, size: anchorSize)
        anchor.orderFront(nil)

        // Show popover anchored to center of anchor window
        if let contentView = anchor.contentView {
            let anchorRect = CGRect(
                x: anchorSize.width / 2,
                y: anchorSize.height / 2,
                width: 1,
                height: 1
            )
            let edge: NSRectEdge = showBelow ? .minY : .maxY
            popover.show(relativeTo: anchorRect, of: contentView, preferredEdge: edge)
        }
    }

    private func presentAtMenuBar(popover: NSPopover) {
        // Original behavior - show at menu bar button
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
