import Foundation
import SwiftUI

@MainActor
final class TransformationPickerViewModel: ObservableObject {
    let inputText: String
    let pasteboardBackup: PasteboardService.PasteboardBackup?

    @Published var isBusy: Bool = false
    @Published var errorMessage: String?
    @Published var selectedIndex: Int = 0

    private let settings: SettingsStore
    private let transformer: TextTransformer

    var onCancel: (() -> Void)?

    /// Called when transformation succeeds.
    /// Provides output + a retry closure.
    var onDidTransform: ((String, @escaping () -> Void) -> Void)?

    init(inputText: String, settings: SettingsStore, transformer: TextTransformer, pasteboardBackup: PasteboardService.PasteboardBackup?) {
        self.inputText = inputText
        self.settings = settings
        self.transformer = transformer
        self.pasteboardBackup = pasteboardBackup
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

                let retry: () -> Void = { [weak self] in
                    self?.run(transformation)
                }
                onDidTransform?(output, retry)
            } catch {
                isBusy = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }
    }

    func selectNext() {
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
