import QtQuick
import QtQuick.Controls

TextField {
    id: field
    color: Theme.text
    placeholderTextColor: Theme.dim
    selectionColor: "#31533f"
    selectedTextColor: Theme.text
    font.family: Theme.font
    font.pixelSize: 12
    implicitHeight: 28
    leftPadding: 9
    rightPadding: 9
    background: Rectangle { radius: 5; color: "#101012"; border.color: field.activeFocus ? "#42694f" : Theme.borderLit }
}
