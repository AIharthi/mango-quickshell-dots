pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"

ColumnLayout {
    id: root
    spacing: 12

    property int overrideCount: 0
    property string activeCursor: "catppuccin-mocha-dark-cursors"
    property int activeCursorSize: 24

    function loadOverrides(): void {
        if (!localProc.running)
            localProc.running = true;
    }

    function resetOverrides(): void {
        if (!resetProc.running)
            resetProc.running = true;
    }

    Component.onCompleted: loadOverrides()

    Process {
        id: localProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (typeof d.overrideCount === "number")
                        root.overrideCount = d.overrideCount;
                    if (typeof d.cursor_theme === "string")
                        root.activeCursor = d.cursor_theme;
                    if (typeof d.cursor_size === "number")
                        root.activeCursorSize = d.cursor_size;
                } catch (err) {}
            }
        }
    }

    Process {
        id: resetProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "reset"]
        onExited: root.loadOverrides()
    }

    // --- 1. Host & OS Summary ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hostCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: hostCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "DEVICE & OS"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: Theme.r(10)
                    color: Theme.withAlpha(Theme.primary, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: DeviceCaps.deviceType === "laptop" ? "󰌢" : "󰍹"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: (DeviceCaps.hostname || "localhost") + " · " + (DeviceCaps.deviceType === "laptop" ? "Laptop Profile" : "Desktop Profile")
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        text: DeviceCaps.distro + " · Kernel " + DeviceCaps.kernel
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        text: "Mode: " + Theme.shellMode.toUpperCase() + " · Cursor: " + root.activeCursor + " (" + root.activeCursorSize + "px)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.primary
                    }
                }
            }
        }
    }

    // --- 2. Detected Hardware Capabilities ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: capCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: capCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "DETECTED HARDWARE CAPABILITIES"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: redetectLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: redetectMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: redetectLbl
                        anchors.centerIn: parent
                        text: "󰑐 Re-detect"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.primary
                    }

                    MouseArea {
                        id: redetectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DeviceCaps.refresh()
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                rowSpacing: 6
                columnSpacing: 6

                Repeater {
                    model: [
                        { label: "Audio",     ok: DeviceCaps.hasAudio },
                        { label: "Displays",  ok: DeviceCaps.hasWlrRandr },
                        { label: "Wi-Fi",     ok: DeviceCaps.hasWifi },
                        { label: "Bluetooth", ok: DeviceCaps.hasBluetooth },
                        { label: "Battery",   ok: DeviceCaps.hasBattery },
                        { label: "Backlight", ok: DeviceCaps.hasBacklight },
                        { label: "Touchpad",  ok: DeviceCaps.hasTouchpad },
                        { label: "Locker",    ok: DeviceCaps.hasLocker }
                    ]

                    delegate: Rectangle {
                        id: capBadge
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: capBadge.modelData.ok
                            ? Theme.withAlpha(Theme.success, 0.16)
                            : Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: capBadge.modelData.ok ? Theme.withAlpha(Theme.success, 0.45) : Theme.cardBorder

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: capBadge.modelData.ok ? "󰄬" : "·"
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: capBadge.modelData.ok ? Theme.success : Theme.outline
                            }

                            Text {
                                text: capBadge.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: capBadge.modelData.ok ? Font.Bold : Font.Normal
                                color: capBadge.modelData.ok ? Theme.fgSurface : Theme.fgSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 3. Power Actions ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: pwrCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: pwrCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                text: "POWER & SESSION"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            PowerMenu {
                Layout.fillWidth: true
            }
        }
    }

    // --- 4. Per-Device MangoWC Overrides ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 46
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Per-Device Overrides (~/.config/mango/local.conf)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Text {
                    text: root.overrideCount + " active override rule(s) on this device"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: reloadWmLbl.implicitWidth + 16
                radius: Theme.r(8)
                color: reloadWmMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                scale: reloadWmMouse.pressed ? 0.95 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                Text {
                    id: reloadWmLbl
                    anchors.centerIn: parent
                    text: "Reload WM"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.primary
                }

                MouseArea {
                    id: reloadWmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "reload_config"])
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: rstLocalLbl.implicitWidth + 16
                radius: Theme.r(8)
                color: rstLocalMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                scale: rstLocalMouse.pressed ? 0.95 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                Text {
                    id: rstLocalLbl
                    anchors.centerIn: parent
                    text: "Reset local.conf"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: rstLocalMouse.containsMouse ? Theme.error : Theme.fgSurface
                }

                MouseArea {
                    id: rstLocalMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetOverrides()
                }
            }
        }
    }
}
