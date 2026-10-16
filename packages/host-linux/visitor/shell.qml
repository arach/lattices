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
                // A small rounded dart, tip on the point, with a soft coral glow.
                Canvas {
                    x: -8
                    y: -8
                    width: 34
                    height: 34
                    onPaint: {
                        const c = getContext("2d");
                        c.clearRect(0, 0, width, height);
                        c.save();
                        c.translate(8, 8);
                        c.beginPath();
                        c.moveTo(0, 0); c.lineTo(4, 15.5); c.lineTo(7.6, 9.4); c.lineTo(14.5, 7.6);
                        c.closePath();
                        c.lineJoin = "round";
                        c.shadowColor = "#99ef6a47";
                        c.shadowBlur = 9;
                        c.strokeStyle = "#ffffff"; c.lineWidth = 4; c.stroke();
                        c.shadowBlur = 0;
                        c.fillStyle = "#ef6a47"; c.fill();
                        c.strokeStyle = "#ef6a47"; c.lineWidth = 1.6; c.stroke();
                        c.restore();
                    }
                }
                Rectangle {
                    x: 15
                    y: 17
                    width: label.implicitWidth + 12
                    height: 17
                    radius: height / 2
                    color: "#ef6a47"
                    border.color: "#59ffffff"
                    border.width: 1
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: root.visit.name
                        textFormat: Text.PlainText
                        color: "#ffffff"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}
