import Cocoa
import SwiftUI

/// Borderless panels refuse key status by default, which would leave the picker and the
/// editable preview without keyboard input.
private final class RewritePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Rounded window background for the borderless panel.
private struct RewritePanelChrome<Content: View>: View {
    let content: Content

    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        // Normally the content is shown at its natural size. On a display too short for
        // it, it scrolls inside the clamped panel instead of being cut off.
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical) { content }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(Color.primary.opacity(0.15)))
    }
}

/// Shows the picker and the preview in one floating panel pinned to the upper-right corner
/// of a display, sized to its content and kept fully on screen as the content changes.
///
/// The panel behaves like a transient popover: when it loses key status while visible (a
/// click elsewhere, an app switch) it reports `onDismiss` so the owner can end the
/// `RewriteSession`.
@MainActor
final class RewritePanelController: NSObject, NSWindowDelegate {
    /// The user dismissed the panel by moving focus away from it.
    var onDismiss: (() -> Void)?

    private typealias HostingController = NSHostingController<AnyView>

    private let panel: RewritePanel
    private var screen: NSScreen?
    private var sizeObservation: NSKeyValueObservation?
    /// Set while this controller hides the panel itself, so that is not reported as a
    /// dismissal by the user.
    private var isClosing = false

    override init() {
        panel = RewritePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // Follow the user to whichever Space they are in, including over a full-screen app.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    /// The panel's window, so key handling can be limited to events meant for it.
    var window: NSWindow { panel }

    /// Shows `content`, replacing whatever the panel showed before. Pass the display to use
    /// when starting a flow; pass `nil` to stay on the display already in use.
    ///
    /// Returns false if the panel could not be put on screen.
    @discardableResult
    func show<Content: View>(_ content: Content, on screen: NSScreen? = nil) -> Bool {
        if let screen {
            self.screen = screen
        }

        let hosting = HostingController(rootView: AnyView(RewritePanelChrome(content: content)))
        // Publish the SwiftUI content's size so the panel can follow it as it changes
        // (error text appearing, the Original disclosure opening).
        hosting.sizingOptions = [.preferredContentSize]

        sizeObservation = nil
        panel.contentViewController = hosting
        sizeObservation = hosting.observe(\.preferredContentSize) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.pinToCorner()
            }
        }

        hosting.view.layoutSubtreeIfNeeded()
        guard pinToCorner() else {
            close()
            return false
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return panel.isVisible
    }

    /// Hides the panel and tears down its content without reporting a dismissal.
    func close() {
        isClosing = true
        defer { isClosing = false }
        sizeObservation = nil
        panel.orderOut(nil)
        panel.contentViewController = nil
    }

    /// Sizes the panel to its content and pins it to the upper-right corner of the display.
    /// Returns false when there is no content or no display to place it on.
    @discardableResult
    private func pinToCorner() -> Bool {
        guard let hosting = panel.contentViewController as? HostingController else { return false }

        // The display can go away mid-session (unplugged, lid closed).
        if let current = screen, !NSScreen.screens.contains(current) {
            screen = nil
        }
        guard let target = screen ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        screen = target

        // Ask the content how big it wants to be within the space this display can offer.
        let visibleFrame = target.visibleFrame
        let available = PanelPlacement.upperRightFrame(
            contentSize: visibleFrame.size,
            visibleFrame: visibleFrame
        ).size
        let frame = PanelPlacement.upperRightFrame(
            contentSize: hosting.sizeThatFits(in: available),
            visibleFrame: visibleFrame
        )
        guard frame.width > 0, frame.height > 0 else { return false }

        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        // AppKit resizes the window around its own idea of the origin when the content
        // changes size; put it back in the corner.
        pinToCorner()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing, panel.isVisible else { return }
        onDismiss?()
    }
}
