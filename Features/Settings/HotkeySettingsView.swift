import SwiftUI
import Carbon.HIToolbox

struct HotkeySettingsView: View {
    @ObservedObject var settings: SettingsStore
    let hotkeyManager: HotkeyManager
    let alertPresenter: AlertPresenter

    @State private var selectedKeyCode: Int = Hotkey.default.keyCode
    @State private var cmd: Bool = true
    @State private var opt: Bool = true
    @State private var ctrl: Bool = false
    @State private var shift: Bool = false

    var body: some View {
        Form {
            Section("Binding") {
                Text("This scaffold uses keyCode + modifier check (NSEvent). A richer hotkey recorder UI can be added later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Toggle("⌘ Command", isOn: $cmd)
                    Toggle("⌥ Option", isOn: $opt)
                    Toggle("⌃ Control", isOn: $ctrl)
                    Toggle("⇧ Shift", isOn: $shift)
                }

                Picker("Key", selection: $selectedKeyCode) {
                    Text("/ (Slash)").tag(Int(kVK_ANSI_Slash))
                    Text("Space").tag(Int(kVK_Space))
                    Text("R").tag(Int(kVK_ANSI_R))
                }

                HStack {
                    Button("Apply") { apply() }
                    Button("Reset") { reset() }
                    Spacer()
                }
            }
        }
        .onAppear { loadFromSettings() }
    }

    private func loadFromSettings() {
        selectedKeyCode = settings.hotkey.keyCode
        cmd = settings.hotkey.modifiers.contains(.command)
        opt = settings.hotkey.modifiers.contains(.option)
        ctrl = settings.hotkey.modifiers.contains(.control)
        shift = settings.hotkey.modifiers.contains(.shift)
    }

    private func apply() {
        var mods: [Hotkey.Modifier] = []
        if cmd { mods.append(.command) }
        if opt { mods.append(.option) }
        if ctrl { mods.append(.control) }
        if shift { mods.append(.shift) }

        settings.hotkey = Hotkey(keyCode: selectedKeyCode, modifiers: mods)

        // Restart monitors so changes apply immediately.
        if !hotkeyManager.start() {
            alertPresenter.showError(
                title: "Hotkey unavailable",
                message: "Unable to register the global hotkey. Enable Input Monitoring or Accessibility permissions in System Settings."
            )
        }
    }

    private func reset() {
        settings.hotkey = .default
        loadFromSettings()
        if !hotkeyManager.start() {
            alertPresenter.showError(
                title: "Hotkey unavailable",
                message: "Unable to register the global hotkey. Enable Input Monitoring or Accessibility permissions in System Settings."
            )
        }
    }
}
