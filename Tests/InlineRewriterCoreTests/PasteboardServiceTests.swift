import AppKit
import Testing
@testable import InlineRewriterCore

/// In-memory clipboard. `swift test` cannot rely on reaching the real pasteboard server.
@MainActor
final class FakeClipboard: ClipboardAccess {
    private(set) var changeCount = 0
    private(set) var items: [[(NSPasteboard.PasteboardType, Data)]] = []

    var string: String? {
        items.first?.first { $0.0 == .string }.flatMap { String(data: $0.1, encoding: .utf8) }
    }

    func clear() {
        items = []
        changeCount += 1
    }

    func setString(_ string: String) {
        items = [[(.string, Data(string.utf8))]]
        changeCount += 1
    }

    func setItems(_ newItems: [[(NSPasteboard.PasteboardType, Data)]]) {
        items = newItems
        changeCount += 1
    }

    func snapshot() -> PasteboardBackup? {
        items.isEmpty ? nil : PasteboardBackup(itemData: items)
    }

    func write(_ backup: PasteboardBackup) -> Bool {
        items = backup.itemData
        changeCount += 1
        return true
    }
}

/// Drives `PasteboardService` against a private pasteboard with a scripted "target app".
@MainActor
final class PasteboardHarness {
    let pasteboard = FakeClipboard()
    let targetPID: pid_t = 4242

    var trusted = true
    var frontmost: pid_t? = 4242
    var terminated = false
    var activations = 0
    /// What the fake app does when it receives ⌘C. `nil` copies nothing.
    var onCopy: ((FakeClipboard) -> Void)? = { $0.setString("selected text") }
    var postError: Error?
    /// Runs on every sleep; lets a test change the world mid-operation.
    var onSleep: (() throws -> Void)?
    /// What the pasteboard held each time ⌘V arrived.
    private(set) var pastes: [String?] = []
    private(set) var postedKeys: [CGKeyCode] = []

    var target: PasteboardService.Target {
        PasteboardService.Target(
            processIdentifier: targetPID,
            isTerminated: { [unowned self] in terminated },
            activate: { [unowned self] in activations += 1 }
        )
    }

    func makeService() -> PasteboardService {
        PasteboardService(pasteboard: pasteboard, environment: .init(
            isAccessibilityTrusted: { [unowned self] in trusted },
            frontmostProcessIdentifier: { [unowned self] in frontmost },
            postCommandKey: { [unowned self] key in
                if let postError { throw postError }
                postedKeys.append(key)
                if key == 8 { onCopy?(pasteboard) }
                if key == 9 { pastes.append(pasteboard.string) }
            },
            sleep: { [unowned self] _ in try onSleep?() }
        ))
    }

    func setClipboard(_ string: String) { pasteboard.setString(string) }

    var clipboard: String? { pasteboard.string }
}

@MainActor
struct PasteboardServiceTests {
    private typealias PBError = PasteboardService.PasteboardError

    // MARK: Capture

    @Test func captureReturnsSelectionAndRestoreBringsBackOriginal() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        let text = try await service.captureSelection(from: h.target)
        #expect(text == "selected text")
        #expect(service.hasPendingTransaction)

        service.restoreClipboard()
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func restoreRecreatesEveryItemAndType() async throws {
        let h = PasteboardHarness()
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        h.pasteboard.setItems([
            [(.string, Data("first".utf8)), (custom, Data([1, 2, 3]))],
            [(.string, Data("second".utf8))],
        ])
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        service.restoreClipboard()

        let items = h.pasteboard.items
        #expect(items.count == 2)
        #expect(items[0].map(\.0) == [.string, custom])
        #expect(items[0].map(\.1) == [Data("first".utf8), Data([1, 2, 3])])
        #expect(items[1].map(\.1) == [Data("second".utf8)])
    }

    @Test func emptyClipboardIsEmptyAgainAfterRestore() async throws {
        let h = PasteboardHarness()
        h.pasteboard.clear()
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        service.restoreClipboard()
        #expect(h.pasteboard.items.isEmpty)
    }

    @Test func noSelectionRestoresClipboard() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.onCopy = nil
        let service = h.makeService()

