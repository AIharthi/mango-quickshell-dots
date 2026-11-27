pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import ".."

Rectangle {
    id: root

    property bool active: true
    property string screenName: ""
    readonly property string currentLayout: MangoState.layoutForScreen(root.screenName)
    readonly property string activeWindowTitle: MangoState.activeWindowTitle
    readonly property real cpuPercent: SystemTelemetry.cpuPercent
    readonly property real ramPercent: SystemTelemetry.memPercent
    readonly property int volPercent: MangoState.volPercent
    readonly property bool volMuted: MangoState.volMuted
    readonly property string kbLayoutShort: MangoState.kbLayoutShort
    readonly property var tagsModel: MangoState.tagsForScreen(root.screenName)

    signal toggleDashboardRequested()
    signal toggleLauncherRequested()
    signal toggleSettingsRequested()
    signal toggleFilesRequested()
    signal toggleNotificationsRequested()

    color: Theme.m3Surface
    radius: 0

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.m3Line
        z: 5
    }

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Left: Flat Square MangoWC Tags + Layout Indicator + Active Window Title
    Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Repeater {
            model: root.tagsModel

            delegate: Rectangle {
                id: tagCell
                required property var modelData
                readonly property bool isActive: tagCell.modelData.is_active
                readonly property bool isUrgent: tagCell.modelData.is_urgent
                readonly property bool isOccupied: tagCell.modelData.client_count > 0

                width: 26
                height: parent.height
                radius: 0
                color: {
                    if (tagCell.isUrgent)
                        return Theme.error;
                    if (tagCell.isActive)
                        return Theme.primary;
                    if (tagMouse.containsMouse)
                        return Theme.hoverBg;
                    return "transparent";
                }

                Text {
                    anchors.centerIn: parent
                    text: tagCell.modelData.index
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: tagCell.isActive ? Font.Bold : Font.Medium
                    color: {
                        if (tagCell.isUrgent)
                            return Theme.fgError;
                        if (tagCell.isActive)
                            return Theme.fgPrimary;
                        if (tagCell.isOccupied)
                            return Theme.fgSurface;
                        return Theme.withAlpha(Theme.fgSurfaceVariant, 0.5);
                    }
                }

                // Minimal 2px bottom square indicator for occupied inactive tags
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 0
                    visible: tagCell.isOccupied && !tagCell.isActive && !tagCell.isUrgent
                    color: Theme.secondary
                }

                MouseArea {
                    id: tagMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + tagCell.modelData.index + ",0"])
                }
            }
        }

        // Crisp 1px separator
        Rectangle {
            visible: ShellState.simpleBarShowLayout
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Flat Layout Switcher
        Rectangle {
            visible: ShellState.simpleBarShowLayout
            width: layoutTxt.implicitWidth + 14
            height: parent.height
            radius: 0
            color: layoutMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                id: layoutTxt
                anchors.centerIn: parent
                text: "[" + root.currentLayout + "]"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: layoutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
            }
        }

        Rectangle {
            visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        Text {
            visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 10
            rightPadding: 8
            width: Math.min(260, implicitWidth)
            elide: Text.ElideRight
            maximumLineCount: 1
            text: root.activeWindowTitle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(10)
            font.weight: Font.Medium
            color: Theme.fgSurfaceVariant
        }
    }

    // Center: Plain Square Monospace Clock
    Row {
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: ShellState.formatTime(clock.date)
            font.family: Theme.monoFont
            font.pixelSize: Theme.fs(12)
            font.weight: Font.Bold
            color: Theme.fgSurface
        }

        Text {
            visible: ShellState.simpleBarShowDate || ShellState.barShowDate
            text: ShellState.formatDate(clock.date)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            color: Theme.fgSurfaceVariant
        }
    }

    // Right: CPU/RAM + Volume + KB Layout + Tray + Battery + Settings + Mode Switches + Hub Toggle
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        // Optional CPU & RAM monitor
        Rectangle {
            visible: ShellState.barShowSystem
            width: sysBarRow.implicitWidth + 14
            height: parent.height
            radius: 0
            color: "transparent"

            Row {
                id: sysBarRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "CPU " + Math.round(root.cpuPercent) + "%"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: root.cpuPercent > 85 ? Theme.error : Theme.fgSurface
                }

                Text {
                    text: "RAM " + Math.round(root.ramPercent) + "%"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: root.ramPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant
                }
            }
        }

        Rectangle {
            visible: ShellState.barShowSystem
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Optional Live Network Throughput
        Rectangle {
            visible: ShellState.barShowNetSpeed
            width: netBarRow.implicitWidth + 14
            height: parent.height
            radius: 0
            color: "transparent"

            Row {
                id: netBarRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "↓" + SystemTelemetry.netDown
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Text {
                    text: "↑" + SystemTelemetry.netUp
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }
            }
        }

        Rectangle {
            visible: ShellState.barShowNetSpeed
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Optional Interactive Volume Indicator
        Rectangle {
            visible: ShellState.barShowVolume && DeviceCaps.hasAudio
            width: volBarTxt.implicitWidth + 14
            height: parent.height
            radius: 0
            color: volBarMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                id: volBarTxt
                anchors.centerIn: parent
                text: root.volMuted ? "VOL MUTE" : ("VOL " + root.volPercent + "%")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: root.volMuted ? Theme.error : Theme.fgSurfaceVariant
            }

            MouseArea {
                id: volBarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: MangoState.toggleMute()
                onWheel: wheel => MangoState.adjustVolumePct(wheel.angleDelta.y > 0 ? 5 : -5)
            }
        }

        Rectangle {
            visible: ShellState.barShowVolume && DeviceCaps.hasAudio
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Optional Keyboard Layout Badge
        Rectangle {
            visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
            width: kbBarTxt.implicitWidth + 14
            height: parent.height
            radius: 0
            color: "transparent"

            Text {
                id: kbBarTxt
                anchors.centerIn: parent
                text: root.kbLayoutShort
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurface
            }
        }

        Rectangle {
            visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // System Tray (shown only when tray module enabled and tray apps exist)
        Item {
            width: trayStrip.implicitWidth + 10
            height: parent.height
            visible: ShellState.barShowTray && trayStrip.hasItems

            SystemTrayStrip {
                id: trayStrip
                anchors.centerIn: parent
                compact: true
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.barShowTray && trayStrip.hasItems
            color: Theme.outlineVariant
        }

        // Live Game Mode Chip (Simple Mode)
        Rectangle {
            width: sbGmRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: ShellState.gameModeActive
            color: sbGmMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Row {
                id: sbGmRow
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰊴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                Text {
                    text: "Game"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: sbGmMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShellState.toggleGameMode()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.gameModeActive
            color: Theme.outlineVariant
        }

        // Live Stopwatch Chip (Simple Mode)
        Rectangle {
            width: sbSwRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: ShellState.stopwatchActive
            color: sbSwMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Row {
                id: sbSwRow
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                Text {
                    text: ShellState.formatTimer(ShellState.stopwatchElapsedSec)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: sbSwMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNotificationsRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.stopwatchActive
            color: Theme.outlineVariant
        }

        // Opt-In Weather Chip (Simple Mode)
        Rectangle {
            width: sbWRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable
            color: sbWMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Row {
                id: sbWRow
                anchors.centerIn: parent
                spacing: 4
                Text { text: ShellState.weatherIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                Text {
                    text: ShellState.weatherTemp
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: sbWMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNotificationsRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable
            color: Theme.outlineVariant
        }

        // Live Recording Chip (Simple Mode)
        Rectangle {
            width: sbRecRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: ShellState.recordingActive
            color: sbRecMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.30) : Theme.withAlpha(Theme.error, 0.18)

            Row {
                id: sbRecRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: "󰑊"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(11)
                    color: Theme.error
                }
                Text {
                    text: "REC " + ShellState.formatTimer(ShellState.recordingElapsedSec)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.error
                }
            }

            MouseArea {
                id: sbRecMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "stop"])
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.recordingActive
            color: Theme.outlineVariant
        }

        // Live Focus Timer Chip (Simple Mode)
        Rectangle {
            width: sbTimerRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: ShellState.timerActive
            color: sbTimerMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Row {
                id: sbTimerRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: "󰔛"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurfaceVariant
                }
                Text {
                    text: ShellState.formatTimer(ShellState.timerRemainingSec)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: sbTimerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNotificationsRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.timerActive
            color: Theme.outlineVariant
        }

        // Unread Notifications Chip (Simple Mode)
        Rectangle {
            width: sbUnreadRow.implicitWidth + 12
            height: parent.height
            radius: 0
            visible: ShellState.unreadCount > 0
            color: sbUnreadMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Row {
                id: sbUnreadRow
                anchors.centerIn: parent
                spacing: 3

                Text {
                    text: "󰂚"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }
                Text {
                    text: String(ShellState.unreadCount)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: sbUnreadMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNotificationsRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.unreadCount > 0
            color: Theme.outlineVariant
        }

        // Active-Only Status Indicators (DND / Keep Awake)
        Rectangle {
            width: 28
            height: parent.height
            radius: 0
            visible: ShellState.dnd
            color: dndBarMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰂛"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(12)
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: dndBarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShellState.toggleDnd()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.dnd
            color: Theme.outlineVariant
        }

        Rectangle {
            width: 28
            height: parent.height
            radius: 0
            visible: ShellState.keepAwake
            color: awakeBarMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰅶"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(12)
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: awakeBarMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ShellState.toggleKeepAwake()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.keepAwake
            color: Theme.outlineVariant
        }

        // Hardware-Aware Battery Indicator (Laptops only)
        Rectangle {
            width: batRow.implicitWidth + 14
            height: parent.height
            radius: 0
            visible: DeviceCaps.hasBattery && ShellState.barShowBattery
            color: "transparent"

            Row {
                id: batRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                    text: DeviceCaps.batteryIcon
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: DeviceCaps.batteryLow
                        ? Theme.error
                        : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant)
                }

                Text {
                    text: DeviceCaps.batteryPercent + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: DeviceCaps.batteryLow
                        ? Theme.error
                        : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurface)
                }
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: DeviceCaps.hasBattery && ShellState.barShowBattery
            color: Theme.outlineVariant
        }

        // File Manager Toggle
        Rectangle {
            width: 30
            height: parent.height
            radius: 0
            visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
            color: filesSbMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰉋"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: filesSbMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
            }

            MouseArea {
                id: filesSbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleFilesRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
            color: Theme.outlineVariant
        }

        // Settings Window Toggle
        Rectangle {
            width: 30
            height: parent.height
            radius: 0
            color: settingsBtnMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰒓"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: settingsBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleSettingsRequested()
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Simple Mode Toggle (click to return to Default mode)
        Rectangle {
            width: simpleLbl.implicitWidth + 16
            height: parent.height
            radius: 0
            color: simpleBtnMouse.containsMouse
                ? Qt.lighter(Theme.primary, 1.08)
                : Theme.primary

            Text {
                id: simpleLbl
                anchors.centerIn: parent
                text: "Simple"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgPrimary
            }

            MouseArea {
                id: simpleBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.toggleShellMode("simple")
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Blur Mode Switch
        Rectangle {
            width: blurLbl.implicitWidth + 16
            height: parent.height
            radius: 0
            color: blurBtnMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                id: blurLbl
                anchors.centerIn: parent
                text: "Blur"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: blurBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.setShellMode("blur")
            }
        }

        Rectangle {
            width: 1
            height: parent.height
            color: Theme.outlineVariant
        }

        // Quick Hub / Controls Toggle
        Rectangle {
            width: 34
            height: parent.height
            radius: 0
            color: hubBtnMouse.containsMouse ? Theme.hoverBg : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰍜"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(13)
                color: Theme.fgSurface
            }

            MouseArea {
                id: hubBtnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleDashboardRequested()
            }
        }
    }

    // Crisp 1px bottom hairline border
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.outlineVariant
    }
}
