import SwiftUI

/// Popover showing transformed text.
struct PreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)

            ScrollView {
                Text(viewModel.outputText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(width: 520, height: 260)

            HStack {
                Button("Cancel") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Retry") { viewModel.retry() }

                Button("Replace") { viewModel.replace() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 36: // Return/Enter
                    viewModel.replace()
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
