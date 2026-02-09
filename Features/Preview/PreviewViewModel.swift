import Foundation
import SwiftUI

@MainActor
final class PreviewViewModel: ObservableObject {
    let inputText: String
    @Published var outputText: String

    private let pasteboardService: PasteboardService
    private let alertPresenter: AlertPresenter
    private let pasteboardBackup: PasteboardService.PasteboardBackup?

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?

    init(inputText: String, outputText: String, pasteboardService: PasteboardService, alertPresenter: AlertPresenter, pasteboardBackup: PasteboardService.PasteboardBackup?) {
        self.inputText = inputText
        self.outputText = outputText
        self.pasteboardService = pasteboardService
        self.alertPresenter = alertPresenter
        self.pasteboardBackup = pasteboardBackup
    }

    func cancel() {
        onCancel?()
    }

    func retry() {
        onRetry?()
    }

    func replace() {
        do {
            try pasteboardService.replaceSelection(with: outputText, restoring: pasteboardBackup)
            onCancel?()
        } catch {
            alertPresenter.showError(title: "Replace failed", message: error.localizedDescription)
        }
    }
}
