import Foundation

/// Centralized constants for the app.
enum AppConstants {
    static let bundleIdentifier = "com.kevinTame.InlineRewriter"
    static let keychainService = bundleIdentifier

    enum KeychainAccounts {
        static let openAIKey = "openai_api_key"
        static let anthropicKey = "anthropic_api_key"
        static let googleGeminiKey = "google_gemini_api_key"
    }
}
