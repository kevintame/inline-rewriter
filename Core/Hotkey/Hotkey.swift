import Foundation
import AppKit
import Carbon.HIToolbox

/// Simple hotkey representation.
/// Stored in UserDefaults as keyCode + modifier flags.
struct Hotkey: Codable, Equatable {
    var keyCode: Int
    var modifiers: [Modifier]

    enum Modifier: String, Codable, CaseIterable {
        case command
        case option
        case control
        case shift
    }

    static let `default` = Hotkey(keyCode: Int(kVK_ANSI_Slash), modifiers: [.command, .option])
}

extension Hotkey {
    /// Convert to NSEvent.ModifierFlags.
    func toModifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for m in modifiers {
            switch m {
            case .command: flags.insert(.command)
            case .option: flags.insert(.option)
            case .control: flags.insert(.control)
            case .shift: flags.insert(.shift)
            }
        }
        return flags
    }
}
