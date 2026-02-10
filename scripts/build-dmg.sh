#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

APP_NAME="InlineRewriter"
SCHEME="$APP_NAME"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA="$PROJECT_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"

# Read version from Info.plist
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
    | tail -5

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build product not found at $APP_PATH"
    exit 1
fi

echo "==> Ad-hoc code signing…"
codesign --force --deep --sign - "$APP_PATH"

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

echo ""
echo "==> Done! DMG created at:"
echo "    $DMG_PATH"
echo ""
echo "Recipients should right-click > Open to bypass Gatekeeper."
