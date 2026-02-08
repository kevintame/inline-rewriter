import Cocoa

/// Global (and local) keyboard event monitor.
///
/// Notes:
/// - `addGlobalMonitorForEvents` listens even when app is not active.
/// - Some environments may require Accessibility permissions for full reliability.
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private let settings: SettingsStore

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    @discardableResult
    func start() -> Bool {
        stop()

        // Local monitor helps when app is active.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matchesHotkey(event) {
                self.onHotkey?()
                return nil
            }
            return event
        }

        // Global monitor for when app is inactive.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.matchesHotkey(event) {
                self.onHotkey?()
            }
        }

        let success = (localMonitor != nil) && (globalMonitor != nil)
        if !success {
            stop()
        }
        return success
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        let hotkey = settings.hotkey
        let expectedFlags = hotkey.toModifierFlags()

        // Normalize flags: only consider standard modifiers.
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let eventFlags = event.modifierFlags.intersection(relevant)

        return event.keyCode == UInt16(hotkey.keyCode) && eventFlags == expectedFlags
    }
}
