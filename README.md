# Inline Rewriter

Menubar app to rewrite selected text via OpenAI.

## Status
Buildable via Xcode project. Still a lightweight scaffold, but runs.

## Bundle ID
`com.kevinTame.InlineRewriter`

## Structure
- `App/`: app lifecycle (InlineRewriterApp, AppDelegate, SceneDelegate)
- `Core/`: services + shared logic (OpenAI, settings, hotkey, pasteboard)
- `Features/`: SwiftUI views + view models (settings, picker, preview)
- `Info.plist`: app metadata
- `InlineRewriter.entitlements`: privacy entitlements

## Notes
- Global hotkey defaults to Cmd+Option+/
- Settings stored in UserDefaults + Keychain
- Transformations: preset “Rewrite” + custom list
