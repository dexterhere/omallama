import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root

  moduleName: "dexterhere.omallama"
  ipcTarget: "dexterhere.omallama"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var sample: Model.parseSample("")
  property var models: []
  property bool settingsOpen: false
  property var doctor: Model.EMPTY_DOCTOR
  property bool setupForced: false
  property bool setupDismissed: false
  property bool modelsScanned: false
  readonly property bool showSetup: setupForced || (!setupDismissed && (Model.needsSetup(doctor) || (doctor.loaded && modelsScanned && models.length === 0)))
  // Memory a model can use: VRAM on a discrete card, otherwise about half of system RAM.
  readonly property real budgetMb: (sample.gpuKind !== "none" && !sample.integrated && sample.vramTotalMb > 0) ? sample.vramTotalMb : doctor.ramTotalMb / 2
  readonly property var starter: Model.starterModel(budgetMb)
  property string modelQuery: ""
  readonly property var shownModels: Model.activeFirst(Model.filterModels(models, modelQuery), sample.activeModel)
  readonly property int visibleRows: 3
  property string addFeedback: ""
  property real idleSince: 0
  readonly property string activeAlias: sample.activeModel.split("/").pop().replace(/\.gguf$/i, "")
  readonly property string endpoint: "http://localhost:" + sample.port + "/v1"
  readonly property string home: Quickshell.env("HOME")
  property var gpuHist: []
  property var vramHist: []
  property var ramHist: []
  property var tpsHist: []
  readonly property bool on: Model.isOn(sample)
  readonly property bool pressure: sample.ramPct >= 90 || sample.vramPct >= 95

  readonly property string dir: Qt.resolvedUrl(".").toString().replace("file://", "")
  property var deleteTarget: null
  property bool uninstallAsk: false
  readonly property var ctxOptions: [4096, 8192, 16384]

  function setModel(path) {
    if (path === sample.activeModel || setProc.running) return
    setProc.command = [dir + "setmodel.sh", "model", path]
    setProc.running = true
  }

  function setCtx(n) {
    if (n === sample.ctx || setProc.running) return
    setProc.command = [dir + "setmodel.sh", "ctx", String(n)]
    setProc.running = true
  }

  function askDelete(info) { if (info && info.path !== sample.activeModel) deleteTarget = info }

  function confirmDelete() {
    var t = deleteTarget
    deleteTarget = null
    if (!t || delProc.running) return
    // Also drops the path from the user's added-models list if it was there.
    delProc.command = ["bash", "-c", '[[ ${1,,} == *.gguf && -f $1 ]] && rm -f -- "$1"; "$2" rmpath "$1"', "x", t.path, dir + "setmodel.sh"]
    delProc.running = true
  }

  // Reveals the file in the file manager (selected), falling back to just opening its folder.
  function viewModel(path) {
    root.close()
    Quickshell.execDetached(["bash", "-c", 'nautilus --select "$1" 2>/dev/null || xdg-open "$(dirname "$1")"', "x", path])
  }

  function copyText(t) {
    if (doctor.missing.indexOf("wl-copy") >= 0) { addFeedback = "err: wl-copy is not installed (package wl-clipboard)"; return }
    Quickshell.execDetached(["wl-copy", "--trim-newline", t])
    addFeedback = "Copied to clipboard"
  }

  function checkSetup() { if (!doctorProc.running) doctorProc.running = true }

  function runSetup() {
    if (setupProc.running) return
    addFeedback = "Installing service…"
    setupProc.command = ["bash", dir + "setup.sh"]
    setupProc.running = true
  }

  function removeService() {
    uninstallAsk = false
    if (setupProc.running) return
    addFeedback = "Removing service…"
    setupProc.command = ["bash", dir + "setup.sh", "remove"]
    setupProc.running = true
  }

  function setKey(key, value, restart) {
    if (setProc.running) return
    setProc.command = [dir + "setmodel.sh", "set", key, String(value)].concat(restart === false ? ["norestart"] : [])
    setProc.running = true
  }

  function addPath(path) {
    var t = String(path || "").trim()
    if (t === "" || pathProc.running) return
    pathProc.command = [dir + "setmodel.sh", "addpath", t]
    pathProc.running = true
  }

  function removePath(path) {
    if (setProc.running) return
    setProc.command = [dir + "setmodel.sh", "rmpath", path]
    setProc.running = true
  }

  // File chooser -> verify each pick as GGUF -> add -> rescan so it shows in the list.
  function browse() {
    if (browseProc.running) return
    addFeedback = "Choose a model in the file window…"
    browseProc.running = true
  }

  function setLogin(on) {
    if (setProc.running) return
    setProc.command = [dir + "setmodel.sh", "login", on ? "on" : "off"]
    setProc.running = true
  }

  function viewLogs() {
    root.close()
    Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.llm-logs", "bash", "-c",
      "journalctl --user -u omallama -f -n 100"])
  }

  // Stops the server after it has had no requests for the configured time.
  function trackIdle(s) {
    if (!Model.isOn(s) || !s.ready || s.busy || s.autoStopMin <= 0) { idleSince = 0; return }
    if (idleSince === 0) { idleSince = Date.now(); return }
    if (Date.now() - idleSince >= s.autoStopMin * 60000) {
      idleSince = 0
      toggleServer()
      Quickshell.execDetached(["notify-send", "Local LLM", "Server stopped after " + s.autoStopMin + " min idle"])
    }
  }

  function scanModels() { if (!scanner.running) scanner.running = true }

  function restartServer() {
    if (!on || action.running) return
    action.command = ["systemctl", "--user", "restart", "omallama"]
    action.running = true
  }

  function refresh() { if (!sampler.running) sampler.running = true }

  function toggleServer() {
    if (action.running) return
    if (!on && (Model.needsSetup(doctor) || sample.activeModel === "")) {
      addFeedback = sample.activeModel === "" ? "Choose a model first" : "Finish setup first"
      setupDismissed = false; setupForced = true
      return
    }
    action.command = ["systemctl", "--user", on ? "stop" : "start", "omallama"]
    action.running = true
  }

  Timer {
    interval: root.opened ? 2000 : 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: sampler
    command: ["bash", root.dir + "sample.sh"]
    stdout: StdioCollector { id: out; waitForEnd: true }
    onExited: {
      var s = Model.parseSample(out.text)
      var addedChanged = JSON.stringify(s.added) !== JSON.stringify(root.sample.added)
      root.sample = s
      root.trackIdle(s)
      if (addedChanged) root.scanModels()
      root.gpuHist = Model.push(root.gpuHist, s.gpuUtil)
      root.vramHist = Model.push(root.vramHist, s.vramPct)
      root.ramHist = Model.push(root.ramHist, s.ramPct)
      root.tpsHist = Model.push(root.tpsHist, s.tps)
    }
  }

  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.scanModels()
  }

  Process {
    id: scanner
    command: ["bash", root.dir + "scan.sh"]
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    onExited: { root.models = Model.parseModels(scanOut.text, root.home); root.modelsScanned = true }
  }

  Process { id: setProc; onExited: root.refresh() }
  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector { id: pasteOut; waitForEnd: true }
    onExited: pathField.text = String(pasteOut.text).trim()
  }

  Process {
    id: doctorProc
    command: ["bash", root.dir + "doctor.sh"]
    stdout: StdioCollector { id: doctorOut; waitForEnd: true }
    onExited: root.doctor = Model.parseDoctor(doctorOut.text)
  }

  Process {
    id: setupProc
    command: ["bash", root.dir + "setup.sh"]
    stdout: StdioCollector { id: setupOut; waitForEnd: true }
    onExited: {
      root.addFeedback = String(setupOut.text).trim()
      root.checkSetup()
      root.refresh()
      root.scanModels()
    }
  }

  onOpenedChanged: if (opened) checkSetup()
  Component.onCompleted: checkSetup()

  Process {
    id: browseProc
    command: ["bash", root.dir + "browse.sh"]
    stdout: StdioCollector { id: browseOut; waitForEnd: true }
    onExited: {
      var lines = String(browseOut.text).trim().split("\n").filter(function(l) { return l !== "" })
      var good = lines.filter(function(l) { return l.indexOf("ok") === 0 })
      root.addFeedback = lines.length === 0 ? "" : good.length > 0 ? "Added " + good.length + (good.length === 1 ? " model" : " models") : lines[lines.length - 1]
      root.refresh()
      root.scanModels()
      if (good.length > 0) { root.modelQuery = ""; root.settingsOpen = false }
    }
  }

  Process {
    id: pathProc
    stdout: StdioCollector { id: pathOut; waitForEnd: true }
    onExited: {
      root.addFeedback = String(pathOut.text).trim()
      if (root.addFeedback.indexOf("ok") === 0) pathField.text = ""
      root.refresh()
    }
  }
  Process { id: delProc; onExited: { root.refresh(); root.scanModels() } }

  Process {
    id: action
    onExited: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function toggleServer(): void { root.toggleServer() }
    function restartServer(): void { root.restartServer() }
    function rescan(): void { root.scanModels() }
    function browse(): void { root.browse() }
    function setup(): void { root.setupForced = !root.setupForced }
    function askDelete(path: string): void { for (var i = 0; i < root.models.length; i++) if (root.models[i].path === path) root.askDelete(root.models[i]) }
    function settings(): void { root.settingsOpen = !root.settingsOpen }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.Glyph.chip
    dimmed: !root.on
    active: root.on
    useActiveColor: false
    activeColor: root.pressure ? Color.urgent : Color.accent
    tooltipText: "Omallama · " + (Model.needsSetup(root.doctor) ? "setup needed" : Model.statusText(root.sample))

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleServer()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: modelSearch.activeFocus || pathField.activeFocus || portField.activeFocus || extraField.activeFocus
      onCloseRequested: { if (root.uninstallAsk) root.uninstallAsk = false; else if (root.deleteTarget) root.deleteTarget = null; else if (root.settingsOpen) root.settingsOpen = false; else root.close() }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "u") root.refresh() }

      Keys.onPressed: function(event) { if (uninstallConfirm.handleKey(event) || deleteConfirm.handleKey(event)) event.accepted = true }

      ConfirmDialog {
        id: uninstallConfirm
        anchors.fill: parent
        z: 11
        opened: root.uninstallAsk
        message: "Stop and remove the Omallama service?\n\nYour models and settings are kept. To remove the plugin afterwards run:\nomarchy plugin remove dexterhere.omallama"
        confirmText: "Remove"
        selectedIndex: 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.uninstallAsk = false
        onConfirmed: root.removeService()
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 10
        opened: root.deleteTarget !== null
        message: root.deleteTarget
          ? "Delete “" + root.deleteTarget.name + "” (" + Model.gb(root.deleteTarget.sizeMb) + ") from disk?\n\n"
            + root.deleteTarget.path + "\n\nThis cannot be undone."
          : ""
        confirmText: "Delete"
        selectedIndex: 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.deleteTarget = null
        onConfirmed: root.confirmDelete()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        PanelHero {
          title: "Omallama"
          meta: root.showSetup ? "Setup" : root.settingsOpen ? "Settings" : Model.statusText(root.sample)
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.on ? 1.0 : 0.5

          iconComponent: Text {
            text: Model.Glyph.chip
            color: root.pressure ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }

          trailingControl: Row {
            spacing: Style.space(6)

            PanelActionButton {
              visible: root.on
              iconText: Model.Glyph.refresh
              tooltipText: "Restart server"
              foreground: root.foreground
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.restartServer()
            }

            PanelActionButton {
              iconText: Model.Glyph.gear
              tooltipText: root.settingsOpen ? "Back" : "Settings"
              foreground: root.settingsOpen ? Color.accent : root.foreground
              hoverColor: Color.accent
              fontFamily: root.fontFamily
              onClicked: { if (root.showSetup) { root.setupForced = false; root.setupDismissed = true; root.settingsOpen = true } else root.settingsOpen = !root.settingsOpen }
            }

            PanelActionButton {
              iconText: Model.Glyph.power
              tooltipText: (root.on ? "Stop" : "Start") + " server"
              foreground: root.on ? Color.accent : root.foreground
              hoverColor: root.on ? Color.urgent : Color.accent
              fontFamily: root.fontFamily
              onClicked: root.toggleServer()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          id: mainView
          visible: !root.settingsOpen && !root.showSetup
          width: parent.width
          spacing: Style.spacing.panelGap

          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(12)
            readonly property real cell: (width - columnSpacing) / 2

            Metric {
              width: parent.cell
              visible: root.sample.gpuKind !== "none"
              label: Model.gpuHeading(root.sample)
              value: Model.gpuText(root.sample)
              values: root.gpuHist
              ceiling: 100
            }
            Metric {
              width: parent.cell
              visible: root.sample.gpuKind !== "none"
              label: Model.memHeading(root.sample)
              value: Model.gb(root.sample.vramUsedMb) + " / " + Model.gb(root.sample.vramTotalMb)
              values: root.vramHist
              ceiling: 100
              warn: root.sample.vramPct >= 95
            }
            Metric {
              width: parent.cell
              label: "RAM"
              value: root.sample.ramPct + "%  ·  " + Model.gb(root.sample.ramFreeMb) + " free"
              values: root.ramHist
              ceiling: 100
              warn: root.sample.ramPct >= 90
            }
            Metric {
              width: parent.cell
              label: "Tokens / s"
              value: !root.on ? "off" : root.sample.tps > 0 ? root.sample.tps.toFixed(1) : "idle"
              values: root.tpsHist
              ceiling: Math.max(50, Math.max.apply(null, root.tpsHist))
            }
          }

          Row {
            width: parent.width
            Repeater {
              model: [
                { k: "Uptime", v: root.on ? Model.fmtUptime(root.sample.uptime) : "—" },
                { k: "Server RAM", v: root.on ? Model.gb(root.sample.serverRssMb) : "—" },
                { k: "Swap", v: Model.gb(root.sample.swapMb) },
                { k: "Endpoint", v: ":8080" }
              ]
              delegate: Column {
                required property var modelData
                width: parent.width / 4
                spacing: Style.space(2)
                Text { text: modelData.k; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                Text { text: modelData.v; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - ctxRow.width - Style.space(8)
              text: "CONTEXT WINDOW"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
            Row {
              id: ctxRow
              spacing: Style.space(6)
              Repeater {
                model: root.ctxOptions
                delegate: Pill {
                  required property int modelData
                  label: Model.ctxLabel(modelData)
                  selected: modelData === root.sample.ctx
                  onClicked: root.setCtx(modelData)
                }
              }
            }
          }

          Row {
            width: parent.width
            Text {
              width: parent.width - folderBtn.width
              anchors.verticalCenter: parent.verticalCenter
              text: "MODELS  ·  " + root.models.length
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }
            PanelActionButton {
              id: folderBtn
              iconText: Model.Glyph.folder
              tooltipText: "Add a model from your files"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.browse()
            }
          }

          Text {
            visible: !root.settingsOpen && root.addFeedback !== ""
            width: parent.width
            text: root.addFeedback
            color: root.addFeedback.indexOf("err") === 0 || root.addFeedback.indexOf("not") >= 0 ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

        TextField {
            id: modelSearch
            visible: root.models.length > root.visibleRows
            height: visible ? implicitHeight : 0
            width: parent.width
            foreground: root.foreground
            placeholderText: "Search models…"
            text: root.modelQuery
            onTextChanged: root.modelQuery = text
            Keys.onEscapePressed: { if (text !== "") text = ""; else root.close() }
          }

          ListView {
            id: modelList
            width: parent.width
            height: Math.min(count, root.visibleRows) * Style.space(48) + Math.max(0, Math.min(count, root.visibleRows) - 1) * spacing
            spacing: Style.space(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: count > root.visibleRows
            model: root.shownModels
            delegate: ModelRow {
              required property var modelData
              width: ListView.view.width
              info: modelData
            }
          }

          Text {
            visible: root.shownModels.length > root.visibleRows
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: "Showing " + root.visibleRows + " of " + root.shownModels.length + "  ·  scroll for more"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

        Text {
            visible: root.shownModels.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: scanner.running ? "Scanning for models…" : root.models.length > 0 ? "No model matches “" + root.modelQuery + "”" : "No .gguf models found on this system"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            text: "Click a model to switch (restarts a running server)  ·  u refreshes"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          id: settingsView
          visible: root.settingsOpen && !root.showSetup
          width: parent.width
          spacing: Style.spacing.panelGap

          SectionLabel { text: "ADD A MODEL" }

          Row {
            width: parent.width
            spacing: Style.space(6)
            TextField {
              id: pathField
              width: parent.width - addBtn.width - browseBtn.width - pasteBtn.width - Style.space(18)
              foreground: root.foreground
              placeholderText: "Path to a .gguf file or a folder of models"
              onAccepted: root.addPath(text)
              Keys.onEscapePressed: root.settingsOpen = false
            }
            PanelActionButton {
              id: pasteBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: Model.Glyph.paste
              tooltipText: "Paste path from clipboard"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: pasteProc.running = true
            }
            PanelActionButton {
              id: browseBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: Model.Glyph.folder
              tooltipText: "Browse for a model file"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.browse()
            }
            Pill {
              id: addBtn
              anchors.verticalCenter: parent.verticalCenter
              label: "Add"
              selected: pathField.text.trim() !== ""
              onClicked: root.addPath(pathField.text)
            }
          }

          Text {
            visible: root.addFeedback !== ""
            width: parent.width
            text: root.addFeedback
            color: root.addFeedback.indexOf("err") === 0 ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Repeater {
            model: root.sample.added
            delegate: Item {
              required property string modelData
              width: settingsView.width
              height: Style.space(26)
              Text {
                anchors.left: parent.left
                anchors.right: removeBtn.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
              PanelActionButton {
                id: removeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: Model.Glyph.close
                tooltipText: "Remove from list (keeps the file)"
                foreground: root.dim
                hoverColor: Color.urgent
                fontFamily: root.fontFamily
                onClicked: root.removePath(modelData)
              }
            }
          }

          PanelSeparator { foreground: root.foreground }
          SectionLabel { text: "SERVER" }

          Text {
            visible: root.doctor.loaded
            width: parent.width
            text: Model.deviceSummary(root.doctor)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          SettingRow {
            label: "Run on"
            hint: "GPU is fastest; layers that don't fit run on the CPU"
            Row {
              spacing: Style.space(6)
              Repeater {
                model: [{ t: "GPU", v: 99 }, { t: "Half", v: 16 }, { t: "CPU", v: 0 }]
                delegate: Pill {
                  required property var modelData
                  label: modelData.t
                  selected: root.sample.ngl === modelData.v
                  onClicked: root.setKey("LLM_NGL", modelData.v)
                }
              }
            }
          }

          SettingRow {
            label: "Compact KV cache"
            hint: "8-bit cache saves VRAM so a longer context fits"
            ToggleSwitch {
              foreground: root.foreground
              checked: root.sample.compactKv
              onToggled: root.setKey("LLM_KV", root.sample.compactKv ? "" : "-ctk q8_0 -ctv q8_0")
            }
          }

          SettingRow {
            label: "Port"
            hint: "Press Enter to apply (1024–65535)"
            TextField {
              id: portField
              width: Style.space(90)
              foreground: root.foreground
              text: String(root.sample.port)
              color: Model.validPort(text) ? root.foreground : Color.urgent
              onAccepted: if (Model.validPort(text)) root.setKey("LLM_PORT", text)
            }
          }

          SettingRow {
            label: "Extra arguments"
            hint: "Passed to llama-server, e.g. --threads 6 --parallel 2"
            TextField {
              id: extraField
              width: Style.space(220)
              foreground: root.foreground
              text: root.sample.extraArgs
              placeholderText: "none"
              onAccepted: root.setKey("LLM_EXTRA", text.trim())
            }
          }

          PanelSeparator { foreground: root.foreground }
          SectionLabel { text: "SAVE MEMORY" }

          SettingRow {
            label: "Stop when idle"
            hint: root.sample.autoStopMin > 0 && root.idleSince > 0
              ? "Idle for " + Model.fmtUptime((Date.now() - root.idleSince) / 1000)
              : "Frees VRAM and RAM when nothing is using the server"
            Row {
              spacing: Style.space(6)
              Repeater {
                model: [{ t: "Off", v: 0 }, { t: "5m", v: 5 }, { t: "15m", v: 15 }, { t: "30m", v: 30 }, { t: "1h", v: 60 }]
                delegate: Pill {
                  required property var modelData
                  label: modelData.t
                  selected: root.sample.autoStopMin === modelData.v
                  onClicked: root.setKey("LLM_AUTOSTOP", modelData.v, false)
                }
              }
            }
          }

          SettingRow {
            label: "Start at login"
            hint: "Off keeps your RAM free until you need the model"
            ToggleSwitch {
              foreground: root.foreground
              checked: root.sample.atLogin
              onToggled: root.setLogin(!root.sample.atLogin)
            }
          }

          PanelSeparator { foreground: root.foreground }
          SectionLabel { text: "TOOLS" }

          Flow {
            width: parent.width
            spacing: Style.space(8)
            Pill { label: "Copy endpoint"; onClicked: root.copyText(root.endpoint) }
            Pill { label: "Copy Zed config"; onClicked: root.copyText(Model.zedConfig(root.sample.port, root.activeAlias)) }
            Pill { label: "View logs"; onClicked: root.viewLogs() }
            Pill { label: "Setup check"; onClicked: { root.setupForced = true; root.checkSetup() } }
            Pill { label: "Reinstall service"; onClicked: root.runSetup() }
            Pill { visible: root.doctor.unitInstalled; label: "Uninstall service"; onClicked: root.uninstallAsk = true }
            Pill { label: "Models folder"; onClicked: Quickshell.execDetached(["xdg-open", root.home + "/models"]) }
            Pill { label: "Config folder"; onClicked: Quickshell.execDetached(["xdg-open", root.home + "/.config/omallama"]) }
          }

          Text {
            width: parent.width
            text: root.endpoint + "  ·  " + root.home + "/.config/omallama/env"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }

        Column {
          id: setupView
          visible: root.showSetup
          width: parent.width
          spacing: Style.spacing.panelGap

          Text {
            width: parent.width
            text: root.doctor.loaded ? "Let's get Omallama running. Each step turns green when it is ready." : "Checking your system…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          SetupStep {
            level: root.doctor.bin !== "" ? 0 : 2
            title: "llama.cpp server"
            detail: root.doctor.bin !== ""
              ? root.doctor.bin + (root.doctor.binVersion !== "" ? "  ·  " + root.doctor.binVersion : "")
              : "llama-server was not found on this machine."
            Pill { visible: root.doctor.bin === ""; label: "Copy build command"; onClicked: root.copyText(Model.buildCommand(root.doctor.gpuKind)) }
          }

          SetupStep {
            level: root.doctor.driverMissing ? 2 : (root.doctor.bin === "" || Model.accelerated(root.doctor)) ? 0 : 1
            title: "Graphics"
            detail: Model.deviceSummary(root.doctor)
            Pill {
              visible: root.doctor.bin !== "" && !Model.accelerated(root.doctor)
              label: "Copy rebuild command"
              onClicked: root.copyText(Model.buildCommand(root.doctor.gpuKind))
            }
          }

          SetupStep {
            level: root.doctor.unitInstalled ? 0 : 2
            title: "Background service"
            detail: root.doctor.unitInstalled
              ? "Installed as a systemd user service (omallama)"
              : "Not installed yet. Omallama uses it to start and stop the server."
            Pill {
              visible: !root.doctor.unitInstalled
              label: root.doctor.bin !== "" ? "Install service" : "Needs llama.cpp first"
              selected: root.doctor.bin !== ""
              onClicked: root.runSetup()
            }
          }

          SetupStep {
            level: root.models.length === 0 ? 2 : root.sample.activeModel === "" ? 1 : 0
            title: "A model"
            detail: root.models.length === 0
              ? (root.modelsScanned ? "No .gguf models found yet." : "Looking for models…")
              : root.sample.activeModel === "" ? root.models.length + " found. Choose the one to run."
              : root.models.length + " found  ·  active: " + root.activeAlias
            Pill { label: "Add from files"; selected: root.models.length === 0; onClicked: root.browse() }
            Pill {
              visible: root.models.length > 0 && root.sample.activeModel === ""
              label: "Use " + (root.models.length > 0 ? root.models[0].name : "")
              onClicked: root.setModel(root.models[0].path)
            }
            Pill { visible: root.models.length === 0; label: "Copy download: " + root.starter.label; onClicked: root.copyText(root.starter.command) }
          }

          SetupStep {
            level: root.doctor.missing.length === 0 ? 0 : root.doctor.missing.some(function(t) { return t.indexOf("!") === 0 }) ? 2 : 1
            title: "Helper tools"
            detail: root.doctor.missing.length === 0 ? "Everything Omallama uses is installed."
              : "Missing: " + Model.missingPackages(root.doctor.missing).join(", ") + " (clipboard, notifications, file picker)"
            Pill {
              visible: root.doctor.missing.length > 0
              label: "Copy install command"
              onClicked: root.copyText("sudo pacman -S --needed " + Model.missingPackages(root.doctor.missing).join(" "))
            }
          }

          Text {
            visible: root.addFeedback !== ""
            width: parent.width
            text: root.addFeedback
            color: root.addFeedback.indexOf("err") === 0 ? Color.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Row {
            spacing: Style.space(8)
            Pill { label: "Recheck"; onClicked: { root.checkSetup(); root.scanModels() } }
            Pill {
              label: "Done"
              selected: !Model.needsSetup(root.doctor)
              onClicked: { root.setupForced = false; root.setupDismissed = true }
            }
          }
        }
      }
    }
  }

  component SetupStep: Rectangle {
    id: step
    property int level: 0
    property string title: ""
    property string detail: ""
    default property alias actions: actionFlow.data
    readonly property color tone: level === 0 ? Color.accent : level === 1 ? root.dim : Color.urgent
    width: parent.width
    height: body.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: Style.normalFill
    border.width: 1
    border.color: level === 2 ? Color.urgent : Style.normalBorderColor

    Rectangle {
      id: dot
      x: Style.space(14); y: Style.space(16)
      width: Style.space(10); height: width; radius: width / 2
      color: step.level === 1 ? "transparent" : step.tone
      border.width: 1
      border.color: step.tone
    }
    Column {
      id: body
      x: Style.space(36); y: Style.space(12)
      width: parent.width - Style.space(36) - Style.space(14)
      spacing: Style.space(4)
      Text { width: parent.width; text: step.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
      Text { width: parent.width; text: step.detail; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WrapAnywhere }
      Flow { id: actionFlow; width: parent.width; spacing: Style.space(8); topPadding: children.length > 0 ? Style.space(4) : 0 }
    }
  }

  component SectionLabel: Text {
    width: parent.width
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  component SettingRow: Item {
    id: sr
    property string label: ""
    property string hint: ""
    default property alias control: slot.data
    width: parent.width
    height: Math.max(labels.implicitHeight, slot.implicitHeight)
    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: slot.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text { width: parent.width; text: sr.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      Text { width: parent.width; text: sr.hint; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
    }
    Item {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: childrenRect.width
      implicitHeight: childrenRect.height
      width: implicitWidth
      height: implicitHeight
    }
  }

  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool selected: false
    signal clicked()
    width: Math.max(Style.space(48), pillText.implicitWidth + Style.space(22)); height: Style.space(24)
    radius: Style.cornerRadius
    color: selected ? Style.selectedAccentFill : area.containsMouse ? Style.hoverFill : Style.normalFill
    border.width: 1
    border.color: selected ? Color.accent : Style.normalBorderColor
    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      color: pill.selected ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: pill.selected
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
  }

  component ModelRow: Rectangle {
    id: row
    property var info: ({ path: "", name: "", params: "", quant: "", sizeMb: 0 })
    readonly property bool active: info.path === root.sample.activeModel
    readonly property var fit: Model.fitFor(info.sizeMb, root.sample)
    height: Style.space(48)
    radius: Style.cornerRadius
    color: active ? Style.selectedAccentFill : rowArea.containsMouse ? Style.hoverFill : Style.normalFill
    border.width: 1
    border.color: active ? Color.accent : Style.normalBorderColor

    MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setModel(row.info.path) }

    Rectangle {
      id: mark
      anchors.left: parent.left; anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8); height: width; radius: width / 2
      color: row.active ? Color.accent : "transparent"
      border.width: 1
      border.color: row.active ? Color.accent : root.dim
    }
    Column {
      anchors.left: mark.right; anchors.leftMargin: Style.space(12)
      anchors.right: fitText.left; anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: row.info.name
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        text: [row.info.params, row.info.quant, Model.gb(row.info.sizeMb), row.info.source].filter(function(x) { return x }).join("  ·  ")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      id: fitText
      anchors.right: actions.left; anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: row.fit.text
      color: row.fit.level === 0 ? root.dim : row.fit.level === 1 ? Color.accent : Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Row {
      id: actions
      anchors.right: parent.right; anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        iconText: Model.Glyph.folderOpen
        tooltipText: "Show in file manager"
        foreground: root.foreground
        hoverColor: Color.accent
        fontFamily: root.fontFamily
        onClicked: root.viewModel(row.info.path)
      }

      PanelActionButton {
        iconText: Model.Glyph.trash
        enabled: !row.active
        opacity: row.active ? 0.3 : 1
        tooltipText: row.active ? "Active model — switch to another first" : "Delete from disk"
        foreground: root.foreground
        hoverColor: Color.urgent
        fontFamily: root.fontFamily
        onClicked: root.askDelete(row.info)
      }
    }
  }

  component Metric: Rectangle {
    id: m
    property string label: ""
    property string value: ""
    property var values: []
    property real ceiling: 100
    property bool warn: false
    readonly property color tint: warn ? Color.urgent : Color.accent

    height: cardBody.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: Style.normalFill
    border.width: 1
    border.color: warn ? Color.urgent : Style.normalBorderColor

    Column {
    id: cardBody
    x: Style.space(10); y: Style.space(10)
    width: parent.width - Style.space(20)
    spacing: Style.space(6)

    Row {
      width: parent.width
      Text {
        id: mLabel
        width: implicitWidth
        text: m.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width - mLabel.width
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: m.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Canvas {
      id: spark
      width: parent.width
      height: Style.space(32)
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        var v = m.values
        if (v.length < 2) return
        var step = width / (Model.HISTORY - 1)
        var x0 = width - (v.length - 1) * step
        ctx.beginPath()
        for (var i = 0; i < v.length; i++) {
          var y = height - 2 - Math.min(1, v[i] / m.ceiling) * (height - 4)
          if (i === 0) ctx.moveTo(x0, y); else ctx.lineTo(x0 + i * step, y)
        }
        ctx.strokeStyle = m.tint
        ctx.lineWidth = 1.5
        ctx.stroke()
        ctx.lineTo(width, height); ctx.lineTo(x0, height); ctx.closePath()
        ctx.fillStyle = Qt.rgba(m.tint.r, m.tint.g, m.tint.b, 0.15)
        ctx.fill()
      }
      Connections { target: m; function onValuesChanged() { spark.requestPaint() } }
    }
    }
  }
}
