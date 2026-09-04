.pragma library

var PRESETS = [
  { key: "facebook", label: "Facebook", domains: ["facebook.com"], defaultEnabled: true },
  { key: "instagram", label: "Instagram", domains: ["instagram.com"], defaultEnabled: true },
  { key: "threads", label: "Threads", domains: ["threads.net"], defaultEnabled: true },
  { key: "x", label: "X / Twitter", domains: ["x.com", "twitter.com"], defaultEnabled: true },
  { key: "tiktok", label: "TikTok", domains: ["tiktok.com"], defaultEnabled: true },
  { key: "reddit", label: "Reddit", domains: ["reddit.com"], defaultEnabled: true },
  { key: "youtube", label: "YouTube", domains: [
    "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com", "ggpht.com",
    "youtubei.googleapis.com", "youtube-nocookie.com"
  ], defaultEnabled: true },
  { key: "twitch", label: "Twitch", domains: ["twitch.tv"], defaultEnabled: true },
  { key: "discord", label: "Discord", domains: ["discord.com", "discord.gg"], defaultEnabled: false },
  { key: "linkedin", label: "LinkedIn", domains: ["linkedin.com"], defaultEnabled: false },
  { key: "pinterest", label: "Pinterest", domains: ["pinterest.com"], defaultEnabled: false },
  { key: "snapchat", label: "Snapchat", domains: ["snapchat.com"], defaultEnabled: false }
]

function defaultPresetKeys() {
  var keys = []
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].defaultEnabled) keys.push(PRESETS[i].key)
  }
  return keys
}

function contains(list, value) {
  if (!Array.isArray(list)) return false
  for (var i = 0; i < list.length; i++) if (list[i] === value) return true
  return false
}

function validPresetKeys(value) {
  var raw = Array.isArray(value) ? value : []
  var keys = []
  for (var i = 0; i < PRESETS.length; i++) {
    if (contains(raw, PRESETS[i].key)) keys.push(PRESETS[i].key)
  }
  return keys
}

function normalizeDomain(value) {
  var domain = String(value || "").trim().toLowerCase()
  domain = domain.replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
  domain = domain.replace(/^\/\//, "")
  domain = domain.split(/[\/?#]/)[0]
  domain = domain.replace(/:\d+$/, "")
  domain = domain.replace(/^\*\./, "").replace(/^\.+|\.+$/g, "")
  return domain
}

function isValidDomain(value) {
  var domain = normalizeDomain(value)
  if (domain.length < 3 || domain.length > 253 || domain.indexOf(".") === -1) return false
  var labels = domain.split(".")
  for (var i = 0; i < labels.length; i++) {
    var label = labels[i]
    if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) return false
  }
  return true
}

function uniqueDomains(values) {
  var result = []
  var seen = ({})
  var raw = Array.isArray(values) ? values : []
  for (var i = 0; i < raw.length; i++) {
    var domain = normalizeDomain(raw[i])
    if (!isValidDomain(domain) || seen[domain]) continue
    seen[domain] = true
    result.push(domain)
  }
  result.sort()
  return result
}

function domainsFor(presetKeys, customDomains) {
  var domains = []
  var keys = validPresetKeys(presetKeys)
  for (var i = 0; i < PRESETS.length; i++) {
    if (!contains(keys, PRESETS[i].key)) continue
    for (var j = 0; j < PRESETS[i].domains.length; j++) domains.push(PRESETS[i].domains[j])
  }
  return uniqueDomains(domains.concat(customDomains || []))
}

function isValidTime(value) {
  var match = String(value || "").match(/^(\d{2}):(\d{2})$/)
  return !!match && Number(match[1]) < 24 && Number(match[2]) < 60
}

function timeMinutes(value) {
  if (!isValidTime(value)) return -1
  var parts = String(value).split(":")
  return Number(parts[0]) * 60 + Number(parts[1])
}

function isValidSchedule(start, end) {
  var startMinutes = timeMinutes(start)
  var endMinutes = timeMinutes(end)
  return startMinutes >= 0 && endMinutes >= 0 && startMinutes < endMinutes
}

function defaultConfig() {
  return {
    version: 1,
    startTime: "09:00",
    endTime: "17:00",
    enabledPresets: defaultPresetKeys(),
    customDomains: []
  }
}

function cleanConfig(value) {
  var defaults = defaultConfig()
  var obj = value && typeof value === "object" ? value : ({})
  var start = isValidTime(obj.startTime) ? String(obj.startTime) : defaults.startTime
  var end = isValidTime(obj.endTime) ? String(obj.endTime) : defaults.endTime
  if (!isValidSchedule(start, end)) {
    start = defaults.startTime
    end = defaults.endTime
  }
  return {
    version: 1,
    startTime: start,
    endTime: end,
    enabledPresets: Array.isArray(obj.enabledPresets) ? validPresetKeys(obj.enabledPresets) : defaults.enabledPresets,
    customDomains: uniqueDomains(obj.customDomains)
  }
}

function formatClock(epochSeconds) {
  var epoch = Number(epochSeconds) || 0
  if (epoch <= 0) return ""
  var date = new Date(epoch * 1000)
  return date.toLocaleString(Qt.locale(), "ddd HH:mm")
}

function dayIndex() {
  var day = new Date().getDay()
  return day === 0 ? 6 : day - 1
}

function fileUrlPath(value) {
  var text = String(value || "")
  if (text.indexOf("file://") === 0) text = text.substring(7)
  try { return decodeURIComponent(text) } catch (e) { return text }
}
