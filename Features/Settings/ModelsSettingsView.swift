import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let keychain: KeychainStoring

    @State private var selectedProvider: ModelProviderID? = .openAI

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selectedProvider) {
                ForEach(ModelProviderID.allCases) { provider in
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        if configFor(provider).isDefaultVendor {
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

            // Detail
            if let selected = selectedProvider,
               let bindingIndex = settings.providerConfigs.firstIndex(where: { $0.providerID == selected }) {
                ProviderDetailView(
                    providerID: selected,
                    config: $settings.providerConfigs[bindingIndex],
                    keychain: keychain,
                    onSetDefaultVendor: { settings.setDefaultVendor(selected) }
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

    private func configFor(_ provider: ModelProviderID) -> ModelProviderConfig {
        settings.providerConfigs.first { $0.providerID == provider } ?? .defaultConfig(for: provider)
    }
}
