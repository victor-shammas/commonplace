#!/bin/bash
# install.sh — Development install of Commonplace Helper.
#
# Builds and signs the helper (helper/build.sh), copies it to /Applications and
# registers it as the native messaging host with every installed Chromium browser.
# Allowed extension IDs live in helper/Sources/Registration.swift.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Commonplace Helper.app"
DEST="/Applications/$APP_NAME"

helper/build.sh
rm -rf "$DEST"
cp -R "helper/build/$APP_NAME" "$DEST"
"$DEST/Contents/MacOS/CommonplaceHelper" --register

echo ""
echo "✓ Installed $DEST"
echo "  Open it once to grant permissions, then restart Chrome and reload the extension."
