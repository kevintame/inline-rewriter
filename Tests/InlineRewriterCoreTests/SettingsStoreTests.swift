import Foundation
import Carbon.HIToolbox
import Testing
@testable import InlineRewriterCore

@MainActor
struct SettingsStoreTests {
    @Test func freshStoreHasDefaults() {
        let store = SettingsStore(defaults: makeTestDefaults())
        #expect(store.transformations == [.presetRewrite])
        #expect(store.hotkey == .default)
        #expect(store.baseAIInstructions == "You are a helpful writing assistant.")
        #expect(!store.hasCompletedOnboarding)
    }

    @Test func transformationsPersistAcrossInstances() {
        let defaults = makeTestDefaults()
        let custom = TextTransformation(name: "Shorten", promptTemplate: "Shorten: {{text}}")

        let first = SettingsStore(defaults: defaults)
        first.transformations.append(custom)

        let second = SettingsStore(defaults: defaults)
        #expect(second.transformations == [.presetRewrite, custom])
    }

    @Test func emptyStoredTransformationsFallBackToPreset() throws {
        let defaults = makeTestDefaults()
        defaults.set(try JSONEncoder().encode([TextTransformation]()), forKey: "transformations")
        #expect(SettingsStore(defaults: defaults).transformations == [.presetRewrite])
    }

    @Test func hotkeyPersists() {
        let defaults = makeTestDefaults()
        let hk = Hotkey(keyCode: Int(kVK_ANSI_R), modifiers: [.control, .option])
        SettingsStore(defaults: defaults).hotkey = hk
        #expect(SettingsStore(defaults: defaults).hotkey == hk)
    }

    @Test func onboardingFlagPersists() {
        let defaults = makeTestDefaults()
        SettingsStore(defaults: defaults).hasCompletedOnboarding = true
        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding)
    }

    @Test func freshStoreHasConfigForEveryProviderWithOpenAIAsDefault() {
        let store = SettingsStore(defaults: makeTestDefaults())
        #expect(Set(store.providerConfigs.map(\.providerID)) == Set(ModelProviderID.allCases))
        #expect(store.providerConfigs.filter(\.isDefaultVendor).map(\.providerID) == [.openAI])
        #expect(store.config(for: .openAI) == .defaultConfig(for: .openAI))
    }

    @Test func storedConfigsAreMergedWithNewProviders() throws {
        let defaults = makeTestDefaults()
        var stored = ModelProviderConfig.defaultConfig(for: .openAI)
        stored.defaultModel = "gpt-4o"
        stored.host = "proxy.example.com"
        defaults.set(try JSONEncoder().encode([stored]), forKey: "providerConfigs")

        let store = SettingsStore(defaults: defaults)
        #expect(store.config(for: .openAI) == stored)
        #expect(Set(store.providerConfigs.map(\.providerID)) == Set(ModelProviderID.allCases))
        #expect(store.providerConfigs.filter(\.isDefaultVendor).map(\.providerID) == [.openAI])
    }

    @Test func missingDefaultVendorIsAssignedToASupportedProvider() throws {
        let defaults = makeTestDefaults()
        var stored = ModelProviderConfig.defaultConfig(for: .openAI)
        stored.isDefaultVendor = false
        defaults.set(try JSONEncoder().encode([stored]), forKey: "providerConfigs")

        let store = SettingsStore(defaults: defaults)
        #expect(store.providerConfigs.filter(\.isDefaultVendor).map(\.providerID) == [.openAI])
    }

    @Test func setDefaultVendorIsExclusive() {
        let store = SettingsStore(defaults: makeTestDefaults())
        store.setDefaultVendor(.anthropic)
        #expect(store.providerConfigs.filter(\.isDefaultVendor).map(\.providerID) == [.anthropic])
    }

    @Test func providerConfigEditsPersist() {
        let defaults = makeTestDefaults()
        let store = SettingsStore(defaults: defaults)
        let idx = store.providerConfigs.firstIndex { $0.providerID == .openAI }!
        store.providerConfigs[idx].defaultModel = "gpt-4o"

        #expect(SettingsStore(defaults: defaults).config(for: .openAI).defaultModel == "gpt-4o")
    }

    // MARK: Invalid persisted shortcuts

    @Test(arguments: [-1, 128, 999, Int.max, Int.min])
    func outOfRangeStoredKeyCodeFallsBackToDefault(keyCode: Int) throws {
        let defaults = makeTestDefaults()
        let stored = Hotkey(keyCode: keyCode, modifiers: [.command])
        defaults.set(try JSONEncoder().encode(stored), forKey: "hotkey")

        #expect(SettingsStore(defaults: defaults).hotkey == .default)
    }

    @Test func undecodableStoredHotkeyFallsBackToDefault() {
        let defaults = makeTestDefaults()
        defaults.set(Data("not json".utf8), forKey: "hotkey")
        #expect(SettingsStore(defaults: defaults).hotkey == .default)
    }

    @Test func validStoredKeyCodeAtTheEdgesIsKept() throws {
        for keyCode in [0, 127] {
            let defaults = makeTestDefaults()
            let stored = Hotkey(keyCode: keyCode, modifiers: [.control])
            defaults.set(try JSONEncoder().encode(stored), forKey: "hotkey")
            #expect(SettingsStore(defaults: defaults).hotkey == stored)
        }
    }
}