        await #expect(throws: PBError.noSelection) {
            try await service.captureSelection(from: h.target)
        }
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func nonTextCopyCountsAsNoSelectionAndRestores() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.onCopy = { $0.setItems([[(.png, Data([0xFF]))]]) }
        let service = h.makeService()

        await #expect(throws: PBError.noSelection) {
            try await service.captureSelection(from: h.target)
        }
        #expect(h.clipboard == "original")
    }

    @Test func captureWithoutPermissionLeavesClipboardUntouched() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.trusted = false
        let service = h.makeService()
        let before = h.pasteboard.changeCount

        await #expect(throws: PBError.accessibilityPermissionRequired) {
            try await service.captureSelection(from: h.target)
        }
        #expect(h.pasteboard.changeCount == before)
        #expect(h.postedKeys.isEmpty)
    }

    @Test func captureFailsClosedWhenTargetIsNotFrontmost() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.frontmost = 1
        let service = h.makeService()

        await #expect(throws: PBError.targetApplicationNotFrontmost) {
            try await service.captureSelection(from: h.target)
        }
        await #expect(throws: PBError.noTargetApplication) {
            try await service.captureSelection(from: nil)
        }
        #expect(h.clipboard == "original")
        #expect(h.postedKeys.isEmpty)
    }

    @Test func eventFailureDuringCaptureRestoresClipboard() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.postError = PBError.cgEventCreationFailed
        let service = h.makeService()

        await #expect(throws: PBError.cgEventCreationFailed) {
            try await service.captureSelection(from: h.target)
        }
        #expect(h.clipboard == "original")
    }

    @Test func cancellationDuringCaptureRestoresClipboard() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.onSleep = { throw CancellationError() }
        let service = h.makeService()

        await #expect(throws: CancellationError.self) {
            try await service.captureSelection(from: h.target)
        }
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    // MARK: Ownership

    @Test func restoreDoesNotOverwriteANewerCopy() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        h.setClipboard("copied during the session")
        service.restoreClipboard()

        #expect(h.clipboard == "copied during the session")
        #expect(!service.hasPendingTransaction)
    }

    @Test func restoreWithoutATransactionDoesNothing() {
        let h = PasteboardHarness()
        h.setClipboard("untouched")
        let before = h.pasteboard.changeCount
        h.makeService().restoreClipboard()
        #expect(h.pasteboard.changeCount == before)
    }

    @Test func keepOnClipboardEndsTheTransactionWithTheResult() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        service.keepOnClipboard("result")
        service.restoreClipboard()
        #expect(h.clipboard == "result")
    }

    // MARK: Replace

    @Test func replacePastesResultThenRestoresOriginal() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        try await service.replaceSelection(with: "rewritten", in: h.target)

        #expect(h.pastes == ["rewritten"])
        #expect(h.activations == 1)
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func replaceRestoresANewerCopyInsteadOfTheOldBackup() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        h.setClipboard("copied during the preview")
        try await service.replaceSelection(with: "rewritten", in: h.target)

        #expect(h.pastes == ["rewritten"])
        #expect(h.clipboard == "copied during the preview")
    }

    @Test func replacePreservesACopyMadeWhileTheTargetWasComingForward() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        // Another app writes to the clipboard during the activation wait.
        var sleeps = 0
        h.onSleep = {
            sleeps += 1
            if sleeps == 1 { h.setClipboard("copied during activation") }
        }
        try await service.replaceSelection(with: "rewritten", in: h.target)

        #expect(h.pastes == ["rewritten"])
        #expect(h.clipboard == "copied during activation")
    }

    @Test func failedReplaceLeavesANewerCopyAlone() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        h.setClipboard("copied during the preview")
        h.terminated = true
        await #expect(throws: PBError.targetApplicationTerminated) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.clipboard == "copied during the preview")
        #expect(!service.hasPendingTransaction)
    }

    @Test func replaceWaitsForTheTargetToComeToTheFront() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        h.frontmost = 1
        var sleeps = 0
        h.onSleep = {
            sleeps += 1
            if sleeps == 5 { h.frontmost = h.targetPID }
        }
        try await service.replaceSelection(with: "rewritten", in: h.target)
        #expect(h.pastes == ["rewritten"])
        #expect(h.clipboard == "original")
    }

    @Test func replaceNeverPastesIntoAnotherApp() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        h.frontmost = 1
        await #expect(throws: PBError.targetApplicationNotFrontmost) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.pastes.isEmpty)
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func replaceRechecksFocusImmediatelyBeforePasting() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        // Focus moves away during the settle wait, after the target was confirmed frontmost.
        h.onSleep = { h.frontmost = 1 }
        await #expect(throws: PBError.targetApplicationNotFrontmost) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.pastes.isEmpty)
        #expect(h.clipboard == "original")
    }

    @Test func replaceFailuresRestoreTheClipboard() async throws {
        // Permission revoked while the preview was up.
        var h = PasteboardHarness()
        h.setClipboard("original")
        var service = h.makeService()
        _ = try await service.captureSelection(from: h.target)
        h.trusted = false
        await #expect(throws: PBError.accessibilityPermissionRequired) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.clipboard == "original")

        // Target app quit.
        h = PasteboardHarness()
        h.setClipboard("original")
        service = h.makeService()
        _ = try await service.captureSelection(from: h.target)
        h.terminated = true
        await #expect(throws: PBError.targetApplicationTerminated) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.clipboard == "original")

        // No target at all.
        h = PasteboardHarness()
        h.setClipboard("original")
        service = h.makeService()
        _ = try await service.captureSelection(from: h.target)
        await #expect(throws: PBError.noTargetApplication) {
            try await service.replaceSelection(with: "rewritten", in: nil)
        }
        #expect(h.clipboard == "original")

        // Event creation fails after the result is already on the clipboard.
        h = PasteboardHarness()
        h.setClipboard("original")
        service = h.makeService()
        _ = try await service.captureSelection(from: h.target)
        h.postError = PBError.cgEventCreationFailed
        await #expect(throws: PBError.cgEventCreationFailed) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func cancellationAfterPasteStillRestoresClipboard() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        h.onSleep = { if !h.pastes.isEmpty { throw CancellationError() } }
        await #expect(throws: CancellationError.self) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.pastes == ["rewritten"])
        #expect(h.clipboard == "original")
    }

    @Test func aSecondCaptureDoesNotLoseTheFirstBackup() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        _ = try await service.captureSelection(from: h.target)
        _ = try await service.captureSelection(from: h.target)
        service.restoreClipboard()
        #expect(h.clipboard == "original")
    }

    // MARK: Ending a transaction mid-operation (quitting)

    @Test func quittingWhileWaitingForTheCopyRestoresTheClipboard() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        h.onCopy = nil
        let service = h.makeService()

        // The quit handler runs during the first poll, before anything was copied.
        var sleeps = 0
        h.onSleep = {
            sleeps += 1
            if sleeps == 1 { service.restoreClipboard() }
        }
        await #expect(throws: CancellationError.self) {
            try await service.captureSelection(from: h.target)
        }
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func quittingAfterTheCopyButBeforeCaptureFinishesRestoresTheClipboard() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        // The target app has copied; the quit handler runs during the settle wait.
        var clipboardAtQuit: String?
        h.onSleep = {
            guard service.hasPendingTransaction else { return }
            service.restoreClipboard()
            clipboardAtQuit = h.clipboard
        }
        await #expect(throws: CancellationError.self) {
            try await service.captureSelection(from: h.target)
        }
        #expect(clipboardAtQuit == "original")
        #expect(h.clipboard == "original")
        #expect(!service.hasPendingTransaction)
    }

    @Test func captureEndedFromOutsideDoesNotTouchTheClipboardAgain() async {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()

        var changeCountAfterQuit: Int?
        h.onSleep = {
            guard service.hasPendingTransaction else { return }
            service.restoreClipboard()
            changeCountAfterQuit = h.pasteboard.changeCount
        }
        _ = try? await service.captureSelection(from: h.target)
        #expect(h.pasteboard.changeCount == changeCountAfterQuit)
    }

    @Test func quittingDuringActivationRestoresAndNothingIsPasted() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        h.frontmost = 1
        h.onSleep = { service.restoreClipboard() }
        await #expect(throws: CancellationError.self) {
            try await service.replaceSelection(with: "rewritten", in: h.target)
        }
        #expect(h.pastes.isEmpty)
        #expect(h.clipboard == "original")
    }

    @Test func quittingAfterThePasteRestoresTheClipboard() async throws {
        let h = PasteboardHarness()
        h.setClipboard("original")
        let service = h.makeService()
        _ = try await service.captureSelection(from: h.target)

        var clipboardAtQuit: String?
        h.onSleep = {
            guard !h.pastes.isEmpty, service.hasPendingTransaction else { return }
            service.restoreClipboard()
            clipboardAtQuit = h.clipboard
        }
        try await service.replaceSelection(with: "rewritten", in: h.target)
        #expect(clipboardAtQuit == "original")
        #expect(h.clipboard == "original")
    }
}
