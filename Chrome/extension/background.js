function tabIsLocalhost(tab) {
  if (!tab?.url) {
    return false;
  }
  try {
    const { hostname } = new URL(tab.url);
    return (
      hostname === "localhost" ||
      hostname === "127.0.0.1" ||
      hostname === "::1" ||
      hostname.endsWith(".localhost")
    );
  } catch {
    return false;
  }
}

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id) {
    return;
  }

  if (!tabIsLocalhost(tab)) {
    console.warn(
      "In-tab Cursor Agent is only available on http(s)://localhost or http(s)://127.0.0.1 pages.",
    );
    return;
  }

  try {
    await chrome.tabs.sendMessage(tab.id, { type: "cursor-agent-toggle" });
  } catch (error) {
    console.warn("Failed to toggle in-tab agent panel:", error);
  }
});
