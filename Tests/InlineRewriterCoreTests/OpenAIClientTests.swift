import Foundation
import Testing
@testable import InlineRewriterCore

@Suite(.serialized)
struct OpenAIClientTests {
    private let apiKeyAccount = ModelProviderID.openAI.keychainAccount

    private func makeClient(apiKey: String? = "sk-test", configure: ((SettingsStore) -> Void)? = nil) -> (OpenAIClient, SettingsStore) {
        StubURLProtocol.reset()
        let settings = SettingsStore(defaults: makeTestDefaults())
        configure?(settings)
        let keychain = InMemoryKeychain(values: apiKey.map { [apiKeyAccount: $0] } ?? [:])
        let client = OpenAIClient(settings: settings, keychain: keychain, session: StubURLProtocol.makeSession())
        return (client, settings)
    }

    private func respond(status: Int, json: String) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    private static let successBody = #"{"choices":[{"message":{"role":"assistant","content":"  Rewritten text.\n"}}]}"#

    @Test func returnsTrimmedContentAndSendsConfiguredRequest() async throws {
        let (client, settings) = makeClient { settings in
            settings.baseAIInstructions = "Be terse."
        }
        StubURLProtocol.handler = respond(status: 200, json: Self.successBody)

        let result = try await client.complete(prompt: "Fix: hello")
        #expect(result == "Rewritten text.")

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request)) as? [String: Any]
        #expect(body?["model"] as? String == settings.config(for: .openAI).defaultModel)
        let messages = body?["messages"] as? [[String: String]]
        #expect(messages == [
            ["role": "system", "content": "Be terse."],
            ["role": "user", "content": "Fix: hello"]
        ])
    }

    @Test func usesHostPathAndModelFromSettings() async throws {
        let (client, _) = makeClient { settings in
            let idx = settings.providerConfigs.firstIndex { $0.providerID == .openAI }!
            settings.providerConfigs[idx].host = "proxy.example.com"
            settings.providerConfigs[idx].subPath = "/openai/v1/chat/completions"
            settings.providerConfigs[idx].defaultModel = "my-custom-model"
        }
        StubURLProtocol.handler = respond(status: 200, json: Self.successBody)

        _ = try await client.complete(prompt: "x")

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.url?.absoluteString == "https://proxy.example.com/openai/v1/chat/completions")
        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request)) as? [String: Any]
        #expect(body?["model"] as? String == "my-custom-model")
    }

    @Test func missingAPIKeyFailsBeforeAnyRequest() async {
        let (client, _) = makeClient(apiKey: nil)
        StubURLProtocol.handler = respond(status: 200, json: Self.successBody)

        await #expect(throws: OpenAIError.missingAPIKey) {
            try await client.complete(prompt: "x")
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func blankAPIKeyCountsAsMissing() async {
        let (client, _) = makeClient(apiKey: "   ")
        await #expect(throws: OpenAIError.missingAPIKey) {
            try await client.complete(prompt: "x")
        }
    }

    @Test func invalidEndpointIsReportedWithoutARequest() async {
        let (client, _) = makeClient { settings in
            let idx = settings.providerConfigs.firstIndex { $0.providerID == .openAI }!
            settings.providerConfigs[idx].host = ""
        }
        StubURLProtocol.handler = respond(status: 200, json: Self.successBody)

        await #expect(throws: OpenAIError.invalidEndpoint(ModelProviderConfig.EndpointError.emptyHost.localizedDescription)) {
            try await client.complete(prompt: "x")
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func apiErrorPayloadIsSurfaced() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = respond(status: 401, json: #"{"error":{"message":"Incorrect API key provided.","type":"invalid_request_error"}}"#)

        await #expect(throws: OpenAIError.api(message: "Incorrect API key provided.")) {
            try await client.complete(prompt: "x")
        }
    }

    @Test func nonJSONFailureFallsBackToStatusCode() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = respond(status: 502, json: "Bad Gateway")

        await #expect(throws: OpenAIError.http(status: 502)) {
            try await client.complete(prompt: "x")
        }
    }

    @Test func emptyContentIsAnError() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = respond(status: 200, json: #"{"choices":[{"message":{"role":"assistant","content":"   "}}]}"#)

        await #expect(throws: OpenAIError.emptyResult) {
            try await client.complete(prompt: "x")
        }
    }

    @Test func timeoutIsMappedToFriendlyError() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }

        await #expect(throws: OpenAIError.timeout) {
            try await client.complete(prompt: "x")
        }
    }

    @Test func testConnectionUsesGivenConfigAndKeyNotSavedOnes() async throws {
        let (client, _) = makeClient(apiKey: "sk-saved")
        StubURLProtocol.handler = respond(status: 200, json: Self.successBody)

        var draft = ModelProviderConfig.defaultConfig(for: .openAI)
        draft.host = "proxy.example.com"
        draft.defaultModel = "draft-model"
        try await client.testConnection(config: draft, apiKey: " sk-draft ")

        let request = try #require(StubURLProtocol.recordedRequests.first)
        #expect(request.url?.absoluteString == "https://proxy.example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-draft")
        let body = try JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request)) as? [String: Any]
        #expect(body?["model"] as? String == "draft-model")
    }

    @Test func testConnectionRejectsBlankKeyWithoutSendingRequest() async {
        let (client, _) = makeClient(apiKey: "sk-saved")
        StubURLProtocol.handler = respond(status: 200, json: Self.successBody)

        await #expect(throws: OpenAIError.missingAPIKey) {
            try await client.testConnection(config: .defaultConfig(for: .openAI), apiKey: "   ")
        }
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func testConnectionSurfacesAPIErrors() async {
        let (client, _) = makeClient()
        StubURLProtocol.handler = respond(status: 401, json: #"{"error":{"message":"Incorrect API key provided"}}"#)

        await #expect(throws: OpenAIError.api(message: "Incorrect API key provided")) {
            try await client.testConnection(config: .defaultConfig(for: .openAI), apiKey: "sk-bad")
        }
    }
}
