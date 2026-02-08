import Foundation
import SwiftUI

@MainActor
final class TransformationPickerViewModel: ObservableObject {
    let inputText: String

    @Published var isBusy: Bool = false
    @Published var errorMessage: String?

    private let settings: SettingsStore
    private let transformer: TextTransformer

    var onCancel: (() -> Void)?

    /// Called when transformation succeeds.
    /// Provides output + a retry closure.
    var onDidTransform: ((String, @escaping () -> Void) -> Void)?

    init(inputText: String, settings: SettingsStore, transformer: TextTransformer) {
        self.inputText = inputText
        self.settings = settings
        self.transformer = transformer
    }

    var transformations: [TextTransformation] {
        settings.transformations
    }

    func cancel() {
        onCancel?()
    }

    func run(_ transformation: TextTransformation) {
        isBusy = true
        errorMessage = nil

        Task {
            do {
                let output = try await transformer.run(transformation: transformation, input: inputText)
                isBusy = false

                let retry = { [weak self] in
                    self?.run(transformation)
                }
                onDidTransform?(output, retry)
            } catch {
                isBusy = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }
}
