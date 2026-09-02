import Foundation

/// Identifies each AI provider the settings model knows about.
enum ModelProviderID: String, Codable, CaseIterable, Identifiable {
    case openAI
    case anthropic
    case googleGemini

    /// Providers with a working client. Anthropic and Gemini have config models but no
    /// request implementation yet, so they stay hidden in Settings until they do.
    static let supported: [ModelProviderID] = [.openAI]

    var id: String { rawValue }

    var isSupported: Bool { Self.supported.contains(self) }

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

    /// Suggestions shown in Settings. The model field accepts any ID, so this list going
    /// stale is an inconvenience rather than a limitation.
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

    enum EndpointError: LocalizedError, Equatable {
        case emptyHost
        case invalidHost
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .emptyHost: return "Host cannot be empty."
            case .invalidHost: return "Host must be a bare hostname such as api.openai.com, optionally with a port."
            case .invalidURL: return "Host and path do not form a valid URL."
            }
        }
    }

    /// Builds the request URL from `host` and `subPath`.
    ///
    /// Always uses HTTPS. The one exception is a loopback host typed with an explicit
    /// `http://` prefix, so local proxies such as Ollama or LM Studio still work.
    func endpointURL() throws -> URL {
        var host = self.host.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = "https"

        if host.lowercased().hasPrefix("https://") {
            host = String(host.dropFirst("https://".count))
        } else if host.lowercased().hasPrefix("http://") {
            host = String(host.dropFirst("http://".count))
            scheme = "http"
        }
        while host.hasSuffix("/") { host.removeLast() }

        guard !host.isEmpty else { throw EndpointError.emptyHost }
        guard !host.contains("/"), !host.contains(" ") else { throw EndpointError.invalidHost }

        var components = URLComponents()
        let parts = host.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let hostname = String(parts[0])
        guard !hostname.isEmpty else { throw EndpointError.invalidHost }
        components.host = hostname
        if parts.count == 2 {
            guard let port = Int(parts[1]), (1...65535).contains(port) else { throw EndpointError.invalidHost }
            components.port = port
        }

        let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
        components.scheme = (scheme == "http" && loopbackHosts.contains(hostname.lowercased())) ? "http" : "https"

        var path = subPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.hasPrefix("/") { path = "/" + path }
        components.path = path

        guard let url = components.url else { throw EndpointError.invalidURL }
        return url
    }
}
