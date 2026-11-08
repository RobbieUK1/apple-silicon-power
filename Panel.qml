import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Battery.js" as Battery

Panel {
  id: root
  moduleName: "robbie.apple-silicon-power"
  ipcTarget: "robbie.apple-silicon-power"

  property var info: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  property bool thresholdBusy: false
  property string thresholdError: ""

  readonly property bool present: info.present !== false
  readonly property bool haveData: info.present === true
  readonly property int percentage: info.percentage === undefined || info.percentage === null ? -1 : Number(info.percentage)
  readonly property string state: String(info.state || "")
  readonly property bool acOnline: info.acOnline === true
  readonly property bool discharging: haveData && state === "discharging" && !acOnline
  readonly property bool holding: haveData && info.holding === true
  readonly property bool charging: haveData && acOnline && (state === "charging" || state === "pending-charge") && !holding
  readonly property bool full: haveData && (state === "full" || (acOnline && percentage >= 100))
  readonly property bool healthKnown: info.healthPercent !== undefined && info.healthPercent !== null
  readonly property real healthPercent: healthKnown ? Math.max(0, Math.min(100, Number(info.healthPercent))) : 0
  readonly property int thresholdEnd: info.thresholdEnd === undefined || info.thresholdEnd === null ? -1 : Number(info.thresholdEnd)
  readonly property int thresholdStart: info.thresholdStart === undefined || info.thresholdStart === null ? -1 : Number(info.thresholdStart)
  readonly property bool thresholdSupported: info.thresholdSupported === true
  readonly property bool showPercentage: setting("showPercentage", true) === true
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string limitScript: Qt.resolvedUrl("set-charge-limit.sh").toString().replace(/^file:\/\//, "")

  readonly property real batteryFraction: percentage < 0 ? 0 : Math.max(0, Math.min(1, percentage / 100))
  readonly property color healthColor: healthPercent >= 80 ? Color.accent : (healthPercent >= 60 ? root.fg : Color.urgent)

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function n(value, decimals) {
    return Commons.I18n.formatNumber(value, decimals)
  }

  function batteryIcon() {
    return Battery.batteryIcon(root.info, root.charging)
  }

  function statusLabel() {
    if (!root.haveData) return strings.t("loading")
    if (root.holding) return strings.t("statusHolding").arg(root.n(root.thresholdEnd))
    if (root.full) return strings.t("statusFull")
    if (root.charging) return strings.t("statusCharging")
    if (root.discharging) return strings.t("statusDischarging")
    return strings.t("statusIdle")
  }

  function duration(value) {
    if (value === undefined || value === null || !isFinite(value) || value < 1) return "—"
    var minutes = Math.round(value)
    var hours = Math.floor(minutes / 60)
    var rest = minutes % 60
    if (hours > 0 && rest > 0) return strings.t("durationHoursMinutes").arg(root.n(hours)).arg(root.n(rest))
    if (hours > 0) return strings.t("durationHours").arg(root.n(hours))
    return strings.t("durationMinutes").arg(root.n(rest))
  }

  readonly property string percentageText: root.percentage < 0 ? "—" : root.n(root.percentage) + "%"
  readonly property string timeLabel: root.discharging ? strings.t("timeLeft") : root.charging ? strings.t("timeToFull") : strings.t("time")
  readonly property string timeValue: info.timeMinutes === undefined || info.timeMinutes === null ? "—" : root.duration(Number(info.timeMinutes))
  readonly property string rateLabel: root.discharging ? strings.t("dischargeRate") : root.charging ? strings.t("chargeRate") : strings.t("power")
  readonly property string rateValue: info.powerW === undefined || info.powerW === null
    ? "—"
    : root.n(info.powerW, 1) + " W" + (root.discharging ? " ↓" : root.charging ? " ↑" : "")
  readonly property string voltageLabel: root.discharging ? strings.t("dischargeVoltage") : root.charging ? strings.t("chargeVoltage") : strings.t("voltage")
  readonly property string voltageValue: info.voltageV === undefined || info.voltageV === null ? "—" : root.n(info.voltageV, 2) + " V"
  readonly property string temperatureValue: info.temperatureC === undefined || info.temperatureC === null ? "—" : root.n(info.temperatureC, 1) + " °C"
  readonly property string cyclesValue: info.cycles === undefined || info.cycles === null ? "—" : root.n(info.cycles)
  readonly property string healthValue: root.healthKnown ? strings.t("healthOfNew").arg(root.n(root.healthPercent, 1)) : "—"
  readonly property string capacityValue: (info.energyFullWh === undefined || info.energyFullWh === null || info.energyFullDesignWh === undefined || info.energyFullDesignWh === null)
    ? ""
    : strings.t("healthCapacity").arg(root.n(info.energyFullWh, 1)).arg(root.n(info.energyFullDesignWh, 1))
  readonly property string limitNote: {
    if (!root.thresholdSupported) return ""
    if (root.thresholdEnd >= 0 && root.thresholdEnd < 100)
      return strings.t("limitRestart").arg(root.n(root.thresholdStart >= 0 ? root.thresholdStart : root.thresholdEnd))
    return strings.t("limitFullNote")
  }
  readonly property string tooltipText: {
    if (!root.haveData) return strings.t("loading")
    var parts = [root.percentageText, root.statusLabel()]
    if (root.timeValue !== "—") parts.push(root.timeValue)
    if (root.rateValue !== "—") parts.push(root.rateValue)
    if (root.voltageValue !== "—") parts.push(root.voltageValue)
    return parts.join(" · ")
  }

  function acceptInfo(raw) {
    var data = Battery.parse(raw)
    if (!data || data.present === undefined) return
    info = data
  }

  function acceptProfiles(raw) {
    var parsed = Battery.parseProfiles(raw)
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    var idx = profiles.indexOf(activeProfile)
    if (idx >= 0 && !cursorActive) profileIndex = idx
  }

  function refresh() {
    if (!batteryProc.running) batteryProc.running = true
  }

  function refreshProfiles() {
    if (!profilesProc.running) profilesProc.running = true
  }

  function setProfile(name) {
    if (!name || profileProc.running) return
    profileProc.command = ["omarchy-powerprofiles-set", "autodetect", String(name)]
    profileProc.running = true
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function moveProfileCursor(delta) {
    profileIndex = Battery.selectProfileIndex(profileIndex, delta, profiles.length)
  }

  function setChargeLimit(limit) {
    if (thresholdBusy || !thresholdSupported) return
    thresholdError = ""
    thresholdProc.command = [root.limitScript, String(limit)]
    thresholdProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      refreshProfiles()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      thresholdError = ""
    }
  }

  Process {
    id: batteryProc
    command: ["python3", Qt.resolvedUrl("battery.py").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptInfo(text)
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.acceptProfiles(text)
    }
  }

  Process {
    id: profileProc
    onExited: {
      root.refreshProfiles()
      root.refresh()
    }
  }

  Process {
    id: thresholdProc
    onRunningChanged: root.thresholdBusy = running
    onExited: {
      if (exitCode !== 0) root.thresholdError = strings.t("limitFailed")
      else root.thresholdError = ""
      root.refresh()
    }
  }

  Timer {
    interval: root.opened ? 5000 : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    onTriggered: root.refreshProfiles()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.batteryIcon()
    labelText: root.showPercentage && !vertical ? root.percentageText : ""
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: root.tooltipText
    onPressed: function(mouse) {
      if (mouse === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        root.moveProfileCursor(dx !== 0 ? dx : dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("title")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusLabel().toUpperCase()
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.percentageText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Charge meter with the configured limit marked ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(10)

          Rectangle {
            id: chargeTrack
            anchors.fill: parent
            radius: height / 2
            color: Util.alpha(root.fg, 0.12)
          }

          Rectangle {
            anchors.left: chargeTrack.left
            anchors.verticalCenter: chargeTrack.verticalCenter
            height: chargeTrack.height
            radius: chargeTrack.radius
            color: root.fg
            width: Math.max(chargeTrack.height, chargeTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
          }

          Rectangle {
            visible: root.thresholdEnd > 0 && root.thresholdEnd < 100
            x: chargeTrack.x + chargeTrack.width * root.thresholdEnd / 100 - width / 2
            anchors.verticalCenter: chargeTrack.verticalCenter
            width: Style.space(2)
            height: chargeTrack.height + Style.space(4)
            radius: width / 2
            color: Color.accent
          }
        }

        // ---------- Live readings ----------
        Row {
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(2)
            InfoLabel { text: root.timeLabel }
            InfoValue { text: root.timeValue }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(2)
            InfoLabel { text: root.rateLabel }
            InfoValue { text: root.rateValue }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(2)
            InfoLabel { text: root.voltageLabel }
            InfoValue { text: root.voltageValue }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(2)
            InfoLabel { text: strings.t("cycles") }
            InfoValue { text: root.cyclesValue }
          }
        }

        Row {
          width: parent.width

          InfoLabel {
            id: temperatureLabel
            text: strings.t("temperature")
          }

          Item {
            width: Math.max(0, parent.width - temperatureLabel.implicitWidth - temperatureReading.implicitWidth)
            height: 1
          }

          InfoValue {
            id: temperatureReading
            text: root.temperatureValue
          }
        }

        // ---------- Battery health compared with a new pack ----------
        PanelSeparator {
          foreground: root.fg
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width

            PanelSectionHeader {
              text: strings.t("health")
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - healthText.implicitWidth); height: 1 }

            Text {
              id: healthText
              textFormat: Text.PlainText
              text: root.healthValue
              color: root.healthColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Item {
            width: parent.width
            implicitHeight: Style.space(8)

            Rectangle {
              id: healthTrack
              anchors.fill: parent
              radius: height / 2
              color: Util.alpha(root.fg, 0.12)
            }

            Rectangle {
              anchors.left: healthTrack.left
              anchors.verticalCenter: healthTrack.verticalCenter
              height: healthTrack.height
              radius: healthTrack.radius
              color: root.healthColor
              width: Math.max(0, healthTrack.width * root.healthPercent / 100)

              Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            text: root.capacityValue
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- Apple Silicon charge limit ----------
        Column {
          visible: root.thresholdSupported
          width: parent.width
          spacing: Style.space(8)

          PanelSeparator {
            foreground: root.fg
          }

          PanelSectionHeader {
            text: strings.t("chargeLimit")
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            id: limitRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: limitRow.cellWidth
              text: strings.t("limit80")
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              active: root.thresholdEnd === 80
              enabled: !root.thresholdBusy
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              onClicked: root.setChargeLimit(80)
            }

            Button {
              width: limitRow.cellWidth
              text: strings.t("limit100")
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              active: root.thresholdEnd === 100
              enabled: !root.thresholdBusy
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              onClicked: root.setChargeLimit(100)
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.limitNote !== ""
            text: root.limitNote
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            visible: root.thresholdBusy
            text: strings.t("limitChanging")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            textFormat: Text.PlainText
            visible: root.thresholdError !== ""
            text: root.thresholdError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }

        // ---------- Power profile picker ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator {
            foreground: root.fg
          }

          PanelSectionHeader {
            text: strings.t("powerProfile")
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: Battery.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: Battery.profileLabel(modelData, strings)
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(hovered) {
                  if (hovered) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.fg
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
