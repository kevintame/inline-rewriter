import Foundation

/// A user-visible transformation.
/// `promptTemplate` should include `{{text}}` where the selected text should be inserted.
struct TextTransformation: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var promptTemplate: String

    /// Presets are not deletable in UI.
    var isPreset: Bool

    init(id: UUID = UUID(), name: String, promptTemplate: String, isPreset: Bool = false) {
        self.id = id
        self.name = name
        self.promptTemplate = promptTemplate
        self.isPreset = isPreset
    }

    func renderPrompt(with text: String) -> String {
        promptTemplate.replacingOccurrences(of: "{{text}}", with: text)
    }

    static let presetRewrite = TextTransformation(
        name: "Rewrite",
        promptTemplate: "Rewrite the following text to be clearer and more concise, preserving meaning:\n\n{{text}}",
        isPreset: true
    )
}
