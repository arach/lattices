pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property var state: ({ windows: [], displays: [], sessions: [], clients: [], pending: [], describe: {} })
    property bool online: false
    property bool busy: false
    property string message: "Connecting to the local host…"
    property string page: "Workspace"
    property double selectedWid: -1
    property string query: ""
    property var selectedWindow: state.windows.find(w => w.wid === selectedWid) || null
    property var filteredWindows: state.windows.filter(w => (w.app + " " + w.title).toLowerCase().includes(query.toLowerCase()))

    function call(method, params) {
        if (!backend.running || busy) return
        busy = true
        message = ""
        backend.write(JSON.stringify({ method: method, params: params || {} }) + "\n")
    }
    function decide(request, approve) {
        call(request.kind === "daemon" ? (approve ? "clients.approve" : "clients.deny") : (approve ? "bridge.pairing.approve" : "bridge.pairing.deny"),
            request.kind === "daemon" ? { clientID: request.deviceID } : { deviceID: request.deviceID })
    }
    component InputField: TextField {
        color: "#efefed"
        placeholderTextColor: "#939397"
        selectionColor: "#80503d"
        selectedTextColor: "#efefed"
        implicitHeight: 36
        background: Rectangle { radius: 7; color: "#202023"; border.color: parent.activeFocus ? "#ef6a47" : "#3b3b3e" }
    }
    component Heading: Text { color: "#efefed"; font.pixelSize: 17; font.weight: Font.DemiBold; textFormat: Text.PlainText }
    component Detail: Text { color: "#939397"; font.pixelSize: 12; textFormat: Text.PlainText; wrapMode: Text.WordWrap }

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
                        root.online = true
                        root.busy = false
                        root.message = ""
                    } else if (update.type === "offline") {
                        root.online = false
                        root.busy = false
                        root.message = update.message
                    } else if (update.type === "error") {
                        root.busy = false
                        root.message = update.message
                    } else if (update.type === "done") root.busy = false
                } catch (e) { root.message = "Could not read the host response."; root.busy = false }
            }
        }
        stderr: SplitParser { onRead: data => console.warn(data) }
        onRunningChanged: if (!running) { root.online = false; root.busy = false; root.message = "The app connection stopped. Reopen Lattices to reconnect." }
    }

    FloatingWindow {
        id: window
        title: "Lattices"
        visible: true
        implicitWidth: 1040
        implicitHeight: 760
        minimumSize: Qt.size(820, 620)
        color: "#151516"
        onClosed: Qt.quit()

        RowLayout {
            anchors.fill: parent
            spacing: 0
            Rectangle {
                Layout.preferredWidth: 192
                Layout.fillHeight: true
                color: "#1b1b1e"
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14
                    RowLayout {
                        Text { text: "▦"; color: "#ef6a47"; font.pixelSize: 29 }
                        Heading { text: "lattices"; font.pixelSize: 22 }
                    }
                    Detail { text: "ON THIS MACHINE"; font.pixelSize: 10; font.letterSpacing: 1.5; Layout.bottomMargin: 17 }
                    Repeater {
                        model: ["Workspace", "Host"]
                        ActionButton {
                            required property string modelData
                            Layout.fillWidth: true
                            text: modelData
                            selected: root.page === modelData
                            onClicked: root.page = modelData
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: "#323235" }
                    RowLayout {
                        Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 4; color: root.online ? "#8ca88b" : "#a9816c" }
                        Detail { text: root.online ? "Local host connected" : "Local host offline" }
                    }
                    Detail { text: "Linux · Hyprland"; font.pixelSize: 11 }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 26
                spacing: 18
                RowLayout {
                    ColumnLayout {
                        Heading { text: root.page; font.pixelSize: 26 }
                        Detail { text: root.page === "Workspace" ? "Your windows, displays, and persistent sessions." : "Local host health and the devices you trust." }
                    }
                    Item { Layout.fillWidth: true }
                    ActionButton { text: root.busy ? "Working…" : "Refresh"; enabled: !root.busy; onClicked: root.call("refresh") }
                }
                Rectangle {
                    visible: root.message !== ""
                    Layout.fillWidth: true
                    implicitHeight: notice.implicitHeight + 22
                    radius: 7
                    color: "#332822"
                    Detail { id: notice; anchors.fill: parent; anchors.margins: 11; text: root.message; color: "#e6b39d" }
                }
                ColumnLayout {
                    visible: !root.online
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Heading { text: "Connect your local host" }
                    Detail { text: "Start Lattices Host in this desktop session, then refresh." }
                    ActionButton { text: "Start Host"; accent: true; enabled: !root.busy; onClicked: root.call("host.start") }
                    Item { Layout.fillHeight: true }
                }
                ScrollView {
                    visible: root.online
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: parent.width
                        spacing: 20
                        ColumnLayout {
                            visible: root.page === "Workspace"
                            Layout.fillWidth: true
                            spacing: 12
                            Flow {
                                Layout.fillWidth: true
                                spacing: 10
                                Repeater {
                                    model: root.state.displays
                                    Rectangle {
                                        id: displayCard
                                        required property var modelData
                                        width: 228; height: 74; radius: 9; color: "#202023"; border.color: "#343437"
                                        Column {
                                            anchors.fill: parent; anchors.margins: 13; spacing: 7
                                            Heading { text: displayCard.modelData.displayId; font.pixelSize: 14 }
                                            Detail { text: displayCard.modelData.frame.w + " × " + displayCard.modelData.frame.h + "  ·  Workspace " + displayCard.modelData.currentSpaceId }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Heading { text: "Windows" }
                                Detail { text: "(" + root.state.windows.length + ")" }
                                Item { Layout.fillWidth: true }
                                InputField { placeholderText: "Find a window"; Layout.preferredWidth: 210; onTextChanged: root.query = text }
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 8
                                ActionButton { text: "Focus"; accent: true; enabled: root.selectedWindow !== null && !root.busy; onClicked: root.call("windows.focus", { wid: root.selectedWid }) }
                                Repeater {
                                    model: ["left", "right", "center", "maximize"]
                                    ActionButton {
                                        required property string modelData
                                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                        enabled: root.selectedWindow !== null && !root.busy
                                        onClicked: root.call("windows.place", { wid: root.selectedWid, placement: modelData })
                                    }
                                }
                            }
                            Repeater {
                                model: root.filteredWindows
                                Rectangle {
                                    id: windowRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 60; radius: 7
                                    color: root.selectedWid === windowRow.modelData.wid ? "#302723" : "#202023"
                                    border.color: root.selectedWid === windowRow.modelData.wid ? "#80503d" : "#323235"
                                    MouseArea { anchors.fill: parent; onClicked: root.selectedWid = windowRow.modelData.wid; onDoubleClicked: root.call("windows.focus", { wid: windowRow.modelData.wid }) }
                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 11; spacing: 13
                                        Rectangle { implicitWidth: 5; implicitHeight: 25; radius: 2; color: windowRow.modelData.isFocused ? "#ef6a47" : "#444447" }
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Heading { text: windowRow.modelData.app; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                                            Detail { text: windowRow.modelData.title || "Untitled"; Layout.fillWidth: true; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                                        }
                                        Detail { text: "WS " + windowRow.modelData.spaceIds.join(", "); Layout.preferredWidth: 50 }
                                    }
                                }
                            }
                            Detail { visible: root.filteredWindows.length === 0; text: root.query ? "No matching windows." : "No windows on this desktop." }
                            Heading { text: "Sessions"; Layout.topMargin: 14 }
                            Repeater {
                                model: root.state.sessions
                                ColumnLayout {
                                    id: sessionRow
                                    required property var modelData
                                    Layout.fillWidth: true; spacing: 4
                                    Heading { text: sessionRow.modelData.name; font.pixelSize: 13 }
                                    Detail { text: (sessionRow.modelData.path || "") + "  ·  " + sessionRow.modelData.windowCount + " tmux windows"; Layout.fillWidth: true }
                                }
                            }
                            Detail { visible: root.state.sessions.length === 0; text: "Start a session to keep your project running." }
                            RowLayout {
                                InputField { id: projectPath; Layout.fillWidth: true; placeholderText: "Project directory, e.g. ~/dev/my-project"; onAccepted: if (text.trim()) root.call("sessions.launch", { path: text.trim() }) }
                                ActionButton { text: "Start Session"; enabled: projectPath.text.trim() !== "" && !root.busy; onClicked: root.call("sessions.launch", { path: projectPath.text.trim() }) }
                            }
                        }
                        ColumnLayout {
                            visible: root.page === "Host"
                            Layout.fillWidth: true
                            spacing: 12
                            Heading { text: root.state.describe.hostname || "This machine" }
                            Detail { text: "Desktop events: " + (root.state.describe.eventStream ? root.state.describe.eventStream.state : "not reported") }
                            Detail { text: root.state.describe.build ? "Build " + root.state.describe.build.version + " · " + (root.state.describe.build.commit ? root.state.describe.build.commit.slice(0, 10) : "revision unknown") + (root.state.describe.build.dirty ? " · local changes" : "") : "Build information is not available from this host." }
                            Heading { text: "Pairing requests"; Layout.topMargin: 12 }
                            Detail { visible: root.state.pending.length === 0; text: root.state.pairingSupported ? "No devices are waiting for approval." : "Daemon pairing controls need a current Lattices Host." }
                            Repeater {
                                model: root.state.pending
                                ColumnLayout {
                                    id: pairingRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Heading { text: pairingRow.modelData.deviceName; font.pixelSize: 14 }
                                    Detail { text: "Code " + pairingRow.modelData.fingerprint + " · " + pairingRow.modelData.capabilities.join(", "); color: "#e6b39d" }
                                    Detail { text: "Check that this code matches the requesting device before approving." }
                                    RowLayout {
                                        ActionButton { text: "Approve"; accent: true; enabled: !root.busy; onClicked: root.decide(pairingRow.modelData, true) }
                                        ActionButton { text: "Deny"; enabled: !root.busy; onClicked: root.decide(pairingRow.modelData, false) }
                                    }
                                }
                            }
                            Heading { text: "Paired devices"; Layout.topMargin: 12 }
                            Detail { visible: root.state.clients.length === 0; text: "No paired devices reported." }
                            Repeater {
                                model: root.state.clients
                                RowLayout {
                                    id: deviceRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Heading { text: deviceRow.modelData.name; font.pixelSize: 14 }
                                        Detail { text: (deviceRow.modelData.node || deviceRow.modelData.kind) + " · " + (deviceRow.modelData.scope || "read") }
                                    }
                                    ActionButton { text: "Revoke"; enabled: !root.busy; onClicked: root.call(deviceRow.modelData.kind === "daemon" ? "clients.revoke" : "bridge.devices.revoke", deviceRow.modelData.kind === "daemon" ? { clientID: deviceRow.modelData.id } : { deviceID: deviceRow.modelData.id }) }
                                }
                            }
                            Heading { text: "Capabilities"; Layout.topMargin: 12 }
                            Detail { text: (root.state.describe.capabilities || []).join(" · "); Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
