import QtQuick
import QtQuick.Controls

Button {
    id: button
    property bool accent: false
    property bool selected: false
    implicitHeight: 34
    horizontalPadding: 13
    font.pixelSize: 12
    opacity: enabled ? 1 : 0.4
    contentItem: Text {
        text: button.text
        textFormat: Text.PlainText
        font: button.font
        color: button.accent ? "#151516" : "#efefed"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 7
        color: button.accent ? (button.hovered ? "#f88e70" : "#ef6a47") : button.selected ? "#39302c" : button.hovered ? "#323235" : "#252528"
        border.color: button.selected ? "#ef6a47" : "#3b3b3e"
    }
}
