import Foundation
import Testing
@testable import InlineRewriterCore

struct ModelProviderConfigTests {
    private func config(host: String, path: String = "/v1/chat/completions") -> ModelProviderConfig {
        var c = ModelProviderConfig.defaultConfig(for: .openAI)
        c.host = host
        c.subPath = path
        return c
    }

    @Test func defaultOpenAIEndpoint() throws {
        let url = try ModelProviderConfig.defaultConfig(for: .openAI).endpointURL()
        #expect(url.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test func stripsSchemeAndTrailingSlashFromHost() throws {
        #expect(try config(host: "https://proxy.example.com/").endpointURL().absoluteString == "https://proxy.example.com/v1/chat/completions")
    }

    @Test func httpIsUpgradedToHTTPSForRemoteHosts() throws {
        #expect(try config(host: "http://proxy.example.com").endpointURL().scheme == "https")
    }

    @Test func httpIsKeptForLoopbackHosts() throws {
        let url = try config(host: "http://localhost:11434", path: "v1/chat/completions").endpointURL()
        #expect(url.absoluteString == "http://localhost:11434/v1/chat/completions")
    }

    @Test func loopbackWithoutExplicitHTTPStaysHTTPS() throws {
        #expect(try config(host: "localhost:8080").endpointURL().scheme == "https")
    }

    @Test func pathGetsLeadingSlash() throws {
        #expect(try config(host: "api.openai.com", path: "v1/chat/completions").endpointURL().path == "/v1/chat/completions")
    }

    @Test func emptyHostIsRejected() {
        #expect(throws: ModelProviderConfig.EndpointError.emptyHost) {
            try config(host: "   ").endpointURL()
        }
    }

    @Test func hostContainingPathIsRejected() {
        #expect(throws: ModelProviderConfig.EndpointError.invalidHost) {
            try config(host: "api.openai.com/v1").endpointURL()
        }
    }

    @Test func nonNumericPortIsRejected() {
        #expect(throws: ModelProviderConfig.EndpointError.invalidHost) {
            try config(host: "localhost:abc").endpointURL()
        }
    }

    @Test func onlyOpenAIIsSupportedForNow() {
        #expect(ModelProviderID.supported == [.openAI])
        #expect(ModelProviderID.openAI.isSupported)
        #expect(!ModelProviderID.anthropic.isSupported)
    }
}
