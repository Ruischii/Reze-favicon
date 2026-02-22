import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../services" as Services

/**
 * NOTE: This component is a DEMO of how to use the FaviconService.
 * In a real-world bar, you would integrate this logic into your existing 
 * taskbar or dock implementation.
 */
Scope {
    id: root

    // ─── Hyprland Client Data ─────────────────────────
    property var clientData: ({})
    property var monitorNames: ({})
    property var dockItems: []

    // Fetches fresh data from hyprctl
    function refreshClients() {
        getClients.running = true;
        getMonitors.running = true;
    }

    // Debounced rebuild of the dock items list
    function rebuildDockItems() {
        rebuildTimer.restart();
    }

    Timer {
        id: rebuildTimer
        interval: 50
        onTriggered: {
            const data = root.clientData;
            const names = root.monitorNames;
            let all = [];
            try {
                all = Array.from(ToplevelManager.toplevels.values);
            } catch(e) { return; }

            let result = [];
            for (const t of all) {
                const addr = t?.HyprlandToplevel?.address ? `0x${t.HyprlandToplevel.address}` : "";
                const client = addr ? data[addr] : null;
                const monName = client ? (names[client.monitor] ?? "") : "";
                const ws = client?.workspace ?? 0;
                const x = client?.x ?? 0;
                const y = client?.y ?? 0;
                result.push({
                    toplevel: t,
                    monitor: monName,
                    workspace: ws,
                    x: x,
                    y: y
                });
            }

            // Sort by workspace ascending, then by Y (row) and then X (column)
            // This ensures logic like "Left-to-Right" and "Top-to-Bottom"
            result.sort((a, b) => {
                if (a.workspace !== b.workspace) {
                    return a.workspace - b.workspace;
                }
                
                // Sort by top-to-bottom first
                if (a.y !== b.y) {
                    return a.y - b.y;
                }
                
                // Then left-to-right
                return a.x - b.x;
            });
            root.dockItems = result;
        }
    }
    
    Component.onCompleted: refreshClients()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["openlayer", "closelayer", "screencast"].includes(event.name)) return;
            refreshClients();
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                try {
                    const clients = JSON.parse(clientsCollector.text);
                    let temp = {};
                    for (const c of clients) {
                        temp[c.address] = {
                            workspace: c.workspace?.id ?? 0,
                            monitor: c.monitor ?? -1,
                            x: c.at?.[0] ?? 0,
                            y: c.at?.[1] ?? 0
                        };
                    }
                    root.clientData = temp;
                } catch(e) {}
                rebuildDockItems();
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    const monitors = JSON.parse(monitorsCollector.text);
                    let temp = {};
                    for (const m of monitors) {
                        temp[m.id] = m.name;
                    }
                    root.monitorNames = temp;
                } catch(e) {}
                rebuildDockItems();
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockWindow
            required property var modelData
            screen: modelData

            anchors {
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "quickshell:favicon-dock"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            exclusiveZone: hasApps ? 72 : 0
            implicitHeight: hasApps ? 72 : 0
            visible: hasApps

            // ─── Theme Constants ──────────────────────────
            readonly property color bgColor: "#f8f8f8"
            readonly property color bgBorder: "#dddddd"
            readonly property color itemBg: "#ffffff"
            readonly property color itemHover: "#eeeeee"
            readonly property color textColor: "#333333"
            readonly property color accentColor: "#357abd"
            readonly property color dotActive: "#357abd"
            readonly property color dotInactive: "#bbbbbb"
            readonly property real rounding: 18

            readonly property string screenName: screen?.name ?? ""
            
            readonly property var myItems: {
                const all = root.dockItems;
                return all.filter(item => item.monitor === screenName);
            }
            
            readonly property bool hasApps: myItems.length > 0

            Behavior on implicitHeight {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: parent
                visible: dockWindow.hasApps
                opacity: dockWindow.hasApps ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    id: dockBg
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 8
                        horizontalCenter: parent.horizontalCenter
                    }
                    height: 56
                    width: dockRow.implicitWidth + 20
                    radius: dockWindow.rounding
                    color: dockWindow.bgColor
                    border.width: 1
                    border.color: dockWindow.bgBorder

                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        id: dockRow
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: dockWindow.myItems

                            FaviconDockItem {
                                required property var modelData
                                toplevel: modelData.toplevel
                                dockTheme: dockWindow
                            }
                        }
                    }
                }
            }
        }
    }
}
