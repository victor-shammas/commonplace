const HOST_NAME = "com.applenotes.bridge";
const CACHE_KEY = "notesCache";
const CACHE_MAX_AGE_MS = 10 * 60 * 1000; // 10 minutes

let allNotes = [];
let pageTitle = "";
let pageUrl = "";

const els = {
  title: document.getElementById("pageTitle"),
  url: document.getElementById("pageUrl"),
  folderSelect: document.getElementById("folderSelect"),
  noteSelect: document.getElementById("noteSelect"),
  comment: document.getElementById("comment"),
  stripQuery: document.getElementById("stripQuery"),
  save: document.getElementById("save"),
  status: document.getElementById("status"),
  refresh: document.getElementById("refresh"),
};

// -- Native messaging wrapper ----------------------------------------------

function sendNative(message) {
  return new Promise((resolve, reject) => {
    const port = chrome.runtime.connectNative(HOST_NAME);
    port.onMessage.addListener((response) => {
      if (response && response.status === "error") {
        reject(new Error(response.error));
      } else {
        resolve(response);
      }
      port.disconnect();
    });
    port.onDisconnect.addListener(() => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      }
    });
    port.postMessage(message);
  });
}

// -- Init ------------------------------------------------------------------

chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
  const tab = tabs[0];
  pageTitle = tab.title || "";
  pageUrl = tab.url || "";
  els.title.textContent = pageTitle;
  els.url.textContent = pageUrl;
});

// Restore strip query preference
chrome.storage.local.get("stripQuery", (r) => {
  if (r.stripQuery !== undefined) els.stripQuery.checked = r.stripQuery;
});

loadNotes(false);
// Auto-focus comment field
setTimeout(() => els.comment.focus(), 100);

// -- Notes list with caching -----------------------------------------------

async function loadNotes(forceRefresh) {
  if (!forceRefresh) {
    const cached = await getCachedNotes();
    if (cached) {
      allNotes = cached;
      buildFolders();
      return;
    }
  }

  setStatus("Loading notes…", "loading");
  els.folderSelect.innerHTML = '<option value="">Loading…</option>';
  els.noteSelect.innerHTML = '<option value="">Loading…</option>';

  try {
    const response = await sendNative({ action: "list" });
    allNotes = response.notes || [];
    await setCachedNotes(allNotes);
    buildFolders();
    setStatus("");
  } catch (e) {
    setStatus("Error: " + e.message, "err");
  }
}

function getCachedNotes() {
  return new Promise((resolve) => {
    chrome.storage.local.get(CACHE_KEY, (result) => {
      const cache = result[CACHE_KEY];
      if (cache && Date.now() - cache.timestamp < CACHE_MAX_AGE_MS) {
        resolve(cache.notes);
      } else {
        resolve(null);
      }
    });
  });
}

function setCachedNotes(notes) {
  return new Promise((resolve) => {
    chrome.storage.local.set({ [CACHE_KEY]: { notes, timestamp: Date.now() } }, resolve);
  });
}

// -- Build folder dropdown -------------------------------------------------

function buildFolders() {
  // Group by folder, sort folders by most recent note (desc)
  const folderMap = {};
  for (const n of allNotes) {
    const f = n.folder || "Notes";
    if (!folderMap[f]) folderMap[f] = [];
    folderMap[f].push(n);
  }

  const folderNames = Object.keys(folderMap).sort((a, b) => {
    const latestA = Math.max(...folderMap[a].map((n) => new Date(n.modified).getTime()));
    const latestB = Math.max(...folderMap[b].map((n) => new Date(n.modified).getTime()));
    return latestB - latestA;
  });

  els.folderSelect.innerHTML = "";
  for (const name of folderNames) {
    const opt = document.createElement("option");
    opt.value = name;
    opt.textContent = `${name} (${folderMap[name].length})`;
    els.folderSelect.appendChild(opt);
  }

  // Restore last folder or pick first
  chrome.storage.local.get(["lastFolder", "lastNoteId"], (r) => {
    if (r.lastFolder) {
      const match = [...els.folderSelect.options].find((o) => o.value === r.lastFolder);
      if (match) match.selected = true;
    }
    buildNotes(r.lastNoteId);
  });
}

// -- Build note list for selected folder -----------------------------------

function buildNotes(restoreNoteId) {
  const folder = els.folderSelect.value;
  const notes = allNotes
    .filter((n) => (n.folder || "Notes") === folder)
    .sort((a, b) => new Date(b.modified).getTime() - new Date(a.modified).getTime());

  els.noteSelect.disabled = false;
  els.noteSelect.innerHTML = "";

  for (const n of notes) {
    const opt = document.createElement("option");
    opt.value = n.id;
    opt.textContent = n.name;
    els.noteSelect.appendChild(opt);
  }

  // Restore last note if it's in this folder
  if (restoreNoteId) {
    const match = [...els.noteSelect.options].find((o) => o.value === restoreNoteId);
    if (match) match.selected = true;
  }

  updateSaveButton();
}

// -- Events ----------------------------------------------------------------

els.folderSelect.addEventListener("change", () => {
  chrome.storage.local.set({ lastFolder: els.folderSelect.value });
  buildNotes();
});

els.noteSelect.addEventListener("change", () => {
  const id = els.noteSelect.value;
  if (id) chrome.storage.local.set({ lastNoteId: id });
  updateSaveButton();
});

els.stripQuery.addEventListener("change", () => {
  chrome.storage.local.set({ stripQuery: els.stripQuery.checked });
});

els.refresh.addEventListener("click", () => loadNotes(true));

// -- Save ------------------------------------------------------------------

els.save.addEventListener("click", async () => {
  const noteId = els.noteSelect.value;
  if (!noteId) return;

  els.save.disabled = true;
  setStatus("Saving…", "loading");

  let url = pageUrl;
  if (els.stripQuery.checked) {
    try {
      const u = new URL(url);
      u.search = "";
      url = u.toString();
    } catch (_) {}
  }

  try {
    await sendNative({
      action: "append",
      note_id: noteId,
      title: pageTitle,
      url,
      comment: els.comment.value.trim(),
    });
    setStatus("Saved ✓", "ok");
    chrome.storage.local.set({
      lastNoteId: noteId,
      lastFolder: els.folderSelect.value,
    });
    setTimeout(() => window.close(), 800);
  } catch (e) {
    setStatus(e.message, "err");
    els.save.disabled = false;
  }
});

// Enter key saves (unless in the note select)
document.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !els.save.disabled) {
    e.preventDefault();
    els.save.click();
  }
});
// -- Helpers ---------------------------------------------------------------

function updateSaveButton() {
  els.save.disabled = !els.noteSelect.value;
}

function setStatus(msg, cls) {
  els.status.textContent = msg;
  els.status.className = "status" + (cls ? ` ${cls}` : "");
}
