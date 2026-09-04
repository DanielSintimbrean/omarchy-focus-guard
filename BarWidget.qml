import QtQuick
import qs.Commons
import qs.Ui
import "Guard.js" as Guard

BarWidget {
  id: root
  moduleName: "io.github.danielsintimbrean.focus-guard"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool guardActive: service ? service.active : false

  readonly property string tooltip: {
    if (!service) return "Focus Guard"
    if (!service.installed) return "Focus Guard · setup required"
    if (!service.statusKnown) return "Focus Guard · checking"
    if (service.active) return "Focus Guard · " + service.blockedDomains.length + " domains blocked"
    if (service.recovery) return "Focus Guard · recovery mode"
    if (service.overridden) return "Focus Guard · paused until " + Guard.formatClock(service.overrideUntil)
    return "Focus Guard · open time"
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰦝"  // nf-md-shield_lock
    slotSize: Style.bar.statusSlot
    active: root.guardActive
    dimmed: !root.guardActive
    opacity: root.service && root.service.installed ? 1.0 : 0.5
    tooltipText: root.tooltip

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
    }
  }
}
