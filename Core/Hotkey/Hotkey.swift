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

    /// Human-readable display string like "⌃⌥⇧⌘/" in standard macOS modifier order.
    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += Self.keyCodeToSymbol(keyCode)
        return s
    }

    /// Map a Carbon virtual key code to a human-readable symbol/string.
    static func keyCodeToSymbol(_ keyCode: Int) -> String {
        switch keyCode {
        // Letters
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        // Numbers
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        // Punctuation / symbols
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_Grave:        return "`"
        // Special keys
        case kVK_Space:             return "Space"
        case kVK_Return:            return "↩"
        case kVK_Tab:               return "⇥"
        case kVK_Delete:            return "⌫"
        case kVK_ForwardDelete:     return "⌦"
        case kVK_Escape:            return "⎋"
        // Arrow keys
        case kVK_UpArrow:           return "↑"
        case kVK_DownArrow:         return "↓"
        case kVK_LeftArrow:         return "←"
        case kVK_RightArrow:        return "→"
        // F-keys
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return "Key\(keyCode)"
        }
    }
}
