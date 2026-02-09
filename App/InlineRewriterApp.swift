import SwiftUI

/// App entry point for Inline Rewriter.
/// Uses an `NSApplicationDelegate` to create the menubar status item and popovers.
@main
struct InlineRewriterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No longer needed - using custom SettingsWindowController
        // Settings scene removed to use NSWindowController for macOS 12.0+ compatibility
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
