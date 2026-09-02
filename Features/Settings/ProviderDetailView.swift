import SwiftUI

struct ProviderDetailView: View {
    let providerID: ModelProviderID
    @Binding var config: ModelProviderConfig
    let keychain: KeychainStoring
    let showsDefaultVendorToggle: Bool
    let onSetDefaultVendor: () -> Void

    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var draftHost: String = ""
    @State private var draftSubPath: String = ""
    @State private var draftModel: String = ""
    @State private var draftIsDefault: Bool = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(providerID.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Form {
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
                } footer: {
                    Text("Stored in your Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Host", text: $draftHost)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Host")
                } footer: {
                    Text("Requests always use HTTPS. Point this at any compatible server, such as a proxy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Path", text: $draftSubPath)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("Path")
                }

                Section {
                    HStack {
                        TextField("Model", text: $draftModel)
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

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? Color.red : Color.secondary)
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
        let trimmedModel = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            showStatus("Model cannot be empty.", isError: true)
            return
        }

        var updated = config
        updated.host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.subPath = draftSubPath.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.defaultModel = trimmedModel

        do {
            _ = try updated.endpointURL()
        } catch {
            showStatus(error.localizedDescription, isError: true)
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedKey.isEmpty {
                try keychain.delete(account: providerID.keychainAccount)
            } else {
                try keychain.writeString(trimmedKey, account: providerID.keychainAccount)
            }
        } catch {
            showStatus("Keychain error: \(error.localizedDescription)", isError: true)
            return
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

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
