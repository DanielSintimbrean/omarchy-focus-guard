"use strict";

const api = globalThis.browser || globalThis.chrome;
const nativeHostName = "io.github.danielsintimbrean.focus_guard";
const nativeRetryDelay = 2500;

let nativePort = null;
let retryTimer = null;
let lastStateKey = "";

function cleanDomains(values) {
  if (!Array.isArray(values)) return [];

  const domains = new Set();
  for (const value of values) {
    const domain = String(value || "").trim().toLowerCase().replace(/\.$/, "");
    if (!domain || domain.length > 253 || !domain.includes(".")) continue;
    if (!domain.split(".").every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) continue;
    domains.add(domain);
  }
  return [...domains].sort();
}

function domainMatches(hostname, domains) {
  const host = String(hostname || "").toLowerCase().replace(/\.$/, "");
  return domains.some((domain) => host === domain || host.endsWith(`.${domain}`));
}

async function updateRules(domains) {
  const existingRules = await api.declarativeNetRequest.getDynamicRules();
  const addRules = [];
  const chunkSize = 500;

  for (let offset = 0; offset < domains.length; offset += chunkSize) {
    addRules.push({
      id: Math.floor(offset / chunkSize) + 1,
      priority: 1,
      action: {
        type: "redirect",
        redirect: { extensionPath: "/blocked.html" }
      },
      condition: {
        requestDomains: domains.slice(offset, offset + chunkSize),
        resourceTypes: ["main_frame"]
      }
    });
  }

  await api.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: existingRules.map((rule) => rule.id),
    addRules
  });
}

async function refreshOpenTabs(domains) {
  if (domains.length === 0) return;

  const tabs = await api.tabs.query({});
  const reloads = [];
  for (const tab of tabs) {
    if (typeof tab.url !== "string" || !/^https?:\/\//i.test(tab.url)) continue;

    let hostname = "";
    try {
      hostname = new URL(tab.url).hostname;
    } catch (_) {
      continue;
    }

    if (domainMatches(hostname, domains) && Number.isInteger(tab.id)) {
      reloads.push(api.tabs.reload(tab.id));
    }
  }
  await Promise.allSettled(reloads);
}

async function applyState(message) {
  const domains = cleanDomains(message && message.domains);
  const active = message && message.active === true && domains.length > 0;
  const nextDomains = active ? domains : [];
  const nextKey = JSON.stringify({ active, domains: nextDomains });
  if (nextKey === lastStateKey) return;

  await updateRules(nextDomains);
  lastStateKey = nextKey;

  if (active) await refreshOpenTabs(nextDomains);
}

function scheduleReconnect() {
  if (retryTimer !== null) return;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    connectNativeHost();
  }, nativeRetryDelay);
}

function connectNativeHost() {
  if (nativePort) return;

  try {
    nativePort = api.runtime.connectNative(nativeHostName);
    nativePort.onMessage.addListener((message) => {
      applyState(message).catch((error) => console.error("Focus Guard rules could not be updated:", error));
    });
    nativePort.onDisconnect.addListener(() => {
      nativePort = null;
      scheduleReconnect();
    });
    nativePort.postMessage({ type: "watch" });
  } catch (error) {
    nativePort = null;
    console.error("Focus Guard native host is unavailable:", error);
    scheduleReconnect();
  }
}

api.runtime.onInstalled.addListener(connectNativeHost);
api.runtime.onStartup.addListener(connectNativeHost);
connectNativeHost();
