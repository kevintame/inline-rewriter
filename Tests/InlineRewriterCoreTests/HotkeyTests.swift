import Foundation
import Carbon.HIToolbox
import Testing
@testable import InlineRewriterCore

struct HotkeyTests {
    @Test func defaultDisplaysInStandardModifierOrder() {
        #expect(Hotkey.default.displayString == "⌥⌘/")
    }

    @Test func displayStringOrdersControlOptionShiftCommand() {
        let hk = Hotkey(keyCode: Int(kVK_ANSI_A), modifiers: [.command, .shift, .option, .control])
        #expect(hk.displayString == "⌃⌥⇧⌘A")
    }

    @Test func unknownKeyCodeFallsBackToNumber() {
        #expect(Hotkey.keyCodeToSymbol(999) == "Key999")
    }

    @Test func carbonModifiersMatchCarbonMasks() {
        let hk = Hotkey(keyCode: Int(kVK_ANSI_Slash), modifiers: [.command, .option])
        #expect(hk.carbonModifiers == UInt32(cmdKey) | UInt32(optionKey))

        let all = Hotkey(keyCode: 0, modifiers: [.command, .option, .control, .shift])
        #expect(all.carbonModifiers == UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey) | UInt32(shiftKey))
    }

    @Test func bareKeyIsNotAValidGlobalShortcut() {
        #expect(!Hotkey(keyCode: Int(kVK_ANSI_A), modifiers: []).isValidGlobalShortcut)
    }

    @Test func shiftAloneIsNotAValidGlobalShortcut() {
        #expect(!Hotkey(keyCode: Int(kVK_ANSI_A), modifiers: [.shift]).isValidGlobalShortcut)
    }

    @Test func commandOptionOrControlMakesAShortcutValid() {
        #expect(Hotkey(keyCode: Int(kVK_ANSI_A), modifiers: [.command]).isValidGlobalShortcut)
        #expect(Hotkey(keyCode: Int(kVK_ANSI_A), modifiers: [.option]).isValidGlobalShortcut)
        #expect(Hotkey(keyCode: Int(kVK_ANSI_A), modifiers: [.control]).isValidGlobalShortcut)
        #expect(Hotkey.default.isValidGlobalShortcut)
    }

    @Test func functionKeysAreValidWithoutModifiers() {
        #expect(Hotkey(keyCode: Int(kVK_F5), modifiers: []).isValidGlobalShortcut)
    }

    @Test func roundTripsThroughJSON() throws {
        let hk = Hotkey(keyCode: Int(kVK_ANSI_R), modifiers: [.control, .shift])
        let data = try JSONEncoder().encode(hk)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        #expect(decoded == hk)
    }

    @Test(arguments: [-1, 128, Int.max, Int.min])
    func outOfRangeKeyCodeIsNeverAValidGlobalShortcut(keyCode: Int) {
        let hk = Hotkey(keyCode: keyCode, modifiers: [.command, .option])
        #expect(!hk.hasValidKeyCode)
        #expect(!hk.isValidGlobalShortcut)
    }

    @Test @MainActor func registeringAnOutOfRangeKeyCodeThrowsInsteadOfTrapping() {
        let settings = SettingsStore(defaults: makeTestDefaults())
        settings.hotkey = Hotkey(keyCode: -1, modifiers: [.command])
        let manager = HotkeyManager(settings: settings)

        #expect(throws: HotkeyManager.RegistrationError.self) {
            try manager.start()
        }
    }
}
