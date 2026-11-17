# Inline Rewriter

macOS menu bar app that rewrites selected text in place using an OpenAI-compatible model.

Select text in any app, press the shortcut (default ⌥⌘/), pick a prompt, preview the result,
and replace the selection. Your clipboard is restored afterwards. If the replace fails, the
preview stays open and the rewritten text is left on the clipboard instead. The picker and preview open
in a small panel in the upper-right corner of the display you are working on.

In the picker, ↑/↓ and Return choose a prompt, or press 1–9 to run one directly. The preview
is editable before you replace: Return replaces, ⌥↩ inserts a newline, and Copy puts the result
on the clipboard instead of pasting it.

## Requirements

- macOS 13 or later
- An OpenAI API key (or any server that speaks the Chat Completions API)
- Accessibility permission, granted on first launch

## How it works

1. The global shortcut is registered with Carbon's `RegisterEventHotKey`, so it needs no
   Input Monitoring permission and the keystroke never reaches the app you're typing in.
2. The selection is read by simulating ⌘C and replaced by simulating ⌘V, which is why
   Accessibility permission is required. The previous clipboard is backed up and restored
   when you replace or cancel, and when reading the selection fails. If you copy something
   else while the panel is open, that newer copy is kept instead. Nothing is pasted unless
   the app you started in is frontmost again. If the replace fails once there is a result
   (the app quit, focus could not be returned), the old clipboard is not restored: the
   preview reopens with the result and the error, and the rewritten text stays on the
   clipboard so you can paste it yourself.
3. The prompt is sent to the configured endpoint with your API key from the Keychain. Only
   the selected text and your prompt leave the machine.

## Project layout

- `App/`: AppKit entry point (`main.swift`), `AppDelegate` (status item, rewrite flow),
  `RewritePanelController` (the picker/preview panel),
  window controllers, main menu
- `Core/`: services with no UI dependencies beyond AppKit types
  - `Hotkey/`: shortcut model and Carbon registration
  - `Pasteboard/`: copy/paste simulation and clipboard backup
  - `Accessibility/`: permission monitor
  - `OpenAI/`: Chat Completions client
  - `Models/`: provider configuration and endpoint validation
  - `Settings/`: UserDefaults-backed settings, Keychain wrapper
  - `System/`: launch-at-login via `SMAppService`
  - `UI/`: alert helper, panel placement math
- `Features/`: SwiftUI views and view models (welcome, settings, picker, preview)
- `Tests/`: unit tests for `Core/`, run with SwiftPM

## Building

Open `InlineRewriter.xcodeproj` in Xcode and run the `InlineRewriter` scheme. The bundle
identifier is `com.kevinTame.InlineRewriter`.

## Tests

`Core/` is also exposed as a SwiftPM library purely so its tests run from the command line.
This needs only the Command Line Tools, not Xcode.

```bash
swift test
```

## Releasing

`scripts/build-dmg.sh` builds a Release app, signs it, and produces a DMG in `build/`.

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=inline-rewriter scripts/build-dmg.sh
```

Without those variables the script ad-hoc signs, which only works on the machine that built
it. Ad-hoc signatures change every build, so users would lose their Accessibility grant and
get Keychain prompts on each update. Distribute with a Developer ID and notarize.

## Settings

- **General**: shortcut recorder (must include ⌘, ⌥, or ⌃), launch at login, Accessibility
  status
- **Models**: API key, host, path, and model for OpenAI. Host accepts any
  Chat-Completions-compatible server; HTTPS is enforced except for `http://localhost`.
  "Test Connection" sends a tiny request with the unsaved values so a bad key or model
  fails here rather than in the picker. Anthropic and Gemini configs exist in the data
  model but have no client yet and are hidden.
- **Prompts**: the system instructions sent with every request, then the preset "Rewrite"
  plus your own. Templates must contain `{{text}}`. The preset can be edited but not deleted.
