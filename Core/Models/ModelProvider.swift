import Foundation

/// Identifies each supported AI provider.
enum ModelProviderID: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case googleGemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .googleGemini: return "Google Gemini"
        }
    }

    var keychainAccount: String {
        switch self {
        case .openAI: return AppConstants.KeychainAccounts.openAIKey
        case .anthropic: return AppConstants.KeychainAccounts.anthropicKey
        case .googleGemini: return AppConstants.KeychainAccounts.googleGeminiKey
        }
    }

    var defaultHost: String {
        switch self {
        case .openAI: return "api.openai.com"
        case .anthropic: return "api.anthropic.com"
        case .googleGemini: return "generativelanguage.googleapis.com"
        }
    }

    var defaultSubPath: String {
        switch self {
        case .openAI: return "/v1/chat/completions"
        case .anthropic: return "/v1/messages"
        case .googleGemini: return "/v1beta/models"
        }
    }

    var availableModels: [String] {
        switch self {
        case .openAI: return ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .anthropic: return ["claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001", "claude-opus-4-20250514"]
        case .googleGemini: return ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-pro"]
        }
    }
}

/// Per-provider configuration stored in UserDefaults.
struct ModelProviderConfig: Codable, Equatable, Identifiable {
    var id: String { providerID.rawValue }

    var providerID: ModelProviderID
    var host: String
    var subPath: String
    var defaultModel: String
    var isDefaultVendor: Bool

    static func defaultConfig(for provider: ModelProviderID) -> ModelProviderConfig {
        ModelProviderConfig(
            providerID: provider,
            host: provider.defaultHost,
            subPath: provider.defaultSubPath,
            defaultModel: provider.availableModels.first ?? "",
            isDefaultVendor: provider == .openAI
        )
    }
}
