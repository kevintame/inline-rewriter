import SwiftUI

struct PromptsSettingsView: View {
    @ObservedObject var settings: SettingsStore

    @State private var editor: EditorState?
    @State private var transformationToDelete: TextTransformation?
    @State private var showDeleteConfirmation = false

    /// What the edit sheet is working on. A new prompt lives only here until it is saved, so
    /// cancelling never leaves a placeholder row behind.
    private struct EditorState: Identifiable {
        let transformation: TextTransformation
        let isNew: Bool
        var id: UUID { transformation.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            systemInstructions
                .padding()

            Divider()

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

            List {
                ForEach(settings.transformations) { transformation in
                    promptRow(transformation)
                }
                .onMove(perform: movePrompts)
            }
        }
        .sheet(item: $editor) { state in
            PromptEditSheet(
                transformation: state.transformation,
                isNew: state.isNew,
                onSave: { saved in
                    if let idx = settings.transformations.firstIndex(where: { $0.id == saved.id }) {
                        settings.transformations[idx] = saved
                    } else {
                        settings.transformations.append(saved)
                    }
                    editor = nil
                },
                onCancel: { editor = nil }
            )
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

    // MARK: - Subviews

    /// Lives here rather than in General because it is part of what the model sees, alongside
    /// the prompts.
    private var systemInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System Instructions", systemImage: "text.quote")
                .font(.headline)

            Text("Sent with every request, before the prompt. Saved as you type.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $settings.baseAIInstructions)
                .font(.body)
                .frame(height: 64)
                .border(Color.secondary.opacity(0.3))
        }
    }

    private func promptRow(_ transformation: TextTransformation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transformation.name)
                    .lineLimit(1)
                let summary = transformation.promptSummary
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { edit(transformation) }) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")

            // Presets stay so there is always a working prompt; they can still be edited.
            if !transformation.isPreset {
                Button(action: { confirmDelete(transformation) }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { edit(transformation) }
    }

    // MARK: - Actions

    private func addPrompt() {
        let t = TextTransformation(
            name: "New prompt",
            promptTemplate: "Do something to this text:\n\n{{text}}"
        )
        editor = EditorState(transformation: t, isNew: true)
    }

    private func edit(_ transformation: TextTransformation) {
        editor = EditorState(transformation: transformation, isNew: false)
    }

    private func confirmDelete(_ transformation: TextTransformation) {
        transformationToDelete = transformation
        showDeleteConfirmation = true
    }

    private func movePrompts(from source: IndexSet, to destination: Int) {
        settings.transformations.move(fromOffsets: source, toOffset: destination)
    }
}
