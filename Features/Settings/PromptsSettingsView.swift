import SwiftUI

struct PromptsSettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var editingTransformationID: UUID?
    @State private var transformationToDelete: TextTransformation?
    @State private var showDeleteConfirmation = false

    /// Wrapper to satisfy `.sheet(item:)` which requires `Identifiable`.
    private struct EditingItem: Identifiable {
        let id: UUID
    }

    private var editingItem: Binding<EditingItem?> {
        Binding(
            get: { editingTransformationID.map { EditingItem(id: $0) } },
            set: { editingTransformationID = $0?.id }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Prompts")
                    .font(.headline)
                Spacer()
                Button(action: addPrompt) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a new prompt")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // List
            List {
                ForEach(settings.transformations) { transformation in
                    HStack {
                        Text(transformation.name)
                            .lineLimit(1)

                        Spacer()

                        Button(action: { editPrompt(id: transformation.id) }) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Edit")

                        Button(action: { confirmDelete(transformation) }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete")
                    }
                    .padding(.vertical, 2)
                }
                .onMove(perform: movePrompts)
            }
        }
        .sheet(item: editingItem) { item in
            if let idx = settings.transformations.firstIndex(where: { $0.id == item.id }) {
                PromptEditSheet(
                    transformation: $settings.transformations[idx],
                    onSave: { editingTransformationID = nil },
                    onCancel: { editingTransformationID = nil }
                )
            }
        }
        .alert("Delete Prompt?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let t = transformationToDelete {
                    settings.transformations.removeAll { $0.id == t.id }
                }
            }
        } message: {
            if let t = transformationToDelete {
                Text("Are you sure you want to delete '\(t.name)'? This cannot be undone.")
            }
        }
    }

    private func addPrompt() {
        let t = TextTransformation(
            name: "New prompt",
            promptTemplate: "Do something to this text:\n\n{{text}}"
        )
        settings.transformations.append(t)
        editingTransformationID = t.id
    }

    private func editPrompt(id: UUID) {
        editingTransformationID = id
    }

    private func confirmDelete(_ transformation: TextTransformation) {
        transformationToDelete = transformation
        showDeleteConfirmation = true
    }

    private func movePrompts(from source: IndexSet, to destination: Int) {
        settings.transformations.move(fromOffsets: source, toOffset: destination)
    }
}
