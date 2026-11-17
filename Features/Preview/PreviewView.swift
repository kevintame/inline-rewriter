import SwiftUI

/// Popover showing transformed text, editable before it is pasted back.
struct PreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel
    @State private var showOriginal = false

    private static let width: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Preview")
                    .font(.headline)
                Text("· \(viewModel.transformationName)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            DisclosureGroup("Original", isExpanded: $showOriginal) {
                ScrollView {
                    Text(viewModel.inputText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(height: 100)
                .border(Color.secondary.opacity(0.3))
            }

            TextEditor(text: $viewModel.outputText)
                .font(.body)
                .frame(height: showOriginal ? 170 : 260)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Cancel") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)

                Text("↩ replaces · ⌥↩ new line")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Copy") { viewModel.copy() }
                    .disabled(viewModel.isOutputEmpty)
                    .help("Copy the result to the clipboard and close without replacing")

                Button("Retry") { viewModel.retry() }

                Button("Replace") { viewModel.replace() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isOutputEmpty)
            }
        }
        .frame(width: Self.width)
        .padding(14)
    }
}
