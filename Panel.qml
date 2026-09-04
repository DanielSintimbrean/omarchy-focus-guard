import QtQuick
import qs.Commons
import qs.Ui
import "Guard.js" as Guard

Panel {
  id: root
  moduleName: "io.github.danielsintimbrean.focus-guard"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool openedFromHotkey: false
  property string viewMode: "main"

  property string draftStart: "09:00"
  property string draftEnd: "17:00"
  property var draftPresets: []
  property var draftCustom: []
  property string formError: ""

  property string challengeExpression: ""
  property int challengeAnswer: 0
  property string challengeError: ""

  readonly property var barIdentity: hostWidget || root
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property color dimmer: Qt.darker(fg, 1.85)
  readonly property color lockColor: Color.accent
  readonly property color overrideColor: "#d8a657"
  readonly property color stateColor: service && service.active
    ? lockColor
    : (service && service.overridden ? overrideColor : dim)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool editing: startField.activeFocus || endField.activeFocus
    || customDomainField.activeFocus || challengeField.activeFocus

  function open() {
    openedFromHotkey = false
    viewMode = "main"
    copyDraft()
    root.controller.show()
    if (service) service.refreshStatus()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    viewMode = "main"
    copyDraft()
    root.controller.show()
    if (service) service.refreshStatus()
  }

  function close() {
    viewMode = "main"
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function copyDraft() {
    if (!service) return
    draftStart = service.startTime
    draftEnd = service.endTime
    draftPresets = service.enabledPresets.slice()
    draftCustom = service.customDomains.slice()
    formError = ""
  }

  function presetSelected(key) {
    return Guard.contains(draftPresets, key)
  }

  function togglePreset(key) {
    var next = draftPresets.slice()
    var found = -1
    for (var i = 0; i < next.length; i++) if (next[i] === key) found = i
    if (found >= 0) next.splice(found, 1)
    else next.push(key)
    draftPresets = Guard.validPresetKeys(next)
  }

  function addCustomDomain() {
    var domain = Guard.normalizeDomain(customDomainField.text)
    if (!Guard.isValidDomain(domain)) {
      formError = "Enter a domain such as news.example.com."
      return
    }
    draftCustom = Guard.uniqueDomains(draftCustom.concat([domain]))
    customDomainField.text = ""
    formError = ""
  }

  function removeCustomDomain(index) {
    var next = draftCustom.slice()
    next.splice(index, 1)
    draftCustom = next
  }

  function saveSettings() {
    if (!service) return
    var error = service.saveSettings(draftStart, draftEnd, draftPresets, draftCustom)
    if (error) {
      formError = error
      return
    }
    formError = ""
    viewMode = "main"
  }

  function randomOperand() {
    return 100 + Math.floor(Math.random() * 900)
  }

  function generateChallenge(message) {
    var first = randomOperand()
    var second = randomOperand()
    var third = randomOperand()
    var firstSign = Math.random() < 0.5 ? 1 : -1
    var secondSign = Math.random() < 0.5 ? 1 : -1
    challengeAnswer = first + firstSign * second + secondSign * third
    challengeExpression = first + (firstSign > 0 ? " + " : " − ")
      + second + (secondSign > 0 ? " + " : " − ") + third
    challengeError = String(message || "")
    challengeField.text = ""
    Qt.callLater(function() { challengeField.forceActiveFocus() })
  }

  function beginChallenge() {
    viewMode = "challenge"
    generateChallenge("")
  }

  function submitChallenge() {
    var answer = String(challengeField.text || "").trim()
    if (!/^-?\d+$/.test(answer) || Number(answer) !== challengeAnswer) {
      generateChallenge("Incorrect. A new problem has been generated.")
      return
    }
    challengeError = ""
    viewMode = "main"
    keyCatcher.forceActiveFocus()
    if (service) service.disableUntilNextPeriod()
  }

  function primaryAction() {
    if (!service || service.busy) return
    if (!service.installed) service.installHelper()
    else if (service.active) beginChallenge()
    else if (service.recovery) service.resumeFromRecovery()
    else service.enableNow()
  }

  function primaryLabel() {
    if (!service) return "Checking…"
    if (service.busy) return "Working…"
    if (!service.installed) return "Install system blocker"
    if (service.active) return "Pause blocking"
    if (service.recovery) return "Resume schedule"
    return "Enable now"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing

      onCloseRequested: {
        if (root.viewMode === "main") root.close()
        else {
          root.viewMode = "main"
          root.copyDraft()
          keyCatcher.forceActiveFocus()
        }
      }
      onTabRequested: function(direction) {
        if (root.viewMode === "main") root.switchPanel(direction)
      }
      onActivateRequested: if (root.viewMode === "main") root.primaryAction()

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Column {
            visible: root.viewMode === "main"
            width: parent.width
            spacing: Style.space(12)

            BorderSurface {
              width: parent.width
              implicitHeight: statusCardContent.implicitHeight + Style.space(28)
              radius: Style.cornerRadius
              color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.08)
              borderSpec: Border.flat(Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.48), 1)

              Column {
                id: statusCardContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(12)

                Row {
                  width: parent.width
                  spacing: Style.space(14)

                  Rectangle {
                    width: Style.space(58)
                    height: width
                    radius: Math.max(Style.cornerRadius, width / 2)
                    color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.13)
                    border.width: 1
                    border.color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.7)

                    Text {
                      anchors.centerIn: parent
                      text: root.service && root.service.active ? "󰦝" : "󰌿"
                      color: root.stateColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.display
                    }
                  }

                  Column {
                    width: parent.width - Style.space(72)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)

                    Text {
                      width: parent.width
                      text: root.service ? root.service.statusTitle : "Focus Guard"
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: root.service ? root.service.statusMeta : ""
                      color: root.stateColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.1
                      elide: Text.ElideRight
                    }

                    Text {
                      width: parent.width
                      text: root.service ? root.service.statusDetail : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                Row {
                  id: workweekRail
                  width: parent.width
                  spacing: Style.space(5)

                  Repeater {
                    model: ["M", "T", "W", "T", "F"]

                    Rectangle {
                      required property string modelData
                      required property int index
                      width: (workweekRail.width - workweekRail.spacing * 4) / 5
                      height: Style.space(18)
                      radius: Math.min(Style.cornerRadius, Style.space(4))
                      color: index === Guard.dayIndex() && index < 5
                        ? Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.3)
                        : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
                      border.width: index === Guard.dayIndex() && index < 5 ? 1 : 0
                      border.color: root.stateColor

                      Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.index === Guard.dayIndex() ? root.fg : root.dimmer
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: parent.index === Guard.dayIndex()
                      }
                    }
                  }
                }
              }
            }

            BorderSurface {
              visible: root.service && (root.service.errorMessage !== "" || root.service.infoMessage !== "")
              width: parent.width
              implicitHeight: messageText.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: root.service && root.service.errorMessage !== ""
                ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12)
                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
              borderSpec: Border.flat(root.service && root.service.errorMessage !== "" ? Color.urgent : root.dimmer, 1)

              Text {
                id: messageText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                text: root.service && root.service.errorMessage !== ""
                  ? root.service.errorMessage
                  : (root.service ? root.service.infoMessage : "")
                color: root.service && root.service.errorMessage !== "" ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Button {
              width: parent.width
              text: root.primaryLabel()
              iconText: root.service && root.service.active ? "󰌿" : "󰦝"
              foreground: root.fg
              accent: root.stateColor
              fontFamily: root.fontFamily
              bordered: true
              selected: root.service && !root.service.busy
              focusable: true
              enabled: root.service && !root.service.busy
              horizontalPadding: Style.space(16)
              verticalPadding: Style.space(10)
              onClicked: root.primaryAction()
            }

            BorderSurface {
              width: parent.width
              implicitHeight: scheduleSummary.implicitHeight + Style.space(20)
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
              borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
              radius: Style.cornerRadius

              Row {
                id: scheduleSummary
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)

                Column {
                  width: parent.width - editSettingsButton.width
                  spacing: Style.space(2)

                  Text {
                    text: "WORK WINDOW"
                    color: root.dimmer
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }

                  Text {
                    text: root.service ? root.service.startTime + "  →  " + root.service.endTime : "09:00  →  17:00"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    text: root.service ? root.service.blockedDomains.length + " domains · Monday to Friday" : "Monday to Friday"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelActionButton {
                  id: editSettingsButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰒓"
                  tooltipText: "Edit schedule and sites"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  focusable: true
                  bordered: true
                  onClicked: {
                    root.copyDraft()
                    root.viewMode = "settings"
                  }
                }
              }
            }

            Text {
              visible: root.service && !root.service.installed
              width: parent.width
              text: "Setup installs dnsmasq and briefly restarts DNS. An administrator prompt appears once."
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            visible: root.viewMode === "settings"
            width: parent.width
            spacing: Style.space(12)

            Row {
              width: parent.width
              spacing: Style.space(8)

              PanelActionButton {
                iconText: "󰅁"
                tooltipText: "Back"
                foreground: root.fg
                fontFamily: root.fontFamily
                focusable: true
                bordered: true
                onClicked: {
                  root.copyDraft()
                  root.viewMode = "main"
                }
              }

              Column {
                width: parent.width - Style.space(38)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: "Schedule and sites"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  text: "Changes apply to the whole computer"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            PanelSectionHeader {
              text: "Work window"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.space(4)

                Text {
                  text: "START"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
                TextField {
                  id: startField
                  width: parent.width
                  text: root.draftStart
                  placeholderText: "09:00"
                  foreground: root.fg
                  accent: Color.accent
                  inputMethodHints: Qt.ImhFormattedNumbersOnly
                  onTextChanged: root.draftStart = text
                }
              }

              Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Style.space(4)

                Text {
                  text: "END"
                  color: root.dimmer
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }
                TextField {
                  id: endField
                  width: parent.width
                  text: root.draftEnd
                  placeholderText: "17:00"
                  foreground: root.fg
                  accent: Color.accent
                  inputMethodHints: Qt.ImhFormattedNumbersOnly
                  onTextChanged: root.draftEnd = text
                }
              }
            }

            Text {
              width: parent.width
              text: "Monday to Friday · local system time"
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            PanelSeparator {
              width: parent.width
              foreground: root.fg
            }

            PanelSectionHeader {
              text: "Preconfigured sites"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Grid {
              id: presetGrid
              width: parent.width
              columns: 2
              columnSpacing: Style.space(7)
              rowSpacing: Style.space(7)

              Repeater {
                model: Guard.PRESETS

                Button {
                  required property var modelData
                  width: (presetGrid.width - presetGrid.columnSpacing) / 2
                  text: modelData.label
                  iconText: root.presetSelected(modelData.key) ? "✓" : ""
                  foreground: root.fg
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  selected: root.presetSelected(modelData.key)
                  bordered: true
                  focusable: true
                  leftAlign: true
                  onClicked: root.togglePreset(modelData.key)
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.fg
            }

            PanelSectionHeader {
              text: "Custom domains"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: root.draftCustom

                BorderSurface {
                  required property string modelData
                  required property int index
                  width: parent.width
                  implicitHeight: Math.max(customDomainLabel.implicitHeight, removeDomainButton.implicitHeight) + Style.space(8)
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.035)
                  radius: Style.cornerRadius
                  borderSpec: Border.controlSpec("normal", root.fg, Color.accent)

                  Text {
                    id: customDomainLabel
                    anchors.left: parent.left
                    anchors.right: removeDomainButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(8)
                    text: parent.modelData
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  PanelActionButton {
                    id: removeDomainButton
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(5)
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰆴"
                    tooltipText: "Remove domain"
                    foreground: root.fg
                    hoverColor: Color.urgent
                    fontFamily: root.fontFamily
                    onClicked: root.removeCustomDomain(parent.index)
                  }
                }
              }

              Text {
                visible: root.draftCustom.length === 0
                width: parent.width
                text: "No custom domains"
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(7)

              TextField {
                id: customDomainField
                width: parent.width - addDomainButton.width - parent.spacing
                placeholderText: "example.com"
                foreground: root.fg
                accent: Color.accent
                onAccepted: root.addCustomDomain()
              }

              Button {
                id: addDomainButton
                text: "Add"
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                onClicked: root.addCustomDomain()
              }
            }

            Text {
              width: parent.width
              text: "Each entry blocks the domain and every subdomain."
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.formError !== ""
              width: parent.width
              text: root.formError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(7)

              Button {
                text: "Cancel"
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                focusable: true
                onClicked: {
                  root.copyDraft()
                  root.viewMode = "main"
                }
              }

              Button {
                text: "Save changes"
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.fontFamily
                selected: true
                bordered: true
                focusable: true
                onClicked: root.saveSettings()
              }
            }
          }

          Column {
            visible: root.viewMode === "challenge"
            width: parent.width
            spacing: Style.space(14)

            Row {
              width: parent.width
              spacing: Style.space(8)

              PanelActionButton {
                iconText: "󰅁"
                tooltipText: "Keep blocking"
                foreground: root.fg
                fontFamily: root.fontFamily
                focusable: true
                bordered: true
                onClicked: {
                  root.viewMode = "main"
                  keyCatcher.forceActiveFocus()
                }
              }

              Column {
                width: parent.width - Style.space(38)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: "Pause Focus Guard"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  text: "Solve one problem to continue"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            BorderSurface {
              width: parent.width
              implicitHeight: challengeColumn.implicitHeight + Style.space(34)
              color: Qt.rgba(root.lockColor.r, root.lockColor.g, root.lockColor.b, 0.07)
              borderSpec: Border.flat(Qt.rgba(root.lockColor.r, root.lockColor.g, root.lockColor.b, 0.5), 1)
              radius: Style.cornerRadius

              Column {
                id: challengeColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(16)
                anchors.rightMargin: Style.space(16)
                spacing: Style.space(10)

                Text {
                  width: parent.width
                  text: root.challengeExpression
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: parent.width
                  text: "Type the exact result. Negative answers are allowed."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
            }

            TextField {
              id: challengeField
              width: parent.width
              placeholderText: "Answer"
              foreground: root.fg
              accent: root.lockColor
              inputMethodHints: Qt.ImhFormattedNumbersOnly
              horizontalAlignment: TextInput.AlignHCenter
              font.pixelSize: Style.font.subtitle
              onAccepted: root.submitChallenge()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.viewMode = "main"
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.challengeError !== ""
              width: parent.width
              text: root.challengeError
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: root.service && root.service.busy ? "Working…" : "Check answer"
              foreground: root.fg
              accent: root.lockColor
              fontFamily: root.fontFamily
              selected: true
              bordered: true
              focusable: true
              enabled: root.service && !root.service.busy
              verticalPadding: Style.space(9)
              onClicked: root.submitChallenge()
            }

            Text {
              width: parent.width
              text: "A wrong answer creates a completely new problem."
              color: root.dimmer
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }

  Connections {
    target: root.service

    function onActiveChanged() {
      if (root.viewMode === "challenge" && root.service && !root.service.active) {
        root.viewMode = "main"
        keyCatcher.forceActiveFocus()
      }
    }
  }
}
