pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: activity
    required property var controller
    contentWidth: availableWidth; clip: true
    ColumnLayout {
        width: activity.availableWidth; spacing: 0
        AppText { text: "Actions from this app session"; color: Theme.dim; Layout.margins: 16 }
        Repeater {
            model: activity.controller.activity
            ColumnLayout {
                id: entry
                required property var modelData
                Layout.fillWidth: true; Layout.leftMargin: 16; Layout.rightMargin: 16; spacing: 8
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: 10
                    Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: entry.modelData.error ? Theme.red : Theme.green }
                    AppText { text: entry.modelData.label; Layout.fillWidth: true }
                    AppText { text: entry.modelData.time; mono: true; font.pixelSize: 10; color: Theme.dim }
                }
                AppText { visible: entry.modelData.detail !== ""; text: entry.modelData.detail; color: entry.modelData.error ? Theme.red : Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 2 }
            }
        }
        AppText { visible: activity.controller.activity.length === 0; text: "No activity yet"; color: Theme.dim; Layout.margins: 16 }
    }
}
