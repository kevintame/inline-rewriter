import Cocoa
import os.log

/// Snapshot of a clipboard, stored as raw data per item and type so it can be recreated.
struct PasteboardBackup {
    let itemData: [[(NSPasteboard.PasteboardType, Data)]]
}

/// The clipboard operations `PasteboardService` needs. `NSPasteboard` in the app; an
/// in-memory double in tests, where the pasteboard server may not be reachable.
@MainActor
protocol ClipboardAccess: AnyObject {
    /// Increases every time the contents change, whoever changes them.
    var changeCount: Int { get }
    var string: String? { get }
    func clear()
    func setString(_ string: String)
    /// Every item and representation currently on the clipboard, or `nil` if it is empty.
    func snapshot() -> PasteboardBackup?
    /// Replaces the contents with `backup`. Returns false if the write was refused.
    func write(_ backup: PasteboardBackup) -> Bool
}

extension NSPasteboard: ClipboardAccess {
    var string: String? { string(forType: .string) }

    func clear() {
        clearContents()
    }

    func setString(_ string: String) {
        clearContents()
        setString(string, forType: .string)
    }

    func snapshot() -> PasteboardBackup? {
        guard let items = pasteboardItems, !items.isEmpty else { return nil }
        let rawItems = items.map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
        return PasteboardBackup(itemData: rawItems)
    }

    func write(_ backup: PasteboardBackup) -> Bool {
        clearContents()
        let items = backup.itemData.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        // One write for all items; separate writes would each replace the previous one's
        // ownership and can drop items.
        return items.isEmpty || writeObjects(items)
    }
}

/// Reads the current selection and replaces it by simulating ⌘C / ⌘V.
///
/// Both operations require Accessibility permission because they post synthetic
/// keyboard events. Waits are `Task.sleep`s so the main thread never blocks.
///
/// The service owns one clipboard transaction at a time. It begins when a capture takes
/// over the clipboard and ends when the user's clipboard is handed back, by
/// `replaceSelection`, `restoreClipboard`, `keepOnClipboard`, or a failure. The rules:
///
/// - Every way out of a capture or a replace hands the clipboard back, including errors.
/// - The backup is only written back while the clipboard still holds what this service put
///   there. If anything newer was copied in the meantime, the newer contents win. The one
///   window this cannot cover is the fraction of a second in which the target app answers
///   ⌘C or reads ⌘V: a change made then is indistinguishable from the app's own.
/// - A synthetic keystroke is only posted while the intended app is frontmost.
@MainActor
final class PasteboardService {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Pasteboard")

    /// The app a selection is read from and pasted back into.
    struct Target {
        let processIdentifier: pid_t
        let isTerminated: () -> Bool
        let activate: () -> Void

        init(processIdentifier: pid_t, isTerminated: @escaping () -> Bool, activate: @escaping () -> Void) {
            self.processIdentifier = processIdentifier
            self.isTerminated = isTerminated
            self.activate = activate
        }

        init(_ app: NSRunningApplication) {
            self.init(
                processIdentifier: app.processIdentifier,
                isTerminated: { app.isTerminated },
                activate: { app.activate(options: .activateIgnoringOtherApps) }
            )
        }
    }

    /// Everything the service needs from the system, replaceable in tests.
    struct Environment {
        var isAccessibilityTrusted: () -> Bool
        var frontmostProcessIdentifier: () -> pid_t?
        /// Posts ⌘ + the given virtual key.
        var postCommandKey: (CGKeyCode) throws -> Void
        var sleep: (_ nanoseconds: UInt64) async throws -> Void

