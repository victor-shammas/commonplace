# Commonplace

A Chrome extension that keeps a commonplace book in Apple Notes. It saves the current page's title, URL, a timestamp and an optional comment to the end of any note you pick. It works through **Commonplace Helper**, a small signed Mac app that Chrome starts only while you save. There's no server, background process or open port.

## Setup

### 1. Install Commonplace Helper

Download `CommonplaceHelper.dmg` from the [latest release](https://github.com/victor-shammas/commonplace/releases/latest) and drag **Commonplace Helper** to Applications. Open it once. It connects itself to your browsers and walks you through three macOS permissions:

- **Notes**: to list your notes and open the one you pick
- **System Events** and **Accessibility**: to paste the entry at the end of the note

### 2. Install the extension

Install Commonplace from the Chrome Web Store, or load it unpacked (see Development).

### 3. Restart Chrome

Quit and reopen Chrome so it picks up the helper.

## Usage

1. Navigate to any page
2. Click the extension icon
3. Select the target note (the list appears instantly from cache and refreshes from Notes in the background)
4. Optionally type a comment. Text you selected on the page before clicking the icon is filled in for you (Return adds a line break)
5. Hit **Save**, or press ⌘↩

The "Remove tracking parameters" option strips only known trackers (`utm_*`, `fbclid`, `gclid`, …), so links like YouTube's `?v=` keep working.

The entry appears in your note as a timestamped link with your comment.

## How it works

```
popup.js  ->  chrome.runtime.connectNative("com.victorshammas.commonplace")
                    |
              Chrome starts Commonplace Helper (one request, then it exits)
                    |
              osascript (JXA: list notes / paste the entry at the end of the note)
                    |
              Apple Notes
```

Entries are pasted rather than written into the note's HTML, because Notes' scripting interface drops links and images when a note's body is rewritten. Your clipboard is restored after each save.

## Development

```
extension/                 Chrome extension (MV3)
  manifest.json
  popup.html, popup.js     Popup UI and native messaging client
helper/                    Commonplace Helper (Swift package)
  Sources/main.swift       Chooses native-host mode or the setup window
  Sources/NativeHost.swift Native messaging protocol and actions
  Sources/Scripts.swift    JXA run through osascript
  Sources/Registration.swift  Native host manifests for each browser
  Sources/SetupWindow.swift   Permissions setup UI
  build.sh                 Universal build, signing, DMG (--notarize to notarize)
install.sh                 Development install to /Applications
package.sh                 Store zip in dist/ (strips the manifest key)
assets/                    Icon sources
```

1. In `chrome://extensions/`, enable **Developer mode**, click **Load unpacked** and select `extension/`.
2. The `key` in `manifest.json` gives the unpacked build the same ID as the Web Store item, which `helper/Sources/Registration.swift` allows.
3. Run `./install.sh`. It builds and signs the helper, copies it to `/Applications` and registers it with every installed Chromium browser.
4. Open Commonplace Helper once to grant permissions, then restart Chrome.

After editing the helper, re-run `./install.sh`. After editing the extension, reload it in `chrome://extensions/`.

To test the helper without Chrome, send it a framed message (4-byte length + JSON) with the extension origin as the argument:

```bash
"/Applications/Commonplace Helper.app/Contents/MacOS/CommonplaceHelper" "chrome-extension://<id>/"
```

## Privacy

Nothing leaves your Mac. See [PRIVACY.md](PRIVACY.md).

## Requirements

- macOS 13 or later, with Apple Notes
- Google Chrome, or another Chromium browser (Brave, Edge, Arc, Vivaldi, Chromium)

## Troubleshooting

### The popup says to get Commonplace Helper

The helper isn't installed, or was registered for a different copy of the extension. Install it, open it once, and restart Chrome.

### "Commonplace Helper needs Accessibility access" or "isn't allowed to control Notes"

Open Commonplace Helper and allow the items it lists. If you denied a prompt earlier, macOS won't ask again. Switch Commonplace Helper on in **System Settings > Privacy & Security > Automation** (Notes, System Events) or **Accessibility**. To start over, run `tccutil reset All com.victorshammas.commonplace.helper`.

Chrome doesn't take responsibility for the helpers it starts, so macOS asks about Commonplace Helper itself, not Chrome.

### Notes don't appear in the list

Apple Notes may need a moment to sync. Try the refresh button in the popup.
