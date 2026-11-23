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
    property var interfaces: []
    property string gateway: ""
    property var dnsList: []
    property bool hasNmcli: DeviceCaps.hasNmcli
    property var connections: []

    function refresh(): void {
        if (!netInfoProc.running)
            netInfoProc.running = true;
        if (DeviceCaps.hasWifi && !wifiListProc.running)
            wifiListProc.running = true;
    }

    function nmAction(act: string, conn: string, extraArg: string): void {
        if (netActProc.running)
            return;
        root.busy = true;
        const args = [Quickshell.shellPath("scripts/manage-system.sh"), "network-action", act, conn];
        if (extraArg && extraArg.length > 0)
            args.push(extraArg);
        netActProc.command = args;
        netActProc.running = true;
    }

    function toggleWifi(): void {
        if (nmActionProc.running)
            return;
        const target = root.wifiEnabled ? "off" : "on";
        root.busy = true;
        root.statusMsg = "Turning Wi-Fi " + target + "...";
        nmActionProc.command = ["timeout", "4", "nmcli", "radio", "wifi", target];
        nmActionProc.running = true;
    }

    function rescan(): void {
        if (nmActionProc.running)
            return;
        root.busy = true;
        root.statusMsg = "Scanning nearby networks...";
        nmActionProc.command = ["timeout", "8", "nmcli", "dev", "wifi", "rescan"];
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
        nmConnectProc.command = ["timeout", "12", "nmcli", "dev", "wifi", "connect", ssid];
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
        nmConnectProc.command = ["timeout", "15", "nmcli", "dev", "wifi", "connect", ssid, "password", pwdInput.text];
        pwdInput.text = "";
        root.pendingSsid = "";
        nmConnectProc.running = true;
    }

    function disconnectWifi(): void {
        if (netActProc.running)
            return;
        root.busy = true;
        root.statusMsg = "Disconnecting...";
        netActProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "network-action", "wifi-disconnect"];
        netActProc.running = true;
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

    Process {
        id: netInfoProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "network-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    root.interfaces = Array.isArray(d.interfaces) ? d.interfaces : [];
                    root.gateway = d.gateway || "";
                    root.dnsList = Array.isArray(d.dns) ? d.dns : [];
                    root.hasNmcli = !!d.hasNmcli;
                    root.connections = Array.isArray(d.connections) ? d.connections : [];
                } catch (err) {}
            }
        }
    }

    Process {
        id: netActProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                try {
                    const d = JSON.parse((text || "").trim());
                    root.interfaces = Array.isArray(d.interfaces) ? d.interfaces : [];
                    root.gateway = d.gateway || "";
                    root.dnsList = Array.isArray(d.dns) ? d.dns : [];
                    root.connections = Array.isArray(d.connections) ? d.connections : [];
                } catch (err) {}
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 400
        repeat: false
        onTriggered: root.refresh()
    }

    // --- 1. Network Interfaces, IP, Gateway & DNS (Ethernet + Wi-Fi) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: ifaceCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: ifaceCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "NETWORK INTERFACES, IP & DNS"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: netRefLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: netRefMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: netRefLbl
                        anchors.centerIn: parent
                        text: "Refresh"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: netRefMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refresh()
                    }
                }
            }

            Repeater {
                model: root.interfaces

                delegate: Rectangle {
                    id: ifRow
                    required property var modelData
                    readonly property bool isUp: String(ifRow.modelData.state || "").toUpperCase() === "UP"

                    Layout.fillWidth: true
                    implicitHeight: ifInner.implicitHeight + 14
                    radius: Theme.r(11)
                    color: Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: ifInner
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: ifRow.modelData.kind === "wifi" ? "󰤨" : "󰈀"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(14)
                                color: ifRow.isUp ? Theme.success : Theme.fgSurfaceVariant
                            }

                            Text {
                                text: ifRow.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                visible: (ifRow.modelData.speed || "").length > 0
                                text: ifRow.modelData.speed
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.secondary
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "RX " + ifRow.modelData.rxMb + "MB · TX " + ifRow.modelData.txMb + "MB"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }

                            Rectangle {
                                implicitHeight: 18
                                implicitWidth: stLbl.implicitWidth + 10
                                radius: Theme.r(5)
                                color: ifRow.isUp ? Theme.withAlpha(Theme.success, 0.20) : Theme.cardBg

                                Text {
                                    id: stLbl
                                    anchors.centerIn: parent
                                    text: ifRow.modelData.state
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                    color: ifRow.isUp ? Theme.success : Theme.fgSurfaceVariant
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: "IP: " + ((ifRow.modelData.addrs && ifRow.modelData.addrs.length > 0) ? ifRow.modelData.addrs.join(" · ") : "Unassigned")
                                + (ifRow.modelData.mac ? ("   MAC: " + ifRow.modelData.mac) : "")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "Gateway: " + (root.gateway.length > 0 ? root.gateway : "None")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurface
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "DNS: " + (root.dnsList.length > 0 ? root.dnsList.join(", ") : "Automatic")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.primary
                }
            }
        }
    }

    // --- 2. NetworkManager Profiles & Quick DNS Presets (when NM profiles exist) ---
    Rectangle {
        visible: root.hasNmcli && root.connections.length > 0
        Layout.fillWidth: true
        implicitHeight: nmCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: nmCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "NETWORKMANAGER PROFILES & DNS PRESETS"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.connections

                delegate: Rectangle {
                    id: nmConnRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: nmConnInner.implicitHeight + 14
                    radius: Theme.r(10)
                    color: Theme.subCardBg
                    border.width: nmConnRow.modelData.active ? 1 : Theme.cardBorderWidth
                    border.color: nmConnRow.modelData.active ? Theme.primary : Theme.cardBorder

                    ColumnLayout {
                        id: nmConnInner
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: nmConnRow.modelData.name + " (" + nmConnRow.modelData.type + ")"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Rectangle {
                                implicitHeight: 22
                                implicitWidth: nmTogLbl.implicitWidth + 12
                                radius: Theme.r(6)
                                color: Theme.cardBg
                                border.width: Theme.cardBorderWidth
                                border.color: Theme.cardBorder

                                Text {
                                    id: nmTogLbl
                                    anchors.centerIn: parent
                                    text: nmConnRow.modelData.active ? "Disconnect" : "Connect"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                    color: nmConnRow.modelData.active ? Theme.warning : Theme.primary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.nmAction(nmConnRow.modelData.active ? "down" : "up", nmConnRow.modelData.name, "")
                                }
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 5

                            Repeater {
                                model: [
                                    { label: "DNS: Auto",       val: "auto" },
                                    { label: "Cloudflare",      val: "1.1.1.1 1.0.0.1" },
                                    { label: "Google",          val: "8.8.8.8 8.8.4.4" },
                                    { label: "Quad9",           val: "9.9.9.9 149.112.112.112" }
                                ]

                                delegate: Rectangle {
                                    id: dnsChip
                                    required property var modelData
                                    implicitHeight: 20
                                    implicitWidth: dnsTxt.implicitWidth + 10
                                    radius: Theme.r(6)
                                    color: dnsMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                                    border.width: Theme.cardBorderWidth
                                    border.color: Theme.cardBorder

                                    Text {
                                        id: dnsTxt
                                        anchors.centerIn: parent
                                        text: dnsChip.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(9)
                                        color: Theme.fgSurfaceVariant
                                    }

                                    MouseArea {
                                        id: dnsMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.nmAction("dns", nmConnRow.modelData.name, dnsChip.modelData.val)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 3. Wi-Fi Radio & Scan Header (shown only when Wi-Fi hardware exists) ---
    Rectangle {
        visible: DeviceCaps.hasWifi
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
                font.pixelSize: Theme.fs(16)
                color: root.wifiEnabled ? Theme.primary : Theme.fgSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Wi-Fi Radio"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Text {
                    text: root.statusMsg.length > 0 ? root.statusMsg : (root.wifiEnabled ? (root.networks.length + " networks visible") : "Radio disabled")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
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
                    font.pixelSize: Theme.fs(10)
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

            ToggleSwitch {
                checked: root.wifiEnabled
                onToggled: root.toggleWifi()
            }
        }
    }

    // --- Inline Password Entry Bar ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 46
        visible: DeviceCaps.hasWifi && root.pendingSsid.length > 0
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
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.primary
            }

            TextInput {
                id: pwdInput
                Layout.fillWidth: true
                echoMode: TextInput.Password
                color: Theme.fgSurface
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
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
                    font.pixelSize: Theme.fs(10)
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
                    font.pixelSize: Theme.fs(10)
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
        visible: DeviceCaps.hasWifi && root.wifiEnabled
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
                font.pixelSize: Theme.fs(10)
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
                            font.pixelSize: Theme.fs(14)
                            color: netRow.modelData.inUse ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.fillWidth: true
                            text: netRow.modelData.ssid
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: netRow.modelData.inUse ? Font.Bold : Font.Medium
                            color: Theme.fgSurface
                        }

                        Text {
                            text: (netRow.modelData.security || "Open") + " · " + netRow.modelData.signal + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
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
                                font.pixelSize: Theme.fs(10)
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
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
