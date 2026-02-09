import Foundation

/// Centralized constants for the app.
enum AppConstants {
    static let bundleIdentifier = "com.kevinTame.InlineRewriter"
    static let keychainService = bundleIdentifier

    enum KeychainAccounts {
        static let openAIKey = "openai_api_key"
    }
}
