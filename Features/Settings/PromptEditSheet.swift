import SwiftUI

/// Edits a copy of a transformation and hands the result back on Save, so Cancel leaves the
/// store untouched whether the prompt is new or existing.
struct PromptEditSheet: View {
    let transformation: TextTransformation
    let isNew: Bool
    let onSave: (TextTransformation) -> Void
    let onCancel: () -> Void

    @State private var draftName: String
    @State private var draftPrompt: String

    init(transformation: TextTransformation,
         isNew: Bool,
         onSave: @escaping (TextTransformation) -> Void,
         onCancel: @escaping () -> Void) {
        self.transformation = transformation
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        _draftName = State(initialValue: transformation.name)
        _draftPrompt = State(initialValue: transformation.promptTemplate)
    }

    private var draft: TextTransformation {
        TextTransformation(
            id: transformation.id,
            name: draftName,
            promptTemplate: draftPrompt,
            isPreset: transformation.isPreset
        )
    }

    /// Nil when the draft can be saved.
    private var validationError: String? {
        do {
            try draft.validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Prompt" : "Edit Prompt")
                .font(.headline)

            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $draftPrompt)
                .font(.body)
                .frame(minHeight: 150)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Text("Use {{text}} where the selected text should go.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !draftPrompt.contains("{{text}}") {
                    Button("Add {{text}}") { appendPlaceholder() }
                        .controlSize(.small)
                }
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
            }
        }
        .padding()
        .frame(width: 450, height: 370)
    }

    /// TextEditor exposes no insertion point, so the placeholder goes on its own line at the
    /// end, which is where nearly every template wants it anyway.
    private func appendPlaceholder() {
        var text = draftPrompt
        while let last = text.last, last.isNewline || last == " " {
            text.removeLast()
        }
        draftPrompt = text.isEmpty ? "{{text}}" : text + "\n\n{{text}}"
    }
}
