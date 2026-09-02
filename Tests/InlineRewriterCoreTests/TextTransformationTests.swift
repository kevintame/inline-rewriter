import Testing
@testable import InlineRewriterCore

struct TextTransformationTests {
    @Test func renderPromptSubstitutesPlaceholder() {
        let t = TextTransformation(name: "Shout", promptTemplate: "Shout this:\n\n{{text}}")
        #expect(t.renderPrompt(with: "hello") == "Shout this:\n\nhello")
    }

    @Test func renderPromptReplacesEveryOccurrence() {
        let t = TextTransformation(name: "Twice", promptTemplate: "{{text}} and again {{text}}")
        #expect(t.renderPrompt(with: "x") == "x and again x")
    }

    @Test func validateAcceptsWellFormedTransformation() throws {
        try TextTransformation(name: "Fix", promptTemplate: "Fix: {{text}}").validate()
    }

    @Test func validateRejectsMissingPlaceholder() {
        let t = TextTransformation(name: "Broken", promptTemplate: "No placeholder here")
        #expect(throws: TextTransformation.ValidationError.missingPlaceholder) {
            try t.validate()
        }
    }

    @Test func validateRejectsBlankName() {
        let t = TextTransformation(name: "   ", promptTemplate: "{{text}}")
        #expect(throws: TextTransformation.ValidationError.emptyName) {
            try t.validate()
        }
    }

    @Test func presetIsValidAndMarkedPreset() throws {
        try TextTransformation.presetRewrite.validate()
        #expect(TextTransformation.presetRewrite.isPreset)
    }
}
