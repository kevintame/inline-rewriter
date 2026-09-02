import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring
    let testConnection: (ModelProviderConfig, String) async throws -> Void

    @State private var selectedProvider: ModelProviderID? = ModelProviderID.supported.first

    private let providers = ModelProviderID.supported

    var body: some View {
        HStack(spacing: 0) {
            // The sidebar only earns its space once there is more than one provider to pick.
            if providers.count > 1 {
                List(selection: $selectedProvider) {
                    ForEach(providers) { provider in
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            if settings.config(for: provider).isDefaultVendor {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                        }
                        .tag(provider)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 180)

                Divider()
            }

            if let selected = selectedProvider,
               let bindingIndex = settings.providerConfigs.firstIndex(where: { $0.providerID == selected }) {
                ProviderDetailView(
                    providerID: selected,
                    config: $settings.providerConfigs[bindingIndex],
                    keychain: keychain,
                    showsDefaultVendorToggle: providers.count > 1,
                    onSetDefaultVendor: { settings.setDefaultVendor(selected) },
                    testConnection: testConnection
                )
                .id(selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a provider")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
