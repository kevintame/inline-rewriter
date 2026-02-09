import Foundation

/// Dependency container.
/// Keep this small; it’s enough for scaffolding and makes future DI/test easier.
final class AppContainer {
    let settingsStore: SettingsStore
    let keychain: KeychainStoring

    let hotkeyManager: HotkeyManager
    let pasteboardService: PasteboardService
    let alertPresenter: AlertPresenter

    let openAIClient: OpenAIClient
    let textTransformer: TextTransformer

    init() {
        self.settingsStore = SettingsStore()
        self.keychain = KeychainStore(service: AppConstants.keychainService)

        self.alertPresenter = AlertPresenter()
        self.pasteboardService = PasteboardService()
        self.hotkeyManager = HotkeyManager(settings: settingsStore)

        self.openAIClient = OpenAIClient(
            settings: settingsStore,
            keychain: keychain
        )
        self.textTransformer = TextTransformer(
            openAI: openAIClient,
            settings: settingsStore
        )
    }
}
