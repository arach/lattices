pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property var state: ({ windows: [], displays: [], sessions: [], clients: [], pending: [], layers: [], stage: { parked: [] }, layersSupported: false, describe: {} })
    readonly property var dialogParent: window.contentItem
    property bool online: false
    property bool busy: false
    property bool compact: false
    property string page: "Home"
    property string message: "Connecting to the local host…"
    property string query: ""
    property double selectedWid: -1
    property var selectedWindow: state.windows.find(w => w.wid === selectedWid) || null
    property var activity: []
    property string pendingMethod: ""
    property string pendingLabel: ""
    readonly property bool needsHost: page === "Home" || page === "Overview" || page === "Layers"
    readonly property int sidebarWidth: Theme.rail + (compact ? 0 : Theme.labels)
    readonly property string hostPort: Quickshell.env("LATTICES_LINUX_PORT") || "9399"

    function appName(raw) {
        const entry = DesktopEntries.heuristicLookup(raw)
        return entry ? entry.name : raw
    }
    function log(label, detail, error) {
        activity = [{ label: label, detail: detail || "", error: !!error, time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) }].concat(activity).slice(0, 50)
    }
    function finish(error, detail) {
        if (pendingLabel) log(pendingLabel, detail, error)
        pendingMethod = ""
        pendingLabel = ""
        busy = false
    }
    function call(method, params) {
        if (!backend.running || busy || (!online && method !== "refresh" && method !== "host.start")) return
        const labels = { "layers.create": "Create layer", "layers.assign": "Add windows to layer", "layers.unassign": "Remove windows from layer", "layers.rename": "Rename layer", "layers.delete": "Delete layer", "layers.layout": "Set layer layout", "layers.activate": "Switch layer", "layers.reveal": "Show all windows", "refresh": "Refresh local host", "host.start": "Start local host", "windows.focus": "Focus window", "windows.place": "Place window", "sessions.launch": "Start session", "clients.approve": "Approve device", "bridge.pairing.approve": "Approve device", "clients.deny": "Deny pairing", "bridge.pairing.deny": "Deny pairing", "clients.revoke": "Revoke device", "bridge.devices.revoke": "Revoke device" }
        pendingMethod = method
        pendingLabel = labels[method] || "Local action"
        if (params && params.placement) pendingLabel += " · " + params.placement
        busy = true
        message = ""
        backend.write(JSON.stringify({ method: method, params: params || {} }) + "\n")
    }
    function decide(request, approve) {
        call(request.kind === "daemon" ? (approve ? "clients.approve" : "clients.deny") : (approve ? "bridge.pairing.approve" : "bridge.pairing.deny"),
            request.kind === "daemon" ? { clientID: request.deviceID } : { deviceID: request.deviceID })
    }
    function newLayer() { page = "Layers"; Qt.callLater(() => layersPage.create()) }
    function newSession() { if (online && !busy) sessionDialog.open() }
    function showSearch() {
        page = "Overview"
        Qt.callLater(() => overview.focusSearch())
    }

    Process {
        id: backend
        command: [Quickshell.env("LATTICES_LINUX_BUN") || "bun", Quickshell.shellDir + "/backend.ts"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const update = JSON.parse(data)
                    if (update.type === "state") {
                        root.state = update
                        if (!root.online || root.pendingMethod === "refresh") root.message = ""
                        root.online = true
                        if (root.pendingMethod === "refresh") root.finish(false, "")
                    } else if (update.type === "offline") {
                        if (root.online && !root.pendingLabel) root.log("Local host disconnected", update.message, true)
                        root.online = false
                        root.finish(true, update.message)
                        root.message = update.message
                    } else if (update.type === "error") {
                        root.finish(true, update.message)
                        root.message = update.message
                    } else if (update.type === "done") {
                        if (root.pendingMethod === "layers.create" && update.result) { layersPage.selectedId = update.result.id; root.page = "Layers" }
                        const held = update.result?.held || []
                        root.finish(false, held.length ? "A written rule still holds " + held.length + " windows" : "")
                        if (held.length) root.message = "A written rule still holds this window. Edit the rule in workspace.json to remove it."
                    }
                } catch (e) { root.message = "Could not read the host response."; root.finish(true, root.message) }
            }
        }
        stderr: SplitParser { onRead: data => console.warn(data) }
        onRunningChanged: if (!running) { root.online = false; root.finish(true, "App connection stopped"); root.message = "The app connection stopped. Reopen Lattices to reconnect." }
    }

    FloatingWindow {
        id: window
        title: "Lattices"
        visible: true
        implicitWidth: 1160
        implicitHeight: 760
        minimumSize: Qt.size(740, 520)
        color: "#373739"
        onClosed: Qt.quit()

        Shortcut { sequence: "Ctrl+K"; onActivated: root.showSearch() }
        Shortcut { sequence: "Ctrl+1"; onActivated: root.page = "Home" }
        Shortcut { sequence: "Ctrl+2"; onActivated: root.page = "Overview" }
        Shortcut { sequence: "Ctrl+3"; onActivated: root.page = "Layers" }

        Shortcut { sequence: "Ctrl+4"; onActivated: root.page = "Activity" }

        Rectangle {
            id: appContent
            anchors.fill: parent
            color: window.color
            RowLayout {
                anchors.fill: parent; spacing: 0
                ColumnLayout {
                    Layout.preferredWidth: root.sidebarWidth
                    Layout.minimumWidth: root.sidebarWidth
                    Layout.maximumWidth: root.sidebarWidth
                    Layout.fillHeight: true; spacing: 0
                    Button {
                        id: brand
                        Layout.fillWidth: true; implicitHeight: 62; padding: 0
                        Accessible.name: root.compact ? "Expand sidebar" : "Collapse sidebar"
                        onClicked: root.compact = !root.compact
                        background: Item {}
                        contentItem: RowLayout {
                            spacing: 0
                            Item { Layout.preferredWidth: Theme.rail; Layout.fillHeight: true; BrandMark { anchors.centerIn: parent } }
                            AppText { visible: !root.compact; text: "Lattices"; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        }
                        ToolTip.visible: hovered; ToolTip.text: root.compact ? "Expand sidebar" : "Collapse sidebar"
                    }
                    AppText { opacity: root.compact ? 0 : 1; text: "WORKSPACE"; mono: true; font.pixelSize: 9; font.letterSpacing: 1; color: "#a3a3a5"; Layout.leftMargin: Theme.rail; Layout.bottomMargin: 6 }
                    NavRow { Layout.fillWidth: true; text: "Home"; glyph: "home"; compact: root.compact; selected: root.page === text; onClicked: root.page = text }
                    NavRow { Layout.fillWidth: true; text: "Overview"; glyph: "overview"; compact: root.compact; selected: root.page === text; onClicked: root.page = text }
                    NavRow { Layout.fillWidth: true; text: "Layers"; glyph: "layers"; compact: root.compact; selected: root.page === text; onClicked: root.page = text }
                    Item { implicitHeight: 24 }
                    AppText { opacity: root.compact ? 0 : 1; text: "SYSTEM"; mono: true; font.pixelSize: 9; font.letterSpacing: 1; color: "#a3a3a5"; Layout.leftMargin: Theme.rail; Layout.bottomMargin: 6 }
                    NavRow { Layout.fillWidth: true; text: "Activity"; glyph: "activity"; compact: root.compact; selected: root.page === text; onClicked: root.page = text }
                    Item { Layout.fillHeight: true }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#49494b" }
                    Button {
                        id: daemon
                        Layout.fillWidth: true; implicitHeight: 30; padding: 0
                        onClicked: root.page = "Settings"
                        Accessible.name: "Local host " + (root.online ? "connected" : "offline")
                        background: Item {}
                        contentItem: RowLayout {
                            spacing: 0
                            Item { Layout.preferredWidth: Theme.rail; Layout.fillHeight: true; Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: root.online ? Theme.green : Theme.dim } }
                            AppText { visible: !root.compact; text: "Daemon"; font.pixelSize: 12; font.weight: Font.Medium; color: "#b3b3b5" }
                            AppText { visible: !root.compact; text: ":" + root.hostPort; mono: true; font.pixelSize: 10; color: "#939395"; Layout.leftMargin: 6; Layout.fillWidth: true }
                        }
                        ToolTip.visible: hovered; ToolTip.text: root.online ? "Local host connected" : "Local host offline"
                    }
                    NavRow { Layout.fillWidth: true; Layout.bottomMargin: 4; text: "Settings"; glyph: "settings"; compact: root.compact; selected: root.page === text; onClicked: root.page = text }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.topMargin: 8; Layout.bottomMargin: 8; Layout.rightMargin: 8
                    radius: 10; color: Theme.bg; border.color: "#303033"
                    ColumnLayout {
                        anchors.fill: parent; spacing: 0
                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: Theme.header; Layout.leftMargin: 16; Layout.rightMargin: 16; spacing: 8
                            AppText { text: root.page; font.pixelSize: 15; font.weight: Font.DemiBold }
                            Item { Layout.fillWidth: true }
                            ActionButton { visible: root.page === "Home"; text: "New session"; glyph: "plus"; accent: true; enabled: root.online && !root.busy; onClicked: root.newSession() }
                            ActionButton { text: root.busy ? "Working…" : "Refresh"; glyph: "refresh"; enabled: !root.busy; onClicked: root.call("refresh") }
                            ActionButton { text: "Search"; glyph: "search"; shortcut: "Ctrl K"; enabled: root.online; onClicked: root.showSearch() }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                        ColumnLayout {
                            visible: !root.online && root.needsHost; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                            Item { Layout.fillHeight: true }
                            Symbol { name: "terminal"; tint: Theme.dim; Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 30; Layout.preferredHeight: 30 }
                            AppText { text: "Local host is offline"; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                            AppText { text: "Start the local host, then reconnect."; color: Theme.muted; Layout.alignment: Qt.AlignHCenter }
                            ActionButton { text: "Start Host"; accent: true; enabled: !root.busy; Layout.alignment: Qt.AlignHCenter; onClicked: root.call("host.start") }
                            Item { Layout.fillHeight: true }
                        }
                        StackLayout {
                            visible: root.online || !root.needsHost; Layout.fillWidth: true; Layout.fillHeight: true
                            currentIndex: ["Home", "Overview", "Layers", "Activity", "Settings"].indexOf(root.page)
                            HomePage { controller: root }
                            OverviewPage { id: overview; controller: root }
                            LayersPage { id: layersPage; controller: root }
                            ActivityPage { controller: root }
                            SettingsPage { controller: root }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: Theme.footer; Layout.leftMargin: 16; Layout.rightMargin: 16; spacing: 16
                            AppText { text: root.state.sessions.length + (root.state.sessions.length === 1 ? " session running" : " sessions running"); mono: true; font.pixelSize: 10; color: Theme.dim }
                            AppText { text: root.state.windows.length + " windows · " + root.state.displays.length + " displays · " + root.state.displays.reduce((n, d) => n + d.spaces.length, 0) + " spaces"; mono: true; font.pixelSize: 10; color: Theme.dim; visible: root.message === "" }
                            AppText { visible: root.message !== ""; text: root.message; mono: true; font.pixelSize: 10; color: root.online ? Theme.red : Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                            Item { Layout.fillWidth: true }
                            AppText { text: root.online ? "Local" : "Offline"; mono: true; font.pixelSize: 10; color: Theme.dim }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: sessionDialog
        parent: window.contentItem
        anchors.centerIn: parent
        width: 410; modal: true; padding: 20
        onOpened: { projectPath.forceActiveFocus(); projectPath.selectAll() }
        background: Rectangle { color: Theme.surface; radius: 10; border.color: Theme.borderLit }
        contentItem: ColumnLayout {
            spacing: 16
            AppText { text: "New session"; font.pixelSize: 15; font.weight: Font.DemiBold }
            AppText { text: "Project directory"; color: Theme.muted }
            InputField { id: projectPath; Layout.fillWidth: true; placeholderText: "~/dev/my-project"; onAccepted: if (text.trim() && root.online && !root.busy) { sessionDialog.close(); root.call("sessions.launch", { path: text.trim() }) } }
            RowLayout {
                Item { Layout.fillWidth: true }
                ActionButton { text: "Cancel"; onClicked: sessionDialog.close() }
                ActionButton { text: "Start session"; accent: true; enabled: projectPath.text.trim() !== "" && root.online && !root.busy; onClicked: { sessionDialog.close(); root.call("sessions.launch", { path: projectPath.text.trim() }) } }
            }
        }
    }
}
