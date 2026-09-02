import AppKit
import ApplicationServices
import Combine

/// Observable view of the Accessibility (TCC) grant for this app.
///
/// macOS offers no notification when the user flips the switch, so views that care call
/// `beginObserving()` and the monitor polls once a second while any of them is on screen.
@MainActor
final class AccessibilityPermissionMonitor: ObservableObject {
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var timer: Timer?
    private var observerCount = 0

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// Shows the system prompt, which also adds the app to the Accessibility list so the
    /// user only has to flip the switch.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func beginObserving() {
        observerCount += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    func endObserving() {
        observerCount = max(0, observerCount - 1)
        if observerCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }
}
