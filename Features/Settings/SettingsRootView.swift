import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring
    let hotkeyManager: HotkeyManager
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @ObservedObject var permission: AccessibilityPermissionMonitor
    let testConnection: (ModelProviderConfig, String) async throws -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(
                settings: settings,
                hotkeyManager: hotkeyManager,
                launchAtLogin: launchAtLogin,
                permission: permission
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            ModelsSettingsView(
                settings: settings,
                keychain: keychain,
                testConnection: testConnection
            )
            .tabItem {
                Label("Models", systemImage: "server.rack")
            }

            PromptsSettingsView(settings: settings)
                .tabItem {
                    Label("Prompts", systemImage: "text.bubble")
                }
        }
        .frame(width: 700, height: 500)
    }
}
