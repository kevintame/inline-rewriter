import SwiftUI
import Carbon.HIToolbox

// MARK: - HotkeyRecorderView

struct HotkeyRecorderView: NSViewRepresentable {
    @ObservedObject var settings: SettingsStore
    /// Called with a valid shortcut once the user finishes recording.
    let onRecord: (Hotkey) -> Void
    /// Called when recording starts (true) or ends (false), so the live hotkey can be
    /// suspended; otherwise pressing the current shortcut triggers a rewrite instead of
    /// being recorded.
    let onRecordingChanged: (Bool) -> Void
    @Binding var validationMessage: String?

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.displayText = settings.hotkey.displayString
        view.onHotkeyRecorded = { hotkey in
            validationMessage = nil
            onRecord(hotkey)
        }
        view.onInvalidShortcut = {
            validationMessage = "Shortcut must include ⌘, ⌥, or ⌃."
        }
        view.onRecordingChanged = onRecordingChanged
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        if !nsView.isRecording {
            nsView.displayText = settings.hotkey.displayString
            nsView.needsDisplay = true
        }
    }
}

class HotkeyRecorderNSView: NSView {
    var displayText: String = ""
    private(set) var isRecording = false
    var onHotkeyRecorded: ((Hotkey) -> Void)?
    var onInvalidShortcut: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        let text = isRecording ? "Press shortcut…" : displayText
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        return NSSize(width: max(size.width + 24, 100), height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.quaternaryLabelColor.setFill()
        }
        path.fill()

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let text = isRecording ? "Press shortcut…" : displayText
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            setRecording(true)
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Ignore modifier-only presses
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(Int(event.keyCode)) { return }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            setRecording(false)
            window?.makeFirstResponder(nil)
            return
        }

        var mods: [Hotkey.Modifier] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.option)  { mods.append(.option) }
        if flags.contains(.shift)   { mods.append(.shift) }
        if flags.contains(.command) { mods.append(.command) }

        let hotkey = Hotkey(keyCode: Int(event.keyCode), modifiers: mods)
        guard hotkey.isValidGlobalShortcut else {
            // Stay in recording mode so the user can try again.
            onInvalidShortcut?()
            return
        }

        displayText = hotkey.displayString
        setRecording(false)
        window?.makeFirstResponder(nil)
        onHotkeyRecorded?(hotkey)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            setRecording(false)
        }
        return super.resignFirstResponder()
    }

    private func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        invalidateIntrinsicContentSize()
        needsDisplay = true
        onRecordingChanged?(recording)
    }
}

// MARK: - GeneralSettingsView

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let hotkeyManager: HotkeyManager
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @ObservedObject var permission: AccessibilityPermissionMonitor

    @State private var hotkeyMessage: String?
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Keyboard Shortcuts
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Keyboard Shortcut", systemImage: "keyboard")
                            .font(.headline)

                        Text("Press this shortcut with text selected in any app to show the prompt picker.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Show prompt picker:")
                            Spacer()
                            HotkeyRecorderView(
                                settings: settings,
                                onRecord: applyHotkey,
                                onRecordingChanged: { recording in
                                    if recording {
                                        hotkeyManager.stop()
                                    } else {
                                        restartHotkey()
                                    }
                                },
                                validationMessage: $hotkeyMessage
                            )
                            .frame(height: 26)
                            Button {
                                applyHotkey(.default)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to default shortcut")
                        }

                        if let hotkeyMessage {
                            Text(hotkeyMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(4)
                }

                // MARK: - Launch at Login
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Launch at Login", systemImage: "arrow.right.circle")
                            .font(.headline)

                        Text("Automatically start Inline Rewriter when you log in to your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle("Launch at Login", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)

                        if launchAtLogin.requiresApproval {
                            HStack {
                                Text("Approve Inline Rewriter under Login Items to finish.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                                    .controlSize(.small)
                            }
                        }

                        if let launchAtLoginError {
                            Text(launchAtLoginError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(4)
                }

                // MARK: - Accessibility
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Accessibility", systemImage: "lock.shield")
                            .font(.headline)

                        Text("Required to read the selected text and paste the result.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Status:")
                            Text(permission.isTrusted ? "Granted" : "Not Granted")
                                .foregroundColor(permission.isTrusted ? .green : .red)
                                .fontWeight(.medium)
                            Spacer()
                            if !permission.isTrusted {
                                Button("Grant Access") { permission.requestAccess() }
                                    .controlSize(.small)
                            }
                            Button("Open System Settings") { permission.openSystemSettings() }
                                .controlSize(.small)
                        }
                    }
                    .padding(4)
                }

                // MARK: - Base AI Instructions
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Base AI Instructions", systemImage: "text.quote")
                            .font(.headline)

                        Text("System prompt sent with every AI request. Customize the assistant's behavior.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $settings.baseAIInstructions)
                            .font(.body)
                            .frame(minHeight: 80)
                            .border(Color.secondary.opacity(0.3))
                    }
                    .padding(4)
                }
            }
            .padding()
        }
        .onAppear {
            permission.beginObserving()
            launchAtLogin.refresh()
        }
        .onDisappear {
            permission.endObserving()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled || launchAtLogin.requiresApproval },
            set: { enabled in
                do {
                    try launchAtLogin.setEnabled(enabled)
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    /// Registers the new shortcut, reverting to the previous one if registration fails
    /// (typically because another app owns it).
    private func applyHotkey(_ hotkey: Hotkey) {
        let previous = settings.hotkey
        settings.hotkey = hotkey
        do {
            try hotkeyManager.start()
            hotkeyMessage = nil
        } catch {
            settings.hotkey = previous
            try? hotkeyManager.start()
            hotkeyMessage = error.localizedDescription
        }
    }

    private func restartHotkey() {
        do {
            try hotkeyManager.start()
        } catch {
            hotkeyMessage = error.localizedDescription
        }
    }
}
