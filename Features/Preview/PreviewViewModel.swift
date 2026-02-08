import Foundation
import SwiftUI

@MainActor
final class PreviewViewModel: ObservableObject {
    let inputText: String
    @Published var outputText: String

    private let pasteboardService: PasteboardService
    private let alertPresenter: AlertPresenter

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?

    init(inputText: String, outputText: String, pasteboardService: PasteboardService, alertPresenter: AlertPresenter) {
        self.inputText = inputText
        self.outputText = outputText
        self.pasteboardService = pasteboardService
        self.alertPresenter = alertPresenter
    }

    func cancel() {
        onCancel?()
    }

    func retry() {
        onRetry?()
    }

    func replace() {
        do {
            try pasteboardService.replaceSelection(with: outputText)
            onCancel?()
        } catch {
            alertPresenter.showError(title: "Replace failed", message: error.localizedDescription)
        }
    }
}
