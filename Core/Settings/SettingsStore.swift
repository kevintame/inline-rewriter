import Foundation
import os.log

/// App settings backed by UserDefaults.
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Settings")

    @Published var transformations: [TextTransformation] {
        didSet { saveTransformations() }
    }

    @Published var hotkey: Hotkey {
        didSet { saveHotkey() }
    }

    @Published var providerConfigs: [ModelProviderConfig] {
        didSet { saveProviderConfigs() }
    }

    @Published var baseAIInstructions: String {
        didSet { defaults.set(baseAIInstructions, forKey: Keys.baseAIInstructions) }
    }

    /// Set once the Welcome window has been dismissed. It is shown again only while
    /// Accessibility permission is missing.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.transformations = Self.loadTransformations(defaults: defaults)
        self.hotkey = Self.loadHotkey(defaults: defaults)
        self.providerConfigs = Self.loadProviderConfigs(defaults: defaults)
        self.baseAIInstructions = defaults.string(forKey: Keys.baseAIInstructions) ?? "You are a helpful writing assistant."
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    /// Config for a provider, falling back to defaults if it is somehow missing.
    func config(for provider: ModelProviderID) -> ModelProviderConfig {
        providerConfigs.first { $0.providerID == provider } ?? .defaultConfig(for: provider)
    }

    /// Enforce single-default-vendor constraint.
    func setDefaultVendor(_ providerID: ModelProviderID) {
        for i in providerConfigs.indices {
            providerConfigs[i].isDefaultVendor = (providerConfigs[i].providerID == providerID)
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let transformations = "transformations"
        static let hotkey = "hotkey"
        static let providerConfigs = "providerConfigs"
        static let baseAIInstructions = "baseAIInstructions"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: - Persistence

    private func saveTransformations() {
        save(transformations, forKey: Keys.transformations, label: "transformations")
    }

    private func saveHotkey() {
        save(hotkey, forKey: Keys.hotkey, label: "hotkey")
    }

    private func saveProviderConfigs() {
        save(providerConfigs, forKey: Keys.providerConfigs, label: "provider configs")
    }

    private func save<T: Encodable>(_ value: T, forKey key: String, label: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            logger.error("Failed to save \(label): \(error.localizedDescription)")
        }
    }

    private static func loadTransformations(defaults: UserDefaults) -> [TextTransformation] {
        guard let data = defaults.data(forKey: Keys.transformations),
              let decoded = try? JSONDecoder().decode([TextTransformation].self, from: data),
              !decoded.isEmpty else {
            return [.presetRewrite]
        }
        return decoded
    }

    private static func loadHotkey(defaults: UserDefaults) -> Hotkey {
        guard let data = defaults.data(forKey: Keys.hotkey),
              let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return .default
        }
        return hk
    }

    /// Loads stored configs and fills in any provider added since they were saved.
    private static func loadProviderConfigs(defaults: UserDefaults) -> [ModelProviderConfig] {
        var configs: [ModelProviderConfig] = []
        if let data = defaults.data(forKey: Keys.providerConfigs),
           let decoded = try? JSONDecoder().decode([ModelProviderConfig].self, from: data) {
            configs = decoded
        }

        for provider in ModelProviderID.allCases where !configs.contains(where: { $0.providerID == provider }) {
            var config = ModelProviderConfig.defaultConfig(for: provider)
            config.isDefaultVendor = false
            configs.append(config)
        }

        if !configs.contains(where: { $0.isDefaultVendor }),
           let first = configs.firstIndex(where: { ModelProviderID.supported.contains($0.providerID) }) {
            configs[first].isDefaultVendor = true
        }

        return configs
    }
}
