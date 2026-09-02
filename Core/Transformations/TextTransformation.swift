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

    /// One-line version of the template for lists: the `{{text}}` placeholder removed and
    /// whitespace collapsed, so a multi-line template reads as a sentence.
    var promptSummary: String {
        promptTemplate
            .replacingOccurrences(of: "{{text}}", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func validate() throws {
        guard promptTemplate.contains("{{text}}") else {
            throw ValidationError.missingPlaceholder
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.emptyName
        }
    }

    enum ValidationError: LocalizedError {
        case missingPlaceholder
        case emptyName

        var errorDescription: String? {
            switch self {
            case .missingPlaceholder:
                return "Prompt template must contain {{text}} placeholder."
            case .emptyName:
                return "Transformation name cannot be empty."
            }
        }
    }

    static let presetRewrite = TextTransformation(
        name: "Rewrite",
        promptTemplate: "Rewrite the following text to be clearer and more concise, preserving meaning:\n\n{{text}}",
        isPreset: true
    )
}
