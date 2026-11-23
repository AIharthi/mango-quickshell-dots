pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property bool powered: false
    property string statusMsg: ""
    property var devices: []

    function refresh(): void {
        if (!btQueryProc.running)
            btQueryProc.running = true;
    }

    function togglePower(): void {
        if (btActionProc.running)
            return;
        const target = root.powered ? "off" : "on";
        root.statusMsg = "Turning Bluetooth " + target + "...";
        btActionProc.command = ["timeout", "3", "bluetoothctl", "power", target];
        btActionProc.running = true;
    }

    function scan(): void {
        if (btActionProc.running)
            return;
        root.statusMsg = "Scanning for 6 seconds...";
        btActionProc.command = ["timeout", "7", "bluetoothctl", "--timeout", "6", "scan", "on"];
        btActionProc.running = true;
    }

    function toggleDevice(mac: string, connected: bool): void {
        if (btActionProc.running)
            return;
        const cleanMac = (mac || "").trim();
        if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(cleanMac)) {
            root.statusMsg = "Invalid Bluetooth MAC address";
            return;
        }
        const op = connected ? "disconnect" : "connect";
        root.statusMsg = (connected ? "Disconnecting " : "Connecting ") + cleanMac + "...";
        btActionProc.command = ["timeout", "10", "bluetoothctl", op, cleanMac];
        btActionProc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: btQueryProc
        command: [
            "python3", "-c",
            "import json,re,subprocess\n" +
            "def out(c):\n" +
            "  try: return subprocess.check_output(c, stderr=subprocess.DEVNULL, text=True)\n" +
            "  except Exception: return ''\n" +
            "show = out(['bluetoothctl','show'])\n" +
            "powered = bool(re.search(r'Powered:\\s*yes', show))\n" +
            "conn_raw = out(['bluetoothctl','devices','Connected'])\n" +
            "conn_macs = set()\n" +
            "for line in conn_raw.splitlines():\n" +
            "  m = re.match(r'Device\\s+([0-9A-Fa-f:]{17})\\s+(.*)', line)\n" +
            "  if m: conn_macs.add(m.group(1))\n" +
            "all_raw = out(['bluetoothctl','devices'])\n" +
            "devs = []\n" +
            "for line in all_raw.splitlines():\n" +
            "  m = re.match(r'Device\\s+([0-9A-Fa-f:]{17})\\s+(.*)', line)\n" +
            "  if m:\n" +
            "    mac, name = m.group(1), m.group(2).strip()\n" +
            "    devs.append({'mac':mac,'name':name or mac,'connected':(mac in conn_macs)})\n" +
            "devs.sort(key=lambda x: (not x['connected'], x['name'].lower()))\n" +
            "print(json.dumps({'powered':powered,'devices':devs}))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    root.powered = !!d.powered;
                    root.devices = Array.isArray(d.devices) ? d.devices : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: btActionProc
        onExited: {
            root.statusMsg = "";
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 400
        repeat: false
        onTriggered: root.refresh()
    }

    // --- Adapter Power Header ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 48
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: root.powered ? "󰂯" : "󰂲"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(16)
                color: root.powered ? Theme.secondary : Theme.fgSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Bluetooth Adapter"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Text {
                    text: root.statusMsg.length > 0 ? root.statusMsg : (root.powered ? (root.devices.length + " known devices") : "Adapter powered off")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }
            }

            Rectangle {
                implicitHeight: 28
                implicitWidth: scanLbl.implicitWidth + 16
                visible: root.powered
                radius: Theme.r(8)
                color: scanMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                Text {
                    id: scanLbl
                    anchors.centerIn: parent
                    text: "󰑐 Scan"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurface
                }

                MouseArea {
                    id: scanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.scan()
                }
            }

            ToggleSwitch {
                checked: root.powered
                activeColor: Theme.secondary
                onToggled: root.togglePower()
            }
        }
    }

    // --- Devices List ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: devCol.implicitHeight + 24
        visible: root.powered
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: devCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Text {
                text: "DEVICES"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.devices

                delegate: Rectangle {
                    id: devRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Theme.r(10)
                    color: devRow.modelData.connected
                        ? Theme.withAlpha(Theme.secondary, 0.20)
                        : (devMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: devRow.modelData.connected ? 1 : Theme.cardBorderWidth
                    border.color: devRow.modelData.connected ? Theme.secondary : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            text: devRow.modelData.connected ? "󰄬" : "󰂯"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(14)
                            color: devRow.modelData.connected ? Theme.secondary : Theme.fgSurfaceVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: devRow.modelData.name
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: devRow.modelData.connected ? Font.Bold : Font.Medium
                                color: Theme.fgSurface
                            }

                            Text {
                                text: devRow.modelData.mac
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: btActTxt.implicitWidth + 14
                            radius: Theme.r(7)
                            color: devRow.modelData.connected ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                id: btActTxt
                                anchors.centerIn: parent
                                text: devRow.modelData.connected ? "Disconnect" : "Connect"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Bold
                                color: devRow.modelData.connected ? Theme.error : Theme.secondary
                            }

                            MouseArea {
                                id: devMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleDevice(devRow.modelData.mac, devRow.modelData.connected)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.devices.length === 0
                text: "No Bluetooth devices found. Click Scan to search."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
