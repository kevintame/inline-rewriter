import Cocoa
import os.log

/// Pasteboard integration.
///
/// To "grab selected text", the common approach is:
/// 1) Simulate ⌘C
/// 2) Read from NSPasteboard.general
///
/// Simulating key events requires Accessibility permission.
final class PasteboardService {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Pasteboard")
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
        logger.info("Copying selection to pasteboard")

        // Backup original clipboard contents before copying
        let backup = backupPasteboard()

        // Simulate ⌘C.
        // If Accessibility permission is not granted, CGEvent posting may fail.
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission not granted for copy")
            throw PasteboardError.accessibilityPermissionRequired
        }
        logger.debug("Accessibility permission verified")

        logger.debug("Creating CGEvents for Cmd+C")
        let keyC: CGKeyCode = 8 // US layout: 'c'
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true) else {
            logger.error("Failed to create keyDown CGEvent for copy")
            throw PasteboardError.cgEventCreationFailed
        }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else {
            logger.error("Failed to create keyUp CGEvent for copy")
            throw PasteboardError.cgEventCreationFailed
        }
        keyUp.flags = .maskCommand

        logger.debug("Posting Cmd+C events")
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.info("Copy completed, waiting for pasteboard update")
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
    func replaceSelection(with text: String, restoring backup: PasteboardBackup?, targetApp: NSRunningApplication?) throws {
        logger.info("Starting replace operation (text length: \(text.count) chars)")

        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission not granted")
            throw PasteboardError.accessibilityPermissionRequired
        }
        logger.debug("Accessibility permission verified")

        // Restore focus to target application
        if let targetApp = targetApp {
            logger.info("Restoring focus to: \(targetApp.localizedName ?? "unknown")")
            if targetApp.isTerminated {
                logger.warning("Target app was terminated")
                throw PasteboardError.targetApplicationTerminated
            } else {
                targetApp.activate(options: .activateIgnoringOtherApps)
                usleep(100_000)  // Wait 100ms for activation
                logger.debug("Focus restored")
            }
        } else {
            logger.warning("No target app provided - paste may go to wrong application")
        }

        logger.debug("Updating pasteboard with transformed text")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        logger.debug("Pasteboard updated")

        logger.debug("Creating CGEvents for Cmd+V")
        let keyV: CGKeyCode = 9 // US layout: 'v'
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true) else {
            logger.error("Failed to create keyDown CGEvent")
            throw PasteboardError.cgEventCreationFailed
        }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            logger.error("Failed to create keyUp CGEvent")
            throw PasteboardError.cgEventCreationFailed
        }
        keyUp.flags = .maskCommand

        logger.debug("Posting Cmd+V events")
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.info("Posted paste events")

        // Small delay to allow paste to complete
        usleep(80_000)
        logger.debug("Paste delay completed")

        // Restore original clipboard if backup exists
        if let backup = backup {
            logger.debug("Restoring original clipboard")
            restorePasteboard(backup)
        }

        logger.info("Replace operation completed successfully")
    }

    enum PasteboardError: LocalizedError {
        case accessibilityPermissionRequired
        case cgEventCreationFailed
        case targetApplicationTerminated

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Accessibility permission is required to copy/paste the current selection. Enable it in System Settings → Privacy & Security → Accessibility."
            case .cgEventCreationFailed:
                return "Failed to create keyboard events. This may be a system issue. Try restarting the app or your Mac."
            case .targetApplicationTerminated:
                return "The target application was closed. Please select text again in the active application."
            }
        }
    }
}
