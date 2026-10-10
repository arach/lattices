pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: home
    required property var controller
    readonly property var activeWindows: controller.state.windows.filter(w => w.isOnScreen).sort((a, b) => Number(b.isFocused) - Number(a.isFocused))
    contentWidth: availableWidth
    clip: true
    ColumnLayout {
        width: home.availableWidth
        spacing: 24
        ColumnLayout {
            Layout.fillWidth: true; Layout.margins: 16; Layout.topMargin: 18; Layout.bottomMargin: 0
            spacing: 10
            RowLayout {
                AppText { text: "Sessions"; font.pixelSize: 13; font.weight: Font.DemiBold }
                AppText { text: home.controller.state.sessions.length; mono: true; font.pixelSize: 11; color: Theme.dim }
                Item { Layout.fillWidth: true }
            }
            Flow {
                id: sessions
                Layout.fillWidth: true
                spacing: 10
                readonly property int columns: Math.min(3, Math.max(1, Math.floor(width / 210)))
                Repeater {
                    model: home.controller.state.sessions
                    Rectangle {
                        id: sessionCard
                        required property var modelData
                        width: (sessions.width - (sessions.columns - 1) * 10) / sessions.columns
                        height: 96; radius: 8; color: Theme.surface; border.color: Theme.border
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 8
                            RowLayout {
                                AppText { text: sessionCard.modelData.name; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: Theme.green }
                                AppText { text: "RUNNING"; mono: true; font.pixelSize: 9; color: Theme.green }
                            }
                            AppText { text: sessionCard.modelData.path || ""; mono: true; font.pixelSize: 10; color: Theme.dim; Layout.fillWidth: true; elide: Text.ElideMiddle }
                            Item { Layout.fillHeight: true }
                            AppText { text: "tmux · " + sessionCard.modelData.windowCount + (sessionCard.modelData.windowCount === 1 ? " window · " : " windows · ") + (sessionCard.modelData.panes || []).length + ((sessionCard.modelData.panes || []).length === 1 ? " pane" : " panes"); mono: true; font.pixelSize: 10; color: Theme.muted }
                        }
                    }
                }
            }
            AppText { visible: home.controller.state.sessions.length === 0; text: "No sessions running"; color: Theme.dim; Layout.topMargin: 5 }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.leftMargin: 16; Layout.rightMargin: 16
            spacing: 10
            RowLayout {
                AppText { text: "Active windows"; font.pixelSize: 13; font.weight: Font.DemiBold }
                AppText { text: home.activeWindows.length; mono: true; font.pixelSize: 11; color: Theme.dim }
                Item { Layout.fillWidth: true }
                ActionButton { text: "Open in Overview"; quiet: true; onClicked: home.controller.page = "Overview" }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 38; Layout.rightMargin: 25; spacing: 10
                AppText { text: "APP"; font.pixelSize: 10; color: Theme.dim; Layout.preferredWidth: home.availableWidth - 32 < 580 ? 112 : 150 }
                AppText { text: "WINDOW"; font.pixelSize: 10; color: Theme.dim; Layout.fillWidth: true }
                AppText { text: "REGION"; font.pixelSize: 10; color: Theme.dim; Layout.preferredWidth: 55 }
                AppText { visible: home.availableWidth - 32 >= 650; text: "SIZE"; font.pixelSize: 10; color: Theme.dim; Layout.preferredWidth: 84; horizontalAlignment: Text.AlignRight }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Repeater {
                    model: home.activeWindows.slice(0, 14)
                    WindowRow {
                        required property var modelData
                        Layout.fillWidth: true
                        entry: modelData
                        appName: home.controller.appName(modelData.app)
                        enabled: !home.controller.busy
                        onClicked: home.controller.call("windows.focus", { wid: modelData.wid })
                    }
                }
            }
            AppText { visible: home.activeWindows.length === 0; text: "No active windows on screen"; color: Theme.dim; Layout.topMargin: 20 }
        }
        Item { implicitHeight: 22 }
    }
}
