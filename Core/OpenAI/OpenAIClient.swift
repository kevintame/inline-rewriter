import Foundation

/// OpenAI Chat Completions client.
///
/// Endpoint and model come from the OpenAI provider config in Settings, so any
/// Chat-Completions-compatible server can be used by changing the host.
final class OpenAIClient {
    private let settings: SettingsStore
    private let keychain: KeychainStoring
    private let session: URLSession

    init(settings: SettingsStore, keychain: KeychainStoring, session: URLSession = OpenAIClient.makeSession()) {
        self.settings = settings
        self.keychain = keychain
        self.session = session
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }

    func complete(prompt: String) async throws -> String {
        let config = settings.config(for: .openAI)

        let apiKey = (try keychain.readString(account: ModelProviderID.openAI.keychainAccount) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }

        let url: URL
        do {
            url = try config.endpointURL()
        } catch {
            throw OpenAIError.invalidEndpoint(error.localizedDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ChatCompletionsRequest(
            model: config.defaultModel,
            messages: [
                .init(role: "system", content: settings.baseAIInstructions),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenAIError.timeout
        }

        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        if !(200...299).contains(http.statusCode) {
            if let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.api(message: apiError.error.message)
            }
            throw OpenAIError.http(status: http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        let content: String?
    }
}

private struct OpenAIErrorResponse: Codable {
    let error: APIError

    struct APIError: Codable {
        let message: String
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidEndpoint(String)
    case http(status: Int)
    case api(message: String)
    case invalidResponse
    case emptyResult
    case timeout

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OpenAI API key. Add it in Settings → Models."
        case .invalidEndpoint(let reason):
            return "The OpenAI endpoint in Settings → Models is invalid. \(reason)"
        case .http(let status):
            return "OpenAI request failed (HTTP \(status))."
        case .api(let message):
            return message
        case .invalidResponse:
            return "Invalid response from OpenAI."
        case .emptyResult:
            return "OpenAI returned an empty result."
        case .timeout:
            return "Request timed out. Check your network connection and try again."
        }
    }
}
