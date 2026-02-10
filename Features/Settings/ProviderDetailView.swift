import SwiftUI

struct ProviderDetailView: View {
    let providerID: ModelProviderID
    @Binding var config: ModelProviderConfig
    let keychain: KeychainStoring
    let onSetDefaultVendor: () -> Void

    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var draftHost: String = ""
    @State private var draftSubPath: String = ""
    @State private var draftModel: String = ""
    @State private var draftIsDefault: Bool = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(providerID.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                // API Key
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("API Key")
                }

                // Host
                Section {
                    TextField("Host", text: $draftHost)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Host")
                }

                // Sub Path
                Section {
                    TextField("Sub Path", text: $draftSubPath)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Sub Path")
                }

                // Default Model
                Section {
                    Picker("Model", selection: $draftModel) {
                        ForEach(providerID.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } header: {
                    Text("Default Model")
                }

                // Default Vendor
                Section {
                    Toggle("Default Vendor", isOn: $draftIsDefault)
                        .toggleStyle(.switch)
                } header: {
                    Text("Default Vendor")
                } footer: {
                    Text("Only one provider can be the default vendor at a time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(action: save) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Spacer()
            }
        }
        .padding()
        .onAppear { loadDraft() }
        .onChange(of: providerID) { _ in loadDraft() }
    }

    private func loadDraft() {
        draftHost = config.host
        draftSubPath = config.subPath
        draftModel = config.defaultModel
        draftIsDefault = config.isDefaultVendor

        do {
            apiKey = try keychain.readString(account: providerID.keychainAccount) ?? ""
        } catch {
            apiKey = ""
        }
    }

    private func save() {
        // Save API key to keychain
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedKey.isEmpty {
                try keychain.delete(account: providerID.keychainAccount)
            } else {
                try keychain.writeString(trimmedKey, account: providerID.keychainAccount)
            }
        } catch {
            statusMessage = "Keychain error"
            return
        }

        // Update config
        config.host = draftHost
        config.subPath = draftSubPath
        config.defaultModel = draftModel

        if draftIsDefault {
            onSetDefaultVendor()
        }

        statusMessage = "Saved"

        // Clear status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == "Saved" {
                statusMessage = nil
            }
        }
    }
}
