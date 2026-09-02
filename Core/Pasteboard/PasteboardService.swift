import Cocoa
import os.log

/// Reads the current selection and replaces it by simulating ⌘C / ⌘V.
///
/// Both operations require Accessibility permission because they post synthetic
/// keyboard events. Waits are `Task.sleep`s so the main thread never blocks.
@MainActor
final class PasteboardService {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Pasteboard")

    /// Snapshot of the user's clipboard, stored as raw data so it can be recreated later.
    /// `nil` means the clipboard was empty.
    struct PasteboardBackup {
        let itemData: [[(NSPasteboard.PasteboardType, Data)]]
    }

    struct Capture {
        let text: String
        let backup: PasteboardBackup?
    }

    enum PasteboardError: LocalizedError {
        case accessibilityPermissionRequired
        case cgEventCreationFailed
        case noSelection
        case targetApplicationTerminated

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Accessibility permission is required to read and replace the selected text. Enable it in System Settings → Privacy & Security → Accessibility."
            case .cgEventCreationFailed:
                return "Failed to create keyboard events. Try restarting the app."
            case .noSelection:
                return "Nothing was copied. Select some text and try again."
            case .targetApplicationTerminated:
                return "The application you were working in has quit."
            }
        }
    }

    // MARK: - Capture

    /// Copies the current selection and returns it with a backup of the previous clipboard.
    /// Restores the clipboard itself if nothing was copied.
    func captureSelection() async throws -> Capture {
        guard AXIsProcessTrusted() else {
            throw PasteboardError.accessibilityPermissionRequired
        }

        let backup = backupPasteboard()
        let pb = NSPasteboard.general
        pb.clearContents()
        let previousChangeCount = pb.changeCount

        try postKeyboardShortcut(virtualKey: 8) // 'c' on US layout

        // Wait for the target app to write to the pasteboard.
        let deadline = Date().addingTimeInterval(0.5)
        while pb.changeCount == previousChangeCount && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // Let the app finish writing all representations.
        try await Task.sleep(nanoseconds: 50_000_000)

        let text = pb.string(forType: .string) ?? ""
        guard pb.changeCount != previousChangeCount, !text.isEmpty else {
            logger.info("No selection captured; restoring clipboard")
            restore(backup)
            throw PasteboardError.noSelection
        }

        logger.info("Captured selection (\(text.count) chars)")
        return Capture(text: text, backup: backup)
    }

    // MARK: - Replace

    /// Puts `text` on the clipboard, pastes into `targetApp`, then restores the clipboard.
    func replaceSelection(with text: String, restoring backup: PasteboardBackup?, targetApp: NSRunningApplication?) async throws {
        guard AXIsProcessTrusted() else {
            throw PasteboardError.accessibilityPermissionRequired
        }

        if let targetApp {
            if targetApp.isTerminated {
                throw PasteboardError.targetApplicationTerminated
            }
            targetApp.activate(options: .activateIgnoringOtherApps)
            try await Task.sleep(nanoseconds: 100_000_000)
        } else {
            logger.warning("No target app; paste will go to whichever app is frontmost")
        }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        try postKeyboardShortcut(virtualKey: 9) // 'v' on US layout
        logger.info("Posted paste (\(text.count) chars)")

        // Heavier apps (Electron editors, Slack) need a few hundred ms to read the pasteboard.
        try await Task.sleep(nanoseconds: 300_000_000)

        restore(backup)
    }

    // MARK: - Clipboard backup

    /// Restores a backup, or clears the clipboard when the backup is `nil` (it was empty).
    func restore(_ backup: PasteboardBackup?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard let backup else { return }
        for itemData in backup.itemData {
            let newItem = NSPasteboardItem()
            for (type, data) in itemData {
                newItem.setData(data, forType: type)
            }
            pb.writeObjects([newItem])
        }
    }

    private func backupPasteboard() -> PasteboardBackup? {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems, !items.isEmpty else { return nil }

        let rawItems = items.map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
        return PasteboardBackup(itemData: rawItems)
    }

    // MARK: - Key events

    private func postKeyboardShortcut(virtualKey: CGKeyCode) throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            throw PasteboardError.cgEventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
