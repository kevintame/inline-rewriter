import Cocoa
import SwiftUI

/// Manages the Settings window for AppKit menu bar integration.
/// Uses NSWindowController for reliable programmatic opening on macOS 12.0+.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Inline Rewriter Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 500)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Configure the window with the settings view.
    /// Must be called after AppDelegate's container is initialized.
    func configure(with settingsView: SettingsRootView) {
        let hostingController = NSHostingController(rootView: settingsView)
        window?.contentViewController = hostingController
    }

    /// Show and activate the Settings window.
    func showSettings() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
