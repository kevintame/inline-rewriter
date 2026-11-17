import Foundation
import SwiftUI

@MainActor
final class TransformationPickerViewModel: ObservableObject {
    let inputText: String

    @Published var isBusy: Bool = false
    @Published var errorMessage: String?
    /// True when the last failure is one Settings can fix (a missing API key), so the view
    /// can offer a shortcut there instead of a dead end.
    @Published var errorNeedsSettings: Bool = false
    @Published var selectedIndex: Int = 0

    private let settings: SettingsStore
    private let transformer: TextTransformer
    private var currentTask: Task<Void, Never>?

    var onCancel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

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

    /// The captured text on one line, so the user can confirm the right selection was read.
    var inputSummary: String {
        inputText
            .prefix(300)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var inputLengthDescription: String {
        let count = inputText.count
        return count == 1 ? "1 character" : "\(count) characters"
    }

    func cancel() {
        cancelInFlight()
        onCancel?()
    }

    func openSettings() {
        cancelInFlight()
        onOpenSettings?()
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
        errorNeedsSettings = false

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
                errorMessage = error.localizedDescription
                errorNeedsSettings = (error as? OpenAIError) == .missingAPIKey
            }
        }
    }

    /// Runs the transformation at `index`, ignoring the request while one is already in flight
    /// so a stray Return or number key cannot restart it.
    func run(at index: Int) {
        guard !isBusy, transformations.indices.contains(index) else { return }
        selectedIndex = index
        run(transformations[index])
    }

    func selectNext() {
        guard !transformations.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, transformations.count - 1)
    }

    func selectPrevious() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func runSelected() {
        run(at: selectedIndex)
    }
}
