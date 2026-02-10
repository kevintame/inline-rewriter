import Foundation

@MainActor
final class PreviewViewModel: ObservableObject {
    let inputText: String
    let outputText: String

    let pasteboardBackup: PasteboardService.PasteboardBackup?

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onReplace: (() -> Void)?

    init(inputText: String, outputText: String, pasteboardBackup: PasteboardService.PasteboardBackup?) {
        self.inputText = inputText
        self.outputText = outputText
        self.pasteboardBackup = pasteboardBackup
    }

    func cancel() {
        onCancel?()
    }

    func retry() {
        onRetry?()
    }

    func replace() {
        onReplace?()
    }
}
