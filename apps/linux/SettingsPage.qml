pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: settings
    required property var controller
    contentWidth: availableWidth; clip: true
    ColumnLayout {
        width: settings.availableWidth; spacing: 24
        ColumnLayout {
            Layout.fillWidth: true; Layout.margins: 20; Layout.bottomMargin: 0; spacing: 10
            AppText { text: "Local host"; font.pixelSize: 13; font.weight: Font.DemiBold }
            AppText { text: settings.controller.state.describe.hostname || "This machine"; color: Theme.muted }
            RowLayout {
                Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: settings.controller.online ? Theme.green : Theme.dim }
                AppText { text: (settings.controller.online ? "Connected" : "Offline") + " · 127.0.0.1:" + settings.controller.hostPort; mono: true; font.pixelSize: 11; color: Theme.muted }
            }
            AppText { text: "Desktop events · " + (settings.controller.state.describe.eventStream ? settings.controller.state.describe.eventStream.state : "not reported"); color: Theme.dim }
            AppText { text: settings.controller.state.describe.build ? "Version " + settings.controller.state.describe.build.version + " · " + (settings.controller.state.describe.build.commit || "unknown revision").slice(0, 10) : "Build information not reported"; mono: true; font.pixelSize: 10; color: Theme.dim }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 8 }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20; spacing: 10
            AppText { text: "Pairing requests"; font.pixelSize: 13; font.weight: Font.DemiBold }
            AppText { visible: settings.controller.state.pending.length === 0; text: settings.controller.state.pairingSupported ? "No devices waiting for approval" : "Update the local host to manage device pairing."; color: Theme.dim }
            Repeater {
                model: settings.controller.state.pending
                ColumnLayout {
                    id: pending
                    required property var modelData
                    Layout.fillWidth: true; spacing: 8
                    AppText { text: pending.modelData.deviceName; font.weight: Font.DemiBold }
                    AppText { text: "Code " + pending.modelData.fingerprint + " · " + pending.modelData.capabilities.join(", "); mono: true; font.pixelSize: 11; color: Theme.green; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    AppText { text: "Check that this code matches the requesting device."; color: Theme.muted }
                    RowLayout {
                        ActionButton { text: "Approve"; accent: true; enabled: settings.controller.online && !settings.controller.busy; onClicked: settings.controller.decide(pending.modelData, true) }
                        ActionButton { text: "Deny"; enabled: settings.controller.online && !settings.controller.busy; onClicked: settings.controller.decide(pending.modelData, false) }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 6 }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20; spacing: 10
            AppText { text: "Paired devices"; font.pixelSize: 13; font.weight: Font.DemiBold }
            AppText { visible: settings.controller.state.clients.length === 0; text: "No paired devices reported"; color: Theme.dim }
            Repeater {
                model: settings.controller.state.clients
                RowLayout {
                    id: device
                    required property var modelData
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        AppText { text: device.modelData.name; font.weight: Font.DemiBold }
                        AppText { text: (device.modelData.node || device.modelData.kind) + " · " + (device.modelData.scope || "read"); color: Theme.dim }
                    }
                    ActionButton { text: "Revoke"; enabled: settings.controller.online && !settings.controller.busy; onClicked: settings.controller.call(device.modelData.kind === "daemon" ? "clients.revoke" : "bridge.devices.revoke", device.modelData.kind === "daemon" ? { clientID: device.modelData.id } : { deviceID: device.modelData.id }) }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.margins: 20; Layout.topMargin: 0; spacing: 10
            AppText { text: "Capabilities"; font.pixelSize: 13; font.weight: Font.DemiBold }
            AppText { text: (settings.controller.state.describe.capabilities || []).join(" · "); mono: true; font.pixelSize: 10; color: Theme.dim; wrapMode: Text.WordWrap; Layout.fillWidth: true; lineHeight: 1.6 }
        }
    }
}
