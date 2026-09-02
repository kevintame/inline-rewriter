import Cocoa

/// Simple alert helper.
/// Keeps UI alerts out of core logic.
@MainActor
final class AlertPresenter {
    func showError(title: String, message: String) {
        // An accessory app is rarely active, so activate first or the alert lands behind
        // whatever the user is working in.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
