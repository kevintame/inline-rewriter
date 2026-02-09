import Cocoa
import ApplicationServices
import os.log

final class TextPositionService {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "TextPosition")

    /// Returns screen coordinates of selected text in frontmost app, or nil if unavailable
    func getSelectedTextBounds(in app: NSRunningApplication?) -> CGRect? {
        guard let app = app else {
            logger.warning("No target app provided")
            return nil
        }

        logger.debug("Querying text position for app: \(app.localizedName ?? "unknown")")

        // Create AXUIElement for the application
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let focused = focusedElement else {
            logger.debug("Could not get focused element (error: \(focusResult.rawValue))")
            return nil
        }

        // Get selected text range
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            focused as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard rangeResult == .success, let range = selectedRange else {
            logger.debug("Could not get selected text range")
            return nil
        }

        // Get bounds for the selected range
        var bounds: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            focused as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &bounds
        )

        guard boundsResult == .success,
              let boundsValue = bounds,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            logger.debug("Could not get bounds for range")
            return nil
        }

        // Extract CGRect from AXValue
        var rect = CGRect.zero
        let success = AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect)

        guard success else {
            logger.error("Failed to extract CGRect from AXValue")
            return nil
        }

        // CRITICAL: Convert from Accessibility coordinates (y=0 at top)
        // to NSWindow coordinates (y=0 at bottom)
        if let screenHeight = NSScreen.main?.frame.height {
            let convertedY = screenHeight - rect.origin.y - rect.height
            rect = CGRect(x: rect.origin.x, y: convertedY, width: rect.width, height: rect.height)
            logger.info("Converted bounds (flipped→normal): \(NSStringFromRect(rect))")
        }

        logger.info("Got text bounds: \(NSStringFromRect(rect))")
        return rect
    }
}
