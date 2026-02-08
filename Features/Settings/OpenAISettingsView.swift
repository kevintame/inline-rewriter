import SwiftUI

struct OpenAISettingsView: View {
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring
    let alertPresenter: AlertPresenter

    @State private var apiKey: String = ""
    @State private var statusText: String?

    var body: some View {
        Form {
            Section("API Key") {
                SecureField("OpenAI API key", text: $apiKey)

                HStack {
                    Button("Load") { load() }
                    Button("Save") { save() }
                    Button("Clear") { clear() }
                    Spacer()
                    if let statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Model") {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(OpenAIModel.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        do {
            apiKey = try keychain.readString(account: "openai_api_key") ?? ""
            statusText = "Loaded"
        } catch {
            statusText = "Load failed"
            alertPresenter.showError(title: "Load failed", message: error.localizedDescription)
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "Save failed"
            alertPresenter.showError(title: "API Key Required", message: "Enter your OpenAI API key before saving.")
            return
        }

        do {
            try keychain.writeString(trimmed, account: "openai_api_key")
            apiKey = trimmed
            statusText = "Saved"
        } catch {
            statusText = "Save failed"
            alertPresenter.showError(title: "Save failed", message: error.localizedDescription)
        }
    }

    private func clear() {
        do {
            try keychain.delete(account: "openai_api_key")
            apiKey = ""
            statusText = "Cleared"
        } catch {
            statusText = "Clear failed"
            alertPresenter.showError(title: "Clear failed", message: error.localizedDescription)
        }
    }
}
