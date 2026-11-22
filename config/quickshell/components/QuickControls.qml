import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: false
    signal draggingChanged(bool dragging)

    property real volumeLevel: 0.5
    property bool volumeMuted: false

    property real brightnessLevel: 0.8
    property bool brightnessSupported: false

    onActiveChanged: {
        if (active)
            refreshAll();
    }

    Component.onCompleted: {
        if (active)
            refreshAll();
    }

    function refreshAll(): void {
        if (!volReadProc.running)
            volReadProc.running = true;
        if (!brightReadProc.running)
            brightReadProc.running = true;
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

    // --- System Queries ---
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
        id: toggleCmdProc
        onExited: exitCode => {
            refreshDelayTimer.restart();
        }
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
        spacing: 9

        Text {
            text: "󰒓  QUICK CONTROLS"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Theme.fgSurfaceVariant
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
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => {
                        root.draggingChanged(true);
                        root.applyVolume(mouse.x / width);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.applyVolume(mouse.x / width);
                    }
                    onReleased: root.draggingChanged(false)
                    onCanceled: root.draggingChanged(false)
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

        // --- Brightness Slider ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
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
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.brightnessSupported
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => {
                        root.draggingChanged(true);
                        root.applyBrightness(mouse.x / width);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.applyBrightness(mouse.x / width);
                    }
                    onReleased: root.draggingChanged(false)
                    onCanceled: root.draggingChanged(false)
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
