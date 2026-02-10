import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring
    let hotkeyManager: HotkeyManager
    let alertPresenter: AlertPresenter

    var body: some View {
        TabView {
            GeneralSettingsView(
                settings: settings,
                hotkeyManager: hotkeyManager,
                alertPresenter: alertPresenter
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            ModelsSettingsView(
                settings: settings,
                keychain: keychain
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
