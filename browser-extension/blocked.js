"use strict";

const api = globalThis.browser || globalThis.chrome;

document.getElementById("close-tab").addEventListener("click", async () => {
  const tab = await api.tabs.getCurrent();
  if (tab && Number.isInteger(tab.id)) await api.tabs.remove(tab.id);
});
