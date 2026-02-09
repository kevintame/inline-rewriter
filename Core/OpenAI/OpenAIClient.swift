import Foundation

/// Thin OpenAI API wrapper (Chat Completions).
///
/// NOTE: This is scaffolding. For production you’ll want:
/// - streaming
/// - retries/backoff
/// - structured errors
/// - telemetry
final class OpenAIClient {
    private let settings: SettingsStore
    private let keychain: KeychainStoring

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0  // 30 seconds per request
        config.timeoutIntervalForResource = 60.0 // 60 seconds total
        return URLSession(configuration: config)
    }()

    init(settings: SettingsStore, keychain: KeychainStoring) {
        self.settings = settings
        self.keychain = keychain
    }

    func complete(prompt: String) async throws -> String {
        let apiKey = try keychain.readString(account: AppConstants.KeychainAccounts.openAIKey) ?? ""
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionsRequest(
            model: settings.selectedModel.rawValue,
            messages: [
                .init(role: "system", content: "You are a helpful writing assistant."),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as NSError where error.code == NSURLErrorTimedOut {
            throw OpenAIError.timeout
        }

        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        if !(200...299).contains(http.statusCode) {
            // Try to parse OpenAI error payload.
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.api(message: apiError.error.message)
            }
            throw OpenAIError.http(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let text = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { throw OpenAIError.emptyResult }
        return text
    }
}

// MARK: - DTOs

private struct ChatCompletionsRequest: Codable {
    let model: String
    let messages: [Message]

    struct Message: Codable {
        let role: String
        let content: String
    }
}

private struct ChatCompletionsResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let role: String?
        let content: String
    }
}

private struct OpenAIErrorResponse: Codable {
    let error: APIError

    struct APIError: Codable {
        let message: String
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case missingAPIKey
    case http(status: Int)
    case api(message: String)
    case invalidResponse
    case emptyResult
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI API key. Set it in Settings."
        case .http(let status):
            return "OpenAI request failed (HTTP \(status))."
        case .api(let message):
            return message
        case .invalidResponse:
            return "Invalid response from OpenAI."
        case .emptyResult:
            return "OpenAI returned an empty result."
        case .timeout:
            return "Request timed out. Please check your network connection and try again."
        }
    }
}
