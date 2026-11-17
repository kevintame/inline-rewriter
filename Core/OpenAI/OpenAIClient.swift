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

    /// Runs `prompt` against the provider saved in Settings.
    ///
    /// Settings are read here, on the main actor where the UI edits them, and passed on
    /// as values. The Keychain read and the request then run off the main thread.
    @MainActor
    func complete(prompt: String) async throws -> String {
        let config = settings.config(for: .openAI)
        let instructions = settings.baseAIInstructions
        return try await send(prompt: prompt, instructions: instructions, config: config, apiKey: nil)
    }

    /// Verifies that `config` and `apiKey` can complete a request, without saving either.
    /// Settings calls this with its unsaved draft so the user can check before committing.
    @MainActor
    func testConnection(config: ModelProviderConfig, apiKey: String) async throws {
        let instructions = settings.baseAIInstructions
        _ = try await send(prompt: "Reply with the single word OK.", instructions: instructions, config: config, apiKey: apiKey)
    }

    /// `apiKey` of `nil` means "use the saved key".
    private nonisolated func send(prompt: String,
                                  instructions: String,
                                  config: ModelProviderConfig,
                                  apiKey suppliedKey: String?) async throws -> String {
        let rawKey = try suppliedKey ?? keychain.readString(account: ModelProviderID.openAI.keychainAccount) ?? ""
        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
                .init(role: "system", content: instructions),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenAIError.timeout
        } catch let error as URLError where error.code != .cancelled {
            // Offline, DNS, TLS, connection refused. Cancellation is left as it is so
            // callers can tell a cancelled request from a failed one.
            throw OpenAIError.network(Self.describe(error))
        }

        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }

        // Some servers echo the submitted credential in their error text.
        func providerMessage() -> String? {
            (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?
                .message
                .replacingOccurrences(of: apiKey, with: "[redacted]")
        }

        guard (200...299).contains(http.statusCode) else {
            if let message = providerMessage() {
                throw OpenAIError.api(message: message)
            }
            throw OpenAIError.http(status: http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(ChatCompletionsResponse.self, from: data) else {
            // A success status with an unexpected body: an error envelope from a proxy,
            // an HTML page from a captive portal, a streamed reply.
            if let message = providerMessage() {
                throw OpenAIError.api(message: message)
            }
            throw OpenAIError.invalidResponse
        }

        let choice = decoded.choices.first
        if choice?.finishReason == "content_filter" { throw OpenAIError.contentFiltered }

        let text = choice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { throw OpenAIError.emptyResult }

        // A reply cut off by the token limit looks like a normal one. Replacing the
        // selection with it would silently lose the end of the user's text.
        if choice?.finishReason == "length" { throw OpenAIError.truncated }
        return text
    }
}

private extension OpenAIClient {
    /// A sentence for the failures a user can act on. `URLError.localizedDescription` is not
    /// used: depending on how the error was produced it can be a raw domain-and-code dump.
    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return "You appear to be offline."
        case .cannotFindHost, .dnsLookupFailed:
            return "The host could not be found. Check the host in Settings → Models."
        case .cannotConnectToHost:
            return "The server refused the connection. Check the host and port in Settings → Models."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return "A secure connection could not be established."
        default:
            return "The request failed (network error \(error.code.rawValue))."
        }
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
        /// Absent on some compatible servers; treated as a normal finish.
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Codable {
        let role: String?
        let content: String?
    }
}

/// Error envelope. OpenAI sends `{"error": {"message": "..."}}`; some compatible servers
/// send `{"error": "..."}`.
private struct OpenAIErrorResponse: Decodable {
    let message: String

    private enum CodingKeys: String, CodingKey { case error }
    private struct APIError: Decodable { let message: String }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let detail = try? container.decode(APIError.self, forKey: .error) {
            message = detail.message
        } else {
            message = try container.decode(String.self, forKey: .error)
        }
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
    case truncated
    case contentFiltered
    case timeout
    case network(String)

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
        case .truncated:
            return "The reply was cut off before it finished (length limit). Try a shorter selection or a model with a larger output limit."
        case .contentFiltered:
            return "The provider's content filter blocked the reply."
        case .timeout:
            return "Request timed out. Check your network connection and try again."
        case .network(let reason):
            return "Couldn't reach the server. \(reason)"
        }
    }
}
