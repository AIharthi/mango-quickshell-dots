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

    function dbusHasOwnerCmd(serviceName: string): string {
        return "dbus-send --system --dest=org.freedesktop.DBus --type=method_call --print-reply=literal /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:" + serviceName + " 2>/dev/null | grep -q true";
    }

    function runDbusGuardedToggle(serviceName: string, commandStr: string): void {
        if (toggleCmdProc.running)
            return;
        toggleCmdProc.command = ["sh", "-c", dbusHasOwnerCmd(serviceName) + " && " + commandStr];
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

    function applyVolume(ratio: real): void {
        const clamped = Math.max(0.0, Math.min(1.0, ratio));
        root.volumeLevel = clamped;
        root.volumeMuted = clamped <= 0.001;
        const pct = Math.round(clamped * 100);
        Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", pct + "%"]);
    }

    function applyBrightness(ratio: real): void {
        if (!root.brightnessSupported)
            return;
        const clamped = Math.max(0.05, Math.min(1.0, ratio));
        root.brightnessLevel = clamped;
        const pct = Math.round(clamped * 100);
        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
    }

    // --- System Queries (gated on detected hardware) ---
    Process {
        id: volReadProc
        command: ["sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@; pactl get-sink-mute @DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/([0-9]+)%/);
                if (match)
                    root.volumeLevel = Math.max(0.0, Math.min(1.0, parseInt(match[1], 10) / 100.0));
                root.volumeMuted = text.indexOf("Mute: yes") !== -1 || root.volumeLevel <= 0.001;
            }
        }
    }

    Process {
        id: sinkLabelProc
        command: [
            "sh", "-c",
            "python3 -c 'import json,subprocess; d=subprocess.check_output([\"pactl\",\"get-default-sink\"],text=True).strip(); s=json.loads(subprocess.check_output([\"pactl\",\"--format=json\",\"list\",\"sinks\"],text=True)); print(next((x.get(\"description\") or x[\"name\"] for x in s if x[\"name\"]==d), \"Audio Output\"))' 2>/dev/null"
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
            "if ! " + root.dbusHasOwnerCmd("org.freedesktop.NetworkManager") + "; then echo 'disabled|'; exit 0; fi; radio=$(timeout 1 nmcli radio wifi </dev/null 2>/dev/null || echo disabled); ssid=$(timeout 1 nmcli -t -f ACTIVE,SSID dev wifi </dev/null 2>/dev/null | awk -F: '$1==\"yes\"{print $2; exit}'); echo \"$radio|$ssid\""
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
            "if ! " + root.dbusHasOwnerCmd("org.bluez") + "; then echo 'no|'; exit 0; fi; pwr=$(timeout 1 bluetoothctl show </dev/null 2>/dev/null | awk '/Powered:/{print $2; exit}'); dev=$(timeout 1 bluetoothctl devices Connected </dev/null 2>/dev/null | head -n1 | cut -d' ' -f3-); echo \"${pwr:-no}|$dev\""
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
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: Math.round(root.volumeLevel * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                color: Theme.fgSurface
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
                            root.runDbusGuardedToggle("org.freedesktop.NetworkManager", "timeout 2 nmcli radio wifi " + target + " </dev/null");
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
                            root.runDbusGuardedToggle("org.bluez", "timeout 2 bluetoothctl power " + target + " </dev/null");
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettingsRequested("audio")
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
