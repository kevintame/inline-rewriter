import Foundation

@MainActor
final class PreviewViewModel: ObservableObject {
    let inputText: String
    let transformationName: String

    /// Editable so a one-word fix does not need another round trip to the model.
    @Published var outputText: String

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    /// Receives the text as it stands when the user commits, including any edits.
    var onReplace: ((String) -> Void)?
    var onCopy: ((String) -> Void)?

    init(inputText: String, outputText: String, transformationName: String) {
        self.inputText = inputText
        self.outputText = outputText
        self.transformationName = transformationName
    }

    var isOutputEmpty: Bool {
        outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func cancel() {
        onCancel?()
    }

    func retry() {
        onRetry?()
    }

    func replace() {
        guard !isOutputEmpty else { return }
        onReplace?(outputText)
    }

    func copy() {
        guard !isOutputEmpty else { return }
        onCopy?(outputText)
    }
}
