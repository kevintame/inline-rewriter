import SwiftUI

/// App entry point for Inline Rewriter.
/// Uses an `NSApplicationDelegate` to create the menubar status item and popovers.
@main
struct InlineRewriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings window is declared here so it appears under the app menu.
        Settings {
            SettingsRootView(
                settings: appDelegate.container.settingsStore,
                keychain: appDelegate.container.keychain,
                hotkeyManager: appDelegate.container.hotkeyManager,
                alertPresenter: appDelegate.container.alertPresenter
            )
        }
    }
}
