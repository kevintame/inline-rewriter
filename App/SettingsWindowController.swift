import Cocoa
import SwiftUI

/// Manages the Settings window for AppKit menu bar integration.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        // Content is a fixed 700x500 SwiftUI view, so the window is not resizable.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Inline Rewriter Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Configure the window with the settings view.
    /// Must be called after AppDelegate's container is initialized.
    func configure(with settingsView: SettingsRootView) {
        window?.contentViewController = NSHostingController(rootView: settingsView)
    }

    /// Show and activate the Settings window.
    func showSettings() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