        static let live = Environment(
            isAccessibilityTrusted: { AXIsProcessTrusted() },
            frontmostProcessIdentifier: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            postCommandKey: { virtualKey in
                let source = CGEventSource(stateID: .combinedSessionState)
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
                    throw PasteboardError.cgEventCreationFailed
                }
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            },
            sleep: { try await Task.sleep(nanoseconds: $0) }
        )
    }

    enum PasteboardError: LocalizedError, Equatable {
        case accessibilityPermissionRequired
        case cgEventCreationFailed
        case noSelection
        case noTargetApplication
        case targetApplicationTerminated
        case targetApplicationNotFrontmost

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                return "Accessibility permission is required to read and replace the selected text. Enable it in System Settings → Privacy & Security → Accessibility."
            case .cgEventCreationFailed:
                return "Failed to create keyboard events. Try restarting the app."
            case .noSelection:
                return "Nothing was copied. Select some text and try again."
            case .noTargetApplication:
                return "Couldn't tell which application you were working in. Click into it and try again."
            case .targetApplicationTerminated:
                return "The application you were working in has quit."
            case .targetApplicationNotFrontmost:
                return "Couldn't switch back to the application you were working in, so nothing was pasted."
            }
        }
    }

    private enum VirtualKey {
        static let c: CGKeyCode = 8 // US layout
        static let v: CGKeyCode = 9 // US layout
    }

    private enum Timing {
        static let pollInterval: UInt64 = 10_000_000
        /// How long the target app gets to put the selection on the clipboard (0.5 s).
        static let copyPolls = 50
        /// Lets the app finish writing every representation after the first change.
        static let copySettle: UInt64 = 50_000_000
        /// How long the target app gets to come to the front (1 s).
        static let activationPolls = 100
        /// Lets the frontmost app restore keyboard focus to its text view.
        static let activationSettle: UInt64 = 100_000_000
        /// Heavier apps (Electron editors, Slack) need a few hundred ms to read the pasteboard.
        static let pasteSettle: UInt64 = 300_000_000
    }

    /// A clipboard takeover in progress.
    private struct Transaction {
        /// What to hand back. `nil` means the clipboard was empty.
        var backup: PasteboardBackup?
        /// `changeCount` after this service's most recent write. The clipboard is still
        /// ours only while it reports this value.
        var ownedChangeCount: Int
    }

    private let pasteboard: ClipboardAccess
    private let environment: Environment
    private var transaction: Transaction?

    init(pasteboard: ClipboardAccess = NSPasteboard.general, environment: Environment = .live) {
        self.pasteboard = pasteboard
        self.environment = environment
    }

    /// True between a successful capture and the clipboard being handed back.
    var hasPendingTransaction: Bool { transaction != nil }

    // MARK: - Capture

    /// Copies the current selection in `target` and returns it. The previous clipboard is
    /// kept until `replaceSelection`, `restoreClipboard`, or `keepOnClipboard` ends the
    /// transaction. If this throws, the clipboard has already been handed back.
    func captureSelection(from target: Target?) async throws -> String {
        // A capture that starts while another is pending would lose the first backup.
        restoreClipboard()

        guard environment.isAccessibilityTrusted() else {
            throw PasteboardError.accessibilityPermissionRequired
        }
        try requireFrontmost(target)

        let backup = pasteboard.snapshot()
        pasteboard.clear()
        let clearedChangeCount = pasteboard.changeCount
        transaction = Transaction(backup: backup, ownedChangeCount: clearedChangeCount)

        do {
            try environment.postCommandKey(VirtualKey.c)

            // Wait for the target app to write to the pasteboard.
            var polls = 0
            while pasteboard.changeCount == clearedChangeCount && polls < Timing.copyPolls {
                try await environment.sleep(Timing.pollInterval)
                polls += 1
            }
            try await environment.sleep(Timing.copySettle)

            let text = pasteboard.string ?? ""
            guard pasteboard.changeCount != clearedChangeCount, !text.isEmpty else {
                throw PasteboardError.noSelection
            }

            // The selection is now what this service "owns" on the clipboard.
            transaction?.ownedChangeCount = pasteboard.changeCount
            logger.info("Captured selection (\(text.count) chars)")
            return text
        } catch {
            // Any change since the clipboard was cleared is attributed to the ⌘C just
            // posted (possibly a non-text copy), so the user's own contents go back.
            // Known limit: a copy made by another app inside this half-second window
            // cannot be told apart from the target app's and is replaced by the backup.
            logger.info("Capture failed; restoring clipboard")
            transaction?.ownedChangeCount = pasteboard.changeCount
            restoreClipboard()
            throw error
        }
    }

    // MARK: - Replace

    /// Puts `text` on the clipboard, pastes into `target`, then hands the clipboard back.
    /// The clipboard is handed back on every failure too, and nothing is pasted unless
    /// `target` is confirmed frontmost.
    func replaceSelection(with text: String, in target: Target?) async throws {
        if transaction == nil {
            transaction = Transaction(backup: pasteboard.snapshot(), ownedChangeCount: pasteboard.changeCount)
        }
        // Covers every exit below. Before the payload is written this is a no-op unless the
        // clipboard still holds the captured selection.
        defer { restoreClipboard() }

        guard environment.isAccessibilityTrusted() else {
            throw PasteboardError.accessibilityPermissionRequired
        }
        guard let target else { throw PasteboardError.noTargetApplication }
        guard !target.isTerminated() else { throw PasteboardError.targetApplicationTerminated }

        target.activate()
        var polls = 0
        while environment.frontmostProcessIdentifier() != target.processIdentifier && polls < Timing.activationPolls {
            try await environment.sleep(Timing.pollInterval)
            polls += 1
        }
        try requireFrontmost(target)
        try await environment.sleep(Timing.activationSettle)

        // Checked after the waits, right before taking the clipboard over again: if
        // something newer was copied while the preview was up or while the target app was
        // coming forward, that is what must survive the paste, not the older backup.
        if let active = transaction, pasteboard.changeCount != active.ownedChangeCount {
            logger.info("Clipboard changed during the session; preserving the newer contents")
            transaction = Transaction(backup: pasteboard.snapshot(), ownedChangeCount: pasteboard.changeCount)
        }
        pasteboard.setString(text)
        transaction?.ownedChangeCount = pasteboard.changeCount

        // Checked last, immediately before posting: focus may have moved during the waits.
        try requireFrontmost(target)
        try environment.postCommandKey(VirtualKey.v)
        logger.info("Posted paste (\(text.count) chars)")

        try await environment.sleep(Timing.pasteSettle)
    }

    // MARK: - Ending a transaction

    /// Hands the user's clipboard back and ends the transaction. Does nothing when no
    /// transaction is pending, and leaves the clipboard alone if something newer than this
    /// service's own write is on it. Synchronous, so it is safe to call while quitting.
    func restoreClipboard() {
        guard let active = transaction else { return }
        transaction = nil

        guard pasteboard.changeCount == active.ownedChangeCount else {
            logger.info("Clipboard has newer contents; not restoring the backup")
            return
        }
        write(active.backup)
    }

    /// Ends the transaction by leaving `text` on the clipboard instead of restoring the
    /// backup (the preview's Copy button).
    func keepOnClipboard(_ text: String) {
        transaction = nil
        pasteboard.setString(text)
    }

    // MARK: - Helpers

    private func requireFrontmost(_ target: Target?) throws {
        guard let target else { throw PasteboardError.noTargetApplication }
        guard !target.isTerminated() else { throw PasteboardError.targetApplicationTerminated }
        guard environment.frontmostProcessIdentifier() == target.processIdentifier else {
            throw PasteboardError.targetApplicationNotFrontmost
        }
    }

    /// Replaces the clipboard with `backup`, or empties it when the backup is `nil`.
    private func write(_ backup: PasteboardBackup?) {
        guard let backup else {
            pasteboard.clear()
            return
        }
        if !pasteboard.write(backup) {
            logger.error("Failed to restore the clipboard backup")
        }
    }
}
