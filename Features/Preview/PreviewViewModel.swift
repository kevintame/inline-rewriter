import Foundation
import SwiftUI
import Cocoa

@MainActor
final class PreviewViewModel: ObservableObject {
    let inputText: String
    let outputText: String

    private let pasteboardService: PasteboardService
    private let alertPresenter: AlertPresenter
    private let pasteboardBackup: PasteboardService.PasteboardBackup?
    private let targetApp: NSRunningApplication?

    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?

    init(inputText: String, outputText: String, pasteboardService: PasteboardService, alertPresenter: AlertPresenter, pasteboardBackup: PasteboardService.PasteboardBackup?, targetApp: NSRunningApplication?) {
        self.inputText = inputText
        self.outputText = outputText
        self.pasteboardService = pasteboardService
        self.alertPresenter = alertPresenter
        self.pasteboardBackup = pasteboardBackup
        self.targetApp = targetApp
    }

    func cancel() {
        onCancel?()
    }

    func retry() {
        onRetry?()
    }

    func replace() {
        do {
            try pasteboardService.replaceSelection(with: outputText, restoring: pasteboardBackup, targetApp: targetApp)
            onCancel?()
        } catch PasteboardService.PasteboardError.cgEventCreationFailed {
            alertPresenter.showError(
                title: "Replace Failed",
                message: "Failed to create keyboard events. This may be a system issue. Try restarting the app."
            )
        } catch PasteboardService.PasteboardError.targetApplicationTerminated {
            alertPresenter.showError(
                title: "Replace Failed",
                message: "The target application was closed. Please try again."
            )
        } catch {
            alertPresenter.showError(
                title: "Replace Failed",
                message: error.localizedDescription
            )
        }
    }
}
