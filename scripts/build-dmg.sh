#!/usr/bin/env bash
#
# Builds a Release .app, signs it, wraps it in a DMG, and optionally notarizes it.
#
# Environment:
#   CODESIGN_IDENTITY   Signing identity. Default "-" (ad-hoc), which is fine for your own
#                       machine but NOT for distribution: Gatekeeper blocks it on macOS 15,
#                       and because the identity changes every build, users lose their
#                       Accessibility grant and get Keychain prompts on every update.
#                       For other people use a Developer ID, e.g.
#                       "Developer ID Application: Your Name (TEAMID)".
#   NOTARY_PROFILE      Optional. A notarytool keychain profile created with
#                       `xcrun notarytool store-credentials`. When set, the DMG is
#                       submitted for notarization and stapled. Requires a Developer ID.
#
# Requires full Xcode (xcodebuild), not just the Command Line Tools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

APP_NAME="InlineRewriter"
SCHEME="$APP_NAME"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA="$PROJECT_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "ERROR: xcodebuild is unavailable. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Info.plist")
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "==> Building $APP_NAME v$VERSION (Release)…"
xcodebuild \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    clean build \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    | tail -5

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build product not found at $APP_PATH" >&2
    exit 1
fi

if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "==> Ad-hoc signing (local use only)…"
    codesign --force --options runtime \
        --entitlements "$PROJECT_ROOT/$APP_NAME.entitlements" \
        --sign - "$APP_PATH"
else
    echo "==> Signing with '$CODESIGN_IDENTITY' (hardened runtime, timestamp)…"
    codesign --force --options runtime --timestamp \
        --entitlements "$PROJECT_ROOT/$APP_NAME.entitlements" \
        --sign "$CODESIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --strict --verbose=2 "$APP_PATH"

echo "==> Staging DMG contents…"
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG…"
mkdir -p "$BUILD_DIR"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

if [ -n "$NOTARY_PROFILE" ]; then
    if [ "$CODESIGN_IDENTITY" = "-" ]; then
        echo "ERROR: Notarization requires a Developer ID; set CODESIGN_IDENTITY." >&2
        exit 1
    fi
    echo "==> Submitting for notarization (this can take a few minutes)…"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling ticket…"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

echo ""
echo "==> Done! DMG created at:"
echo "    $DMG_PATH"
echo ""
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "This build is ad-hoc signed. It will run on this Mac, but other Macs will refuse it"
    echo "unless the recipient allows it under System Settings → Privacy & Security."
    echo "Set CODESIGN_IDENTITY and NOTARY_PROFILE for a distributable build."
elif [ -z "$NOTARY_PROFILE" ]; then
    echo "Signed but not notarized. Set NOTARY_PROFILE to notarize and staple."
else
    echo "Signed, notarized, and stapled."
fi
