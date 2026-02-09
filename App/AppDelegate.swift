import Cocoa
import SwiftUI

/// Creates the menubar status item and coordinates popovers.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = AppContainer()

    private var statusItem: NSStatusItem!

    private let transformationPopover = NSPopover()
    private let previewPopover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPopovers()

        // Start listening for the global hotkey.
        container.hotkeyManager.onHotkey = { [weak self] in
            self?.handleHotkey()
        }
        if !container.hotkeyManager.start() {
            container.alertPresenter.showError(
                title: "Hotkey unavailable",
                message: "Unable to register the global hotkey. Enable Input Monitoring or Accessibility permissions in System Settings."
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func handleHotkey() {
        Task { @MainActor in
            do {
                // 1) Try to copy selection (simulates ⌘C) and backup original clipboard
                let backup = try container.pasteboardService.copySelectionToPasteboard()

                // 2) Read plain text from pasteboard
                guard let input = container.pasteboardService.readStringFromPasteboard(), !input.isEmpty else {
                    container.alertPresenter.showError(title: "No text", message: "Could not read selected text from the clipboard.")
                    return
                }

                showTransformationPicker(for: input, backup: backup)
            } catch {
                container.alertPresenter.showError(title: "Permission required", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func showTransformationPicker(for input: String, backup: PasteboardService.PasteboardBackup?) {
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
            self?.showPreview(input: input, output: result, backup: viewModel.pasteboardBackup, retry: retry)
        }

        transformationPopover.contentViewController = NSHostingController(
            rootView: TransformationPickerView(viewModel: viewModel)
        )

        present(popover: transformationPopover)
    }

    @MainActor
    private func showPreview(input: String, output: String, backup: PasteboardService.PasteboardBackup?, retry: @escaping () -> Void) {
        let viewModel = PreviewViewModel(
            inputText: input,
            outputText: output,
            pasteboardService: container.pasteboardService,
            alertPresenter: container.alertPresenter,
            pasteboardBackup: backup
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

        present(popover: previewPopover)
    }

    @MainActor
    private func present(popover: NSPopover) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
