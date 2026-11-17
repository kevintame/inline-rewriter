import Cocoa
import Carbon.HIToolbox
import os.log

/// Registers the global hotkey through Carbon's `RegisterEventHotKey`.
///
/// Compared to `NSEvent.addGlobalMonitorForEvents` this needs no Input Monitoring
/// permission, works before Accessibility is granted, and consumes the keystroke so the
/// frontmost app never sees it.
@MainActor
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private let settings: SettingsStore
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Four-char code "INRW" identifying our hotkey registrations.
    private static let signature: OSType = 0x494E_5257
    private static let hotKeyID: UInt32 = 1

    init(settings: SettingsStore) {
        self.settings = settings
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    enum RegistrationError: LocalizedError {
        case invalidShortcut(Hotkey)
        case handlerInstallFailed(OSStatus)
        case registrationFailed(Hotkey, OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidShortcut(let hotkey):
                return "The shortcut \(hotkey.displayString) can't be used as a global shortcut. It must be a real key combined with ⌘, ⌥, or ⌃. Change it in Settings."
            case .handlerInstallFailed(let status):
                return "Could not install the hotkey event handler (status \(status))."
            case .registrationFailed(let hotkey, _):
                return "The shortcut \(hotkey.displayString) could not be registered. Another app may already be using it. Change it in Settings."
            }
        }
    }

    /// Registers the current shortcut from settings, replacing any previous registration.
    func start() throws {
        stop()

        let hotkey = settings.hotkey
        guard hotkey.isValidGlobalShortcut, let keyCode = UInt32(exactly: hotkey.keyCode) else {
            throw RegistrationError.invalidShortcut(hotkey)
        }

        try installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            keyCode,
            hotkey.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            logger.error("RegisterEventHotKey failed for \(hotkey.displayString) (status \(status))")
            throw RegistrationError.registrationFailed(hotkey, status)
        }

        hotKeyRef = ref
        logger.info("Registered global hotkey \(hotkey.displayString)")
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            logger.debug("Unregistered global hotkey")
        }
        hotKeyRef = nil
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            userData,
            &eventHandlerRef
        )
        guard status == noErr else {
            throw RegistrationError.handlerInstallFailed(status)
        }
    }

    fileprivate func handleHotKeyEvent(_ id: EventHotKeyID) {
        guard id.signature == Self.signature, id.id == Self.hotKeyID else { return }
        onHotkey?()
    }
}

/// C callback invoked by Carbon on the main thread when a registered hotkey is pressed.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handleHotKeyEvent(hotKeyID)
    }
    return noErr
}
