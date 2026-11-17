import AppKit

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

    /// Return commits even while the editor has focus, so the fast path stays
    /// hotkey → Return → Return. ⌥↩ is left to the editor as a newline. Escape cancels.
    /// Returns true when the key was used.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.numericPad, .function])
            if modifiers.contains(.option) { return false }
            replace()
            return true
        case 53: // Escape
            cancel()
            return true
        default:
            return false
        }
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
