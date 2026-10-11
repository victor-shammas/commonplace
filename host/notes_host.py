#!/usr/bin/python3
"""Native messaging host for Commonplace.

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
    const Notes = Application("com.apple.Notes");
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
        comment_html = html.escape(comment).replace("\r\n", "\n").replace("\n", "<br>")
        snippet += f"<div>[{comment_html}]</div>"

    safe_snippet = (snippet.replace("\\", "\\\\").replace("'", "\\'")
                     .replace("\n", "\\n").replace("\r", "\\r"))
    safe_id = note_id.replace("\\", "\\\\").replace("'", "\\'")

    # Paste rather than rewriting note.body: Notes' scripting body getter drops
    # link hrefs and inline images, so a read-modify-write destroys earlier entries.
    jxa = f"""
    ObjC.import('AppKit');
    ObjC.import('Foundation');

    // Spin the run loop rather than blocking the thread, so NSWorkspace sees app switches
    function sleep(s) {{ $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(s)); }}
    function waitFor(cond, seconds) {{
        const end = Date.now() + seconds * 1000;
        while (Date.now() < end) {{
            if (cond()) return true;
            sleep(0.05);
        }}
        return cond();
    }}

    const Notes = Application("com.apple.Notes");
    const note = Notes.notes.whose({{id: '{safe_id}'}})[0];
    const beforeDate = note.modificationDate().getTime();
    const ws = $.NSWorkspace.sharedWorkspace;
    const previousApp = ws.frontmostApplication.bundleIdentifier.js;

    // Snapshot the user's clipboard so it can be restored after pasting
    const pb = $.NSPasteboard.generalPasteboard;
    const saved = [];
    const items = pb.pasteboardItems;
    if (!items.isNil()) {{
        for (let i = 0; i < items.count; i++) {{
            const item = items.objectAtIndex(i);
            const entry = [];
            for (let j = 0; j < item.types.count; j++) {{
                const type = item.types.objectAtIndex(j);
                const data = item.dataForType(type);
                if (!data.isNil()) entry.push([type, data]);
            }}
            saved.push(entry);
        }}
    }}

    function restoreClipboard() {{
        pb.clearContents;
        const restored = $.NSMutableArray.array;
        for (const entry of saved) {{
            const item = $.NSPasteboardItem.alloc.init;
            for (const [type, data] of entry) item.setDataForType(data, type);
            restored.addObject(item);
        }}
        if (restored.count > 0) pb.writeObjects(restored);
    }}

    let verified = false;
    try {{
        // Put HTML on clipboard
        pb.clearContents;
        const wrapper = '<meta charset="utf-8">' + '{safe_snippet}';
        const htmlStr = $.NSString.stringWithString(wrapper);
        const htmlData = htmlStr.dataUsingEncoding($.NSUTF8StringEncoding);
        pb.setDataForType(htmlData, $.NSPasteboardTypeHTML);

        // Open the specific note and wait for Notes to come to front
        Notes.activate();
        note.show();
        if (!waitFor(() => ws.frontmostApplication.bundleIdentifier.js === 'com.apple.Notes', 3)) {{
            throw new Error('Notes did not come to the front.');
        }}
        // note.show() can leave keyboard focus in the folder sidebar, where the
        // keystrokes below would do nothing. Find the editor showing this note
        // and focus it explicitly; refuse to paste if it shows a different note.
        const se = Application("System Events");
        const win = se.processes.byName("Notes").windows[0];
        const noteName = note.name().trim();
        let editor = null;
        const shown = waitFor(() => {{
            try {{
                for (const area of win.splitterGroups[0].scrollAreas()) {{
                    const texts = area.textAreas();
                    if (texts.length && texts[0].value().trim().startsWith(noteName)) {{
                        editor = texts[0];
                        return true;
                    }}
                }}
            }} catch (e) {{}}
            return false;
        }}, 3);
        if (!shown) throw new Error('Notes did not open the selected note.');
        editor.focused = true;
        sleep(0.2);

        // Cmd+Down to move to end, then paste
        se.keyCode(125, {{using: 'command down'}});
        sleep(0.1);
        se.keystroke('v', {{using: 'command down'}});

        // Verify the note was actually modified
        verified = waitFor(() => note.modificationDate().getTime() > beforeDate, 3);
    }} finally {{
        restoreClipboard();
        if (previousApp && previousApp !== 'com.apple.Notes') Application(previousApp).activate();
    }}
    JSON.stringify({{verified}});
    """
    try:
        result = run_jxa(jxa)
    except RuntimeError as e:
        raise RuntimeError(explain_osascript_error(str(e))) from e
    check = json.loads(result)
    if not check.get("verified"):
        raise RuntimeError("Paste may have failed — Notes did not register a change. Try with Notes open.")


def explain_osascript_error(stderr):
    if any(s in stderr for s in ("(1002)", "(-1719)", "assistive access", "not allowed to send keystrokes")):
        return ("Commonplace needs Accessibility access to paste into Notes. Allow python3 in "
                "System Settings › Privacy & Security › Accessibility, then try again.")
    if "(-1743)" in stderr:
        return ("Commonplace isn't allowed to control Notes or System Events. Allow python3 in "
                "System Settings › Privacy & Security › Automation, then try again.")
    return stderr


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
