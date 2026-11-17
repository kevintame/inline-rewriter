# Contributing

## Setup

- Xcode 16 or later to build and run the app.
- The Command Line Tools alone are enough to run `swift test`.

## Workflow

1. Make the change. Keep `Core/` free of SwiftUI so it stays testable from SwiftPM.
2. Run `swift test`. Add or update tests in `Tests/InlineRewriterCoreTests` for anything in `Core/`.
3. Build and run from Xcode and exercise the flow end to end: shortcut, picker, preview, replace, cancel.
   Check the clipboard is restored after both replace and cancel, and that a failed replace
   (quit the target app while the preview is up) reopens the preview with the result on the clipboard.
4. If you add a Swift file, add it to the Xcode target. The SwiftPM package picks up `Core/` automatically.

## Things that are easy to break

- **Panel state.** `AppDelegate` tracks one `RewriteSession`. Any new way to dismiss the panel must
  end the session, or the shortcut stops responding.
- **Shortcut registration.** `HotkeyManager` uses Carbon `RegisterEventHotKey`. Shortcuts without
  ⌘, ⌥, or ⌃ are rejected because they would swallow normal typing system-wide.
- **Permissions.** Only Accessibility is required. Do not reintroduce `NSEvent` global monitors;
  they need Input Monitoring as well and cannot consume the keystroke.
- **Signing.** TCC grants are tied to the code signature. Use a stable identity when testing
  permission flows or you will re-grant Accessibility on every build.

## Release

See "Releasing" in the README. `scripts/build-dmg.sh` needs full Xcode.
