import Cocoa
import SwiftUI

/// Manages the Welcome window shown on app launch.
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Inline Rewriter"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WelcomeView())

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func showWelcome() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.window?.center()
        }
    }
}
