const HOST_NAME = "com.victorshammas.commonplace";
const CACHE_KEY = "notesCache2"; // compact list format from helper protocol 2
const REQUIRED_PROTOCOL = 2;
const SETUP_URL = "https://github.com/victor-shammas/commonplace#setup";
const NATIVE_TIMEOUT_MS = 40 * 1000; // the host gives osascript 30s
const MAX_SELECTION_CHARS = 5000;
const TRACKING_PARAM = /^(utm_\w+|fbclid|gclid|dclid|gbraid|wbraid|msclkid|yclid|mc_cid|mc_eid|igshid|_hsenc|_hsmi|mkt_tok)$/i;

let library = { folders: [], notes: [] };
let libraryJSON = "";
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
  form: document.getElementById("form"),
  setup: document.getElementById("setup"),
};

// -- Native messaging wrapper ----------------------------------------------

function sendNative(message) {
  return new Promise((resolve, reject) => {
    const port = chrome.runtime.connectNative(HOST_NAME);
    let settled = false;
    const settle = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(value);
    };
    const timer = setTimeout(() => {
      settle(reject, new Error("The Commonplace helper didn't respond. Try again."));
      port.disconnect();
    }, NATIVE_TIMEOUT_MS);

    port.onMessage.addListener((response) => {
      if (!response || (response.protocol || 0) < REQUIRED_PROTOCOL) {
        const error = new Error("Commonplace Helper needs to be updated.");
        error.needsSetup = error.outdated = true;
        settle(reject, error);
      } else if (response.status === "error") {
        settle(reject, new Error(response.error));
      } else {
        settle(resolve, response);
      }
      port.disconnect();
    });
    port.onDisconnect.addListener(() => {
      const text = chrome.runtime.lastError
        ? chrome.runtime.lastError.message
        : "The Commonplace helper exited unexpectedly.";
      const error = new Error(text);
      // Host missing, or registered for a different extension ID
      error.needsSetup = /not found|forbidden/i.test(text);
      settle(reject, error);
    });
    port.postMessage(message);
  });
}

function showSetup(outdated) {
  els.form.hidden = true;
  els.setup.hidden = false;
  document.getElementById("extId").textContent = chrome.runtime.id;
  const text = document.getElementById("setupText");
  if (!/Mac/.test(navigator.userAgent)) {
    text.textContent = "Commonplace saves pages to Apple Notes, so it works only on a Mac.";
  } else if (outdated) {
    text.textContent = "This version of Commonplace needs a newer Commonplace Helper. Download the latest version, open it once, then try again.";
  }
}

document.getElementById("setupLink").addEventListener("click", () => {
  chrome.tabs.create({ url: SETUP_URL });
  window.close();
});

// -- Init ------------------------------------------------------------------

chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
  const tab = tabs[0];
  if (!tab) return;
  pageTitle = tab.title || "";
  pageUrl = tab.url || "";
  els.title.textContent = pageTitle;
  els.url.textContent = pageUrl;
  updateSaveButton();
  prefillSelection(tab.id);
});

// The popup closes when the page is clicked, so text can't be copied into it
// while open. Instead, pre-fill the quick note with the page's selection.
async function prefillSelection(tabId) {
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => window.getSelection().toString(),
    });
    const selection = (result && result.result || "").trim().slice(0, MAX_SELECTION_CHARS);
    if (selection && !els.comment.value) els.comment.value = selection;
  } catch (_) {
    // Pages like chrome:// and the Web Store can't be scripted
  }
}

// Restore strip query preference
chrome.storage.local.get("stripQuery", (r) => {
  if (r.stripQuery !== undefined) els.stripQuery.checked = r.stripQuery;
});

chrome.storage.local.remove("notesCache"); // pre-protocol-2 cache format
loadNotes(false);
// Auto-focus comment field
setTimeout(() => els.comment.focus(), 100);

// -- Notes list with caching -----------------------------------------------

// Show the cached list immediately, then always refresh it from Notes (~2s)
// and rebuild the dropdowns without disturbing the current selection.
async function loadNotes(forceRefresh) {
  if (!forceRefresh && !library.notes.length) {
    const cached = await getCachedNotes();
    if (cached) setLibrary(cached, null);
  }

  if (!library.notes.length) {
    setStatus("Loading notes…", "loading");
    els.folderSelect.innerHTML = '<option value="">Loading…</option>';
    els.noteSelect.innerHTML = '<option value="">Loading…</option>';
  }
  els.refresh.classList.add("busy");

  try {
    const response = await sendNative({ action: "list" });
    const raw = response.notes;
    await setCachedNotes(raw);
    if (JSON.stringify(raw) !== libraryJSON) {
      const current = library.notes.length
        ? { folder: els.folderSelect.value, noteId: els.noteSelect.value }
        : null;
      setLibrary(raw, current);
    }
    if (els.status.textContent === "Loading notes…") setStatus("");
  } catch (e) {
    if (e.needsSetup) showSetup(e.outdated);
    else setStatus("Error: " + e.message, "err");
  } finally {
    els.refresh.classList.remove("busy");
  }
}

