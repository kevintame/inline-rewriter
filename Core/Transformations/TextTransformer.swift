import Foundation

/// Domain service that applies a transformation using the configured model client.
final class TextTransformer {
    private let openAI: OpenAIClient

    init(openAI: OpenAIClient) {
        self.openAI = openAI
    }

    func run(transformation: TextTransformation, input: String) async throws -> String {
        let prompt = transformation.renderPrompt(with: input)
        return try await openAI.complete(prompt: prompt)
    }
}
