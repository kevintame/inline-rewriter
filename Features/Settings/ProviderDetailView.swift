import SwiftUI

struct ProviderDetailView: View {
    let providerID: ModelProviderID
    @Binding var config: ModelProviderConfig
    let keychain: KeychainStoring
    let showsDefaultVendorToggle: Bool
    let onSetDefaultVendor: () -> Void
    /// Sends a minimal request with the given unsaved config and key.
    let testConnection: (ModelProviderConfig, String) async throws -> Void

    @State private var apiKey: String = ""
    /// The key as it was read from the Keychain, to tell an edit from an untouched field.
    @State private var loadedAPIKey: String = ""
    /// The saved key could not be read, so an empty field does not mean "no key".
    @State private var apiKeyLoadFailed = false
    @State private var showAPIKey: Bool = false
    @State private var draftHost: String = ""
    @State private var draftSubPath: String = ""
    @State private var draftModel: String = ""
    @State private var draftIsDefault: Bool = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false

    private enum DraftError: LocalizedError {
        case emptyModel
        var errorDescription: String? { "Model cannot be empty." }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(providerID.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("sk-…", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-…", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Stored in your Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField(providerID.defaultHost, text: $draftHost)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Host")
                } footer: {
                    Text("HTTPS is used, except for http://localhost. Point this at any compatible server, such as a proxy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField(providerID.defaultSubPath, text: $draftSubPath)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Path")
                }

                Section {
                    HStack {
                        TextField(providerID.availableModels.first ?? "Model", text: $draftModel)
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            ForEach(providerID.availableModels, id: \.self) { model in
                                Button(model) { draftModel = model }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Suggested models")
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Any model ID the provider accepts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsDefaultVendorToggle {
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
            }

            HStack {
                Button(action: save) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(action: test) {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "bolt")
                        }
                        Text(isTesting ? "Testing…" : "Test Connection")
                    }
                }
                .disabled(isTesting)
                .help("Send a tiny request with these values to check the key, host, and model")

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                        .lineLimit(2)
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
            loadedAPIKey = try keychain.readString(account: providerID.keychainAccount) ?? ""
            apiKeyLoadFailed = false
        } catch {
            loadedAPIKey = ""
            apiKeyLoadFailed = true
            showStatus("Couldn't read the saved API key (\(error.localizedDescription)). It is unchanged; enter a key to replace it.", isError: true)
        }
        apiKey = loadedAPIKey
    }

    /// The form fields as a config, validated the same way for Save and Test.
    private func draftConfig() throws -> ModelProviderConfig {
        let trimmedModel = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw DraftError.emptyModel }

        var updated = config
        updated.host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subPath = draftSubPath.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.defaultModel = trimmedModel
        _ = try updated.endpointURL()
        return updated
    }

    private func save() {
        let updated: ModelProviderConfig
        do {
            updated = try draftConfig()
        } catch {
            showStatus(error.localizedDescription, isError: true)
            return
        }

        // Only touch the Keychain when the key field was actually edited. In particular an
        // empty field after a failed read must not delete a key that is still there.
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyWasEdited = apiKeyLoadFailed ? !trimmedKey.isEmpty : trimmedKey != loadedAPIKey
        if keyWasEdited {
            do {
                if trimmedKey.isEmpty {
                    try keychain.delete(account: providerID.keychainAccount)
                } else {
                    try keychain.writeString(trimmedKey, account: providerID.keychainAccount)
                }
                loadedAPIKey = trimmedKey
                apiKeyLoadFailed = false
            } catch {
                showStatus("Keychain error: \(error.localizedDescription)", isError: true)
                return
            }
        }

        config.host = updated.host
        config.subPath = updated.subPath
        config.defaultModel = updated.defaultModel

        if draftIsDefault {
            onSetDefaultVendor()
        }

        showStatus("Saved", isError: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == "Saved" {
                statusMessage = nil
            }
        }
    }

    private func test() {
        let draft: ModelProviderConfig
        do {
            draft = try draftConfig()
        } catch {
            showStatus(error.localizedDescription, isError: true)
            return
        }

        isTesting = true
        showStatus("Connecting…", isError: false)
        let key = apiKey
        Task { @MainActor in
            defer { isTesting = false }
            do {
                try await testConnection(draft, key)
                showStatus("Connected · \(draft.defaultModel)", isError: false)
            } catch {
                showStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
