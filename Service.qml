import QtQuick
import Quickshell
import Quickshell.Io
import "Guard.js" as Guard

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: String(Quickshell.env("HOME") || "")
  readonly property string configDir: home + "/.config/focus-guard"
  readonly property string configPath: configDir + "/config.json"
  readonly property string controllerPath: "/usr/local/bin/focus-guardctl"
  readonly property string installScriptPath: Guard.fileUrlPath(Qt.resolvedUrl("system/install.sh"))

  property bool installed: false
  property bool configLoaded: false
  property bool statusKnown: false
  property bool active: false
  property bool expectedActive: false
  property bool healthy: true
  property bool scheduled: false
  property bool manual: false
  property bool overridden: false
  property bool recovery: false
  property string mode: "checking"
  property int manualUntil: 0
  property int overrideUntil: 0
  property int systemDomainCount: 0

  property string startTime: "09:00"
  property string endTime: "17:00"
  property var enabledPresets: Guard.defaultPresetKeys()
  property var customDomains: []
  readonly property var presets: Guard.PRESETS
  readonly property var blockedDomains: Guard.domainsFor(enabledPresets, customDomains)

  property string errorMessage: ""
  property string infoMessage: ""
  property string actionKind: ""
  property string actionOutput: ""
  property string actionError: ""
  property bool pendingConfigSync: false
  readonly property bool busy: actionProcess.running

  readonly property string statusTitle: {
    if (!installed) return "Setup required"
    if (!statusKnown) return "Checking guard"
    if (!healthy) return "Guard needs attention"
    if (active) return "Focus locked"
    if (recovery) return "Recovery mode"
    if (overridden) return "Override active"
    return "Open time"
  }

  readonly property string statusMeta: {
    if (!installed) return "SYSTEM HELPER NOT INSTALLED"
    if (!statusKnown) return "READING SYSTEM STATE"
    if (active && manual) return "MANUAL SESSION"
    if (active && scheduled) return "WORK SCHEDULE"
    if (recovery) return "BLOCKING DISABLED BY RECOVERY"
    if (overridden) return "UNTIL " + Guard.formatClock(overrideUntil).toUpperCase()
    return "MONDAY TO FRIDAY"
  }

  readonly property string statusDetail: {
    if (!installed) return "Install the blocker once to control DNS for the whole computer."
    if (!healthy) return "The requested state and DNS state do not match. Run setup again to repair it."
    if (active && manual) return blockedDomains.length + " domains · until " + Guard.formatClock(manualUntil)
    if (active) return blockedDomains.length + " domains · " + startTime + "–" + endTime
    if (recovery) return "Run setup again or enable a manual session to resume."
    if (overridden) return "Blocking resumes " + Guard.formatClock(overrideUntil)
    return "Scheduled " + startTime + "–" + endTime
  }

  function configJson() {
    return JSON.stringify({
      version: 1,
      startTime: startTime,
      endTime: endTime,
      enabledPresets: enabledPresets,
      customDomains: customDomains
    }, null, 2) + "\n"
  }

  function loadConfig(text) {
    var parsed = null
    try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = null }
    var config = Guard.cleanConfig(parsed)
    startTime = config.startTime
    endTime = config.endTime
    enabledPresets = config.enabledPresets.slice()
    customDomains = config.customDomains.slice()
    configLoaded = true
    if (!parsed) configFile.setText(configJson())
  }

  function saveSettings(nextStart, nextEnd, nextPresets, nextCustomDomains) {
    var start = String(nextStart || "").trim()
    var end = String(nextEnd || "").trim()
    if (!Guard.isValidSchedule(start, end)) {
      return "Use 24-hour times and make the end later than the start."
    }

    var custom = []
    var rawCustom = Array.isArray(nextCustomDomains) ? nextCustomDomains : []
    for (var i = 0; i < rawCustom.length; i++) {
      var domain = Guard.normalizeDomain(rawCustom[i])
      if (!Guard.isValidDomain(domain)) return "Invalid domain: " + rawCustom[i]
      custom.push(domain)
    }

    var presets = Guard.validPresetKeys(nextPresets)
    custom = Guard.uniqueDomains(custom)
    if (Guard.domainsFor(presets, custom).length === 0) {
      return "Select at least one site or add a custom domain."
    }

    startTime = start
    endTime = end
    enabledPresets = presets.slice()
    customDomains = custom
    configFile.setText(configJson())
    errorMessage = ""
    infoMessage = installed ? "Saving settings…" : "Settings saved. Install the blocker to apply them."
    if (installed) syncConfig()
    return ""
  }

  function parseStatus(text) {
    var data
    try { data = JSON.parse(String(text || "")) } catch (e) {
      healthy = false
      errorMessage = "The system helper returned an unreadable status."
      return
    }

    var knewStatus = statusKnown
    var wasActive = active
    active = data.active === true
    expectedActive = data.expectedActive === true
    healthy = data.healthy === true
    scheduled = data.scheduled === true
    manual = data.manual === true
    overridden = data.overridden === true
    recovery = data.recovery === true
    mode = String(data.mode || "inactive")
    manualUntil = Number(data.manualUntil) || 0
    overrideUntil = Number(data.overrideUntil) || 0
    systemDomainCount = Number(data.domainCount) || 0
    statusKnown = true
    if (knewStatus && wasActive !== active) notifyState(active)
  }

  function refreshStatus() {
    if (!installed || statusProcess.running) return
    statusOutput = ""
    statusError = ""
    statusProcess.command = [controllerPath, "status"]
    statusProcess.running = true
  }

  function startAction(kind, command) {
    if (actionProcess.running) return false
    actionKind = kind
    actionOutput = ""
    actionError = ""
    errorMessage = ""
    actionProcess.command = command
    actionProcess.running = true
    return true
  }

  function installHelper() {
    infoMessage = "Installing the system blocker…"
    return startAction("setup", ["pkexec", "/usr/bin/bash", installScriptPath])
  }

  function syncConfig() {
    if (!installed) return false
    if (actionProcess.running) {
      pendingConfigSync = true
      return true
    }
    var command = ["pkexec", controllerPath, "configure", startTime, endTime]
    for (var i = 0; i < blockedDomains.length; i++) command.push(blockedDomains[i])
    return startAction("configure", command)
  }

  function enableNow() {
    if (!installed) return false
    infoMessage = "Starting focus session…"
    return startAction("enable", ["pkexec", controllerPath, "enable"])
  }

  function disableUntilNextPeriod() {
    if (!installed) return false
    infoMessage = "Applying override…"
    return startAction("disable", ["pkexec", controllerPath, "disable"])
  }

  function resumeFromRecovery() {
    if (!installed) return false
    infoMessage = "Resuming schedule…"
    return startAction("resume", ["pkexec", controllerPath, "resume"])
  }

  function friendlyActionError(exitCode, output) {
    var message = String(output || "").trim()
    if (exitCode === 126 || /dismissed|cancelled|canceled/i.test(message))
      return "Administrator authentication was cancelled."
    var lines = message.split("\n")
    return lines.length ? lines[lines.length - 1] : "The Focus Guard command failed."
  }

  function notifyState(isActive) {
    notificationProcess.command = [
      "notify-send",
      "--app-name=Focus Guard",
      isActive ? "Focus Guard enabled" : "Focus Guard disabled",
      isActive ? blockedDomains.length + " distracting domains are blocked." : "Distraction blocking is off."
    ]
    notificationProcess.running = true
  }

  Process {
    id: mkdirProcess
    command: ["mkdir", "-p", root.configDir]
    onExited: configFile.reload()
  }

  FileView {
    id: configFile
    path: root.configPath
    printErrors: false
    blockWrites: true
    atomicWrites: true
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
  }

  Process {
    id: checkProcess
    command: ["test", "-x", root.controllerPath]
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      root.statusKnown = false
      if (root.installed) root.refreshStatus()
      else root.mode = "uninstalled"
    }
  }

  property string statusOutput: ""
  property string statusError: ""

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: root.statusOutput = text
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: root.statusError = text
    }
    onExited: function(exitCode) {
      var output = String(statusStdout.text || root.statusOutput || "")
      var error = String(statusStderr.text || root.statusError || "")
      if (exitCode === 0) root.parseStatus(output)
      else {
        if (exitCode === 127 || /no such file|not found/i.test(error)) {
          root.installed = false
          root.statusKnown = false
          root.mode = "uninstalled"
        }
        root.healthy = false
        root.errorMessage = root.friendlyActionError(exitCode, error || output)
      }
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root.actionOutput = text
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root.actionError = text
    }
    onExited: function(exitCode) {
      var output = String(actionStdout.text || root.actionOutput || "")
      var error = String(actionStderr.text || root.actionError || "")
      var finishedKind = root.actionKind
      root.actionKind = ""
      if (exitCode !== 0) {
        root.infoMessage = ""
        root.errorMessage = root.friendlyActionError(exitCode, error || output)
      } else {
        root.errorMessage = ""
        if (finishedKind === "setup") {
          root.installed = true
          root.infoMessage = "System blocker installed. Applying your settings…"
          root.pendingConfigSync = true
        } else if (finishedKind === "configure") {
          root.infoMessage = "Settings saved."
        } else if (finishedKind === "enable") {
          root.infoMessage = "Focus session started."
        } else if (finishedKind === "disable") {
          root.infoMessage = "Blocking paused until the next work period."
        } else if (finishedKind === "resume") {
          root.infoMessage = "Schedule resumed."
        }
      }
      refreshDelay.restart()
      messageTimer.restart()
      if (root.pendingConfigSync && root.installed) {
        root.pendingConfigSync = false
        Qt.callLater(root.syncConfig)
      }
    }
  }

  Process {
    id: notificationProcess
    command: []
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.installed
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: refreshDelay
    interval: 450
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: messageTimer
    interval: 3500
    onTriggered: root.infoMessage = ""
  }

  IpcHandler {
    target: "focus-guard"

    function status(): string {
      return JSON.stringify({
        installed: root.installed,
        active: root.active,
        mode: root.mode,
        healthy: root.healthy,
        schedule: root.startTime + "-" + root.endTime,
        domains: root.blockedDomains.length
      })
    }

    function enable(): string { return root.enableNow() ? "ok" : "unavailable" }
    function refresh(): string { root.refreshStatus(); return "ok" }
  }

  Component.onCompleted: {
    mkdirProcess.running = true
    checkProcess.running = true
  }
}
