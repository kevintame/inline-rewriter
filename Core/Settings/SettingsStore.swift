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

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// Computed bridge so OpenAIClient continues to work unchanged.
    var selectedModel: OpenAIModel {
        get {
            let config = providerConfigs.first { $0.providerID == .openAI }
            let rawValue = config?.defaultModel ?? "gpt-4o-mini"
            return OpenAIModel(rawValue: rawValue) ?? .gpt4oMini
        }
        set {
            if let idx = providerConfigs.firstIndex(where: { $0.providerID == .openAI }) {
                providerConfigs[idx].defaultModel = newValue.rawValue
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.transformations = Self.loadTransformations(defaults: defaults)
        self.hotkey = Self.loadHotkey(defaults: defaults)
        self.providerConfigs = Self.loadProviderConfigs(defaults: defaults)
        self.baseAIInstructions = defaults.string(forKey: Keys.baseAIInstructions) ?? "You are a helpful writing assistant."
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

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
        static let launchAtLogin = "launchAtLogin"
    }

    // MARK: - Persistence

    private func saveTransformations() {
        do {
            let data = try JSONEncoder().encode(transformations)
            defaults.set(data, forKey: Keys.transformations)
            _ = defaults.synchronize()
        } catch {
            logger.error("Failed to save transformations: \(error.localizedDescription)")
        }
    }

    private func saveHotkey() {
        do {
            let data = try JSONEncoder().encode(hotkey)
            defaults.set(data, forKey: Keys.hotkey)
            _ = defaults.synchronize()
        } catch {
            logger.error("Failed to save hotkey: \(error.localizedDescription)")
        }
    }

    private func saveProviderConfigs() {
        do {
            let data = try JSONEncoder().encode(providerConfigs)
            defaults.set(data, forKey: Keys.providerConfigs)
            _ = defaults.synchronize()
        } catch {
            logger.error("Failed to save provider configs: \(error.localizedDescription)")
        }
    }

    private static func loadTransformations(defaults: UserDefaults) -> [TextTransformation] {
        guard let data = defaults.data(forKey: Keys.transformations) else {
            return [.presetRewrite]
        }
        return (try? JSONDecoder().decode([TextTransformation].self, from: data)) ?? [.presetRewrite]
    }

    private static func loadHotkey(defaults: UserDefaults) -> Hotkey {
        guard let data = defaults.data(forKey: Keys.hotkey),
              let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else {
            return .default
        }
        return hk
    }

    private static func loadProviderConfigs(defaults: UserDefaults) -> [ModelProviderConfig] {
        guard let data = defaults.data(forKey: Keys.providerConfigs),
              let configs = try? JSONDecoder().decode([ModelProviderConfig].self, from: data),
              !configs.isEmpty else {
            return ModelProviderID.allCases.map { ModelProviderConfig.defaultConfig(for: $0) }
        }
        return configs
    }
}
