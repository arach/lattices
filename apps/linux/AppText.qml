import QtQuick

Text {
    property bool mono: false
    color: Theme.text
    font.family: mono ? Theme.mono : Theme.font
    font.pixelSize: 12
    textFormat: Text.PlainText
}
