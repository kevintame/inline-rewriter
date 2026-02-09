import Foundation
import os.log

/// App settings backed by UserDefaults.
///
/// Stores:
/// - Transformations (including the preset Rewrite)
/// - Selected model
/// - Hotkey binding
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Settings")

    @Published var transformations: [TextTransformation] {
        didSet { saveTransformations() }
    }

    @Published var selectedModel: OpenAIModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel) }
    }

    @Published var hotkey: Hotkey {
        didSet { saveHotkey() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.transformations = Self.loadTransformations(defaults: defaults)
        self.selectedModel = OpenAIModel(rawValue: defaults.string(forKey: Keys.selectedModel) ?? "gpt-4o-mini") ?? .gpt4oMini
        self.hotkey = Self.loadHotkey(defaults: defaults)

        // Ensure preset exists.
        if !transformations.contains(where: { $0.isPreset && $0.name == "Rewrite" }) {
            transformations.insert(.presetRewrite, at: 0)
        }
    }

    private enum Keys {
        static let transformations = "transformations"
        static let selectedModel = "selectedModel"
        static let hotkey = "hotkey"
    }

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
}
