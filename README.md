# Inline Rewriter

macOS menu bar app that rewrites selected text in place using an OpenAI-compatible model.

Select text in any app, press the shortcut (default ⌥⌘/), pick a prompt, preview the result,
and replace the selection. Your clipboard is restored afterwards.

## Requirements

- macOS 13 or later
- An OpenAI API key (or any server that speaks the Chat Completions API)
- Accessibility permission, granted on first launch

## How it works

1. The global shortcut is registered with Carbon's `RegisterEventHotKey`, so it needs no
   Input Monitoring permission and the keystroke never reaches the app you're typing in.
2. The selection is read by simulating ⌘C and replaced by simulating ⌘V, which is why
   Accessibility permission is required. The previous clipboard is backed up and restored
   whether you replace or cancel.
3. The prompt is sent to the configured endpoint with your API key from the Keychain. Only
   the selected text and your prompt leave the machine.

## Project layout

- `App/`: AppKit entry point (`main.swift`), `AppDelegate` (status item, popover flow),
  window controllers, main menu
- `Core/`: services with no UI dependencies beyond AppKit types
  - `Hotkey/`: shortcut model and Carbon registration
  - `Pasteboard/`: copy/paste simulation and clipboard backup
  - `Accessibility/`: permission monitor, selected-text position lookup
  - `OpenAI/`: Chat Completions client
  - `Models/`: provider configuration and endpoint validation
  - `Settings/`: UserDefaults-backed settings, Keychain wrapper
  - `System/`: launch-at-login via `SMAppService`
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
  status, system prompt sent with every request
- **Models**: API key, host, path, and model for OpenAI. Host accepts any
  Chat-Completions-compatible server; HTTPS is enforced except for `http://localhost`.
  Anthropic and Gemini configs exist in the data model but have no client yet and are hidden.
- **Prompts**: the preset "Rewrite" plus your own. Templates must contain `{{text}}`.
