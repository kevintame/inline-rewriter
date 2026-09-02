import Cocoa
import SwiftUI

/// Manages the Welcome window: first-run onboarding and the Accessibility permission flow.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private var onClose: (() -> Void)?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Inline Rewriter"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    /// Installs the content view. `onClose` runs whenever the window closes, however it
    /// was closed, so onboarding can be marked complete.
    func configure(with welcomeView: WelcomeView, onClose: @escaping () -> Void) {
        window?.contentViewController = NSHostingController(rootView: welcomeView)
        self.onClose = onClose
    }

    func showWelcome() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
