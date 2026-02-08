import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring
    let hotkeyManager: HotkeyManager
    let alertPresenter: AlertPresenter

    var body: some View {
        TabView {
            TransformationsSettingsView(settings: settings)
                .tabItem { Text("Transformations") }

            OpenAISettingsView(settings: settings, keychain: keychain, alertPresenter: alertPresenter)
                .tabItem { Text("OpenAI") }

            HotkeySettingsView(settings: settings, hotkeyManager: hotkeyManager, alertPresenter: alertPresenter)
                .tabItem { Text("Hotkey") }
        }
        .padding(16)
        .frame(width: 640, height: 420)
    }
}
