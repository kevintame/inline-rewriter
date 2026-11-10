# Inline Rewriter

macOS menu bar app that rewrites selected text in place using an OpenAI-compatible model. `README.md` covers behavior and releasing. `CONTRIBUTING.md` covers workflow.

## Stack

Swift, AppKit with SwiftUI views, Xcode project plus a SwiftPM package for `Core/`. macOS 13 or later.

## Run

```bash
swift test               # Command Line Tools are enough
scripts/build-dmg.sh     # needs full Xcode
```

Build and run from Xcode 16 or later, then exercise shortcut, picker, preview, replace and cancel. Confirm the clipboard is restored after both replace and cancel.

## Layout

- `App/`: entry point, `AppDelegate`, window controllers.
- `Core/`: services, kept free of SwiftUI so SwiftPM can test them.
- `Features/`: UI.
- `Tests/InlineRewriterCoreTests`: tests for `Core/`.

## Pitfalls

- New Swift files must be added to the Xcode target. SwiftPM picks up `Core/` on its own.
- Any new way to dismiss a popover must end the `RewriteSession`, or the shortcut stops responding.
- Only Accessibility permission is required. Do not reintroduce `NSEvent` global monitors.
- TCC grants follow the code signature. Use a stable identity when testing permissions.

## Repo notes

- Two remotes: `github` (GitHub) and `origin` (gitea.tame.bot). `master` tracks `github/master`.
