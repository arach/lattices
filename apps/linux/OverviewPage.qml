pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: overview
    required property var controller
    property int workspace: -1
    readonly property var windows: controller.state.windows.filter(w => (workspace < 0 || w.spaceIds.includes(workspace)) && (w.app + " " + w.title).toLowerCase().includes(controller.query.toLowerCase()))
    spacing: 0
    function focusSearch() { filter.forceActiveFocus() }

    RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: 44; Layout.leftMargin: 14; Layout.rightMargin: 14; spacing: 8
        AppText { text: (overview.workspace < 0 ? "All windows" : "Workspace " + overview.workspace) + " · " + overview.windows.length; color: Theme.muted; Layout.fillWidth: true }
        ActionButton { visible: overview.workspace >= 0; text: "All windows"; quiet: true; onClicked: overview.workspace = -1 }
        InputField { id: filter; placeholderText: "Filter windows"; Layout.preferredWidth: 165; text: overview.controller.query; onTextEdited: overview.controller.query = text }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
    RowLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
        ScrollView {
            id: desk
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth; clip: true
            ColumnLayout {
                width: desk.availableWidth; spacing: 16
                Repeater {
                    model: overview.controller.state.displays
                    ColumnLayout {
                        id: display
                        required property var modelData
                        Layout.fillWidth: true; Layout.margins: 16; Layout.bottomMargin: 0; spacing: 8
                        RowLayout {
                            AppText { text: display.modelData.displayId; font.weight: Font.DemiBold; Layout.fillWidth: true }
                            AppText { text: display.modelData.frame.w + " × " + display.modelData.frame.h; mono: true; font.pixelSize: 10; color: Theme.dim }
                        }
                        Rectangle {
                            id: monitor
                            Layout.fillWidth: true
                            implicitHeight: Math.min(330, width * display.modelData.frame.h / display.modelData.frame.w)
                            radius: 7; color: "#101113"; border.color: Theme.borderLit
                            Item {
                                id: canvas
                                anchors.fill: parent; anchors.margins: 8; clip: true
                                readonly property real desktopScale: Math.min(width / display.modelData.frame.w, height / display.modelData.frame.h)
                                readonly property real offsetX: (width - display.modelData.frame.w * desktopScale) / 2
                                readonly property real offsetY: (height - display.modelData.frame.h * desktopScale) / 2
                                Repeater {
                                    model: overview.windows.filter(w => w.displayIndex === display.modelData.displayIndex && w.spaceIds.includes(overview.workspace < 0 ? display.modelData.currentSpaceId : overview.workspace))
                                    Rectangle {
                                        id: miniature
                                        required property var modelData
                                        readonly property bool selected: overview.controller.selectedWid === modelData.wid
                                        x: canvas.offsetX + (modelData.frame.x - display.modelData.frame.x) * canvas.desktopScale
                                        y: canvas.offsetY + (modelData.frame.y - display.modelData.frame.y) * canvas.desktopScale
                                        width: Math.max(20, modelData.frame.w * canvas.desktopScale)
                                        height: Math.max(20, modelData.frame.h * canvas.desktopScale)
                                        z: selected ? 2 : modelData.isFocused ? 1 : 0
                                        radius: 4; color: selected ? "#243d2e" : "#222427"
                                        border.color: selected ? Theme.green : modelData.isFocused ? "#467054" : "#484a4e"
                                        clip: true
                                        AppText { anchors.fill: parent; anchors.margins: 7; text: overview.controller.appName(miniature.modelData.app) + "\n" + miniature.modelData.title; font.pixelSize: 10; color: miniature.selected ? Theme.text : Theme.muted; elide: Text.ElideRight; wrapMode: Text.Wrap; maximumLineCount: 2 }
                                        MouseArea { anchors.fill: parent; onClicked: overview.controller.selectedWid = miniature.modelData.wid; onDoubleClicked: overview.controller.call("windows.focus", { wid: miniature.modelData.wid }) }
                                    }
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: 5
                            Repeater {
                                model: display.modelData.spaces
                                ActionButton {
                                    required property var modelData
                                    text: String(modelData.id)
                                    selected: overview.workspace === modelData.id
                                    onClicked: overview.workspace = overview.workspace === modelData.id ? -1 : modelData.id
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Workspace " + modelData.id + " · " + modelData.windowCount + " windows"
                                }
                            }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.margins: 16; spacing: 3
                    AppText { text: "Windows"; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.bottomMargin: 8 }
                    Repeater {
                        model: overview.windows
                        WindowRow {
                            required property var modelData
                            Layout.fillWidth: true; entry: modelData
                            appName: overview.controller.appName(modelData.app)
                            selected: overview.controller.selectedWid === modelData.wid
                            onClicked: overview.controller.selectedWid = modelData.wid
                        }
                    }
                    AppText { visible: overview.windows.length === 0; text: "No matching windows"; color: Theme.dim; Layout.topMargin: 14 }
                }
            }
        }
        Rectangle { visible: overview.controller.selectedWindow !== null; Layout.fillHeight: true; implicitWidth: 1; color: Theme.border }
        ColumnLayout {
            visible: overview.controller.selectedWindow !== null
            Layout.preferredWidth: 220; Layout.fillHeight: true; Layout.margins: 16; spacing: 10
            AppText { text: "SELECTED WINDOW"; mono: true; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.dim }
            AppText { text: overview.controller.selectedWindow ? overview.controller.appName(overview.controller.selectedWindow.app) : ""; font.pixelSize: 14; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            AppText { text: overview.controller.selectedWindow ? overview.controller.selectedWindow.title : ""; color: Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true; maximumLineCount: 4; elide: Text.ElideRight }
            AppText { text: overview.controller.selectedWindow ? "Workspace " + overview.controller.selectedWindow.spaceIds.join(", ") + "\n" + overview.controller.selectedWindow.frame.w + " × " + overview.controller.selectedWindow.frame.h : ""; mono: true; font.pixelSize: 10; color: Theme.dim; lineHeight: 1.5 }
            ActionButton { text: "Focus window"; accent: true; Layout.fillWidth: true; Layout.topMargin: 8; enabled: !overview.controller.busy; onClicked: overview.controller.call("windows.focus", { wid: overview.controller.selectedWid }) }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border; Layout.topMargin: 8; Layout.bottomMargin: 8 }
            AppText { text: "Placement"; font.weight: Font.DemiBold }
            GridLayout {
                columns: 2; columnSpacing: 6; rowSpacing: 6; Layout.fillWidth: true
                Repeater {
                    model: ["left", "right", "center", "maximize"]
                    ActionButton {
                        required property string modelData
                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        Layout.fillWidth: true; enabled: !overview.controller.busy
                        onClicked: overview.controller.call("windows.place", { wid: overview.controller.selectedWid, placement: modelData })
                    }
                }
            }
            ActionButton { text: "Clear selection"; quiet: true; Layout.topMargin: 8; onClicked: overview.controller.selectedWid = -1 }
            Item { Layout.fillHeight: true }
        }
    }
}
