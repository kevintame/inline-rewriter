import SwiftUI

/// Popover view listing transformations.
struct TransformationPickerView: View {
    @ObservedObject var viewModel: TransformationPickerViewModel
    @State private var eventMonitor: Any?
    @State private var listContentHeight: CGFloat = 0

    private static let width: CGFloat = 420
    private static let maxListHeight: CGFloat = 240

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
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.errorNeedsSettings {
                        Spacer(minLength: 0)
                        Button("Open Settings…") { viewModel.openSettings() }
                            .controlSize(.small)
                    }
                }
            }

            ScrollView {
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
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ListContentHeightKey.self, value: proxy.size.height)
                    }
                )
            }
            .onPreferenceChange(ListContentHeightKey.self) { listContentHeight = $0 }
            // Size to the rows, scrolling only once they outgrow the cap.
            .frame(width: Self.width, height: min(max(listContentHeight, 44), Self.maxListHeight))
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
                case 36, 76: // Return, keypad Enter
                    viewModel.runSelected()
                    return nil
                case 53: // Escape
                    viewModel.cancel()
                    return nil
                default:
                    break
                }

                // Plain 1–9 picks that row directly.
                let modifiers = event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .subtracting([.numericPad, .function])
                if modifiers.isEmpty,
                   let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
                   (1...9).contains(digit) {
                    viewModel.run(at: digit - 1)
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private struct ListContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
