# Commonplace

A Chrome extension that keeps a commonplace book in Apple Notes: it saves the current page's title, URL, and an optional comment to any existing Apple Note. Uses Chrome's native messaging -- no server running, no open ports. The host script is spawned only when you click Save.

## Setup

### 1. Load the extension

1. Open `chrome://extensions/`
2. Enable **Developer mode** (top right)
3. Click **Load unpacked** and select the `extension/` folder
4. Copy the **extension ID** shown under the name

### 2. Register the native host

```bash
./install.sh <YOUR_EXTENSION_ID>
```

This does three things:
- Copies `host/notes_host.py` to `~/.local/bin/` (required -- see Troubleshooting)
- Creates a shell wrapper at `~/.local/bin/notes_host`
- Writes a Chrome native messaging manifest pointing to the wrapper

### 3. Restart Chrome

Quit and reopen Chrome so it picks up the native host registration.

## Usage

1. Navigate to any page
2. Click the extension icon
3. Select the target note (the list appears instantly from cache and refreshes from Notes in the background)
4. Optionally type a comment -- text you selected on the page before clicking the icon is filled in for you
5. Hit **Save**

The entry appears in your note as a timestamped link with your comment.

## How it works

```
popup.js  ->  chrome.runtime.connectNative
                    |
              Chrome spawns ~/.local/bin/notes_host (bash wrapper)
                    |
              notes_host.py (stdin/stdout JSON, native messaging protocol)
                    |
              osascript (JXA to list notes / clipboard+paste to append)
                    |
              Apple Notes
```

No server, no daemon, no open port. The Python script runs only for the duration of each request.

## Project structure

```
extension/
  manifest.json    Chrome extension manifest (MV3)
  popup.html       Popup UI
  popup.js         Popup logic, native messaging client
host/
  notes_host.py    Native messaging host (source copy)
  com.victorshammas.commonplace.json   Manifest template (not used at runtime)
install.sh         Deployment script
```

## Requirements

- macOS (Apple Notes + osascript)
- Python 3 (ships with macOS)
- Chrome or Chromium-based browser

## Troubleshooting

### "Failed to start native messaging host"

The shebang in `notes_host.py` may point to a Python path that doesn't exist. The install script uses a bash wrapper to avoid this -- re-run `install.sh` with your extension ID.

### "Native host has exited"

Most common cause: **macOS TCC sandbox restrictions**. Chrome-spawned processes cannot read files in protected directories (`~/Desktop`, `~/Documents`, `~/Downloads`). The `install.sh` script copies the host to `~/.local/bin/` to avoid this. If you moved the project or edited the source, re-run `install.sh`.

To debug, add logging to the bash wrapper at `~/.local/bin/notes_host`:
```bash
#!/bin/bash
/usr/bin/python3 "$HOME/.local/bin/notes_host.py" "$@" 2>> /tmp/notes_host_debug.log
echo "EXIT: $?" >> /tmp/notes_host_debug.log
```

### "Application isn't running" (-600)

This error can appear **even when Apple Notes is open**. It means JXA/osascript cannot resolve the Notes application. Two possible causes:

1. **JXA name resolution failure** -- macOS updates can break `Application("Notes")` in JXA. The fix is to use the bundle identifier `Application("com.apple.Notes")` instead. This is already handled in the current version.

2. **Missing Automation permission** -- macOS requires explicit permission for one app to control another via Apple Events. Check **System Settings > Privacy & Security > Automation** and ensure **python3** has access to **Notes** and **System Events**. Chrome disclaims responsibility for native hosts, so the permission belongs to `/usr/bin/python3`, not Chrome.

### "Commonplace needs Accessibility access"

Saving pastes the entry into the note with a simulated ⌘V, which macOS only allows for apps with Accessibility permission. Allow **python3** in **System Settings > Privacy & Security > Accessibility**. (Chrome disclaims responsibility for native hosts it launches, so macOS attributes the permission to the host's interpreter, `/usr/bin/python3`, not to Chrome.) Your clipboard is restored after each save.

### Notes don't appear in the list

Apple Notes may need a moment to sync. Try the refresh button in the popup. macOS may also prompt to allow `osascript` to access Notes the first time.

### After editing `notes_host.py`

Re-run `install.sh` to re-deploy the updated script to `~/.local/bin/`. The source copy in `host/` is not used at runtime.
