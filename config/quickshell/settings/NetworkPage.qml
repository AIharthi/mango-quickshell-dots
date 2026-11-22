pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property bool wifiEnabled: false
    property bool busy: false
    property string statusMsg: ""
    property string pendingSsid: ""
    property var networks: []

    function refresh(): void {
        if (!wifiListProc.running)
            wifiListProc.running = true;
    }

    function toggleWifi(): void {
        if (nmActionProc.running)
            return;
        const target = root.wifiEnabled ? "off" : "on";
        root.busy = true;
        root.statusMsg = "Turning Wi-Fi " + target + "...";
        nmActionProc.command = ["sh", "-c", "timeout 4 nmcli radio wifi " + target + " </dev/null"];
        nmActionProc.running = true;
    }

    function rescan(): void {
        if (nmActionProc.running)
            return;
        root.busy = true;
        root.statusMsg = "Scanning nearby networks...";
        nmActionProc.command = ["sh", "-c", "timeout 8 nmcli dev wifi rescan </dev/null || true"];
        nmActionProc.running = true;
    }

    function connectNetwork(ssid: string, security: string): void {
        if (nmConnectProc.running)
            return;
        root.busy = true;
        root.pendingSsid = "";
        root.statusMsg = "Connecting to " + ssid + "...";
        nmConnectProc.lastTriedSsid = ssid;
        nmConnectProc.lastSecurity = security;
        nmConnectProc.command = ["sh", "-c", "timeout 12 nmcli dev wifi connect \"$1\" </dev/null", "_", ssid];
        nmConnectProc.running = true;
    }

    function connectWithPassword(): void {
        if (nmConnectProc.running || root.pendingSsid.length === 0)
            return;
        const ssid = root.pendingSsid;
        root.busy = true;
        root.statusMsg = "Authenticating to " + ssid + "...";
        nmConnectProc.lastTriedSsid = ssid;
        nmConnectProc.lastSecurity = "WPA";
        nmConnectProc.command = [
            "sh", "-c",
            "timeout 15 nmcli dev wifi connect \"$1\" password \"$2\" </dev/null",
            "_", ssid, pwdInput.text
        ];
        pwdInput.text = "";
        root.pendingSsid = "";
        nmConnectProc.running = true;
    }

    function disconnectWifi(): void {
        if (nmActionProc.running)
            return;
        root.busy = true;
        root.statusMsg = "Disconnecting...";
        nmActionProc.command = [
            "sh", "-c",
            "dev=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2==\"wifi\"{print $1; exit}'); [ -n \"$dev\" ] && timeout 5 nmcli dev disconnect \"$dev\" </dev/null"
        ];
        nmActionProc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: wifiListProc
        command: [
            "python3", "-c",
            "import json,subprocess\n" +
            "def out(c):\n" +
            "  try: return subprocess.check_output(c, stderr=subprocess.DEVNULL, text=True)\n" +
            "  except Exception: return ''\n" +
            "enabled = out(['nmcli','radio','wifi']).strip() == 'enabled'\n" +
            "nets = []\n" +
            "seen = set()\n" +
            "if enabled:\n" +
            "  raw = out(['nmcli','-t','-f','IN-USE,SSID,SIGNAL,SECURITY','dev','wifi','list'])\n" +
            "  for line in raw.splitlines():\n" +
            "    parts = line.split(':')\n" +
            "    if len(parts) < 4: continue\n" +
            "    in_use = (parts[0].strip() == '*')\n" +
            "    sec = parts[-1].strip()\n" +
            "    sig = int(parts[-2].strip() or 0)\n" +
            "    ssid = ':'.join(parts[1:-2]).replace('\\\\:', ':').strip()\n" +
            "    if not ssid or ssid in seen: continue\n" +
            "    seen.add(ssid)\n" +
            "    nets.append({'inUse':in_use,'ssid':ssid,'signal':sig,'security':sec})\n" +
            "print(json.dumps({'enabled':enabled,'networks':nets}))"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    root.wifiEnabled = !!d.enabled;
                    root.networks = Array.isArray(d.networks) ? d.networks : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: nmActionProc
        onExited: {
            root.busy = false;
            root.statusMsg = "";
            refreshTimer.restart();
        }
    }

    Process {
        id: nmConnectProc
        property string lastTriedSsid: ""
        property string lastSecurity: ""
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0 && lastSecurity.length > 0) {
                root.pendingSsid = lastTriedSsid;
                root.statusMsg = "Enter password for " + lastTriedSsid;
            } else if (exitCode !== 0) {
                root.statusMsg = "Failed to connect to " + lastTriedSsid;
            } else {
                root.statusMsg = "Connected to " + lastTriedSsid;
            }
            refreshTimer.restart();
        }
    }

    Timer {
        id: refreshTimer
        interval: 400
        repeat: false
        onTriggered: root.refresh()
    }

    // --- Wi-Fi Radio & Scan Header ---
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
                text: root.wifiEnabled ? "󰤨" : "󰤭"
                font.family: Theme.iconFont
                font.pixelSize: 16
                color: root.wifiEnabled ? Theme.primary : Theme.fgSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Wi-Fi Radio"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Text {
                    text: root.statusMsg.length > 0 ? root.statusMsg : (root.wifiEnabled ? (root.networks.length + " networks visible") : "Radio disabled")
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }
            }

            Rectangle {
                implicitHeight: 28
                implicitWidth: scanLbl.implicitWidth + 16
                visible: root.wifiEnabled
                radius: Theme.r(8)
                color: scanMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                Text {
                    id: scanLbl
                    anchors.centerIn: parent
                    text: "󰑐 Scan"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgSurface
                }

                MouseArea {
                    id: scanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.rescan()
                }
            }

            Rectangle {
                implicitWidth: 56
                implicitHeight: 28
                radius: Theme.r(8)
                color: root.wifiEnabled ? Theme.primary : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: root.wifiEnabled ? Theme.primary : Theme.cardBorder

                Text {
                    anchors.centerIn: parent
                    text: root.wifiEnabled ? "ON" : "OFF"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: root.wifiEnabled ? Theme.fgPrimary : Theme.fgSurfaceVariant
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWifi()
                }
            }
        }
    }

    // --- Inline Password Entry Bar ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 46
        visible: root.pendingSsid.length > 0
        radius: Theme.r(12)
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.primary

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
                text: "Password (" + root.pendingSsid + "):"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.primary
            }

            TextInput {
                id: pwdInput
                Layout.fillWidth: true
                echoMode: TextInput.Password
                color: Theme.fgSurface
                font.family: Theme.fontFamily
                font.pixelSize: 11
                clip: true
                Keys.onReturnPressed: root.connectWithPassword()
                Keys.onEnterPressed: root.connectWithPassword()
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: 68
                radius: Theme.r(7)
                color: Theme.primary

                Text {
                    anchors.centerIn: parent
                    text: "Connect"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgPrimary
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.connectWithPassword()
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: 54
                radius: Theme.r(7)
                color: Theme.subCardBg

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pwdInput.text = "";
                        root.pendingSsid = "";
                        root.statusMsg = "";
                    }
                }
            }
        }
    }

    // --- Networks List ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: netCol.implicitHeight + 24
        visible: root.wifiEnabled
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: netCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Text {
                text: "AVAILABLE NETWORKS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.networks

                delegate: Rectangle {
                    id: netRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Theme.r(10)
                    color: netRow.modelData.inUse
                        ? Theme.withAlpha(Theme.primary, 0.20)
                        : (netMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: netRow.modelData.inUse ? 1 : Theme.cardBorderWidth
                    border.color: netRow.modelData.inUse ? Theme.primary : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            text: netRow.modelData.inUse ? "󰄬" : "󰤨"
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                            color: netRow.modelData.inUse ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            text: netRow.modelData.ssid
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: netRow.modelData.inUse ? Font.Bold : Font.Medium
                            color: Theme.fgSurface
                        }

                        Text {
                            text: (netRow.modelData.security || "Open") + " · " + netRow.modelData.signal + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: actTxt.implicitWidth + 14
                            radius: Theme.r(7)
                            color: netRow.modelData.inUse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                id: actTxt
                                anchors.centerIn: parent
                                text: netRow.modelData.inUse ? "Disconnect" : "Connect"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: netRow.modelData.inUse ? Theme.error : Theme.primary
                            }

                            MouseArea {
                                id: netMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (netRow.modelData.inUse)
                                        root.disconnectWifi();
                                    else
                                        root.connectNetwork(netRow.modelData.ssid, netRow.modelData.security);
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.networks.length === 0
                text: "No Wi-Fi networks found. Click Scan to refresh."
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
