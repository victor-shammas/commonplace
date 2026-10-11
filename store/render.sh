#!/bin/bash
# render.sh — Regenerate the Chrome Web Store images in store/ with headless Chrome.
# The screenshot shows the real extension/popup.html + popup.js, with chrome.* APIs
# replaced by src/stub.js (sample folders and notes, no real data).

set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp src/* ../assets/icon.svg ../extension/popup.js "$WORK/"
sed 's#<script src="popup.js"></script>#<script src="stub.js"></script><script src="popup.js"></script>#' \
  ../extension/popup.html > "$WORK/popup.html"

shoot() { # name width height scale
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --virtual-time-budget=5000 --window-size="$2,$3" --force-device-scale-factor="$4" \
    --screenshot="$WORK/$1.png" "file://$WORK/$1.html" 2>/dev/null
}

# The popup is captured on its own (an iframe can be captured before popup.js finishes),
# then placed into the screenshot page as an image
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --virtual-time-budget=5000 --window-size=340,504 --force-device-scale-factor=2 \
  --screenshot="$WORK/popup.png" "file://$WORK/popup.html" 2>/dev/null
shoot screenshot 1280 800 1
shoot screenshot-2 1280 800 1
shoot screenshot-3 1280 800 1
shoot promo-small 440 280 2
shoot promo-marquee 1400 560 2

# Store images must be exact sizes, without alpha
python3 - "$WORK" <<'PY'
import sys
from PIL import Image
work = sys.argv[1]
for src, dest, size in [("screenshot", "screenshot-1", (1280, 800)),
                        ("screenshot-2", "screenshot-2", (1280, 800)),
                        ("screenshot-3", "screenshot-3", (1280, 800)),
                        ("promo-small", "promo-small", (440, 280)),
                        ("promo-marquee", "promo-marquee", (1400, 560))]:
    Image.open(f"{work}/{src}.png").convert("RGB").resize(size, Image.LANCZOS).save(f"{dest}.png")
    print(f"✓ store/{dest}.png {size[0]}x{size[1]}")
PY
