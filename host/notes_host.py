#!/usr/bin/python3
"""Native messaging host for Save to Apple Notes.

Chrome spawns this process, sends a JSON message to stdin (4-byte length prefix),
and reads the JSON response from stdout (same framing). Process exits after.
"""

import html
import json
import struct
import subprocess
import sys
from datetime import datetime


def read_message():
    raw_length = sys.stdin.buffer.read(4)
    if not raw_length:
        return None
    length = struct.unpack("=I", raw_length)[0]
    data = sys.stdin.buffer.read(length)
    return json.loads(data.decode("utf-8"))


def send_message(obj):
    encoded = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("=I", len(encoded)))
    sys.stdout.buffer.write(encoded)
    sys.stdout.buffer.flush()


def run_jxa(script):
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def run_applescript(script):
    result = subprocess.run(
        ["osascript", "-e", script],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def list_notes():
    jxa = """
    const Notes = Application("Notes");
    const out = [];
    const folders = Notes.folders();
    for (const folder of folders) {
        const folderName = folder.name();
        const ids = folder.notes.id();
        const names = folder.notes.name();
        const dates = folder.notes.modificationDate();
        for (let i = 0; i < ids.length; i++) {
            out.push({
                id: ids[i],
                name: names[i],
                folder: folderName,
                modified: dates[i].toISOString()
            });
        }
    }
    JSON.stringify(out);
    """
    raw = run_jxa(jxa)
    return json.loads(raw)


def append_to_note(note_id, title, url, comment):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    link_html = f'<a href="{html.escape(url)}">{html.escape(title)}</a>'
    snippet = (
        f"<div><br></div>"
        f"<div><b>{link_html}</b></div>"
        f"<div>{html.escape(url)}</div>"
        f"<div>{html.escape(timestamp)}</div>"
    )
    if comment:
        snippet += f"<div>[{html.escape(comment)}]</div>"

    safe_snippet = (snippet.replace("\\", "\\\\").replace("'", "\\'")
                     .replace("\n", "\\n").replace("\r", "\\r"))
    safe_id = note_id.replace("\\", "\\\\").replace("'", "\\'")

    jxa = f"""
    ObjC.import('AppKit');
    ObjC.import('Foundation');

    // Grab modification date before paste
    const Notes = Application("Notes");
    const note = Notes.notes.whose({{id: '{safe_id}'}})[0];
    const beforeDate = note.modificationDate().getTime();

    // Put HTML on clipboard
    const pb = $.NSPasteboard.generalPasteboard;
    pb.clearContents;
    const wrapper = '<meta charset="utf-8">' + '{safe_snippet}';
    const htmlStr = $.NSString.stringWithString(wrapper);
    const htmlData = htmlStr.dataUsingEncoding($.NSUTF8StringEncoding);
    pb.setDataForType(htmlData, $.NSPasteboardTypeHTML);

    // Open the specific note
    Notes.activate();
    note.show();

    // Wait for Notes to come to front
    $.NSThread.sleepForTimeInterval(0.7);

    // Cmd+Down to move to end, then paste
    const se = Application("System Events");
    se.keyCode(125, {{using: 'command down'}});
    $.NSThread.sleepForTimeInterval(0.1);
    se.keystroke('v', {{using: 'command down'}});
    $.NSThread.sleepForTimeInterval(0.5);

    // Switch back to Chrome
    const chrome = Application("Google Chrome");
    chrome.activate();

    // Verify the note was actually modified
    const afterDate = note.modificationDate().getTime();
    JSON.stringify({{verified: afterDate > beforeDate}});
    """
    result = run_jxa(jxa)
    check = json.loads(result)
    if not check.get("verified"):
        raise RuntimeError("Paste may have failed — Notes did not register a change. Try with Notes open.")


def main():
    msg = read_message()
    if not msg:
        return

    action = msg.get("action")

    try:
        if action == "list":
            notes = list_notes()
            send_message({"status": "ok", "notes": notes})
        elif action == "append":
            append_to_note(
                msg["note_id"],
                msg.get("title", ""),
                msg.get("url", ""),
                msg.get("comment", ""),
            )
            send_message({"status": "ok"})
        else:
            send_message({"status": "error", "error": f"Unknown action: {action}"})
    except Exception as e:
        send_message({"status": "error", "error": str(e)})


if __name__ == "__main__":
    main()
