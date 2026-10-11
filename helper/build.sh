#!/bin/bash
# build.sh — Build, sign and package Commonplace Helper.
#
#   ./build.sh               universal build, Developer ID signed, in helper/build/
#   ./build.sh --notarize    also notarize and staple the app and the DMG; needs a
#                            notarytool keychain profile (NOTARY_PROFILE, default "notary")
#
# Signing identity can be overridden with SIGN_IDENTITY.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Commonplace Helper"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/CommonplaceHelper.dmg"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Victor Andreas Lund Shammas (JPP8RN6BJB)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
NOTARIZE=false
[ "${1:-}" = "--notarize" ] && NOTARIZE=true

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# 1. Universal binary
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

# 2. App bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CommonplaceHelper" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# 3. Sign with the hardened runtime (required for notarization)
codesign --force --options runtime --timestamp \
  --entitlements Resources/CommonplaceHelper.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

if $NOTARIZE; then
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/app.zip"
  notarize "$BUILD_DIR/app.zip"
  xcrun stapler staple "$APP"
  rm "$BUILD_DIR/app.zip"
fi

# 4. DMG with an Applications shortcut
STAGING="$BUILD_DIR/dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if $NOTARIZE; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi

echo "✓ $APP"
echo "✓ $DMG"
