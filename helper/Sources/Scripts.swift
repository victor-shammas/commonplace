// JXA scripts run through /usr/bin/osascript. Input is passed as a JSON argument to
// run(argv), never interpolated into the source.

enum Scripts {
    /// Lists folders and notes for every account. Output (compact, to stay well under
    /// Chrome's 1 MB native message limit):
    ///   { prefixes: [idPrefix], folders: [{id, name}],
    ///     notes: [[prefixIndex, idSuffix, name, folderIndex, modifiedSeconds]] }
    static let list = #"""
    function run() {
        const Notes = Application("com.apple.Notes");
        // "Recently Deleted" can only be recognised by name
        const TRASH = ["Recently Deleted", "Nylig slettet", "Senast raderade", "Nyligt slettet",
            "Zuletzt gelöscht", "Supprimés récemment", "Eliminados recientemente",
            "Eliminati di recente", "Recent verwijderd", "Äskettäin poistetut",
            "Apagados recentemente", "Apagadas recentemente", "最近删除", "最近刪除",
            "最近削除した項目", "최근 삭제된 항목"];

        const prefixes = [];
        const prefixIndex = {};
        function splitId(id) {
            const cut = id.lastIndexOf("/") + 1;
            const prefix = id.slice(0, cut);
            if (!(prefix in prefixIndex)) {
                prefixIndex[prefix] = prefixes.length;
                prefixes.push(prefix);
            }
            return [prefixIndex[prefix], id.slice(cut)];
        }

        const accounts = Notes.accounts();
        const folders = [];
        const notes = [];
        for (const account of accounts) {
            const accountName = account.name();
            const ids = account.folders.id();
            const names = account.folders.name();
            let parents;
            try { parents = account.folders.container.id(); } catch (e) { parents = ids.map(() => null); }
            const byId = {};
            ids.forEach((id, i) => { byId[id] = { name: names[i], parent: parents[i] }; });
            function path(id) {
                const parts = [];
                const seen = {};
                for (let cur = id; cur && byId[cur] && !seen[cur]; cur = byId[cur].parent) {
                    seen[cur] = true;
                    parts.unshift(byId[cur].name);
                }
                return parts.join(" / ");
            }

            // One Apple Event per property for all folders' notes at once
            const noteIds = account.folders.notes.id();
            const noteNames = account.folders.notes.name();
            const noteDates = account.folders.notes.modificationDate();

            for (let i = 0; i < ids.length; i++) {
                if (TRASH.indexOf(names[i]) >= 0) continue;
                const folderIndex = folders.length;
                folders.push({
                    id: ids[i],
                    name: path(ids[i]) + (accounts.length > 1 ? " — " + accountName : ""),
                });
                for (let j = 0; j < noteIds[i].length; j++) {
                    const [p, suffix] = splitId(noteIds[i][j]);
                    notes.push([p, suffix, String(noteNames[i][j]).slice(0, 120), folderIndex,
                                Math.floor(noteDates[i][j].getTime() / 1000)]);
                }
            }
        }
        return JSON.stringify({ prefixes, folders, notes });
    }
    """#

    /// Appends argv[0].html to the note argv[0].noteId by pasting it at the end.
    /// Paste rather than rewriting note.body: Notes' scripting body getter drops link
    /// hrefs and inline images, so a read-modify-write destroys earlier entries.
    static let append = #"""
    ObjC.import('AppKit');
    ObjC.import('Foundation');

    // Spin the run loop rather than blocking the thread, so NSWorkspace sees app switches
    function sleep(s) { $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(s)); }
    function waitFor(cond, seconds) {
        const end = Date.now() + seconds * 1000;
        while (Date.now() < end) {
            if (cond()) return true;
            sleep(0.05);
        }
        return cond();
    }

    function run(argv) {
        const input = JSON.parse(argv[0]);
        const Notes = Application("com.apple.Notes");
        const matches = Notes.notes.whose({id: input.noteId});
        if (matches.length === 0) throw new Error('That note no longer exists. Refresh the list and pick another.');
        const note = matches[0];
        const beforeDate = note.modificationDate().getTime();
        const ws = $.NSWorkspace.sharedWorkspace;
        const frontmost = () => ws.frontmostApplication.bundleIdentifier.js;
        const previousApp = frontmost();

        // Snapshot the user's clipboard so it can be restored after pasting
        const pb = $.NSPasteboard.generalPasteboard;
        const saved = [];
        const items = pb.pasteboardItems;
        if (!items.isNil()) {
            for (let i = 0; i < items.count; i++) {
                const item = items.objectAtIndex(i);
                const entry = [];
                for (let j = 0; j < item.types.count; j++) {
                    const type = item.types.objectAtIndex(j);
                    const data = item.dataForType(type);
                    if (!data.isNil()) entry.push([type, data]);
                }
                saved.push(entry);
            }
        }

        function restoreClipboard() {
            pb.clearContents;
            const restored = $.NSMutableArray.array;
            for (const entry of saved) {
                const item = $.NSPasteboardItem.alloc.init;
                for (const [type, data] of entry) item.setDataForType(data, type);
                restored.addObject(item);
            }
            if (restored.count > 0) pb.writeObjects(restored);
        }

        let verified = false;
        try {
            // Put HTML on clipboard
            pb.clearContents;
            const htmlStr = $.NSString.stringWithString('<meta charset="utf-8">' + input.html);
            pb.setDataForType(htmlStr.dataUsingEncoding($.NSUTF8StringEncoding), $.NSPasteboardTypeHTML);

            // Open the specific note and wait for Notes to come to front
            Notes.activate();
            note.show();
            if (!waitFor(() => frontmost() === 'com.apple.Notes', 3)) {
                throw new Error('Notes did not come to the front.');
            }

            // note.show() can leave keyboard focus in the folder sidebar, where the
            // keystrokes below would do nothing. Find the editor showing this note
            // and focus it explicitly; refuse to paste if it shows a different note.
            const se = Application("System Events");
            const win = se.processes.byName("Notes").windows[0];
            const noteName = note.name().trim();
            let editor = null;
            const shown = waitFor(() => {
                try {
                    for (const area of win.splitterGroups[0].scrollAreas()) {
                        const texts = area.textAreas();
                        if (texts.length && texts[0].value().trim().startsWith(noteName)) {
                            editor = texts[0];
                            return true;
                        }
                    }
                } catch (e) {}
                return false;
            }, 3);
            if (!shown) throw new Error('Notes did not open the selected note. Is it locked?');
            editor.focused = true;
            sleep(0.2);
            // Keystrokes go to whichever app is frontmost, so check again right before sending them
            if (frontmost() !== 'com.apple.Notes') throw new Error('Notes lost focus before pasting. Try again.');

            // Cmd+Down to move to end, then paste
            se.keyCode(125, {using: 'command down'});
            sleep(0.1);
            se.keystroke('v', {using: 'command down'});

            // Verify the note was actually modified
            verified = waitFor(() => note.modificationDate().getTime() > beforeDate, 3);
        } finally {
            restoreClipboard();
            if (previousApp && previousApp !== 'com.apple.Notes') Application(previousApp).activate();
        }
        return JSON.stringify({ verified });
    }
    """#
}
