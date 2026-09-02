import Foundation

/// Dependency container.
/// Keep this small; it’s enough for scaffolding and makes future DI/test easier.
@MainActor
final class AppContainer {
    let settingsStore: SettingsStore
    let keychain: KeychainStoring

    let hotkeyManager: HotkeyManager
    let pasteboardService: PasteboardService
    let alertPresenter: AlertPresenter
    let accessibilityPermission: AccessibilityPermissionMonitor
    let launchAtLogin: LaunchAtLoginService

    let openAIClient: OpenAIClient
    let textTransformer: TextTransformer

    init() {
        self.settingsStore = SettingsStore()
        self.keychain = KeychainStore(service: AppConstants.keychainService)

        self.alertPresenter = AlertPresenter()
        self.pasteboardService = PasteboardService()
        self.hotkeyManager = HotkeyManager(settings: settingsStore)
        self.accessibilityPermission = AccessibilityPermissionMonitor()
        self.launchAtLogin = LaunchAtLoginService()

        self.openAIClient = OpenAIClient(
            settings: settingsStore,
            keychain: keychain
        )
        self.textTransformer = TextTransformer(openAI: openAIClient)
    }
}
