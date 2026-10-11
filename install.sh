#!/bin/bash
# install.sh — Register the native messaging host with Chrome.
# Run once after loading the unpacked extension.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_DIR="$SCRIPT_DIR/host"
HOST_SCRIPT_SRC="$HOST_DIR/notes_host.py"
MANIFEST_NAME="com.victorshammas.commonplace.json"
CHROME_NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

# Deploy location outside ~/Desktop to avoid macOS TCC sandbox restrictions.
# Chrome-spawned processes cannot read files in ~/Desktop, ~/Documents, etc.
DEPLOY_DIR="$HOME/.local/bin"
DEPLOY_SCRIPT="$DEPLOY_DIR/notes_host.py"
DEPLOY_WRAPPER="$DEPLOY_DIR/notes_host"

# 1. Get extension ID
if [ -z "$1" ]; then
  echo ""
  echo "Usage: ./install.sh <EXTENSION_ID>"
  echo ""
  echo "To find your extension ID:"
  echo "  1. Open chrome://extensions/"
  echo "  2. Enable Developer mode"
  echo "  3. Load the extension/ folder"
  echo "  4. Copy the ID shown under the extension name"
  echo ""
  exit 1
fi

EXT_ID="$1"

# 2. Copy host script to a location Chrome can access
mkdir -p "$DEPLOY_DIR"
cp "$HOST_SCRIPT_SRC" "$DEPLOY_SCRIPT"
chmod +x "$DEPLOY_SCRIPT"

# 3. Create a shell wrapper so the shebang is always correct
cat > "$DEPLOY_WRAPPER" <<'WRAPPER'
#!/bin/bash
exec /usr/bin/python3 "$HOME/.local/bin/notes_host.py" "$@"
WRAPPER
chmod +x "$DEPLOY_WRAPPER"

# 4. Build manifest with correct paths
mkdir -p "$CHROME_NM_DIR"
cat > "$CHROME_NM_DIR/$MANIFEST_NAME" <<EOF
{
  "name": "com.victorshammas.commonplace",
  "description": "Commonplace native messaging host",
  "path": "$DEPLOY_WRAPPER",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXT_ID/"
  ]
}
EOF

echo "✓ Native messaging host installed."
echo "  Host:     $DEPLOY_SCRIPT"
echo "  Wrapper:  $DEPLOY_WRAPPER"
echo "  Manifest: $CHROME_NM_DIR/$MANIFEST_NAME"
echo "  Extension ID: $EXT_ID"
echo ""
echo "Restart Chrome to pick up the changes."
