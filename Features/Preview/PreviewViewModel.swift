import Foundation

@MainActor
final class PreviewViewModel: ObservableObject {
    let outputText: String

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onReplace: (() -> Void)?

    init(outputText: String) {
        self.outputText = outputText
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
