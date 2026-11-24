pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: false
    property bool hideDuplicateToggles: false
    property bool hideHeader: false
    property bool hideStyleFooter: false
    property bool showFocusAwakeRow: false
    property bool tallActionTiles: false
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
    property string hoveredActionLabel: ""

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
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.hideHeader ? 10 : 10
        spacing: root.hideHeader ? 8 : 6

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !root.hideHeader

            Text {
                text: "Quick Controls"
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

        // --- Apple Control Center Capsule Volume Slider ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8

            Item {
                id: volCapsule
                Layout.fillWidth: true
                implicitHeight: root.tallActionTiles ? 34 : 32

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.r(root.tallActionTiles ? 17 : 16)
                    color: Theme.subCardBg
                    border.width: Theme.activeControlBorderWidth
                    border.color: Theme.cardBorder
                    clip: true

                    Rectangle {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: Math.max(parent.height, parent.width * root.volumeLevel)
                        radius: Theme.r(root.tallActionTiles ? 17 : 16)
                        color: root.volumeMuted ? Theme.surfaceContainerHighest : Theme.primary

                        Behavior on width {
                            enabled: !root._dragging && !Theme.reducedMotion
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 6

                        Text {
                            text: root.volumeMuted ? "󰝟" : (root.volumeLevel <= 0.45 ? "󰖀" : "󰕾")
                            font.family: Theme.iconFont
                            font.pixelSize: 15
                            color: root.volumeMuted ? Theme.fgSurfaceVariant : Theme.fgPrimary

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    toggleCmdProc.command = ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"];
                                    toggleCmdProc.running = true;
                                }
                            }
                        }

                        Text {
                            text: root.volumeMuted ? "Muted" : "Sound"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: root.volumeLevel > 0.25 && !root.volumeMuted ? Theme.fgPrimary : Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Math.round(root.volumeLevel * 100) + "%"
                            font.family: Theme.monoFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: root.volumeLevel > 0.88 && !root.volumeMuted ? Theme.fgPrimary : Theme.fgSurface
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.leftMargin: 32
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            root._dragging = true;
                            root.draggingChanged(true);
                            root.applyVolume((mouse.x + 32) / volCapsule.width);
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                root.applyVolume((mouse.x + 32) / volCapsule.width);
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
            }

            Rectangle {
                implicitWidth: root.tallActionTiles ? 34 : 32
                implicitHeight: root.tallActionTiles ? 34 : 32
                radius: Theme.r(root.tallActionTiles ? 17 : 16)
                color: root.micMuted
                    ? Theme.error
                    : (micMuteArea.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: Theme.activeControlBorderWidth
                border.color: root.micMuted ? Theme.error : Theme.cardBorder

                Text {
                    anchors.centerIn: parent
                    text: root.micMuted ? "󰍭" : "󰍬"
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                    color: root.micMuted ? Theme.fgError : Theme.fgSurface
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

        // --- Apple Capsule Brightness Slider (laptops / external DDC) ---
        Item {
            id: brightCapsule
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 30
            visible: DeviceCaps.hasBacklight
            opacity: root.brightnessSupported ? 1.0 : 0.45

            Rectangle {
                anchors.fill: parent
                radius: Theme.r(15)
                color: Theme.subCardBg
                border.width: Theme.activeControlBorderWidth
                border.color: Theme.cardBorder
                clip: true

                Rectangle {
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    width: root.brightnessSupported ? Math.max(parent.height, parent.width * root.brightnessLevel) : parent.height
                    radius: Theme.r(15)
                    color: Theme.warning

                    Behavior on width {
                        enabled: !root._dragging && !Theme.reducedMotion
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 6

                    Text {
                        text: "󰃠"
                        font.family: Theme.iconFont
                        font.pixelSize: 14
                        color: root.brightnessLevel > 0.15 ? Theme.fgPrimary : Theme.warning
                    }

                    Text {
                        text: "Display"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: root.brightnessLevel > 0.25 ? Theme.fgPrimary : Theme.fgSurface
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.brightnessSupported ? (Math.round(root.brightnessLevel * 100) + "%") : "N/A"
                        font.family: Theme.monoFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: root.brightnessLevel > 0.88 ? Theme.fgPrimary : Theme.fgSurface
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.brightnessSupported
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => {
                        root._dragging = true;
                        root.draggingChanged(true);
                        root.applyBrightness(mouse.x / brightCapsule.width);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.applyBrightness(mouse.x / brightCapsule.width);
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
        }

        // --- Hardware-Aware Wi-Fi & Bluetooth Pills (only shown when hardware exists) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8
            visible: DeviceCaps.hasWifi || DeviceCaps.hasBluetooth

            // Wi-Fi Pill (borderless tonal elevation + solid accent disc)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                visible: DeviceCaps.hasWifi
                radius: Theme.r(12)
                color: root.wifiEnabled
                    ? Theme.tileActiveBg
                    : (wifiArea.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: root.wifiEnabled ? Theme.activeControlBorderWidth : 0
                border.color: Theme.primary
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
                    anchors.leftMargin: 8
                    anchors.rightMargin: 10
                    spacing: 7

                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Theme.r(11)
                        color: root.wifiEnabled ? Theme.primary : Theme.surfaceContainerHighest

                        Text {
                            anchors.centerIn: parent
                            text: root.wifiEnabled ? "󰤨" : "󰤭"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: root.wifiEnabled ? Theme.fgPrimary : Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.wifiSsid
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: root.wifiEnabled ? Font.Bold : Font.DemiBold
                        color: root.wifiEnabled ? Theme.fgSurface : Theme.fgSurfaceVariant
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

            // Bluetooth Pill (borderless tonal elevation + solid accent disc)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                visible: DeviceCaps.hasBluetooth
                radius: Theme.r(12)
                color: root.btEnabled
                    ? Theme.tileActiveBg
                    : (btArea.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: root.btEnabled ? Theme.activeControlBorderWidth : 0
                border.color: Theme.secondary
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
                    anchors.leftMargin: 8
                    anchors.rightMargin: 10
                    spacing: 7

                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Theme.r(11)
                        color: root.btEnabled ? Theme.secondary : Theme.surfaceContainerHighest

                        Text {
                            anchors.centerIn: parent
                            text: root.btEnabled ? "󰂯" : "󰂲"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: root.btEnabled ? Theme.fgSecondary : Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.btDevice
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: root.btEnabled ? Font.Bold : Font.DemiBold
                        color: root.btEnabled ? Theme.fgSurface : Theme.fgSurfaceVariant
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

        // --- Desktop Audio & Settings Shortcut ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 32
            visible: !DeviceCaps.hasExtraQuickControls && !root.hideDuplicateToggles
            radius: Theme.r(11)
            color: audioSettingsArea.containsMouse ? Theme.controlFillHover : Theme.subCardBg
            border.width: Theme.activeControlBorderWidth
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
                    color: Theme.fgSurfaceVariant
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
                    color: cycSinkMouse.containsMouse ? Theme.tileActiveBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰓃"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: cycSinkMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
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

        // --- Optional Focus & Keep Awake Row (fills Desktop Cockpit deck cleanly) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 6
            visible: root.showFocusAwakeRow && !root.hideDuplicateToggles

            Repeater {
                model: [
                    { id: "dnd",   label: "Focus",      sub: ShellState.dnd ? "DND On" : "Normal", icon: ShellState.dnd ? "󰂛" : "󰂚", active: ShellState.dnd, tint: Theme.secondary },
                    { id: "awake", label: "Keep Awake", sub: ShellState.keepAwake ? "Paused" : "Auto", icon: "󰅶", active: ShellState.keepAwake, tint: Theme.warning }
                ]

                delegate: Rectangle {
                    id: faTile
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: Theme.r(10)
                    color: faTile.modelData.active
                        ? Theme.tileActiveBg
                        : (faMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: faTile.modelData.active ? Theme.activeControlBorderWidth : 0
                    border.color: faTile.modelData.tint
                    scale: faMouse.pressed ? 0.96 : 1.0

                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 9
                        spacing: 7

                        Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: Theme.r(10)
                            color: faTile.modelData.active ? faTile.modelData.tint : Theme.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: faTile.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: faTile.modelData.active ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: faTile.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: faTile.modelData.active ? Font.Bold : Font.DemiBold
                            color: faTile.modelData.active ? Theme.fgSurface : Theme.fgSurfaceVariant
                        }

                        Text {
                            text: faTile.modelData.sub
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: faTile.modelData.active ? Theme.fgSurface : Theme.withAlpha(Theme.fgSurfaceVariant, 0.72)
                        }
                    }

                    MouseArea {
                        id: faMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (faTile.modelData.id === "dnd")
                                ShellState.toggleDnd();
                            else
                                ShellState.toggleKeepAwake();
                        }
                    }
                }
            }
        }

        // --- Decluttered 4-Pill Quick Actions Strip ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 6

            Repeater {
                model: root.hideDuplicateToggles
                    ? [
                        { id: "shot",  label: "Capture", icon: "󰹑", active: false, isAlert: false, tint: Theme.primary },
                        { id: "rec",   label: "Record",  icon: "󰑊", active: ShellState.recordingActive, isAlert: true, tint: Theme.error },
                        { id: "keys",  label: "Keys",    icon: "󰌌", active: false, isAlert: false, tint: Theme.primary },
                        { id: "wins",  label: "Windows", icon: "󰖯", active: false, isAlert: false, tint: Theme.primary }
                    ]
                    : [
                        { id: "shot",  label: "Capture", icon: "󰹑", active: false, isAlert: false, tint: Theme.primary },
                        { id: "rec",   label: "Record",  icon: "󰑊", active: ShellState.recordingActive, isAlert: true, tint: Theme.error },
                        { id: "game",  label: "Game",    icon: "󰊴", active: ShellState.gameModeActive, isAlert: false, tint: Theme.tertiary },
                        { id: "wins",  label: "Windows", icon: "󰖯", active: false, isAlert: false, tint: Theme.primary }
                    ]

                delegate: Rectangle {
                    id: qaBtn
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: root.tallActionTiles ? 54 : 30
                    radius: Theme.r(root.tallActionTiles ? 12 : 10)
                    color: {
                        if (qaBtn.modelData.active)
                            return qaBtn.modelData.isAlert ? Theme.error : Theme.tileActiveBg;
                        return qaMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg;
                    }
                    border.width: qaBtn.modelData.active ? Theme.activeControlBorderWidth : 0
                    border.color: qaBtn.modelData.tint
                    scale: qaMouse.pressed ? 0.94 : 1.0

                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                    ColumnLayout {
                        visible: root.tallActionTiles
                        anchors.centerIn: parent
                        spacing: 3

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qaBtn.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: 15
                            color: qaBtn.modelData.active
                                ? (qaBtn.modelData.isAlert ? Theme.fgError : qaBtn.modelData.tint)
                                : (qaMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant)
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qaBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: qaBtn.modelData.active ? Font.Bold : Font.DemiBold
                            color: qaBtn.modelData.active
                                ? (qaBtn.modelData.isAlert ? Theme.fgError : Theme.fgSurface)
                                : Theme.fgSurface
                        }
                    }

                    RowLayout {
                        visible: !root.tallActionTiles
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: qaBtn.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: qaBtn.modelData.active
                                ? (qaBtn.modelData.isAlert ? Theme.fgError : qaBtn.modelData.tint)
                                : (qaMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant)
                        }

                        Text {
                            text: qaBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: qaBtn.modelData.active ? Font.Bold : Font.DemiBold
                            color: qaBtn.modelData.active
                                ? (qaBtn.modelData.isAlert ? Theme.fgError : Theme.fgSurface)
                                : Theme.fgSurface
                        }
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
                            } else if (aid === "rec") {
                                Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"]);
                            } else if (aid === "game") {
                                ShellState.toggleGameMode();
                            } else if (aid === "keys") {
                                Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleKeybindSheet"]);
                            } else if (aid === "wins") {
                                Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
                            }
                        }
                    }
                }
            }

            // Night Light compact icon (shown when wlsunset/hyprsunset/gammastep installed)
            Rectangle {
                visible: DeviceCaps.hasNightLight
                implicitWidth: root.tallActionTiles ? 38 : 32
                implicitHeight: root.tallActionTiles ? 54 : 30
                radius: Theme.r(root.tallActionTiles ? 12 : 10)
                color: ShellState.nightLightEnabled
                    ? Theme.tileActiveBg
                    : (nlMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: ShellState.nightLightEnabled ? Theme.activeControlBorderWidth : 0
                border.color: Theme.warning

                Text {
                    anchors.centerIn: parent
                    text: "󰖔"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: ShellState.nightLightEnabled ? Theme.warning : (nlMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant)
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

        // --- Clean Apple Visual Style Summary Pill (LMB -> Settings Appearance, RMB -> Cycle Mode) ---
        Rectangle {
            id: styleSummaryCard
            visible: !root.hideStyleFooter
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 30
            radius: Theme.r(10)
            color: styleSummaryMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.cardBorder
            scale: styleSummaryMouse.pressed ? 0.97 : 1.0

            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

            readonly property var curModeObj: {
                const modes = Theme.availableModes;
                for (let i = 0; i < modes.length; i++) {
                    if (modes[i].id === Theme.shellMode)
                        return modes[i];
                }
                return modes[0];
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: styleSummaryCard.curModeObj ? styleSummaryCard.curModeObj.icon : "󰏘"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.fgSurfaceVariant
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Style: " + (styleSummaryCard.curModeObj ? styleSummaryCard.curModeObj.label : "Island")
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Text {
                    text: "Appearance"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    color: styleSummaryMouse.containsMouse ? Theme.fgSurface : Theme.primary
                }
            }

            MouseArea {
                id: styleSummaryMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        Theme.cycleShellMode();
                    else
                        root.openSettingsRequested("appearance");
                }
            }
        }
    }
}
