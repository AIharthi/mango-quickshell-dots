pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../m3"

// Material 3 Expressive Control Center Quick Controls modeled on DarkShadowShell ControlCenter.qml
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

    property real _dragRatio: 0.5
    readonly property real maxVolRatio: ShellState.audioOverAmp ? 1.5 : 1.0
    readonly property real volumeLevel: root._dragging ? root._dragRatio : Math.max(0.0, Math.min(root.maxVolRatio, MangoState.volPercent / 100.0))
    readonly property bool volumeMuted: MangoState.volMuted
    readonly property bool micMuted: MangoState.micMuted
    property real micLevel: 0.85
    property bool _dragging: false

    property real brightnessLevel: 0.8
    property bool brightnessSupported: false

    property bool wifiEnabled: false
    property string wifiSsid: "Offline"

    property bool btEnabled: false
    property string btDevice: "Off"

    readonly property string defaultSinkLabel: MangoState.defaultSinkLabel

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
        MangoState.refreshAudioFallback();
        if (DeviceCaps.hasBacklight && !brightReadProc.running)
            brightReadProc.running = true;
        if (DeviceCaps.hasWifi && !wifiReadProc.running)
            wifiReadProc.running = true;
        if (DeviceCaps.hasBluetooth && !btReadProc.running)
            btReadProc.running = true;
    }

    property int _pendingBrightPct: -1

    function applyVolume(ratio: real): void {
        const clamped = Math.max(0.0, Math.min(root.maxVolRatio, ratio));
        root._dragRatio = clamped;
        MangoState.setVolumeRatio(clamped);
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

    function cycleAudioSink(): void {
        MangoState.cycleAudioSink();
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
                    : (root.wifiEnabled ? "On" : "Off");
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

    radius: root.hideHeader ? 0 : Theme.r(26)
    implicitHeight: qcCol.implicitHeight + (root.hideHeader ? 0 : 20)
    color: root.hideHeader ? "transparent" : Theme.m3SurfaceC
    border.width: root.hideHeader ? 0 : 1
    border.color: Theme.m3Line
    clip: true

    ColumnLayout {
        id: qcCol
        anchors.fill: parent
        anchors.margins: root.hideHeader ? 0 : 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !root.hideHeader

            Text {
                text: "Quick Controls"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.m3InkDim
            }

            Item { Layout.fillWidth: true }

            Text {
                text: DeviceCaps.deviceType === "laptop" ? "󰌢" : "󰍹"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(12)
                color: Theme.m3InkDim
            }
        }

        // --- Brightness Full-Width 46px M3 Capsule Slider ---
        M3CapsuleSlider {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: DeviceCaps.hasBacklight && root.brightnessSupported
            icon: "󰃟"
            label: "Display"
            value: root.brightnessLevel
            activeColor: Theme.m3Primary
            onMoved: v => root.applyBrightness(v)
            onIconClicked: root.openSettingsRequested("displays")
            onDraggingChanged: d => {
                root._dragging = d;
                root.draggingChanged(d);
            }
        }

        // --- Sound (62%) + Mic Toggle/Volume (38%) 46px M3 Capsule Row ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8

            M3CapsuleSlider {
                Layout.fillWidth: true
                Layout.preferredWidth: 62
                icon: root.volumeMuted ? "󰝟" : (root.volumeLevel <= 0.45 ? "󰖀" : "󰕾")
                label: root.volumeMuted ? "Muted" : "Sound"
                value: root.volumeLevel
                maxValue: root.maxVolRatio
                muted: root.volumeMuted
                activeColor: Theme.m3Primary
                onMoved: v => {
                    root._dragging = true;
                    root.applyVolume(v);
                }
                onIconClicked: MangoState.toggleMute()
                onRightClicked: root.cycleAudioSink()
                onDraggingChanged: d => {
                    root._dragging = d;
                    root.draggingChanged(d);
                }
            }

            // Mic 46px capsule toggle
            Rectangle {
                Layout.preferredWidth: 112
                implicitHeight: 46
                radius: Theme.r(micArea.pressed ? 16 : 23)
                color: root.micMuted ? Theme.m3SurfaceHigh : Theme.m3SecondaryContainer
                border.width: 1
                border.color: Theme.m3Line

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160 } }
                Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: root.micMuted ? "󰍭" : "󰍬"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(16)
                        color: root.micMuted ? Theme.m3Error : Theme.m3OnSecondaryContainer
                    }

                    Text {
                        text: root.micMuted ? "Muted" : "Mic On"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Medium
                        color: root.micMuted ? Theme.m3Error : Theme.m3OnSecondaryContainer
                    }
                }

                MouseArea {
                    id: micArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.callLater(() => root.openSettingsRequested("audio"));
                        else
                            MangoState.toggleMicMute();
                    }
                }
            }
        }

        // --- 2 Wide 62px M3 Connectivity / Audio Cards with Chevron ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8
            visible: DeviceCaps.hasWifi || DeviceCaps.hasBluetooth || !root.hideDuplicateToggles

            // Left Wide Card: Wi-Fi (or Output Sink on Desktop without Wi-Fi)
            Rectangle {
                id: wideLeft
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 62
                radius: Theme.r(wlMouse.pressed ? 16 : 24)
                readonly property bool isOn: DeviceCaps.hasWifi ? root.wifiEnabled : !root.volumeMuted
                color: isOn ? Theme.m3Primary : (wlMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)
                border.width: 1
                border.color: isOn ? Theme.m3Primary : Theme.m3Line

                Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }
                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                readonly property color inkCol: isOn ? Theme.m3OnPrimary : Theme.m3Ink
                readonly property color subCol: isOn ? Theme.withAlpha(Theme.m3OnPrimary, 0.78) : Theme.m3InkDim

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 10

                    Text {
                        text: DeviceCaps.hasWifi ? (root.wifiEnabled ? "󰤨" : "󰤭") : "󰋋"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(19)
                        color: wideLeft.inkCol
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: DeviceCaps.hasWifi ? (root.wifiEnabled && root.wifiSsid !== "On" ? root.wifiSsid : "Wi-Fi") : "Output"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.DemiBold
                            color: wideLeft.inkCol
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: DeviceCaps.hasWifi
                                ? (root.wifiEnabled ? (root.wifiSsid !== "On" && root.wifiSsid !== "Off" ? "Connected" : "On") : "Off")
                                : root.defaultSinkLabel
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: wideLeft.subCol
                        }
                    }

                    Item {
                        implicitWidth: 34
                        implicitHeight: 54
                        Text { anchors.centerIn: parent; text: "󰅂"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: wideLeft.subCol }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSettingsRequested(DeviceCaps.hasWifi ? "network" : "audio")
                        }
                    }
                }

                MouseArea {
                    id: wlMouse
                    anchors.fill: parent
                    anchors.rightMargin: 36
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (DeviceCaps.hasWifi) {
                            const target = root.wifiEnabled ? "off" : "on";
                            root.runDbusGuardedToggle("org.freedesktop.NetworkManager", ["timeout", "2", "nmcli", "radio", "wifi", target]);
                        } else {
                            root.cycleAudioSink();
                        }
                    }
                }
            }

            // Right Wide Card: Bluetooth (or Night Light on Desktop without BT)
            Rectangle {
                id: wideRight
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 62
                radius: Theme.r(wrMouse.pressed ? 16 : 24)
                readonly property bool isOn: DeviceCaps.hasBluetooth ? root.btEnabled : ShellState.nightLightEnabled
                color: isOn ? Theme.m3Primary : (wrMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)
                border.width: 1
                border.color: isOn ? Theme.m3Primary : Theme.m3Line

                Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }
                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                readonly property color inkCol: isOn ? Theme.m3OnPrimary : Theme.m3Ink
                readonly property color subCol: isOn ? Theme.withAlpha(Theme.m3OnPrimary, 0.78) : Theme.m3InkDim

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 6
                    spacing: 10

                    Text {
                        text: DeviceCaps.hasBluetooth ? (root.btEnabled ? "󰂯" : "󰂲") : "󰖔"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(19)
                        color: wideRight.inkCol
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: DeviceCaps.hasBluetooth ? (root.btEnabled && root.btDevice !== "On" && root.btDevice !== "Off" ? root.btDevice : "Bluetooth") : "Night Light"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(12)
                            font.weight: Font.DemiBold
                            color: wideRight.inkCol
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: DeviceCaps.hasBluetooth
                                ? (root.btEnabled ? (root.btDevice !== "On" && root.btDevice !== "Off" ? "Connected" : "On") : "Off")
                                : (ShellState.nightLightEnabled ? (ShellState.nightLightTemp + "K") : "Off")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: wideRight.subCol
                        }
                    }

                    Item {
                        implicitWidth: 34
                        implicitHeight: 54
                        Text { anchors.centerIn: parent; text: "󰅂"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: wideRight.subCol }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSettingsRequested(DeviceCaps.hasBluetooth ? "bluetooth" : "displays")
                        }
                    }
                }

                MouseArea {
                    id: wrMouse
                    anchors.fill: parent
                    anchors.rightMargin: 36
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (DeviceCaps.hasBluetooth) {
                            const target = root.btEnabled ? "off" : "on";
                            root.runDbusGuardedToggle("org.bluez", ["timeout", "2", "bluetoothctl", "power", target]);
                        } else {
                            ShellState.setNightLight(!ShellState.nightLightEnabled, ShellState.nightLightTemp);
                        }
                    }
                }
            }
        }

        // --- 4-Column Morphing M3 Tiles (radius 34 -> 22 -> 14) ---
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 4
            rowSpacing: 8
            columnSpacing: 8

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: ShellState.dnd ? "󰂛" : "󰂚"
                label: "DND"
                active: ShellState.dnd
                onClicked: ShellState.toggleDnd()
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: "󰖔"
                label: "Night Light"
                active: ShellState.nightLightEnabled
                onClicked: ShellState.setNightLight(!ShellState.nightLightEnabled, ShellState.nightLightTemp)
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: "󰅶"
                label: "Keep Awake"
                active: ShellState.keepAwake
                onClicked: ShellState.toggleKeepAwake()
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: "󰊴"
                label: "Game"
                active: ShellState.gameModeActive
                onClicked: ShellState.toggleGameMode()
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: "󰹑"
                label: "Capture"
                active: false
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--area"])
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: ShellState.recordingActive ? "󰓛" : "󰑊"
                label: ShellState.recordingActive ? ShellState.formatTimer(ShellState.recordingElapsedSec) : "Record"
                active: ShellState.recordingActive
                accentColor: Theme.m3Error
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"])
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: Theme.colorScheme === "dark" ? "󰖙" : "󰖔"
                label: Theme.colorScheme === "dark" ? "Dark" : "Light"
                active: Theme.colorScheme === "light"
                onClicked: Theme.toggleScheme()
            }

            M3Tile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                icon: root.hideDuplicateToggles ? "󰌌" : "󰖯"
                label: root.hideDuplicateToggles ? "Shortcuts" : "Windows"
                active: false
                onClicked: Quickshell.execDetached([
                    "qs", "ipc", "call", "island",
                    root.hideDuplicateToggles ? "toggleKeybindSheet" : "toggleWindowSwitcher"
                ])
            }
        }

        // --- Clean M3 Visual Style Pill Footer ---
        Rectangle {
            id: styleSummaryCard
            visible: !root.hideStyleFooter
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 36
            radius: Theme.r(18)
            color: styleSummaryMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
            border.width: 1
            border.color: Theme.m3Line

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
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Text {
                    text: styleSummaryCard.curModeObj ? styleSummaryCard.curModeObj.icon : "󰏘"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(14)
                    color: Theme.m3Primary
                }

                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: "Style: " + (styleSummaryCard.curModeObj ? styleSummaryCard.curModeObj.label : "Island")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Medium
                    color: Theme.m3Ink
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: appPillTxt.implicitWidth + 14
                    radius: Theme.r(11)
                    color: Theme.m3SecondaryContainer

                    Text {
                        id: appPillTxt
                        anchors.centerIn: parent
                        text: "Appearance"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Medium
                        color: Theme.m3OnSecondaryContainer
                    }
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
                        Qt.callLater(() => Theme.cycleShellMode());
                    else
                        root.openSettingsRequested("appearance");
                }
            }
        }
    }
}
