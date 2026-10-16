pragma Singleton
import QtQuick

// apps/mac/Sources/UI/Theme.swift and AppShellView.swift are the reference.
QtObject {
    readonly property color bg: "#141416"
    readonly property color surface: "#1a1a1a"
    readonly property color hover: "#242424"
    readonly property color border: "#28282a"
    readonly property color borderLit: "#353537"
    readonly property color text: "#ebebeb"
    readonly property color muted: "#9d9d9e"
    readonly property color dim: "#727274"
    readonly property color green: "#33c773"
    readonly property color greenSoft: "#20372b"
    readonly property color red: "#f04d59"
    readonly property string font: "Adwaita Sans"
    readonly property string mono: "JetBrains Mono"
    readonly property int rail: 48
    readonly property int labels: 120
    readonly property int header: 46
    readonly property int footer: 26
}
