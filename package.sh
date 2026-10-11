#!/bin/bash
# package.sh — Zip extension/ for upload to the Chrome Web Store dashboard.
# The manifest must sit at the root of the zip. Output: dist/commonplace-<version>.zip

set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(python3 -c 'import json; print(json.load(open("extension/manifest.json"))["version"])')"
ZIP="dist/commonplace-$VERSION.zip"

mkdir -p dist
rm -f "$ZIP"

# The manifest "key" only pins the unpacked dev build to the store's extension ID;
# the store manages the key itself, so strip it from the upload.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R extension/ "$STAGING/"
python3 - "$STAGING/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
manifest = json.load(open(path))
manifest.pop("key", None)
open(path, "w").write(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
PY
(cd "$STAGING" && zip -qr -X "$OLDPWD/$ZIP" . -x '.*' -x '*/.*')
echo "✓ $ZIP"
unzip -l "$ZIP"
