import SwiftUI

struct PromptEditSheet: View {
    @Binding var transformation: TextTransformation
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var draftName: String = ""
    @State private var draftPrompt: String = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Prompt")
                .font(.headline)

            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $draftPrompt)
                .font(.body)
                .frame(minHeight: 150)
                .border(Color.secondary.opacity(0.3))

            Text("Use {{text}} as a placeholder for the selected text.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .onAppear {
            draftName = transformation.name
            draftPrompt = transformation.promptTemplate
        }
    }

    private func save() {
        let temp = TextTransformation(
            id: transformation.id,
            name: draftName,
            promptTemplate: draftPrompt,
            isPreset: transformation.isPreset
        )

        do {
            try temp.validate()
            validationError = nil
            transformation.name = draftName
            transformation.promptTemplate = draftPrompt
            onSave()
        } catch {
            validationError = error.localizedDescription
        }
    }
}
