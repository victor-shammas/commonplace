let panel = null;

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === "toggle-panel") {
    if (panel) {
      closePanel();
    } else {
      openPanel();
    }
  }
});

function openPanel() {
  panel = document.createElement("div");
  panel.id = "url-notes-ext-panel";
  Object.assign(panel.style, {
    position: "fixed",
    top: "16px",
    right: "16px",
    width: "360px",
    zIndex: "2147483647",
    borderRadius: "12px",
    boxShadow: "0 8px 32px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.08)",
    overflow: "hidden",
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    background: "#fff",
  });

  const header = document.createElement("div");
  Object.assign(header.style, {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    padding: "8px 12px",
    background: "#f5f5f7",
    borderBottom: "1px solid #e5e5e7",
    cursor: "default",
    userSelect: "none",
  });

  const title = document.createElement("span");
  title.textContent = "URL to Notes";
  Object.assign(title.style, {
    fontSize: "12px",
    fontWeight: "600",
    color: "#1d1d1f",
  });

  const closeBtn = document.createElement("button");
  closeBtn.textContent = "✕";
  Object.assign(closeBtn.style, {
    background: "none",
    border: "none",
    fontSize: "14px",
    cursor: "pointer",
    color: "#86868b",
    padding: "2px 4px",
    lineHeight: "1",
    borderRadius: "4px",
  });
  closeBtn.addEventListener("mouseenter", () => (closeBtn.style.color = "#1d1d1f"));
  closeBtn.addEventListener("mouseleave", () => (closeBtn.style.color = "#86868b"));
  closeBtn.addEventListener("click", closePanel);

  header.appendChild(title);
  header.appendChild(closeBtn);

  const iframe = document.createElement("iframe");
  iframe.src = chrome.runtime.getURL("popup.html");
  Object.assign(iframe.style, {
    width: "100%",
    height: "460px",
    border: "none",
    display: "block",
  });

  panel.appendChild(header);
  panel.appendChild(iframe);
  document.body.appendChild(panel);

  iframe.addEventListener("load", () => {
    iframe.contentWindow.postMessage(
      { type: "pageInfo", title: document.title, url: location.href },
      "*"
    );
  });

  window.addEventListener("message", handleIframeMessage);
  document.addEventListener("keydown", handleEscape);
}

function closePanel() {
  if (panel) {
    panel.remove();
    panel = null;
    window.removeEventListener("message", handleIframeMessage);
    document.removeEventListener("keydown", handleEscape);
  }
}

function handleIframeMessage(e) {
  if (e.data && e.data.type === "close-panel") {
    closePanel();
  }
}

function handleEscape(e) {
  if (e.key === "Escape") {
    closePanel();
  }
}