// The helper sends a compact list: { prefixes, folders: [{id, name}],
// notes: [[prefixIndex, idSuffix, name, folderIndex, modifiedSeconds]] }
function setLibrary(raw, current) {
  libraryJSON = JSON.stringify(raw);
  library = {
    folders: raw.folders,
    notes: raw.notes.map(([prefix, suffix, name, folder, modified]) => ({
      id: raw.prefixes[prefix] + suffix,
      name,
      folder: raw.folders[folder].id,
      modified,
    })),
  };
  buildFolders(current);
}

function getCachedNotes() {
  return new Promise((resolve) => {
    chrome.storage.local.get(CACHE_KEY, (result) => {
      const cache = result[CACHE_KEY];
      resolve(cache ? cache.notes : null);
    });
  });
}

function setCachedNotes(notes) {
  return new Promise((resolve) => {
    chrome.storage.local.set({ [CACHE_KEY]: { notes, timestamp: Date.now() } }, resolve);
  });
}

// -- Build folder dropdown -------------------------------------------------

function buildFolders(current) {
  // Folders that have notes, most recently modified first
  const counts = {};
  const latest = {};
  for (const n of library.notes) {
    counts[n.folder] = (counts[n.folder] || 0) + 1;
    latest[n.folder] = Math.max(latest[n.folder] || 0, n.modified);
  }
  const folders = library.folders
    .filter((f) => counts[f.id])
    .sort((a, b) => latest[b.id] - latest[a.id]);

  els.folderSelect.innerHTML = "";
  for (const f of folders) {
    const opt = document.createElement("option");
    opt.value = f.id;
    opt.textContent = `${f.name} (${counts[f.id]})`;
    els.folderSelect.appendChild(opt);
  }

  // Keep the current selection on refresh; otherwise restore last folder or pick first
  if (current) {
    selectFolder(current.folder, current.noteId);
  } else {
    chrome.storage.local.get(["lastFolder", "lastNoteId"], (r) => selectFolder(r.lastFolder, r.lastNoteId));
  }
}

function selectFolder(folder, noteId) {
  if (folder) {
    const match = [...els.folderSelect.options].find((o) => o.value === folder);
    if (match) match.selected = true;
  }
  buildNotes(noteId);
}

// -- Build note list for selected folder -----------------------------------

function buildNotes(restoreNoteId) {
  const folder = els.folderSelect.value;
  const notes = library.notes
    .filter((n) => n.folder === folder)
    .sort((a, b) => b.modified - a.modified);

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

  const url = els.stripQuery.checked ? stripTracking(pageUrl) : pageUrl;

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
    if (e.needsSetup) showSetup(e.outdated);
    else setStatus(e.message, "err");
    els.save.disabled = false;
  }
});

// ⌘↩ saves from anywhere; plain ↩ saves too, except in the quick note (where it
// adds a line break) and on the refresh button. Never while an IME is composing.
document.addEventListener("keydown", (e) => {
  if (e.key !== "Enter" || e.isComposing || els.save.disabled) return;
  const plain = !e.metaKey && !e.ctrlKey;
  if (plain && (e.shiftKey || e.target === els.comment || e.target === els.refresh)) return;
  e.preventDefault();
  els.save.click();
});
// -- Helpers ---------------------------------------------------------------

function updateSaveButton() {
  els.save.disabled = !els.noteSelect.value || !pageUrl;
}

// Remove only known tracking parameters; other query strings (e.g. YouTube's ?v=) are content
function stripTracking(url) {
  try {
    const u = new URL(url);
    const tracking = [...u.searchParams.keys()].filter((k) => TRACKING_PARAM.test(k));
    if (!tracking.length) return url;
    for (const k of tracking) u.searchParams.delete(k);
    return u.toString();
  } catch (_) {
    return url;
  }
}

function setStatus(msg, cls) {
  els.status.textContent = msg;
  els.status.className = "status" + (cls ? ` ${cls}` : "");
}
