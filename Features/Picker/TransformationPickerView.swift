import SwiftUI

/// Lists the prompts for the captured text. Shown first when the shortcut is pressed.
struct TransformationPickerView: View {
    @ObservedObject var viewModel: TransformationPickerViewModel

    private static let width: CGFloat = 420
    /// Up to this many prompts are laid out at their natural height, so the panel is
    /// exactly as tall as its content. Longer lists scroll in a fixed-height area.
    private static let maxUnscrolledRows = 5
    private static let scrollingListHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Transform")
                    .font(.headline)
                Spacer()
                if viewModel.isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
            }

            // What was captured, so a wrong selection is obvious before the model runs.
            HStack(spacing: 8) {
                Text(viewModel.inputSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(viewModel.inputLengthDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if let error = viewModel.errorMessage {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Wraps within the panel's width; a long provider message must not
                    // stretch the panel or push the buttons off its edge.
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if viewModel.errorNeedsSettings {
                        Spacer(minLength: 0)
                        Button("Open Settings…") { viewModel.openSettings() }
                            .controlSize(.small)
                    }
                }
            }

            list
        }
        // One fixed width for the whole picker, so nothing in it can widen the panel.
        .frame(width: Self.width)
        .padding(14)
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.transformations.count <= Self.maxUnscrolledRows {
            rows
        } else {
            ScrollView { rows }
                .frame(height: Self.scrollingListHeight)
        }
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(Array(viewModel.transformations.enumerated()), id: \.element.id) { index, transformation in
                TransformationRow(
                    transformation: transformation,
                    shortcutNumber: index < 9 ? index + 1 : nil,
                    isSelected: index == viewModel.selectedIndex,
                    isDisabled: viewModel.isBusy,
                    onHover: { viewModel.selectedIndex = index },
                    action: { viewModel.run(at: index) }
                )
            }
        }
        .padding(.vertical, 4)
    }
}

struct TransformationRow: View {
    let transformation: TextTransformation
    let shortcutNumber: Int?
    let isSelected: Bool
    let isDisabled: Bool
    let onHover: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transformation.name)
                        .foregroundStyle(isSelected ? .white : .primary)
                    let summary = transformation.promptSummary
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if let shortcutNumber {
                    Text("\(shortcutNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.tertiary))
                        .frame(minWidth: 16, alignment: .trailing)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { inside in
            if inside && !isDisabled { onHover() }
        }
    }
}
