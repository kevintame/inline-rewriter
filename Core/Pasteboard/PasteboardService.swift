import Cocoa

/// Pasteboard integration.
///
/// To “grab selected text”, the common approach is:
/// 1) Simulate ⌘C
/// 2) Read from NSPasteboard.general
///
/// Simulating key events requires Accessibility permission.
final class PasteboardService {
    func copySelectionToPasteboard() throws {
        // Simulate ⌘C.
        // If Accessibility permission is not granted, CGEvent posting may fail.
        guard AXIsProcessTrusted() else {
            throw PasteboardError.accessibilityPermissionRequired
        }

        let keyC: CGKeyCode = 8 // US layout: 'c'
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Small delay to allow pasteboard to update.
        usleep(80_000)
    }

    func readStringFromPasteboard() -> String? {
        let pb = NSPasteboard.general
        return pb.string(forType: .string)
    }

    /// Replace selection by putting output on pasteboard and simulating ⌘V.
    ///
    /// In many editors, pasting will replace the existing selection.
    func replaceSelection(with text: String) throws {
        guard AXIsProcessTrusted() else {
            throw PasteboardError.accessibilityPermissionRequired
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        let keyV: CGKeyCode = 9 // US layout: 'v'
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    enum PasteboardError: LocalizedError {
        case accessibilityPermissionRequired

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Accessibility permission is required to copy/paste the current selection. Enable it in System Settings → Privacy & Security → Accessibility."
            }
        }
    }
}
