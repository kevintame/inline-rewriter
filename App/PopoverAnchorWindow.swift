import Cocoa

/// Invisible window used as an anchor point for popover positioning
final class PopoverAnchorWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    func positionAt(_ point: CGPoint, size: CGSize = CGSize(width: 1, height: 1)) {
        self.setFrame(NSRect(origin: point, size: size), display: false)
    }
}
