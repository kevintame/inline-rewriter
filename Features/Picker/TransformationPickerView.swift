import SwiftUI

/// Popover view listing transformations.
struct TransformationPickerView: View {
    @ObservedObject var viewModel: TransformationPickerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transform")
                    .font(.headline)
                Spacer()
                Button("Cancel") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List(viewModel.transformations) { t in
                Button {
                    viewModel.run(t)
                } label: {
                    VStack(alignment: .leading) {
                        Text(t.name)
                        Text(t.promptTemplate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
                .disabled(viewModel.isBusy)
            }
            .frame(width: 420, height: 240)

            if viewModel.isBusy {
                HStack {
                    ProgressView()
                    Text("Working…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }
}
