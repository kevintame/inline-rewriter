import SwiftUI

struct TransformationsSettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var selection: TextTransformation.ID?
    @State private var draftName: String = ""
    @State private var draftPrompt: String = ""
    @State private var validationError: String?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Transformations")
                        .font(.headline)
                    Spacer()
                    Button("Add") { add() }
                }

                List(selection: $selection) {
                    ForEach(settings.transformations) { t in
                        Text(t.name)
                            .tag(t.id)
                    }
                    .onDelete(perform: delete)
                }
                .frame(minWidth: 220)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Edit")
                    .font(.headline)

                TextField("Name", text: $draftName)
                TextEditor(text: $draftPrompt)
                    .font(.body)
                    .frame(minHeight: 220)

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
                    Button("Save") { save() }
                        .disabled(selection == nil)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: selection) { _, _ in
            loadSelection()
        }
        .onAppear { loadSelection() }
    }

    private func loadSelection() {
        guard let selection,
              let t = settings.transformations.first(where: { $0.id == selection }) else {
            draftName = ""
            draftPrompt = ""
            validationError = nil
            return
        }
        draftName = t.name
        draftPrompt = t.promptTemplate
        validationError = nil
    }

    private func add() {
        var t = TextTransformation(name: "New transformation", promptTemplate: "Do something to this text:\n\n{{text}}")
        settings.transformations.append(t)
        selection = t.id
    }

    private func save() {
        guard let selection,
              let idx = settings.transformations.firstIndex(where: { $0.id == selection }) else { return }

        if settings.transformations[idx].isPreset {
            // Presets are locked (name/prompt) in this scaffold.
            return
        }

        // Create temporary transformation to validate
        let temp = TextTransformation(
            id: settings.transformations[idx].id,
            name: draftName,
            promptTemplate: draftPrompt,
            isPreset: false
        )

        do {
            try temp.validate()
            validationError = nil
            settings.transformations[idx].name = draftName
            settings.transformations[idx].promptTemplate = draftPrompt
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        // Prevent deleting presets.
        let idsToDelete = offsets.map { settings.transformations[$0].id }
        settings.transformations.removeAll { t in
            idsToDelete.contains(t.id) && !t.isPreset
        }
        if let selection, !settings.transformations.contains(where: { $0.id == selection }) {
            self.selection = settings.transformations.first?.id
        }
    }
}
