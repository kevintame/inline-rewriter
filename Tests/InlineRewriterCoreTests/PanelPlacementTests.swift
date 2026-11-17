import CoreGraphics
import Testing
@testable import InlineRewriterCore

struct PanelPlacementTests {
    /// A 1440x900 display with a 25 pt menu bar and a 70 pt Dock.
    private let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)

    @Test func pinsToUpperRightCornerWithInset() {
        let frame = PanelPlacement.upperRightFrame(contentSize: CGSize(width: 448, height: 200), visibleFrame: visible, inset: 12)
        #expect(frame == CGRect(x: 1440 - 12 - 448, y: 875 - 12 - 200, width: 448, height: 200))
    }

    @Test func topRightCornerStaysPutWhenContentGrows() {
        let small = PanelPlacement.upperRightFrame(contentSize: CGSize(width: 448, height: 120), visibleFrame: visible)
        let large = PanelPlacement.upperRightFrame(contentSize: CGSize(width: 548, height: 420), visibleFrame: visible)
        #expect(small.maxX == large.maxX)
        #expect(small.maxY == large.maxY)
    }

    @Test func usesTheOriginOfASecondaryDisplay() {
        // A display arranged to the left of and below the primary one.
        let secondary = CGRect(x: -1920, y: -300, width: 1920, height: 1055)
        let frame = PanelPlacement.upperRightFrame(contentSize: CGSize(width: 548, height: 400), visibleFrame: secondary, inset: 12)
        #expect(abs(frame.maxX - (-12)) < 0.001)
        #expect(abs(frame.maxY - 743) < 0.001)
        #expect(secondary.contains(frame))
    }

    @Test func oversizedContentIsClampedInsideTheVisibleFrame() {
        let frame = PanelPlacement.upperRightFrame(contentSize: CGSize(width: 5000, height: 5000), visibleFrame: visible, inset: 12)
        #expect(frame == visible.insetBy(dx: 12, dy: 12))
    }

    @Test(arguments: [
        CGSize(width: 1, height: 1),
        CGSize(width: 448, height: 300),
        CGSize(width: 548, height: 2000),
        CGSize(width: 3000, height: 100),
    ])
    func neverLeavesTheVisibleFrame(size: CGSize) {
        let frame = PanelPlacement.upperRightFrame(contentSize: size, visibleFrame: visible)
        #expect(visible.contains(frame))
    }

    @Test func degenerateInputsDoNotProduceNegativeSizes() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        let frame = PanelPlacement.upperRightFrame(contentSize: CGSize(width: -5, height: 40), visibleFrame: tiny, inset: 12)
        #expect(frame.width == 0)
        #expect(frame.height == 10)
        #expect(tiny.contains(frame) || frame.width == 0)
    }
}
