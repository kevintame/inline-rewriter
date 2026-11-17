import Cocoa
import SwiftUI

/// Borderless panels refuse key status by default, which would leave the picker and the
/// editable preview without keyboard input.
private final class RewritePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Gives its one child, a scroll view, the size of the scroll view's content, capped at the
/// size on offer. So the panel is exactly as big as its content when there is room, and
/// never bigger than the room there is.
private struct FitOrScrollLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let scrollView = subviews.first else { return .zero }
        // A scroll view's ideal size is the natural size of what it scrolls.
        let natural = scrollView.sizeThatFits(.unspecified)
        return CGSize(
            width: min(natural.width, proposal.width ?? natural.width),
            height: min(natural.height, proposal.height ?? natural.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Rounded window background for the borderless panel.
struct RewritePanelChrome<Content: View>: View {
    let content: Content

    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        // The content is shown at its natural size wherever that fits. Where the usable
        // screen area is smaller (a short display, a side Dock on a narrow one), the panel
        // is clamped and the content scrolls inside it instead of being cut off.
        FitOrScrollLayout {
            ScrollView([.horizontal, .vertical]) { content }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(Self.shape)
        .overlay(Self.shape.strokeBorder(Color.primary.opacity(0.15)))
    }
}

/// Shows the picker and the preview in one floating panel pinned to the upper-right corner
/// of a display, sized to its content and kept fully on screen as the content changes.
///
/// The panel behaves like a transient popover: when it loses key status while visible (a
/// click elsewhere, an app switch) it reports `onDismiss` so the owner can end the
/// `RewriteSession`.
@MainActor
final class RewritePanelController: NSObject, NSWindowDelegate {
    /// The user dismissed the panel by moving focus away from it.
    var onDismiss: (() -> Void)?

    private typealias HostingController = NSHostingController<AnyView>

    private let panel: RewritePanel
    private var screen: NSScreen?
    /// Owns the SwiftUI content. Its view is installed as the panel's content view rather
    /// than through `contentViewController`, so the panel's frame is set only here and
    /// AppKit does not also resize the window behind our back.
    private var hosting: HostingController?
    private var sizeObservation: NSKeyValueObservation?
    private var screenObservation: NSObjectProtocol?
    /// Set while this controller hides the panel itself, so that is not reported as a
    /// dismissal by the user.
    private var isClosing = false

    /// Keyboard handling for whatever the panel is showing. One monitor, installed while
    /// the panel is up and removed when it closes, rather than one per SwiftUI view whose
    /// removal would depend on view lifecycle callbacks.
    private var keyMonitor: Any?
    private var keyHandler: ((NSEvent) -> Bool)?

    override init() {
        panel = RewritePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // Follow the user to whichever Space they are in, including over a full-screen app.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self

        // The Dock moving or a display being reconfigured changes the usable area without
        // the content changing size.
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.pinToCorner()
            }
        }
    }

    deinit {
        if let screenObservation {
            NotificationCenter.default.removeObserver(screenObservation)
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// The panel's window, so key handling can be limited to events meant for it.
    var window: NSWindow { panel }

    /// Shows `content`, replacing whatever the panel showed before. Pass the display to use
    /// when starting a flow; pass `nil` to stay on the display already in use.
    ///
    /// `onKeyDown` sees key presses aimed at the panel and returns true for the ones it
    /// used. Returns false if the panel could not be put on screen.
    @discardableResult
    func show<Content: View>(_ content: Content,
                             on screen: NSScreen? = nil,
                             onKeyDown: @escaping (NSEvent) -> Bool = { _ in false }) -> Bool {
        if let screen {
            self.screen = screen
        }
        keyHandler = onKeyDown
        installKeyMonitor()

        let hosting = HostingController(rootView: AnyView(RewritePanelChrome(content: content)))
        // Publish the SwiftUI content's size so the panel can follow it as it changes
        // (error text appearing, the Original disclosure opening).
        hosting.sizingOptions = [.preferredContentSize]

        sizeObservation = nil
        self.hosting = hosting
        panel.contentView = hosting.view
        sizeObservation = hosting.observe(\.preferredContentSize) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.pinToCorner()
            }
        }

        hosting.view.layoutSubtreeIfNeeded()
        guard pinToCorner() else {
            close()
            return false
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return panel.isVisible
    }

    /// The display showing the frontmost window of the app with process id `pid`, which is
    /// where the user is working. Falls back to the display under the pointer, then to
    /// AppKit's main screen.
    ///
    /// Uses the window server's window list, which needs no permission for bounds and does
    /// not wait on the other app.
    static func activeScreen(forProcess pid: pid_t?) -> NSScreen? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }

        if let pid,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            // Front to back; layer 0 is ordinary app windows.
            for window in windows {
                guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                      (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                      let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                      let quartzBounds = CGRect(dictionaryRepresentation: boundsDictionary) else { continue }
                let bounds = PanelPlacement.appKitRect(fromQuartz: quartzBounds, primaryScreenHeight: primary.frame.height)
                if let index = PanelPlacement.indexOfScreen(containingMostOf: bounds, screenFrames: screens.map(\.frame)) {
                    return screens[index]
                }
            }
        }

        let pointer = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? primary
    }

    /// Hides the panel and tears down its content without reporting a dismissal.
    func close() {
        isClosing = true
        defer { isClosing = false }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        keyHandler = nil
        sizeObservation = nil
        panel.orderOut(nil)
        // Dropping the content tears down the SwiftUI views and anything they installed.
        panel.contentView = NSView()
        hosting = nil
    }

    /// Sizes the panel to its content and pins it to the upper-right corner of the display.
    /// Returns false when there is no content or no display to place it on.
    @discardableResult
    private func pinToCorner() -> Bool {
        guard let hosting else { return false }

        // The display can go away mid-session (unplugged, lid closed).
        if let current = screen, !NSScreen.screens.contains(current) {
            screen = nil
        }
        guard let target = screen ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        screen = target

        // Ask the content how big it wants to be within the space this display can offer.
        let visibleFrame = target.visibleFrame
        let available = PanelPlacement.upperRightFrame(
            contentSize: visibleFrame.size,
            visibleFrame: visibleFrame
        ).size
        let frame = PanelPlacement.upperRightFrame(
            contentSize: hosting.sizeThatFits(in: available),
            visibleFrame: visibleFrame
        )
        guard frame.width > 0, frame.height > 0 else { return false }

        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
        return true
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // A local monitor only sees this app's own events; it needs no extra permission.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Keys typed in Settings or Welcome are none of the panel's business.
        guard event.window === panel, let keyHandler else { return false }
        // While an input method is composing (Japanese, Chinese, Korean…), Return and
        // Escape belong to it: they confirm or cancel the composition.
        if let input = panel.firstResponder as? NSTextInputClient, input.hasMarkedText() {
            return false
        }
        return keyHandler(event)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing, panel.isVisible else { return }
        onDismiss?()
    }
}
