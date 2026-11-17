import CoreGraphics

/// Where the rewriter panel goes on screen.
///
/// The panel is pinned to the upper-right corner of the active display rather than anchored
/// to the selection: selection bounds from other apps are unreliable, and an anchored
/// popover could end up partly off-screen.
enum PanelPlacement {
    /// Gap between the panel and the edges of the usable screen area.
    static let defaultInset: CGFloat = 12

    /// Converts a rectangle from Quartz global coordinates (origin at the top-left of the
    /// primary display, y down) to AppKit screen coordinates (origin at its bottom-left,
    /// y up).
    static func appKitRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the screen frame that holds the largest part of `rect`, or `nil` if it
    /// touches none of them.
    static func indexOfScreen(containingMostOf rect: CGRect, screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in screenFrames.enumerated() {
            let overlap = frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }

    /// Frame for a panel of `contentSize` pinned to the upper-right corner of `visibleFrame`
    /// (the screen area below the menu bar and clear of the Dock, in AppKit's bottom-left
    /// coordinates).
    ///
    /// The result never extends past any edge of `visibleFrame`: content larger than the
    /// available area is shrunk to fit, so the caller's content must cope with being smaller
    /// than it asked for.
    static func upperRightFrame(contentSize: CGSize,
                                visibleFrame: CGRect,
                                inset: CGFloat = defaultInset) -> CGRect {
        // A degenerate screen area cannot afford the inset; use the whole of it.
        let inset = (visibleFrame.width > 2 * inset && visibleFrame.height > 2 * inset) ? max(inset, 0) : 0
        let available = visibleFrame.insetBy(dx: inset, dy: inset)

        let width = min(max(contentSize.width, 0), available.width)
        let height = min(max(contentSize.height, 0), available.height)

        return CGRect(
            x: available.maxX - width,
            y: available.maxY - height,
            width: width,
            height: height
        )
    }
}
