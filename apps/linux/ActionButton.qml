import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: button
    property bool accent: false
    property bool selected: false
    property bool quiet: false
    property string glyph: ""
    property string shortcut: ""
    implicitHeight: 26
    horizontalPadding: quiet ? 4 : 10
    font.family: Theme.font
    font.pixelSize: 12
    opacity: enabled ? 1 : 0.4
    readonly property color ink: accent || selected ? Theme.green : hovered ? Theme.text : Theme.muted
    contentItem: RowLayout {
        spacing: 6
        Symbol { visible: button.glyph !== ""; name: button.glyph; tint: button.ink; Layout.preferredWidth: 12; Layout.preferredHeight: 12 }
        AppText { text: button.text; font: button.font; color: button.ink; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        Rectangle {
            visible: button.shortcut !== ""
            implicitWidth: key.implicitWidth + 7; implicitHeight: 18
            radius: 3; color: Theme.hover
            AppText { id: key; anchors.centerIn: parent; text: button.shortcut; mono: true; font.pixelSize: 9; color: Theme.muted }
        }
    }
    background: Rectangle {
        radius: 6
        color: button.quiet ? "transparent" : button.accent || button.selected ? Theme.greenSoft : button.hovered ? Theme.hover : Theme.surface
        border.width: button.quiet ? 0 : 1
        border.color: button.accent || button.selected ? "#31533f" : button.hovered ? Theme.borderLit : Theme.border
    }
}
