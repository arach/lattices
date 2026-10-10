pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var visit: ({ visible: false, name: "", x: 0, y: 0, screens: [] })
    property var realScreens: Quickshell.screens.filter(s => root.visit.screens.some(real => real.name === s.name))

    Socket {
        id: positions
        path: Quickshell.env("LATTICES_VISITOR_SOCKET")
        connected: true
        onConnectionStateChanged: if (!connected) root.visit = ({ visible: false, name: "", x: 0, y: 0, screens: [] })
        parser: SplitParser {
            onRead: data => {
                try { root.visit = JSON.parse(data); }
                catch (e) { root.visit = ({ visible: false, name: "", x: 0, y: 0, screens: [] }); }
            }
        }
    }

    Variants {
        model: root.realScreens
        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            property var area: root.visit.screens.find(s => s.name === modelData.name)
            visible: root.visit.visible && area !== undefined
            color: "transparent"
            anchors { left: true; right: true; top: true; bottom: true }
            // Ignore uses zone -1: cover reserved bars without reserving space.
            // Setting exclusiveZone separately resets this mode to Normal.
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "lattices-visitor"

            Item {
                x: root.visit.x - (panel.area ? panel.area.x : 0)
                y: root.visit.y - (panel.area ? panel.area.y : 0)
                visible: panel.area !== undefined && x >= 0 && y >= 0 && x < panel.width && y < panel.height
                width: 120
                height: 46
                Canvas {
                    width: 24
                    height: 30
                    onPaint: {
                        const c = getContext("2d");
                        c.clearRect(0, 0, width, height);
                        c.beginPath();
                        c.moveTo(1, 1); c.lineTo(1, 24); c.lineTo(7, 18);
                        c.lineTo(12, 29); c.lineTo(17, 27); c.lineTo(12, 16);
                        c.lineTo(22, 16); c.closePath();
                        c.fillStyle = "#ef6a47"; c.fill();
                        c.strokeStyle = "#ffffff"; c.lineWidth = 1.5; c.stroke();
                    }
                }
                Rectangle {
                    x: 19
                    y: 25
                    width: label.implicitWidth + 12
                    height: 20
                    radius: 5
                    color: "#ef6a47"
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: root.visit.name
                        textFormat: Text.PlainText
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
