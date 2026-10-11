// Stand-in for the chrome.* APIs with sample data, for rendering store screenshots
const prefix = "x-coredata://SAMPLE/ICNote/";
const folders = [
  { id: "f1", name: "Reading log" },
  { id: "f2", name: "Research / Sources" },
  { id: "f3", name: "Teaching / Seminar notes" },
  { id: "f4", name: "Notes" },
];
const now = Math.floor(Date.now() / 1000);
const notes = [
  [0, "p1", "2026 reading log", 0, now - 600],
  [0, "p2", "Essays to revisit", 0, now - 86400],
  [0, "p3", "Annotated sources", 1, now - 3600],
  [0, "p4", "Week 7 readings", 2, now - 7200],
  [0, "p5", "Ideas", 3, now - 9000],
];
const store = { lastFolder: "f1", lastNoteId: prefix + "p1", stripQuery: true };
window.chrome = {
  runtime: {
    id: "pckjhgfeeiebcdegmgnllooegobohcoc",
    lastError: null,
    connectNative() {
      const listeners = { message: [], disconnect: [] };
      return {
        onMessage: { addListener: (f) => listeners.message.push(f) },
        onDisconnect: { addListener: (f) => listeners.disconnect.push(f) },
        postMessage(msg) {
          const response = { status: "ok", protocol: 2, version: "1.0.0" };
          if (msg.action === "list") response.notes = { prefixes: [prefix], folders, notes };
          Promise.resolve().then(() => listeners.message.forEach((f) => f(response)));
        },
        disconnect() {},
      };
    },
  },
  tabs: {
    query: (_, cb) => cb([{ id: 1, title: "Commonplace book - Wikipedia", url: "https://en.wikipedia.org/wiki/Commonplace_book" }]),
    create() {},
  },
  scripting: {
    executeScript: async () => [{ result: "Locke published a method for indexing commonplace books in 1706. Worth trying for the reading log." }],
  },
  storage: {
    local: {
      get: (keys, cb) => {
        const out = {};
        for (const k of [].concat(keys)) if (k in store) out[k] = store[k];
        cb(out);
      },
      set: (obj, cb) => { Object.assign(store, obj); cb && cb(); },
      remove() {},
    },
  },
};
