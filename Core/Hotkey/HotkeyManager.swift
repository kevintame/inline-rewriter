import Cocoa
import os.log

/// Global (and local) keyboard event monitor.
///
/// Notes:
/// - `addGlobalMonitorForEvents` listens even when app is not active.
/// - Some environments may require Accessibility permissions for full reliability.
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private let settings: SettingsStore
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Hotkey")

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    @discardableResult
    func start() -> Bool {
        stop()

        logger.info("Starting hotkey manager with hotkey: \(self.settings.hotkey.keyCode)")

        var localMonitorCreated = false
        var globalMonitorCreated = false

        // Local monitor helps when app is active.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matchesHotkey(event) {
                self.onHotkey?()
                return nil
            }
            return event
        }
        localMonitorCreated = (localMonitor != nil)

        // Global monitor for when app is inactive.
        // May return nil if accessibility permissions are not granted.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.matchesHotkey(event) {
                self.onHotkey?()
            }
        }
        globalMonitorCreated = (globalMonitor != nil)

        let success = localMonitorCreated && globalMonitorCreated
        if success {
            logger.info("Hotkey manager started successfully")
        } else {
            logger.error("Failed to start hotkey manager - Local: \(localMonitorCreated), Global: \(globalMonitorCreated)")
            if !globalMonitorCreated {
                logger.error("Global monitor creation failed - check Accessibility permissions")
            }
            stop() // Clean up partial initialization
        }
        return success
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            logger.debug("Removed global monitor")
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            logger.debug("Removed local monitor")
        }
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
