import Cocoa
import os.log
import ApplicationServices

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

        // Check Accessibility permissions explicitly
        let hasAccessibility = AXIsProcessTrusted()
        logger.info("Accessibility permission status: \(hasAccessibility)")
        if !hasAccessibility {
            logger.warning("Accessibility permission not granted - global hotkey monitoring may not work")
        }

        var localMonitorCreated = false
        var globalMonitorCreated = false

        // Local monitor helps when app is active.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // DEBUG: Log every keyDown event received by local monitor
            self.logger.debug("Local monitor: keyDown event - keyCode: \(event.keyCode), flags: \(event.modifierFlags.rawValue)")

            if self.matchesHotkey(event) {
                self.logger.info("✓ Local hotkey matched! Triggering callback...")
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

            // DEBUG: Log every keyDown event received by global monitor
            self.logger.debug("Global monitor: keyDown event - keyCode: \(event.keyCode), flags: \(event.modifierFlags.rawValue)")

            if self.matchesHotkey(event) {
                self.logger.info("✓ Global hotkey matched! Triggering callback...")
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
                logger.error("Global monitor creation failed - Input Monitoring permission may be required")
                logger.error("Check: System Settings → Privacy & Security → Input Monitoring")
            }
            if !localMonitorCreated {
                logger.error("Local monitor creation failed - this is very unusual and may indicate a system issue")
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

        let keyCodeMatches = event.keyCode == UInt16(hotkey.keyCode)
        let flagsMatch = eventFlags == expectedFlags

        // DEBUG: Log comparison details
        logger.debug("Hotkey match check:")
        logger.debug("  Expected: keyCode=\(hotkey.keyCode), flags=\(expectedFlags.rawValue)")
        logger.debug("  Received: keyCode=\(event.keyCode), flags=\(eventFlags.rawValue)")
        logger.debug("  KeyCode match: \(keyCodeMatches), Flags match: \(flagsMatch)")

        return keyCodeMatches && flagsMatch
    }
}
