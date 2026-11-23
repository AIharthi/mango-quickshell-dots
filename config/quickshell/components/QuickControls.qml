pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: false
    signal draggingChanged(bool dragging)
    signal openSettingsRequested(string page)

    property real volumeLevel: 0.5
    property bool volumeMuted: false
    property bool micMuted: false
    property bool _dragging: false

    property real brightnessLevel: 0.8
    property bool brightnessSupported: false

    property bool wifiEnabled: false
    property string wifiSsid: "Offline"

    property bool btEnabled: false
    property string btDevice: "Off"

    property string defaultSinkLabel: "Audio Output"

    onActiveChanged: {
        if (active)
            refreshAll();
    }

    Component.onCompleted: {
        if (active)
            refreshAll();
    }

    function runDbusGuardedToggle(serviceName: string, cmdArgs: list<string>): void {
        if (toggleCmdProc.running)
            return;
        toggleCmdProc.command = [
            "sh", "-c",
            "svc=\"$1\"; shift; if dbus-send --system --dest=org.freedesktop.DBus --type=method_call --print-reply=literal /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \"string:$svc\" 2>/dev/null | grep -q true; then exec \"$@\"; fi",
            "_", serviceName
        ].concat(cmdArgs);
        toggleCmdProc.running = true;
    }

    function refreshAll(): void {
        if (DeviceCaps.hasAudio && !volReadProc.running)
            volReadProc.running = true;
        if (DeviceCaps.hasBacklight && !brightReadProc.running)
            brightReadProc.running = true;
        if (DeviceCaps.hasWifi && !wifiReadProc.running)
            wifiReadProc.running = true;
        if (DeviceCaps.hasBluetooth && !btReadProc.running)
            btReadProc.running = true;
        if (!DeviceCaps.hasExtraQuickControls && DeviceCaps.hasAudio && !sinkLabelProc.running)
            sinkLabelProc.running = true;
    }

    property int _pendingVolPct: -1
    property int _pendingBrightPct: -1

    function applyVolume(ratio: real): void {
        const clamped = Math.max(0.0, Math.min(1.0, ratio));
        root.volumeLevel = clamped;
        root.volumeMuted = clamped <= 0.001;
        root._pendingVolPct = Math.round(clamped * 100);
        if (!volApplyTimer.running)
            volApplyTimer.start();
    }

    function applyBrightness(ratio: real): void {
        if (!root.brightnessSupported)
            return;
        const clamped = Math.max(0.05, Math.min(1.0, ratio));
        root.brightnessLevel = clamped;
        root._pendingBrightPct = Math.round(clamped * 100);
        if (!brightApplyTimer.running)
            brightApplyTimer.start();
    }

    Timer {
        id: volApplyTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root._pendingVolPct >= 0) {
                const pct = root._pendingVolPct;
                root._pendingVolPct = -1;
                Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", pct + "%"]);
            }
        }
    }

    Timer {
        id: brightApplyTimer
        interval: 35
        repeat: false
        onTriggered: {
            if (root._pendingBrightPct >= 0) {
                const pct = root._pendingBrightPct;
                root._pendingBrightPct = -1;
                Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
            }
        }
    }

    // --- System Queries (gated on detected hardware) ---
    function cycleAudioSink(): void {
        if (toggleCmdProc.running)
            return;
        toggleCmdProc.command = [
            "sh", "-c",
            "def=$(pactl get-default-sink 2>/dev/null); nxt=$(pactl list short sinks 2>/dev/null | awk -v d=\"$def\" '{a[NR]=$2; if($2==d) idx=NR} END{if(NR>0){print a[(idx%NR)+1]}}'); [ -n \"$nxt\" ] && pactl set-default-sink \"$nxt\""
        ];
        toggleCmdProc.running = true;
    }

    Process {
        id: volReadProc
        command: ["sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@; pactl get-sink-mute @DEFAULT_SINK@; echo '---MIC---'; pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").split("---MIC---");
                const sinkTxt = parts[0] || "";
                const match = sinkTxt.match(/([0-9]+)%/);
                if (match)
                    root.volumeLevel = Math.max(0.0, Math.min(1.0, parseInt(match[1], 10) / 100.0));
                root.volumeMuted = sinkTxt.indexOf("Mute: yes") !== -1 || root.volumeLevel <= 0.001;
                if (parts.length > 1)
                    root.micMuted = parts[1].indexOf("Mute: yes") !== -1;
            }
        }
    }

    Process {
        id: sinkLabelProc
        command: [
            "sh", "-c",
            "def=$(pactl get-default-sink 2>/dev/null); pactl list sinks 2>/dev/null | awk -v d=\"$def\" 'BEGIN{m=0} /^[[:space:]]*Name:/{m=($2==d)} m && /^[[:space:]]*Description:/{sub(/^[[:space:]]*Description:[[:space:]]*/,\"\"); print; exit}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = (text || "").trim();
                if (s.length > 0)
                    root.defaultSinkLabel = s;
            }
        }
    }

    Process {
        id: brightReadProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",");
                if (parts.length >= 4) {
                    const pct = parseFloat(parts[3].replace("%", ""));
                    if (!isNaN(pct)) {
                        root.brightnessLevel = Math.max(0.0, Math.min(1.0, pct / 100.0));
                        root.brightnessSupported = true;
                        return;
                    }
                }
                root.brightnessSupported = false;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.brightnessSupported = false;
        }
    }

    Process {
        id: wifiReadProc
        command: [
            "sh", "-c",
            "if ! dbus-send --system --dest=org.freedesktop.DBus --type=method_call --print-reply=literal /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.freedesktop.NetworkManager 2>/dev/null | grep -q true; then echo 'disabled|'; exit 0; fi; radio=$(timeout 1 nmcli radio wifi </dev/null 2>/dev/null || echo disabled); ssid=$(timeout 1 nmcli -t -f ACTIVE,SSID dev wifi </dev/null 2>/dev/null | awk -F: '$1==\"yes\"{print $2; exit}'); echo \"$radio|$ssid\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root.wifiEnabled = (parts[0] === "enabled");
                root.wifiSsid = (parts.length > 1 && parts[1].length > 0)
                    ? parts[1]
                    : (root.wifiEnabled ? "Disconnected" : "Off");
            }
        }
    }

    Process {
        id: btReadProc
        command: [
            "sh", "-c",
            "if ! dbus-send --system --dest=org.freedesktop.DBus --type=method_call --print-reply=literal /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.bluez 2>/dev/null | grep -q true; then echo 'no|'; exit 0; fi; pwr=$(timeout 1 bluetoothctl show </dev/null 2>/dev/null | awk '/Powered:/{print $2; exit}'); dev=$(timeout 1 bluetoothctl devices Connected </dev/null 2>/dev/null | head -n1 | cut -d' ' -f3-); echo \"${pwr:-no}|$dev\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root.btEnabled = (parts[0] === "yes");
                root.btDevice = (parts.length > 1 && parts[1].length > 0)
                    ? parts[1]
                    : (root.btEnabled ? "On" : "Off");
            }
        }
    }

    Process {
        id: toggleCmdProc
        onExited: refreshDelayTimer.restart()
    }

    Timer {
        id: refreshDelayTimer
        interval: 350
        repeat: false
        onTriggered: root.refreshAll()
    }

    radius: Theme.r(18)
    color: Theme.cardBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "󰒓  QUICK CONTROLS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            Text {
                text: DeviceCaps.deviceType === "laptop" ? "󰌢" : "󰍹"
                font.family: Theme.iconFont
                font.pixelSize: 12
                color: Theme.fgSurfaceVariant
            }
        }

        // --- Volume Slider ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: muteArea.containsMouse ? Theme.hoverBg : Theme.surfaceContainer

                Text {
                    anchors.centerIn: parent
                    text: root.volumeMuted ? "󰝟" : "󰕾"
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                    color: root.volumeMuted ? Theme.error : Theme.primary
                }

                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        toggleCmdProc.command = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"];
                        toggleCmdProc.running = true;
                    }
                }
            }

            Item {
                id: volSlider
                Layout.fillWidth: true
                implicitHeight: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 8
                    radius: Theme.r(4)
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        height: parent.height
                        width: parent.width * root.volumeLevel
                        radius: Theme.r(4)
                        color: root.volumeMuted ? Theme.outline : Theme.primary

                        Behavior on width {
                            enabled: !root._dragging && !Theme.isSimple
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => {
                        root._dragging = true;
                        root.draggingChanged(true);
                        root.applyVolume(mouse.x / width);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.applyVolume(mouse.x / width);
                    }
                    onReleased: {
                        root._dragging = false;
                        root.draggingChanged(false);
                    }
                    onCanceled: {
                        root._dragging = false;
                        root.draggingChanged(false);
                    }
                }
            }

            Text {
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                text: Math.round(root.volumeLevel * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                color: Theme.fgSurface
            }

            Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: Theme.r(13)
                color: micMuteArea.containsMouse ? Theme.hoverBg : Theme.surfaceContainer

                Text {
                    anchors.centerIn: parent
                    text: root.micMuted ? "󰍭" : "󰍬"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: root.micMuted ? Theme.error : Theme.secondary
                }

                MouseArea {
                    id: micMuteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        toggleCmdProc.command = ["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"];
                        toggleCmdProc.running = true;
                    }
                }
            }
        }

        // --- Brightness Slider (shown only on devices with backlight) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: DeviceCaps.hasBacklight
            opacity: root.brightnessSupported ? 1.0 : 0.45

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: Theme.surfaceContainer

                Text {
                    anchors.centerIn: parent
                    text: "󰃠"
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                    color: Theme.warning
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 22

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 8
                    radius: Theme.r(4)
                    color: Theme.surfaceContainerHighest

                    Rectangle {
                        height: parent.height
                        width: root.brightnessSupported ? (parent.width * root.brightnessLevel) : 0
                        radius: Theme.r(4)
                        color: Theme.warning

                        Behavior on width {
                            enabled: !root._dragging && !Theme.isSimple
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.brightnessSupported
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => {
                        root._dragging = true;
                        root.draggingChanged(true);
                        root.applyBrightness(mouse.x / width);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.applyBrightness(mouse.x / width);
                    }
                    onReleased: {
                        root._dragging = false;
                        root.draggingChanged(false);
                    }
                    onCanceled: {
                        root._dragging = false;
                        root.draggingChanged(false);
                    }
                }
            }

            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: root.brightnessSupported ? (Math.round(root.brightnessLevel * 100) + "%") : "N/A"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                color: Theme.fgSurface
            }
        }

        // --- Hardware-Aware Wi-Fi & Bluetooth Pills (only shown when hardware exists) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: DeviceCaps.hasWifi || DeviceCaps.hasBluetooth

            // Wi-Fi Pill
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                visible: DeviceCaps.hasWifi
                radius: Theme.r(12)
                color: root.wifiEnabled
                    ? Theme.withAlpha(Theme.primary, 0.22)
                    : (wifiArea.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: Theme.cardBorderWidth
                border.color: root.wifiEnabled ? Theme.primary : Theme.cardBorder
                scale: wifiArea.pressed ? 0.97 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        text: root.wifiEnabled ? "󰤨" : "󰤭"
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                        color: root.wifiEnabled ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.wifiSsid
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }
                }

                MouseArea {
                    id: wifiArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            root.openSettingsRequested("network");
                        } else {
                            const target = root.wifiEnabled ? "off" : "on";
                            root.runDbusGuardedToggle("org.freedesktop.NetworkManager", ["timeout", "2", "nmcli", "radio", "wifi", target]);
                        }
                    }
                }
            }

            // Bluetooth Pill
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                visible: DeviceCaps.hasBluetooth
                radius: Theme.r(12)
                color: root.btEnabled
                    ? Theme.withAlpha(Theme.secondary, 0.22)
                    : (btArea.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: Theme.cardBorderWidth
                border.color: root.btEnabled ? Theme.secondary : Theme.cardBorder
                scale: btArea.pressed ? 0.97 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        text: root.btEnabled ? "󰂯" : "󰂲"
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                        color: root.btEnabled ? Theme.secondary : Theme.fgSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.btDevice
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }
                }

                MouseArea {
                    id: btArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            root.openSettingsRequested("bluetooth");
                        } else {
                            const target = root.btEnabled ? "off" : "on";
                            root.runDbusGuardedToggle("org.bluez", ["timeout", "2", "bluetoothctl", "power", target]);
                        }
                    }
                }
            }
        }

        // --- Desktop Audio & Settings Shortcut (shown when no backlight/wifi/bt clutter exists) ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            visible: !DeviceCaps.hasExtraQuickControls
            radius: Theme.r(11)
            color: audioSettingsArea.containsMouse ? Theme.hoverBg : Theme.subCardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            scale: audioSettingsArea.pressed ? 0.97 : 1.0

            Behavior on color {
                enabled: !Theme.isSimple
                ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.isSimple
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: "󰋋"
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                    color: Theme.secondary
                }

                Text {
                    Layout.fillWidth: true
                    text: root.defaultSinkLabel
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: Theme.r(7)
                    color: cycSinkMouse.containsMouse ? Theme.hoverBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰓃"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: cycSinkMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: cycSinkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cycleAudioSink()
                    }
                }

                Text {
                    text: "󰒓"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.fgSurfaceVariant
                }
            }

            MouseArea {
                id: audioSettingsArea
                anchors.fill: parent
                anchors.rightMargin: 28
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettingsRequested("audio")
            }
        }

        // --- Quick Desktop Actions Strip ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: [
                    { id: "shot",  icon: "󰹑", active: false, accent: Theme.primary },
                    { id: "pick",  icon: "󰈊", active: false, accent: Theme.secondary },
                    { id: "rec",   icon: "󰑊", active: ShellState.recordingActive, accent: Theme.error },
                    { id: "game",  icon: "󰊴", active: ShellState.gameModeActive, accent: Theme.tertiary },
                    { id: "wins",  icon: "󰖯", active: false, accent: Theme.primary },
                    { id: "power", icon: "󰐥", active: false, accent: Theme.error }
                ]

                delegate: Rectangle {
                    id: qaBtn
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(9)
                    color: qaBtn.modelData.active
                        ? Theme.withAlpha(qaBtn.modelData.accent, 0.24)
                        : (qaMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: qaBtn.modelData.active ? 1 : Theme.cardBorderWidth
                    border.color: qaBtn.modelData.active ? qaBtn.modelData.accent : Theme.cardBorder
                    scale: qaMouse.pressed ? 0.94 : 1.0

                    Behavior on scale { enabled: !Theme.isSimple; NumberAnimation { duration: 90 } }

                    Text {
                        anchors.centerIn: parent
                        text: qaBtn.modelData.icon
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: (qaBtn.modelData.active || qaMouse.containsMouse) ? qaBtn.modelData.accent : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: qaMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const aid = qaBtn.modelData.id;
                            if (aid === "shot") {
                                Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--area"]);
                            } else if (aid === "pick") {
                                Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--color"]);
                            } else if (aid === "rec") {
                                Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"]);
                            } else if (aid === "game") {
                                ShellState.toggleGameMode();
                            } else if (aid === "wins") {
                                Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
                            } else if (aid === "power") {
                                Quickshell.execDetached(["qs", "ipc", "call", "island", "togglePowerOverlay"]);
                            }
                        }
                    }
                }
            }

            // Night Light quick toggle (shown when wlsunset/hyprsunset/gammastep installed)
            Rectangle {
                visible: DeviceCaps.hasNightLight
                Layout.fillWidth: true
                implicitHeight: 28
                radius: Theme.r(9)
                color: ShellState.nightLightEnabled
                    ? Theme.withAlpha(Theme.warning, 0.24)
                    : (nlMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: ShellState.nightLightEnabled ? 1 : Theme.cardBorderWidth
                border.color: ShellState.nightLightEnabled ? Theme.warning : Theme.cardBorder

                Text {
                    anchors.centerIn: parent
                    text: "󰖔"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: ShellState.nightLightEnabled ? Theme.warning : Theme.fgSurfaceVariant
                }

                MouseArea {
                    id: nlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.setNightLight(!ShellState.nightLightEnabled, ShellState.nightLightTemp)
                }
            }
        }

        // --- MangoWC & Quickshell Mode Toggles (Simple / Blur) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Simple Mode (Everything Square + Minimal Bar)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Theme.r(12)
                color: Theme.isSimple
                    ? Theme.withAlpha(Theme.primary, 0.24)
                    : (simpleArea.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: Theme.isSimple ? 1 : Theme.cardBorderWidth
                border.color: Theme.isSimple ? Theme.primary : Theme.cardBorder
                scale: simpleArea.pressed ? 0.97 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        text: Theme.isSimple ? "󰝤" : "󰝣"
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                        color: Theme.isSimple ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Theme.isSimple ? "Simple · On" : "Simple"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Theme.isSimple ? Font.Bold : Font.DemiBold
                        color: Theme.isSimple ? Theme.primary : Theme.fgSurface
                    }
                }

                MouseArea {
                    id: simpleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.toggleShellMode("simple")
                }
            }

            // Blur Mode (Dynamic Island + Frosted Blurry Windows)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Theme.r(12)
                color: Theme.isBlur
                    ? Theme.withAlpha(Theme.secondary, 0.24)
                    : (blurArea.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: Theme.isBlur ? 1 : Theme.cardBorderWidth
                border.color: Theme.isBlur ? Theme.secondary : Theme.cardBorder
                scale: blurArea.pressed ? 0.97 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        text: Theme.isBlur ? "󰂵" : "󰂷"
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                        color: Theme.isBlur ? Theme.secondary : Theme.fgSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        text: Theme.isBlur ? "Blur · On" : "Blur"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Theme.isBlur ? Font.Bold : Font.DemiBold
                        color: Theme.isBlur ? Theme.secondary : Theme.fgSurface
                    }
                }

                MouseArea {
                    id: blurArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.toggleShellMode("blur")
                }
            }
        }
    }
}
