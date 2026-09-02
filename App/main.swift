import Cocoa

// AppKit-driven entry point. A SwiftUI `App` would create a main window at launch, which a
// menu bar app has to hide again; driving NSApplication directly avoids that.
//
// Top-level code runs on the main thread, but the compiler does not know that in Swift 5
// language mode, hence `assumeIsolated`.
let delegate = MainActor.assumeIsolated { () -> AppDelegate in
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    return delegate
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
