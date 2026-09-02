import Foundation
import SwiftUI

@MainActor
final class TransformationPickerViewModel: ObservableObject {
    let inputText: String

    @Published var isBusy: Bool = false
    @Published var errorMessage: String?
    @Published var selectedIndex: Int = 0

    private let settings: SettingsStore
    private let transformer: TextTransformer
    private var currentTask: Task<Void, Never>?

    var onCancel: (() -> Void)?

    /// Called when a transformation succeeds, with the output and the transformation that
    /// produced it so the caller can offer a retry.
    var onDidTransform: ((String, TextTransformation) -> Void)?

    init(inputText: String, settings: SettingsStore, transformer: TextTransformer) {
        self.inputText = inputText
        self.settings = settings
        self.transformer = transformer
    }

    var transformations: [TextTransformation] {
        settings.transformations
    }

    func cancel() {
        cancelInFlight()
        onCancel?()
    }

    /// Cancels any request in progress without notifying `onCancel`.
    func cancelInFlight() {
        currentTask?.cancel()
        currentTask = nil
        isBusy = false
    }

    func run(_ transformation: TextTransformation) {
        currentTask?.cancel()
        isBusy = true
        errorMessage = nil

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await transformer.run(transformation: transformation, input: inputText)
                guard !Task.isCancelled else { return }
                isBusy = false
                onDidTransform?(output, transformation)
            } catch {
                // URLSession reports cancellation as an error; a cancelled flow has no UI left to show it in.
                guard !Task.isCancelled else { return }
                isBusy = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    func selectNext() {
        guard !transformations.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, transformations.count - 1)
    }

    func selectPrevious() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func runSelected() {
        guard transformations.indices.contains(selectedIndex) else { return }
        run(transformations[selectedIndex])
    }
}
