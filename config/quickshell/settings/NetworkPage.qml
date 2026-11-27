pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../m3"

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

    // --- Ethernet Wi-Fi Share (Laptop Host <-> PC Client) ---
    property var ethStatus: ({})
    property string ethRoleTab: "client"
    property bool ethRoleUserPicked: false
    property string selectedUpstream: ""
    property string selectedEth: ""
    property string hostDnsMode: "auto"
    property bool ethBusy: false
    property string ethMsg: ""
    property bool ethMsgIsError: false
    property var linkTestResult: null
    property bool linkTesting: false

    readonly property var hostSourceList: {
        const wifi = (root.ethStatus && Array.isArray(root.ethStatus.wifiInterfaces)) ? root.ethStatus.wifiInterfaces : [];
        if (wifi.length > 0)
            return wifi;
        const eth = (root.ethStatus && Array.isArray(root.ethStatus.ethInterfaces)) ? root.ethStatus.ethInterfaces : [];
        return eth.length >= 2 ? eth : [];
    }

    readonly property var hostEthList: {
        const eth = (root.ethStatus && Array.isArray(root.ethStatus.ethInterfaces)) ? root.ethStatus.ethInterfaces : [];
        return eth.filter(i => i.name !== root.selectedUpstream);
    }

    readonly property var clientEthList: (root.ethStatus && Array.isArray(root.ethStatus.ethInterfaces)) ? root.ethStatus.ethInterfaces : []
    readonly property string activeRole: (root.ethStatus && root.ethStatus.role) ? String(root.ethStatus.role) : "off"
    readonly property bool shareActive: !!(root.ethStatus && root.ethStatus.active)

    function applyEthStatus(raw: string): void {
        const clean = (raw || "").trim();
        if (clean.length === 0)
            return;
        try {
            const d = JSON.parse(clean);
            if (!d || typeof d !== "object")
                return;
            if (d.error) {
                root.ethMsg = String(d.error);
                root.ethMsgIsError = true;
            } else if (d.message) {
                root.ethMsg = String(d.message);
                root.ethMsgIsError = false;
            }
            if (Array.isArray(d.interfaces)) {
                root.ethStatus = d;
                ShellState.applyEthShareJson(clean);
                if (!root.ethRoleUserPicked) {
                    if (d.role === "host" || d.role === "client")
                        root.ethRoleTab = String(d.role);
                    else
                        root.ethRoleTab = String(d.recommendedRole || "client");
                }
                const upDef = String(d.upstreamIface || d.sourceIface || "");
                if (root.selectedUpstream.length === 0 && upDef.length > 0)
                    root.selectedUpstream = upDef;
                const ethDef = String(d.ethIface || d.targetIface || d.clientEthIface || "");
                if (root.selectedEth.length === 0 && ethDef.length > 0)
                    root.selectedEth = ethDef;
                if (root.ethRoleTab === "host" && root.selectedEth === root.selectedUpstream && root.hostEthList.length > 0)
                    root.selectedEth = root.hostEthList[0].name;
            }
        } catch (err) {}
    }

    function refreshEthStatus(): void {
        if (!ethStatusProc.running)
            ethStatusProc.running = true;
    }

    function runEthAction(argsList): void {
        if (ethActionProc.running)
            return;
        root.ethBusy = true;
        root.ethMsg = "";
        root.ethMsgIsError = false;
        ethActionProc.command = [Quickshell.shellPath("scripts/manage-eth-share.sh")].concat(argsList);
        ethActionProc.running = true;
    }

    function runLinkTest(): void {
        if (ethTestProc.running)
            return;
        root.linkTesting = true;
        root.linkTestResult = null;
        const gw = (root.ethStatus && root.ethStatus.role === "client") ? "10.42.0.1" : "";
        ethTestProc.command = gw.length > 0
            ? [Quickshell.shellPath("scripts/manage-eth-share.sh"), "test-link", gw]
            : [Quickshell.shellPath("scripts/manage-eth-share.sh"), "test-link"];
        ethTestProc.running = true;
    }

    function backendLabel(code: string): string {
        if (code === "nmcli") return "NetworkManager";
        if (code === "standalone") return "Standalone (nft + dnsmasq)";
        if (code === "static-host") return "NAT Only (Static PC)";
        if (code === "dhcp-client") return "Auto DHCP";
        if (code === "static-client") return "Direct Static (10.42.0.2)";
        return code || "Off";
    }

    function refresh(): void {
        if (!netInfoProc.running)
            netInfoProc.running = true;
        if (DeviceCaps.hasWifi && !wifiListProc.running)
            wifiListProc.running = true;
        refreshEthStatus();
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

    Timer {
        id: ethPollTimer
        interval: 4000
        repeat: true
        running: root.visible && root.shareActive
        onTriggered: root.refreshEthStatus()
    }

    Process {
        id: ethStatusProc
        command: [Quickshell.shellPath("scripts/manage-eth-share.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyEthStatus(text)
        }
    }

    Process {
        id: ethActionProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.ethBusy = false;
                root.applyEthStatus(text);
                refreshTimer.restart();
            }
        }
        onExited: root.ethBusy = false
    }

    Process {
        id: ethTestProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.linkTesting = false;
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && d.ok)
                        root.linkTestResult = d;
                } catch (err) {}
            }
        }
        onExited: root.linkTesting = false
    }

    // --- 0. Ethernet Wi-Fi Share (Laptop Host <-> PC Client) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: ethCol.implicitHeight + 28
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: root.shareActive ? Theme.withAlpha(Theme.m3Primary, 0.45) : Theme.m3Line

        ColumnLayout {
            id: ethCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // Header + Live Role & Cable Badges
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: Theme.r(17)
                    color: root.shareActive ? Theme.m3PrimaryContainer : Theme.m3SurfaceHigh

                    Text {
                        anchors.centerIn: parent
                        text: root.activeRole === "host" ? "󰤨" : "󰈀"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(16)
                        color: root.shareActive ? Theme.m3OnPrimaryContainer : Theme.m3InkDim
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Ethernet Wi-Fi Share"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.Bold
                        color: Theme.m3Ink
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Share laptop Wi-Fi to a PC over Ethernet (both running Aurora Shell)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.m3InkDim
                    }
                }

                // Cable Link Chip
                Rectangle {
                    implicitHeight: 24
                    implicitWidth: cableRow.implicitWidth + 14
                    radius: Theme.r(12)
                    color: Theme.m3SurfaceHigh

                    RowLayout {
                        id: cableRow
                        anchors.centerIn: parent
                        spacing: 5

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: (root.ethStatus && root.ethStatus.carrier) ? Theme.success : Theme.m3InkDim
                        }

                        Text {
                            text: (root.ethStatus && root.ethStatus.carrier)
                                ? ("Plugged" + ((root.ethStatus.linkSpeed && root.ethStatus.linkSpeed.length > 0) ? (" · " + root.ethStatus.linkSpeed) : ""))
                                : "No cable"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(9)
                            font.weight: Font.DemiBold
                            color: (root.ethStatus && root.ethStatus.carrier) ? Theme.m3Ink : Theme.m3InkDim
                        }
                    }
                }

                // Active State Chip
                Rectangle {
                    implicitHeight: 24
                    implicitWidth: roleBadgeLbl.implicitWidth + 16
                    radius: Theme.r(12)
                    color: root.activeRole === "host"
                        ? Theme.m3Primary
                        : (root.activeRole === "client" ? Theme.m3SecondaryContainer : Theme.m3SurfaceHigh)

                    Text {
                        id: roleBadgeLbl
                        anchors.centerIn: parent
                        text: root.activeRole === "host" ? "Sharing" : (root.activeRole === "client" ? "Receiving" : "Off")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.activeRole === "host"
                            ? Theme.m3OnPrimary
                            : (root.activeRole === "client" ? Theme.m3OnSecondaryContainer : Theme.m3InkDim)
                    }
                }
            }

            // Role Switcher Segmented Control
            M3Seg {
                compact: true
                options: [
                    { value: "host", label: "Share Wi-Fi (Laptop)", icon: "󰤨" },
                    { value: "client", label: "Receive (PC)", icon: "󰈀" }
                ]
                current: root.ethRoleTab
                onChosen: function(v) {
                    root.ethRoleUserPicked = true;
                    root.ethRoleTab = v;
                    if (v === "host" && root.selectedEth === root.selectedUpstream && root.hostEthList.length > 0)
                        root.selectedEth = root.hostEthList[0].name;
                }
            }

            // ==================== HOST MODE (LAPTOP) ====================
            ColumnLayout {
                visible: root.ethRoleTab === "host"
                Layout.fillWidth: true
                spacing: 10

                // Active Sharing Summary Box
                Rectangle {
                    visible: root.activeRole === "host"
                    Layout.fillWidth: true
                    implicitHeight: hostLiveCol.implicitHeight + 18
                    radius: Theme.r(16)
                    color: Theme.m3PrimaryContainer
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.m3Primary, 0.35)

                    ColumnLayout {
                        id: hostLiveCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: "Sharing " + (root.ethStatus.upstreamIface || "Wi-Fi") + " to " + (root.ethStatus.ethIface || "Ethernet")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.m3OnPrimaryContainer
                            }

                            Text {
                                text: (root.ethStatus.subnet || "10.42.0.0/24") + " · " + root.backendLabel(root.ethStatus.backend || "")
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.DemiBold
                                color: Theme.m3OnPrimaryContainer
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                visible: !root.ethStatus.clients || root.ethStatus.clients.length === 0
                                text: "Waiting for PC on Ethernet (gateway 10.42.0.1)..."
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.m3OnPrimaryContainer
                            }

                            Repeater {
                                model: (root.ethStatus && Array.isArray(root.ethStatus.clients)) ? root.ethStatus.clients : []

                                delegate: Rectangle {
                                    id: peerChip
                                    required property var modelData
                                    implicitHeight: 24
                                    implicitWidth: peerLbl.implicitWidth + 14
                                    radius: Theme.r(12)
                                    color: Theme.m3SurfaceC

                                    Text {
                                        id: peerLbl
                                        anchors.centerIn: parent
                                        text: (peerChip.modelData.hostname || "PC") + " · " + peerChip.modelData.ip + " · " + peerChip.modelData.state
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fs(9)
                                        font.weight: Font.DemiBold
                                        color: Theme.m3Ink
                                    }
                                }
                            }
                        }
                    }
                }

                // Missing Wi-Fi Notice (Desktop without Wi-Fi)
                Rectangle {
                    visible: root.hostSourceList.length === 0
                    Layout.fillWidth: true
                    implicitHeight: noWifiTxt.implicitHeight + 16
                    radius: Theme.r(14)
                    color: Theme.m3SurfaceHigh

                    Text {
                        id: noWifiTxt
                        anchors.fill: parent
                        anchors.margins: 10
                        wrapMode: Text.Wrap
                        text: "No separate Wi-Fi or secondary upstream adapter detected on this machine. Switch to 'Receive (PC)' to accept internet shared from your laptop."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.m3InkDim
                    }
                }

                // Source (Wi-Fi / Upstream) Selector
                ColumnLayout {
                    visible: root.hostSourceList.length > 0
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "Source Internet (Wi-Fi)"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.m3InkDim
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.hostSourceList

                            delegate: Rectangle {
                                id: srcChip
                                required property var modelData
                                readonly property bool picked: root.selectedUpstream === srcChip.modelData.name
                                implicitHeight: 28
                                implicitWidth: srcRow.implicitWidth + 16
                                radius: Theme.r(14)
                                color: picked ? Theme.m3Primary : (srcMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                                border.width: 1
                                border.color: picked ? Theme.m3Primary : Theme.m3Line

                                RowLayout {
                                    id: srcRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: srcChip.modelData.kind === "wifi" ? "󰤨" : "󰈀"
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.fs(12)
                                        color: srcChip.picked ? Theme.m3OnPrimary : Theme.m3InkDim
                                    }

                                    Text {
                                        text: srcChip.modelData.name + (srcChip.modelData.ssid ? (" · " + srcChip.modelData.ssid) : "")
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fs(10)
                                        font.weight: srcChip.picked ? Font.Bold : Font.Medium
                                        color: srcChip.picked ? Theme.m3OnPrimary : Theme.m3Ink
                                    }
                                }

                                MouseArea {
                                    id: srcMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selectedUpstream = srcChip.modelData.name;
                                        if (root.selectedEth === root.selectedUpstream && root.hostEthList.length > 0)
                                            root.selectedEth = root.hostEthList[0].name;
                                    }
                                }
                            }
                        }
                    }
                }

                // Target (Ethernet Port) Selector
                ColumnLayout {
                    visible: root.hostSourceList.length > 0
                    Layout.fillWidth: true
                    spacing: 5

                    Text {
                        text: "Ethernet Output Port"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.m3InkDim
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.hostEthList

                            delegate: Rectangle {
                                id: ethOutChip
                                required property var modelData
                                readonly property bool picked: root.selectedEth === ethOutChip.modelData.name
                                implicitHeight: 28
                                implicitWidth: ethOutRow.implicitWidth + 16
                                radius: Theme.r(14)
                                color: picked ? Theme.m3Primary : (ethOutMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                                border.width: 1
                                border.color: picked ? Theme.m3Primary : Theme.m3Line

                                RowLayout {
                                    id: ethOutRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Rectangle {
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: ethOutChip.modelData.carrier
                                            ? (ethOutChip.picked ? Theme.m3OnPrimary : Theme.success)
                                            : Theme.m3InkDim
                                    }

                                    Text {
                                        text: ethOutChip.modelData.name + (ethOutChip.modelData.speed ? (" · " + ethOutChip.modelData.speed) : "")
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fs(10)
                                        font.weight: ethOutChip.picked ? Font.Bold : Font.Medium
                                        color: ethOutChip.picked ? Theme.m3OnPrimary : Theme.m3Ink
                                    }
                                }

                                MouseArea {
                                    id: ethOutMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedEth = ethOutChip.modelData.name
                                }
                            }
                        }
                    }
                }

                // DHCP / NAT Mode Selector + Actions
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    M3Seg {
                        visible: root.hostSourceList.length > 0 && root.activeRole !== "host"
                        compact: true
                        options: [
                            { value: "auto", label: "Auto DHCP + DNS", icon: "󰩟" },
                            { value: "static", label: "NAT Only (Static PC)", icon: "󰒍" }
                        ]
                        current: root.hostDnsMode
                        onChosen: function(v) { root.hostDnsMode = v }
                    }

                    M3Btn {
                        visible: root.activeRole !== "host"
                        compact: true
                        variant: "filled"
                        icon: "󰤨"
                        text: root.ethBusy ? "Starting..." : "Start Sharing Wi-Fi"
                        buttonEnabled: !root.ethBusy && root.hostSourceList.length > 0 && root.hostEthList.length > 0
                        onClicked: {
                            const eth = root.selectedEth.length > 0 ? root.selectedEth : "auto";
                            const up = root.selectedUpstream.length > 0 ? root.selectedUpstream : "auto";
                            root.runEthAction(["start-host", eth, up, root.hostDnsMode]);
                        }
                    }

                    M3Btn {
                        visible: root.activeRole === "host"
                        compact: true
                        variant: "danger"
                        icon: "󰓛"
                        text: root.ethBusy ? "Stopping..." : "Stop Sharing"
                        buttonEnabled: !root.ethBusy
                        onClicked: root.runEthAction(["stop-host"])
                    }

                    M3Btn {
                        compact: true
                        variant: "tonal"
                        icon: "󰑐"
                        text: "Refresh"
                        buttonEnabled: !root.ethBusy
                        onClicked: root.refreshEthStatus()
                    }
                }
            }

            // ==================== CLIENT MODE (PC) ====================
            ColumnLayout {
                visible: root.ethRoleTab === "client"
                Layout.fillWidth: true
                spacing: 10

                // Active / Auto-Detected Client Card
                Rectangle {
                    visible: root.activeRole === "client"
                    Layout.fillWidth: true
                    implicitHeight: cliLiveCol.implicitHeight + 18
                    radius: Theme.r(16)
                    color: Theme.m3SecondaryContainer
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.m3Primary, 0.35)

                    ColumnLayout {
                        id: cliLiveCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Receiving Wi-Fi from Laptop (10.42.0.1)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: Theme.m3OnSecondaryContainer
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: root.backendLabel(root.ethStatus.backend || "")
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.Bold
                                color: Theme.m3OnSecondaryContainer
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "Port: " + (root.ethStatus.clientEthIface || root.ethStatus.ethIface || "-")
                                + "   ·   IP: " + (root.ethStatus.clientIp || "10.42.0.x")
                                + ((root.ethStatus.linkSpeed && root.ethStatus.linkSpeed.length > 0) ? ("   ·   " + root.ethStatus.linkSpeed) : "")
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            color: Theme.m3OnSecondaryContainer
                        }
                    }
                }

                // Helpful Guide when waiting for link
                Text {
                    visible: root.activeRole !== "client"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "Plug an Ethernet cable from a laptop running Aurora Shell ('Share Wi-Fi'). Click Auto DHCP to request a 10.42.0.x lease, or Direct Static (10.42.0.2) if no DHCP server is running."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.m3InkDim
                }

                // Ethernet Port Chips
                Flow {
                    visible: root.clientEthList.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.clientEthList

                        delegate: Rectangle {
                            id: cliEthChip
                            required property var modelData
                            readonly property bool picked: root.selectedEth === cliEthChip.modelData.name
                            implicitHeight: 28
                            implicitWidth: cliEthRow.implicitWidth + 16
                            radius: Theme.r(14)
                            color: picked ? Theme.m3Primary : (cliEthMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                            border.width: 1
                            border.color: picked ? Theme.m3Primary : Theme.m3Line

                            RowLayout {
                                id: cliEthRow
                                anchors.centerIn: parent
                                spacing: 6

                                Rectangle {
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: cliEthChip.modelData.carrier
                                        ? (cliEthChip.picked ? Theme.m3OnPrimary : Theme.success)
                                        : Theme.m3InkDim
                                }

                                Text {
                                    text: cliEthChip.modelData.name + (cliEthChip.modelData.ipv4 ? (" · " + cliEthChip.modelData.ipv4) : "")
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: cliEthChip.picked ? Font.Bold : Font.Medium
                                    color: cliEthChip.picked ? Theme.m3OnPrimary : Theme.m3Ink
                                }
                            }

                            MouseArea {
                                id: cliEthMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedEth = cliEthChip.modelData.name
                            }
                        }
                    }
                }

                // Client Action Buttons
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    M3Btn {
                        compact: true
                        variant: "filled"
                        icon: "󰩟"
                        text: root.ethBusy ? "Working..." : "Connect (Auto DHCP)"
                        buttonEnabled: !root.ethBusy && root.clientEthList.length > 0
                        onClicked: {
                            const eth = root.selectedEth.length > 0 ? root.selectedEth : "auto";
                            root.runEthAction(["connect-client", eth, "auto"]);
                        }
                    }

                    M3Btn {
                        compact: true
                        variant: "tonal"
                        icon: "󰒍"
                        text: "Direct Static (10.42.0.2)"
                        buttonEnabled: !root.ethBusy && root.clientEthList.length > 0
                        onClicked: {
                            const eth = root.selectedEth.length > 0 ? root.selectedEth : "auto";
                            root.runEthAction(["connect-client", eth, "static"]);
                        }
                    }

                    M3Btn {
                        visible: root.ethStatus && root.ethStatus.backend === "static-client"
                        compact: true
                        variant: "danger"
                        icon: "󰅖"
                        text: "Restore Ethernet"
                        buttonEnabled: !root.ethBusy
                        onClicked: {
                            const eth = root.selectedEth.length > 0 ? root.selectedEth : "auto";
                            root.runEthAction(["disconnect-client", eth]);
                        }
                    }

                    M3Btn {
                        compact: true
                        variant: "outlined"
                        icon: "󰖩"
                        text: root.linkTesting ? "Testing..." : "Test Link"
                        buttonEnabled: !root.linkTesting
                        onClicked: root.runLinkTest()
                    }
                }

                // Live Ping Diagnostic Readout
                Rectangle {
                    visible: root.linkTestResult !== null
                    Layout.fillWidth: true
                    implicitHeight: pingRow.implicitHeight + 14
                    radius: Theme.r(12)
                    color: Theme.m3SurfaceHigh

                    Flow {
                        id: pingRow
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        Text {
                            text: root.linkTestResult
                                ? ("Gateway " + root.linkTestResult.gateway + ": " + (root.linkTestResult.gatewayOk ? (root.linkTestResult.gatewayMs + " ms") : "Unreachable"))
                                : ""
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: (root.linkTestResult && root.linkTestResult.gatewayOk) ? Theme.success : Theme.m3Error
                        }

                        Text {
                            text: root.linkTestResult
                                ? ("Internet (1.1.1.1): " + (root.linkTestResult.internetOk ? ("Online (" + root.linkTestResult.internetMs + " ms)") : "Offline"))
                                : ""
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.DemiBold
                            color: (root.linkTestResult && root.linkTestResult.internetOk) ? Theme.success : Theme.m3Error
                        }
                    }
                }
            }

            // Warnings or Action Feedback Banner
            Rectangle {
                visible: root.ethMsg.length > 0 || (root.ethStatus && Array.isArray(root.ethStatus.warnings) && root.ethStatus.warnings.length > 0 && root.shareActive)
                Layout.fillWidth: true
                implicitHeight: fbTxt.implicitHeight + 14
                radius: Theme.r(12)
                color: root.ethMsgIsError ? Theme.m3ErrorContainer : Theme.m3SurfaceHigh

                Text {
                    id: fbTxt
                    anchors.fill: parent
                    anchors.margins: 8
                    wrapMode: Text.Wrap
                    text: root.ethMsg.length > 0
                        ? root.ethMsg
                        : ((root.ethStatus && Array.isArray(root.ethStatus.warnings) && root.ethStatus.warnings.length > 0) ? root.ethStatus.warnings.join(" ") : "")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: root.ethMsgIsError ? Font.DemiBold : Font.Normal
                    color: root.ethMsgIsError ? Theme.m3OnErrorContainer : Theme.m3Ink
                }
            }
        }
    }

    // --- 1. Network Interfaces, IP, Gateway & DNS (Ethernet + Wi-Fi) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: ifaceCol.implicitHeight + 24
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
                    text: "Network interfaces, IP & DNS"
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
                    border.width: Theme.subBorderWidth
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
                    border.width: Theme.subBorderWidth
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
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(10)
                                color: Theme.secondary
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "RX " + ifRow.modelData.rxMb + "MB · TX " + ifRow.modelData.txMb + "MB"
                                font.family: Theme.monoFont
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
                            font.family: Theme.monoFont
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
                    font.family: Theme.monoFont
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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: nmCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "NetworkManager profiles & DNS presets"
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
                    clip: true
                    color: nmConnRow.modelData.active ? Theme.tileActiveBg : Theme.subCardBg
                    border.width: nmConnRow.modelData.active ? Theme.activeControlBorderWidth : 0
                    border.color: Theme.primary

                    Rectangle {
                        visible: nmConnRow.modelData.active
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: Theme.primary
                    }

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
                                implicitWidth: nmTogLbl.implicitWidth + 14
                                radius: Theme.r(6)
                                color: nmConnRow.modelData.active ? Theme.withAlpha(Theme.warning, 0.16) : Theme.cardBg
                                border.width: Theme.activeControlBorderWidth
                                border.color: nmConnRow.modelData.active ? Theme.warning : Theme.cardBorder

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
                                    border.width: Theme.subBorderWidth
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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

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
                border.width: Theme.subBorderWidth
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
        radius: Theme.r(22)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line

        ColumnLayout {
            id: netCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            Text {
                text: "Available networks"
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
                    clip: true
                    color: netRow.modelData.inUse
                        ? Theme.tileActiveBg
                        : (netMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: netRow.modelData.inUse ? Theme.activeControlBorderWidth : 0
                    border.color: Theme.primary

                    Rectangle {
                        visible: netRow.modelData.inUse
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        color: Theme.primary
                    }

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
                            color: netRow.modelData.inUse ? Theme.withAlpha(Theme.error, 0.18) : Theme.cardBg
                            border.width: Theme.activeControlBorderWidth
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
