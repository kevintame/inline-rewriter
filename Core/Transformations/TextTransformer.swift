import Foundation

/// Domain service that applies a transformation using OpenAI.
final class TextTransformer {
    private let openAI: OpenAIClient
    private let settings: SettingsStore

    init(openAI: OpenAIClient, settings: SettingsStore) {
        self.openAI = openAI
        self.settings = settings
    }

    func run(transformation: TextTransformation, input: String) async throws -> String {
        let prompt = transformation.renderPrompt(with: input)
        return try await openAI.complete(prompt: prompt)
    }
}
