#!/bin/bash
# package.sh — Zip extension/ for upload to the Chrome Web Store dashboard.
# The manifest must sit at the root of the zip. Output: dist/commonplace-<version>.zip

set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(python3 -c 'import json; print(json.load(open("extension/manifest.json"))["version"])')"
ZIP="dist/commonplace-$VERSION.zip"

mkdir -p dist
rm -f "$ZIP"
(cd extension && zip -qr -X "../$ZIP" . -x '.*' -x '*/.*' -x 'key.pem')
echo "✓ $ZIP"
unzip -l "$ZIP"
