import SwiftUI

/// Popover view listing transformations.
struct TransformationPickerView: View {
    @ObservedObject var viewModel: TransformationPickerViewModel
    @State private var eventMonitor: Any?

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

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(viewModel.transformations.enumerated()), id: \.element.id) { index, transformation in
                        TransformationRow(
                            transformation: transformation,
                            isSelected: index == viewModel.selectedIndex,
                            isDisabled: viewModel.isBusy
                        ) {
                            viewModel.run(transformation)
                        }
                    }
                }
                .padding(.vertical, 4)
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
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125: // Down arrow
                    viewModel.selectNext()
                    return nil
                case 126: // Up arrow
                    viewModel.selectPrevious()
                    return nil
                case 36: // Return/Enter
                    viewModel.runSelected()
                    return nil
                case 53: // Escape
                    viewModel.cancel()
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct TransformationRow: View {
    let transformation: TextTransformation
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Text(transformation.name)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(transformation.promptTemplate)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
