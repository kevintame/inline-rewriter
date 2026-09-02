import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp`. The system is the source of truth, so nothing is stored
/// in UserDefaults; the toggle in Settings reads and writes the registration directly.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    /// True when the user toggled it on but macOS still wants confirmation in
    /// System Settings → General → Login Items.
    @Published private(set) var requiresApproval: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        requiresApproval = (status == .requiresApproval)
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
