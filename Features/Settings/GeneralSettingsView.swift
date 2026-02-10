import SwiftUI
import Carbon.HIToolbox

// MARK: - HotkeyRecorderView

struct HotkeyRecorderView: NSViewRepresentable {
    @ObservedObject var settings: SettingsStore
    let hotkeyManager: HotkeyManager

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.displayText = settings.hotkey.displayString
        view.onHotkeyRecorded = { keyCode, modifiers in
            settings.hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
            _ = hotkeyManager.start()
        }
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
    var isRecording = false
    var onHotkeyRecorded: ((_ keyCode: Int, _ modifiers: [Hotkey.Modifier]) -> Void)?

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
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea!)
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
            isRecording = true
            window?.makeFirstResponder(self)
            invalidateIntrinsicContentSize()
            needsDisplay = true
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
            isRecording = false
            invalidateIntrinsicContentSize()
            needsDisplay = true
            window?.makeFirstResponder(nil)
            return
        }

        let keyCode = Int(event.keyCode)
        var mods: [Hotkey.Modifier] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.option)  { mods.append(.option) }
        if flags.contains(.shift)   { mods.append(.shift) }
        if flags.contains(.command) { mods.append(.command) }

        isRecording = false
        displayText = Hotkey(keyCode: keyCode, modifiers: mods).displayString
        invalidateIntrinsicContentSize()
        needsDisplay = true
        window?.makeFirstResponder(nil)

        onHotkeyRecorded?(keyCode, mods)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        invalidateIntrinsicContentSize()
        needsDisplay = true
        return super.resignFirstResponder()
    }
}

// MARK: - GeneralSettingsView

struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    let hotkeyManager: HotkeyManager
    let alertPresenter: AlertPresenter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Keyboard Shortcuts
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Keyboard Shortcuts", systemImage: "keyboard")
                            .font(.headline)

                        Text("Set the keyboard shortcut to show the AI popup when text is selected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Show AI Popup:")
                            Spacer()
                            HotkeyRecorderView(settings: settings, hotkeyManager: hotkeyManager)
                                .frame(height: 26)
                            Button {
                                settings.hotkey = .default
                                _ = hotkeyManager.start()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to default shortcut")
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

                        Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                    }
                    .padding(4)
                }

                // MARK: - Accessibility
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Accessibility", systemImage: "lock.shield")
                            .font(.headline)

                        Text("Accessibility permission is required to read selected text and simulate keystrokes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Status:")
                            if AXIsProcessTrusted() {
                                Text("Granted")
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                            } else {
                                Text("Not Granted")
                                    .foregroundColor(.red)
                                    .fontWeight(.medium)
                            }
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
    }
}
