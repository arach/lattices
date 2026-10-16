import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: row
    required property string glyph
    property bool selected: false
    property bool compact: false
    implicitHeight: 30
    padding: 0
    Accessible.name: text
    ToolTip.visible: compact && hovered
    ToolTip.text: text
    contentItem: RowLayout {
        spacing: 0
        Item {
            Layout.preferredWidth: Theme.rail
            Layout.fillHeight: true
            Symbol { anchors.centerIn: parent; name: row.glyph; tint: row.selected ? Theme.green : row.hovered ? Theme.text : "#b3b3b5" }
            Rectangle { visible: row.compact && row.selected; width: 16; height: 1; color: Theme.green; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3 }
        }
        AppText {
            visible: !row.compact
            Layout.fillWidth: true
            text: row.text
            font.pixelSize: 13
            font.weight: row.selected ? Font.DemiBold : Font.Medium
            color: row.selected || row.hovered ? Theme.text : "#b3b3b5"
        }
    }
    background: Item {
        Rectangle {
            anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; anchors.topMargin: 2; anchors.bottomMargin: 2
            visible: !row.compact && (row.selected || row.hovered)
            radius: 6
            color: row.selected ? "#405647" : "#474749"
        }
    }
}
