import SwiftUI

/// Popover showing transformed text.
struct PreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)

            TextEditor(text: $viewModel.outputText)
                .font(.body)
                .frame(width: 520, height: 260)

            HStack {
                Button("Cancel") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Retry") { viewModel.retry() }

                Button("Replace") { viewModel.replace() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }
}
