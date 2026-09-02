import SwiftUI

/// First-run screen. Walks through the two things the app cannot work without:
/// Accessibility permission and an API key.
struct WelcomeView: View {
    @ObservedObject var permission: AccessibilityPermissionMonitor
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring
    let onOpenSettings: () -> Void
    let onFinish: () -> Void

    @State private var hasAPIKey = false

    var body: some View {
        VStack(spacing: 20) {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            Text("Inline Rewriter")
                .font(.system(size: 24, weight: .bold))

            Text("Select text in any app, press \(settings.hotkey.displayString), choose a prompt, and replace the selection with the result.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            stepRow(
                done: permission.isTrusted,
                title: "Allow Accessibility access",
                detail: permission.isTrusted
                    ? "Granted."
                    : "Needed to read the selected text and paste the result. Nothing else is read or recorded."
            ) {
                if !permission.isTrusted {
                    Button("Grant Access") { permission.requestAccess() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") { permission.openSystemSettings() }
                }
            }

            stepRow(
                done: hasAPIKey,
                title: "Add your OpenAI API key",
                detail: hasAPIKey ? "Saved in your Keychain." : "Stored in your Keychain and sent only to the endpoint you configure."
            ) {
                if hasAPIKey {
                    Button("Open Settings") { onOpenSettings() }
                } else {
                    Button("Add Key…") { onOpenSettings() }
                        .buttonStyle(.borderedProminent)
                }
            }

            Spacer(minLength: 0)

            Button(permission.isTrusted && hasAPIKey ? "Get Started" : "Skip for Now") { onFinish() }
                .keyboardShortcut(.defaultAction)

            Text("Made with \u{1FA77} by Kevin")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 460, height: 520)
        .onAppear {
            permission.beginObserving()
            refreshAPIKey()
        }
        .onDisappear {
            permission.endObserving()
        }
    }

    @ViewBuilder
    private func stepRow<Actions: View>(done: Bool, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack { actions() }
                }
                Spacer(minLength: 0)
            }
            .padding(6)
        }
    }

    private func refreshAPIKey() {
        let key = (try? keychain.readString(account: ModelProviderID.openAI.keychainAccount)) ?? nil
        hasAPIKey = !(key ?? "").isEmpty
    }
}
