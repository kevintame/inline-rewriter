import Cocoa

/// Pasteboard integration.
///
/// To "grab selected text", the common approach is:
/// 1) Simulate ⌘C
/// 2) Read from NSPasteboard.general
///
/// Simulating key events requires Accessibility permission.
final class PasteboardService {
    /// Backup of original pasteboard state.
    struct PasteboardBackup {
        let items: [NSPasteboardItem]
        let changeCount: Int
    }

    /// Backs up the current pasteboard contents.
    private func backupPasteboard() -> PasteboardBackup? {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems else { return nil }

        // Deep copy items to preserve their data
        let copiedItems = items.compactMap { item -> NSPasteboardItem? in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }

        return PasteboardBackup(items: copiedItems, changeCount: pb.changeCount)
    }

    /// Restores a previously backed-up pasteboard state.
    private func restorePasteboard(_ backup: PasteboardBackup) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(backup.items)
    }

    func copySelectionToPasteboard() throws -> PasteboardBackup? {
        // Backup original clipboard contents before copying
        let backup = backupPasteboard()
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

        return backup
    }

    func readStringFromPasteboard() -> String? {
        let pb = NSPasteboard.general
        return pb.string(forType: .string)
    }

    /// Replace selection by putting output on pasteboard and simulating ⌘V.
    ///
    /// In many editors, pasting will replace the existing selection.
    /// Optionally restores the original clipboard after pasting.
    func replaceSelection(with text: String, restoring backup: PasteboardBackup?) throws {
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

        // Small delay to allow paste to complete
        usleep(80_000)

        // Restore original clipboard if backup exists
        if let backup = backup {
            restorePasteboard(backup)
        }
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
