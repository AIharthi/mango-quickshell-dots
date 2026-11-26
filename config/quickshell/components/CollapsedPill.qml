pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."

Item {
    id: root

    property var player: null
    property string screenName: ""
    property bool active: true
    property bool barMode: false
    property string barUiStyle: ShellState.barUiStyle

    signal expandRequested()
    signal launcherClicked()
    signal settingsClicked()
    signal filesClicked()
    signal notificationsClicked()
    signal timerClicked()

    implicitHeight: ShellState.pillHeight
    implicitWidth: {
        if (root.barUiStyle === "split" || root.barMode)
            return parent ? parent.width : 640;
        return barStyleLoader.implicitWidth > 0 ? barStyleLoader.implicitWidth : 120;
    }

    // --- Shared Live State from MangoState (zero per-monitor processes) ---
    readonly property string currentLayout: MangoState.layoutForScreen(root.screenName)
    readonly property var tagsModel: MangoState.tagsForScreen(root.screenName)
    readonly property int activeTagIndex: MangoState.activeTagForScreen(root.screenName)
    readonly property string activeWindowTitle: MangoState.activeWindowTitle
    readonly property real cpuPercent: SystemTelemetry.cpuPercent
    readonly property real ramPercent: SystemTelemetry.memPercent
    readonly property int volPercent: MangoState.volPercent
    readonly property bool volMuted: MangoState.volMuted
    readonly property string kbLayoutShort: MangoState.kbLayoutShort

    readonly property var visibleTags: {
        const arr = root.tagsModel || [];
        if (root.barMode || root.barUiStyle === "split") {
            const occupiedOrActive = arr.filter(t => t.is_active || t.is_urgent || t.client_count > 0);
            if (root.barUiStyle === "split")
                return occupiedOrActive.length >= 4 ? occupiedOrActive : arr.slice(0, Math.max(4, occupiedOrActive.length));
            return arr;
        }
        const filtered = arr.filter(t => t.is_active || t.is_urgent || t.client_count > 0);
        return filtered.length > 0 ? filtered : arr.slice(0, 4);
    }

    readonly property bool hasMedia: ShellState.pillShowMedia
        && root.player !== null
        && (root.player.isPlaying || (root.player.trackTitle && root.player.trackTitle.length > 0))
    readonly property bool isPlaying: root.player !== null && root.player.isPlaying
    readonly property string artUrl: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
    readonly property string mediaLabel: {
        if (!root.player)
            return "";
        const title = root.player.trackTitle || "";
        const artist = root.player.trackArtist || "";
        if (title.length > 0 && artist.length > 0)
            return title + "  ·  " + artist;
        return title || artist || (root.player.identity || "Playing");
    }

    readonly property bool showVolEffective: DeviceCaps.hasAudio && ShellState.barShowVolume
    readonly property bool hasBatteryChip: DeviceCaps.hasBattery && ShellState.barShowBattery
    property bool activeTrayHasItems: false
    readonly property bool hasTrayChip: ShellState.barShowTray && root.activeTrayHasItems
    readonly property bool hasAnyClassicModule: hasMedia
        || hasBatteryChip
        || ShellState.dnd
        || ShellState.keepAwake
        || ShellState.barShowDate
        || (ShellState.barShowWindow && activeWindowTitle.length > 0)
        || ShellState.barShowWorkspaces
        || ShellState.barShowLayout
        || ShellState.barShowSystem
        || ShellState.barShowNetSpeed
        || (ShellState.barShowVolume && DeviceCaps.hasAudio)
        || (ShellState.barShowKbLayout && kbLayoutShort.length > 0)
        || hasTrayChip
        || ShellState.barShowQuickIcons
        || ShellState.barShowFiles
        || ShellState.fmOpActive
        || ShellState.recordingActive
        || ShellState.timerActive
        || ShellState.stopwatchActive
        || ShellState.gameModeActive
        || (ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable)
        || ShellState.unreadCount > 0
        || barMode

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // ==================== REUSABLE COMPACT SUBCOMPONENTS ====================
    function switchTagRelative(delta: int): void {
        const cur = Math.max(1, Math.min(9, root.activeTagIndex || 1));
        const next = ((cur - 1 + delta + 9) % 9) + 1;
        Quickshell.execDetached(["mmsg", "dispatch", "view," + next + ",0"]);
    }

    component SpacesChipStrip : Item {
        id: scWrap
        property var model: root.visibleTags
        implicitWidth: scStrip.implicitWidth
        implicitHeight: scStrip.implicitHeight

        WheelHandler {
            onWheel: event => root.switchTagRelative(event.angleDelta.y > 0 ? -1 : 1)
        }

        Row {
            id: scStrip
            spacing: 3

            Repeater {
                model: scWrap.model

            delegate: Rectangle {
                id: tgPill
                required property var modelData
                readonly property bool isActive: tgPill.modelData.is_active
                readonly property bool isUrgent: tgPill.modelData.is_urgent
                readonly property bool isOccupied: tgPill.modelData.client_count > 0

                width: tgPill.isActive ? 20 : 18
                height: 18
                radius: Theme.r(7)
                color: {
                    if (tgPill.isUrgent) return Theme.error;
                    if (tgPill.isActive) return Theme.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.11);
                    if (tgMouse.containsMouse) return Theme.controlFillHover;
                    return "transparent";
                }
                border.width: tgPill.isActive ? Theme.activeControlBorderWidth : 0
                border.color: Theme.primary

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: (tgPill.isOccupied && !tgPill.isActive && !tgPill.isUrgent) ? -1 : 0
                    text: tgPill.modelData.index
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: tgPill.isActive ? Font.Bold : Font.Medium
                    color: {
                        if (tgPill.isUrgent) return Theme.fgError;
                        if (tgPill.isActive) return Theme.fgSurface;
                        return tgPill.isOccupied ? Theme.fgSurface : Theme.withAlpha(Theme.fgSurfaceVariant, 0.55);
                    }
                }

                Rectangle {
                    visible: tgPill.isOccupied && !tgPill.isActive && !tgPill.isUrgent
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1.5
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Theme.fgSurfaceVariant
                }

                MouseArea {
                    id: tgMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + tgPill.modelData.index + ",0"])
                }
            }
        }
        }
    }

    component MediaMiniGroup : RowLayout {
        id: mmg
        property int maxTitleWidth: 165
        spacing: 6

        ClippingRectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 20
            implicitHeight: 20
            radius: 10
            color: Theme.primaryContainer
            contentUnderBorder: false
            contentInsideBorder: true

            rotation: 0
            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 12000
                loops: Animation.Infinite
                running: root.active && root.isPlaying && root.visible && mmArtImg.visible && ShellState.pillSpinArt && !Theme.reducedMotion
            }

            Image {
                id: mmArtImg
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize: Qt.size(40, 40)
                visible: root.artUrl.length > 0 && status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: !mmArtImg.visible
                text: "󰎈"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(11)
                color: Theme.fgPrimaryContainer
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: mmg.maxTitleWidth
            text: root.mediaLabel
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            font.weight: Font.Medium
            color: root.isPlaying ? Theme.fgSurface : Theme.fgSurfaceVariant
        }

        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            visible: root.isPlaying && ShellState.pillShowEqualizer && !Theme.reducedMotion

            Repeater {
                model: [
                    { minH: 4, maxH: 13, dur: 420 },
                    { minH: 6, maxH: 15, dur: 310 },
                    { minH: 3, maxH: 11, dur: 480 }
                ]
                delegate: Rectangle {
                    id: eqBarM
                    required property var modelData
                    width: 2.5
                    height: eqBarM.modelData.minH
                    radius: 1.25
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fgSurfaceVariant

                    SequentialAnimation on height {
                        running: root.active && root.isPlaying && root.visible && ShellState.pillShowEqualizer && !Theme.reducedMotion
                        loops: Animation.Infinite
                        NumberAnimation { to: eqBarM.modelData.maxH; duration: eqBarM.modelData.dur; easing.type: Easing.InOutSine }
                        NumberAnimation { to: eqBarM.modelData.minH; duration: eqBarM.modelData.dur; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    component VolumePillButton : Rectangle {
        id: vpBtn
        implicitHeight: 20
        implicitWidth: vpRow.implicitWidth + 10
        radius: Theme.r(7)
        color: vpMouse.containsMouse ? Theme.controlFillHover : "transparent"

        RowLayout {
            id: vpRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: root.volMuted ? "󰝟" : (root.volPercent <= 50 ? "󰖀" : "󰕾")
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(12)
                color: root.volMuted ? Theme.withAlpha(Theme.fgSurfaceVariant, 0.65) : Theme.fgSurfaceVariant
            }

            Text {
                text: root.volMuted ? "Mute" : (root.volPercent + "%")
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(10)
                font.weight: Font.DemiBold
                color: root.volMuted ? Theme.withAlpha(Theme.fgSurfaceVariant, 0.65) : Theme.fgSurfaceVariant
            }
        }

        MouseArea {
            id: vpMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    Qt.callLater(() => MangoState.cycleAudioSink());
                else
                    MangoState.toggleMute();
            }
            onWheel: wheel => MangoState.adjustVolumePct(wheel.angleDelta.y > 0 ? 5 : -5)
        }
    }

    component LiveActivityChips : RowLayout {
        spacing: 5

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.gameModeActive
            implicitHeight: 19
            implicitWidth: gmPillRowC.implicitWidth + 10
            radius: Theme.r(9)
            color: gmPillMouseC.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: gmPillRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰊴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                Text { text: "Game"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            MouseArea { id: gmPillMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleGameMode() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.stopwatchActive
            implicitHeight: 19
            implicitWidth: swPillRowC.implicitWidth + 10
            radius: Theme.r(9)
            color: swPillMouseC.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: swPillRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                Text { text: ShellState.formatTimer(ShellState.stopwatchElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            MouseArea { id: swPillMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.timerClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable
            implicitHeight: 19
            implicitWidth: wPillRowC.implicitWidth + 8
            radius: Theme.r(9)
            color: wPillMouseC.containsMouse ? Theme.controlFillHover : "transparent"

            RowLayout {
                id: wPillRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: ShellState.weatherIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                Text { text: ShellState.weatherTemp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            MouseArea { id: wPillMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.notificationsClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.recordingActive
            implicitHeight: 19
            implicitWidth: recRowC.implicitWidth + 10
            radius: Theme.r(9)
            color: Theme.withAlpha(Theme.error, 0.22)
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.error

            RowLayout {
                id: recRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰑊"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.error }
                Text { text: "REC " + ShellState.formatTimer(ShellState.recordingElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.error }
            }

            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "stop"]) }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.timerActive
            implicitHeight: 19
            implicitWidth: tmRowC.implicitWidth + 8
            radius: Theme.r(9)
            color: tmMouseC.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: tmRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰔛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: 9; font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            MouseArea { id: tmMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.timerClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.unreadCount > 0
            implicitHeight: 19
            implicitWidth: unrRowC.implicitWidth + 8
            radius: Theme.r(9)
            color: unrMouseC.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: unrRowC
                anchors.centerIn: parent
                spacing: 3
                Text { text: "󰂚"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                Text { text: String(ShellState.unreadCount); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgSurface }
            }

            MouseArea { id: unrMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.notificationsClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.fmOpActive
            implicitHeight: 19
            implicitWidth: fmRowC.implicitWidth + 8
            radius: Theme.r(9)
            color: fmOpMouseC.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover
            border.width: Theme.activeControlBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: fmRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                Text { text: Math.round(ShellState.fmOpProgress * 100) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            MouseArea { id: fmOpMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
        }
    }

    // ==================== SINGLE ACTIVE BAR STYLE LOADER ====================
    Loader {
        id: barStyleLoader
        anchors.centerIn: parent
        width: (root.barUiStyle === "split" || root.barMode) ? root.width : implicitWidth
        height: root.height
        active: true
        sourceComponent: root.barUiStyle === "split"
            ? splitBarComp
            : (root.barUiStyle === "classic" ? classicBarComp : appleBarComp)
    }

    // ==================== BAR STYLE 1: APPLE DYNAMIC ISLAND CAPSULE ====================
    Component {
        id: appleBarComp

        RowLayout {
            id: appleRow
            spacing: 8
            clip: true

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                color: apLaunchMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apLaunchMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: apLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
            }

            SpacesChipStrip {
                visible: ShellState.barShowWorkspaces
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: !ShellState.barShowWorkspaces && !root.hasMedia
                implicitHeight: 18
                implicitWidth: Math.max(18, spDotLbl.implicitWidth + 10)
                radius: Theme.r(9)
                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                Text {
                    id: spDotLbl
                    anchors.centerIn: parent
                    text: String(root.activeTagIndex)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowLayout
                implicitHeight: 18; implicitWidth: apLayLbl.implicitWidth + 8; radius: Theme.r(6)
                color: apLayMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { id: apLayLbl; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: apLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: apLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
                spacing: 4
                Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                Text {
                    Layout.maximumWidth: root.barMode ? 220 : 140
                    elide: Text.ElideRight
                    text: root.activeWindowTitle
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Medium; color: Theme.fgSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: ShellState.formatTime(clock.date)
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(12)
                font.weight: Font.Bold
                color: Theme.fgSurface
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowDate
                text: ShellState.formatDate(clock.date)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Medium
                color: Theme.fgSurfaceVariant
            }

            MediaMiniGroup {
                visible: root.hasMedia
                maxTitleWidth: root.barMode ? 200 : 160
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowSystem
                spacing: 6
                Text { text: "󰍛 " + Math.round(root.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
                Text { text: "󰘚 " + Math.round(root.ramPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.ramPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowNetSpeed
                spacing: 5
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
            }

            VolumePillButton {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowVolume && DeviceCaps.hasAudio
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
                implicitHeight: 18; implicitWidth: kbPillRowAp.implicitWidth + 8; radius: Theme.r(6)
                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
                RowLayout {
                    id: kbPillRowAp
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                    Text { text: root.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }
            }

            LiveActivityChips {
                visible: ShellState.gameModeActive || ShellState.stopwatchActive || ShellState.recordingActive
                    || ShellState.timerActive || ShellState.unreadCount > 0 || ShellState.fmOpActive
                    || (ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable)
            }

            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.dnd; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.keepAwake; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                visible: root.hasBatteryChip
                Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: DeviceCaps.batteryLow ? Theme.error : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant) }
                Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant }
            }

            SystemTrayStrip {
                id: trayStripApple
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowTray && trayStripApple.hasItems
                compact: true
                onHasItemsChanged: root.activeTrayHasItems = hasItems
                Component.onCompleted: root.activeTrayHasItems = hasItems
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                color: apFilesMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apFilesMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: apFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                color: apGearMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apGearMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: apGearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsClicked() }
            }
        }
    }

    // ==================== BAR STYLE 2: SPLIT FLOATING ISLANDS (3 GLASS PODS) ====================
    Component {
        id: splitBarComp

        Item {
            id: splitRow
            clip: true

            Rectangle {
                id: splitPodLeft
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: ShellState.pillHeight
                width: Math.min(podLeftRow.implicitWidth + 18, Math.max(220, Math.round(splitRow.width * 0.36)))
                radius: Theme.r(Math.round(ShellState.pillHeight / 2))
                color: Theme.notchBg
                border.width: Theme.islandBorderWidth > 0 ? Theme.islandBorderWidth : (Theme.isSimple ? 0 : 1)
                border.color: Theme.islandBorderWidth > 0 ? Theme.islandBorder : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09))
                clip: true

                RowLayout {
                    id: podLeftRow
                    anchors.centerIn: parent
                    spacing: 7

                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                        color: spLaunchMouse.containsMouse ? Theme.controlFillHover : "transparent"
                        Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spLaunchMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                        MouseArea { id: spLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
                    }

                    SpacesChipStrip { visible: ShellState.barShowWorkspaces }

                    Rectangle {
                        visible: !ShellState.barShowWorkspaces
                        implicitHeight: 18; implicitWidth: spDotLblSplit.implicitWidth + 10; radius: Theme.r(9)
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                        Text {
                            id: spDotLblSplit
                            anchors.centerIn: parent
                            text: "Tag " + root.activeTagIndex
                            font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        visible: ShellState.barShowLayout
                        implicitHeight: 18; implicitWidth: spLayTxt.implicitWidth + 8; radius: Theme.r(6)
                        color: spLayMouse.containsMouse ? Theme.controlFillHover : "transparent"
                        Text { id: spLayTxt; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: spLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                        MouseArea { id: spLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
                    }

                    Text {
                        visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
                        Layout.maximumWidth: 130; elide: Text.ElideRight; text: root.activeWindowTitle
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant
                    }
                }
            }

            Rectangle {
                id: splitPodCenter
                anchors.centerIn: parent
                height: ShellState.pillHeight
                width: Math.max(120, Math.min(Math.max(140, splitRow.width - splitPodLeft.width - splitPodRight.width - 20), podCenterRow.implicitWidth + 24))
                radius: Theme.r(Math.round(ShellState.pillHeight / 2))
                color: podCenterMouse.containsMouse ? Qt.lighter(Theme.notchBg, 1.06) : Theme.notchBg
                border.width: Theme.islandBorderWidth > 0 ? Theme.islandBorderWidth : (Theme.isSimple ? 0 : 1)
                border.color: Theme.islandBorderWidth > 0 ? Theme.islandBorder : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(0, 0, 0, 0.10))
                clip: true

                MouseArea {
                    id: podCenterMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.expandRequested()
                }

                RowLayout {
                    id: podCenterRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text { text: ShellState.formatTime(clock.date); font.family: Theme.monoFont; font.pixelSize: Theme.fs(12); font.weight: Font.Bold; color: Theme.fgSurface }
                    Text { visible: ShellState.barShowDate; text: ShellState.formatDate(clock.date); font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                    MediaMiniGroup { visible: root.hasMedia; maxTitleWidth: 165 }
                }
            }

            Rectangle {
                id: splitPodRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: ShellState.pillHeight
                width: Math.min(podRightRow.implicitWidth + 18, Math.max(200, Math.round(splitRow.width * 0.36)))
                radius: Theme.r(Math.round(ShellState.pillHeight / 2))
                color: Theme.notchBg
                border.width: Theme.islandBorderWidth > 0 ? Theme.islandBorderWidth : (Theme.isSimple ? 0 : 1)
                border.color: Theme.islandBorderWidth > 0 ? Theme.islandBorder : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09))
                clip: true

                RowLayout {
                    id: podRightRow
                    anchors.centerIn: parent
                    spacing: 6

                    RowLayout {
                        visible: ShellState.barShowSystem
                        spacing: 5
                        Text { text: "󰍛 " + Math.round(root.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: root.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
                        Text { text: "󰘚 " + Math.round(root.ramPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: root.ramPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
                    }

                    RowLayout {
                        visible: ShellState.barShowNetSpeed
                        spacing: 4
                        Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
                        Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
                    }

                    LiveActivityChips {}

                    VolumePillButton { visible: root.showVolEffective }

                    Rectangle {
                        visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
                        implicitHeight: 18; implicitWidth: kbPillRowSp.implicitWidth + 8; radius: Theme.r(6)
                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
                        RowLayout {
                            id: kbPillRowSp
                            anchors.centerIn: parent; spacing: 3
                            Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                            Text { text: root.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                        }
                    }

                    Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.dnd; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                    Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.keepAwake; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }

                    RowLayout {
                        visible: root.hasBatteryChip
                        spacing: 3
                        Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: DeviceCaps.batteryLow ? Theme.error : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant) }
                        Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant }
                    }

                    SystemTrayStrip {
                        id: trayStripSplit
                        visible: ShellState.barShowTray && trayStripSplit.hasItems
                        compact: true
                        onHasItemsChanged: root.activeTrayHasItems = hasItems
                        Component.onCompleted: root.activeTrayHasItems = hasItems
                    }

                    Rectangle {
                        visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
                        implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                        color: spFilesMouse.containsMouse ? Theme.controlFillHover : "transparent"
                        Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spFilesMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                        MouseArea { id: spFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
                    }

                    Rectangle {
                        visible: ShellState.barShowQuickIcons
                        implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                        color: spGearMouse.containsMouse ? Theme.controlFillHover : "transparent"
                        Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spGearMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                        MouseArea { id: spGearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsClicked() }
                    }

                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                        color: spNotifMouse.containsMouse ? Theme.controlFillHover : "transparent"
                        Text { anchors.centerIn: parent; text: "󰂚"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spNotifMouse.containsMouse || ShellState.unreadCount > 0 ? Theme.fgSurface : Theme.fgSurfaceVariant }
                        MouseArea { id: spNotifMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.notificationsClicked() }
                    }

                    Rectangle {
                        implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
                        color: spCcMouse.containsMouse ? Theme.controlFillHover : "transparent"
                        Text { anchors.centerIn: parent; text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spCcMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                        MouseArea { id: spCcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.expandRequested() }
                    }
                }
            }
        }
    }

    // ==================== BAR STYLE 3: MODULAR CLASSIC PILL / FULL BAR ====================
    Component {
        id: classicBarComp

        RowLayout {
            id: classicRow
            spacing: root.hasAnyClassicModule ? 8 : 0
            clip: true

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 22; implicitHeight: 22; radius: Theme.r(7)
                color: clLaunchMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: clLaunchMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: clLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
            }

            SpacesChipStrip { visible: ShellState.barShowWorkspaces }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowLayout
                implicitHeight: 18; implicitWidth: clLayLbl.implicitWidth + 8; radius: Theme.r(6)
                color: clLayMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { id: clLayLbl; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: clLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: clLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
                spacing: 4
                Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurfaceVariant }
                Text {
                    Layout.maximumWidth: root.barMode ? 250 : 160
                    elide: Text.ElideRight
                    text: root.activeWindowTitle
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium; color: Theme.fgSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: ShellState.formatTime(clock.date)
                font.family: Theme.monoFont; font.pixelSize: Theme.fs(13); font.weight: Font.Bold; color: Theme.fgSurface
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowDate
                text: ShellState.formatDate(clock.date)
                font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium; color: Theme.fgSurfaceVariant
            }

            MediaMiniGroup {
                visible: root.hasMedia
                maxTitleWidth: root.barMode ? 210 : 175
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowSystem
                spacing: 6
                Text { text: "󰍛 " + Math.round(root.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
                Text { text: "󰘚 " + Math.round(root.ramPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.ramPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowNetSpeed
                spacing: 5
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
            }

            VolumePillButton { visible: ShellState.barShowVolume && DeviceCaps.hasAudio }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
                implicitHeight: 18; implicitWidth: kbPillRowCl.implicitWidth + 8; radius: Theme.r(6)
                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
                RowLayout {
                    id: kbPillRowCl
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                    Text { text: root.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }
            }

            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.dnd; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurfaceVariant }
            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.keepAwake; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurfaceVariant }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                visible: root.hasBatteryChip
                Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: DeviceCaps.batteryLow ? Theme.error : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant) }
                Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(11); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.error : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant) }
            }

            LiveActivityChips {}

            SystemTrayStrip {
                id: trayStripClassic
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowTray && trayStripClassic.hasItems
                compact: true
                onHasItemsChanged: root.activeTrayHasItems = hasItems
                Component.onCompleted: root.activeTrayHasItems = hasItems
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
                implicitWidth: 22; implicitHeight: 22; radius: Theme.r(7)
                color: filesBtnMouseCl.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: filesBtnMouseCl.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: filesBtnMouseCl; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 22; implicitHeight: 22; radius: Theme.r(7)
                color: gearBtnMouseCl.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: gearBtnMouseCl.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: gearBtnMouseCl; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsClicked() }
            }
        }
    }
}
