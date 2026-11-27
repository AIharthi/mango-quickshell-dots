pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../m3"

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

    component SpacesChipStrip : M3WsStrip {
        id: scWrap
        barHeight: Math.max(32, ShellState.pillHeight)
        compact: ShellState.pillHeight < 30
        onSwitchRequested: wid => Quickshell.execDetached(["mmsg", "dispatch", "view," + wid + ",0"])
        onRelativeSwitchRequested: delta => root.switchTagRelative(delta)
    }

    component MediaMiniGroup : RowLayout {
        id: mmg
        property int maxTitleWidth: 165
        spacing: 6

        M3ShapeImage {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(20, ShellState.pillHeight - 10)
            implicitHeight: Math.max(20, ShellState.pillHeight - 10)
            kind: "circle"
            source: root.artUrl
            empty: Theme.m3PrimaryContainer
            fallbackGlyph: "󰎈"
            fallbackColor: Theme.m3OnPrimaryContainer
            spinning: root.active && root.isPlaying && root.visible && ShellState.pillSpinArt
            spinDurationMs: 14000
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
            color: root.isPlaying ? Theme.m3Ink : Theme.m3InkDim
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
                    color: Theme.m3Primary

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
        radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
        color: vpMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"

        RowLayout {
            id: vpRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: root.volMuted ? "󰝟" : (root.volPercent <= 50 ? "󰖀" : "󰕾")
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(12)
                color: root.volMuted ? Theme.m3InkDim : Theme.m3Primary
            }

            Text {
                text: root.volMuted ? "Mute" : (root.volPercent + "%")
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(10)
                font.weight: Font.DemiBold
                color: root.volMuted ? Theme.m3InkDim : Theme.m3Ink
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
            radius: Theme.isSimple ? 0 : 10
            color: gmPillMouseC.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

            RowLayout {
                id: gmPillRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰊴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3OnSecondaryContainer }
                Text { text: "Game"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3OnSecondaryContainer }
            }

            MouseArea { id: gmPillMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleGameMode() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.stopwatchActive
            implicitHeight: 19
            implicitWidth: swPillRowC.implicitWidth + 10
            radius: Theme.isSimple ? 0 : 10
            color: swPillMouseC.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

            RowLayout {
                id: swPillRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3Primary }
                Text { text: ShellState.formatTimer(ShellState.stopwatchElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3OnSecondaryContainer }
            }

            MouseArea { id: swPillMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.timerClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable
            implicitHeight: 19
            implicitWidth: wPillRowC.implicitWidth + 8
            radius: Theme.isSimple ? 0 : 10
            color: wPillMouseC.containsMouse ? Theme.m3SurfaceHigh : "transparent"

            RowLayout {
                id: wPillRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: ShellState.weatherIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                Text { text: ShellState.weatherTemp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3Ink }
            }

            MouseArea { id: wPillMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.notificationsClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.recordingActive
            implicitHeight: 19
            implicitWidth: recRowC.implicitWidth + 10
            radius: Theme.isSimple ? 0 : 10
            color: Theme.m3ErrorContainer

            RowLayout {
                id: recRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰑊"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.m3Error }
                Text { text: "REC " + ShellState.formatTimer(ShellState.recordingElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3OnErrorContainer }
            }

            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "stop"]) }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.timerActive
            implicitHeight: 19
            implicitWidth: tmRowC.implicitWidth + 8
            radius: Theme.isSimple ? 0 : 10
            color: tmMouseC.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

            RowLayout {
                id: tmRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰔛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3Primary }
                Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: 9; font.weight: Font.DemiBold; color: Theme.m3OnSecondaryContainer }
            }

            MouseArea { id: tmMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.timerClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.unreadCount > 0
            implicitHeight: 19
            implicitWidth: unrRowC.implicitWidth + 8
            radius: Theme.isSimple ? 0 : 10
            color: unrMouseC.containsMouse ? Theme.m3SurfaceHighest : Theme.m3PrimaryContainer

            RowLayout {
                id: unrRowC
                anchors.centerIn: parent
                spacing: 3
                Text { text: "󰂚"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3Primary }
                Text { text: String(ShellState.unreadCount); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3OnPrimaryContainer }
            }

            MouseArea { id: unrMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.notificationsClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.fmOpActive
            implicitHeight: 19
            implicitWidth: fmRowC.implicitWidth + 8
            radius: Theme.isSimple ? 0 : 10
            color: fmOpMouseC.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

            RowLayout {
                id: fmRowC
                anchors.centerIn: parent
                spacing: 4
                Text { text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3Primary }
                Text { text: Math.round(ShellState.fmOpProgress * 100) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3Ink }
            }

            MouseArea { id: fmOpMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
        }
    }

    // ==================== SINGLE ACTIVE BAR STYLE LOADER ====================
    Loader {
        id: barStyleLoader
        anchors.centerIn: parent
        width: root.barMode ? root.width : implicitWidth
        height: root.height
        active: true
        sourceComponent: root.barUiStyle === "classic" ? classicBarComp : appleBarComp
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
                implicitWidth: 20; implicitHeight: 20; radius: Theme.isSimple ? 0 : 10
                color: apLaunchMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apLaunchMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: apLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
            }

            SpacesChipStrip {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowWorkspaces
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: !ShellState.barShowWorkspaces && !root.hasMedia
                implicitHeight: 18
                implicitWidth: Math.max(18, spDotLbl.implicitWidth + 10)
                radius: Theme.isSimple ? 0 : 9
                color: Theme.m3SurfaceHigh

                Text {
                    id: spDotLbl
                    anchors.centerIn: parent
                    text: String(root.activeTagIndex)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: Theme.m3InkDim
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowLayout
                implicitHeight: 18; implicitWidth: apLayLbl.implicitWidth + 8; radius: Theme.isSimple ? 0 : 9
                color: apLayMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { id: apLayLbl; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: apLayMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: apLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
                spacing: 4
                Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3InkDim }
                Text {
                    Layout.maximumWidth: root.barMode ? 220 : 140
                    elide: Text.ElideRight
                    text: root.activeWindowTitle
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Medium; color: Theme.m3InkDim
                }
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowDate
                text: ShellState.formatDate(clock.date)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Medium
                color: Theme.m3InkDim
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowDate
                text: "·"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.m3InkDim
            }

            Text {
                id: apClockTxt
                Layout.alignment: Qt.AlignVCenter
                text: ShellState.formatTime(clock.date)
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(12)
                font.weight: Font.Bold
                color: Theme.m3Ink
            }

            MediaMiniGroup {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasMedia
                maxTitleWidth: root.barMode ? 200 : 160
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowSystem
                spacing: 6
                Text { text: "󰍛 " + Math.round(root.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.cpuPercent > 85 ? Theme.m3Error : Theme.m3InkDim }
                Text { text: "󰘚 " + Math.round(root.ramPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.ramPercent > 85 ? Theme.warning : Theme.m3InkDim }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowNetSpeed
                spacing: 5
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3InkDim }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3InkDim }
            }

            VolumePillButton {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowVolume && DeviceCaps.hasAudio
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
                implicitHeight: 18; implicitWidth: kbPillRowAp.implicitWidth + 8; radius: Theme.isSimple ? 0 : 9
                color: Theme.m3SurfaceC
                RowLayout {
                    id: kbPillRowAp
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                    Text { text: root.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3Ink }
                }
            }

            LiveActivityChips {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.gameModeActive || ShellState.stopwatchActive || ShellState.recordingActive
                    || ShellState.timerActive || ShellState.unreadCount > 0 || ShellState.fmOpActive
                    || (ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable)
            }

            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.dnd; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3Primary }
            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.keepAwake; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3Primary }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                visible: root.hasBatteryChip
                Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: DeviceCaps.batteryLow ? Theme.m3Error : (DeviceCaps.batteryCharging ? Theme.m3Primary : Theme.m3InkDim) }
                Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.m3Error : Theme.m3Ink }
            }

            SystemTrayStrip {
                id: trayStripApple
                Layout.alignment: Qt.AlignVCenter
                hiddenPlayerHint: root.hasMedia && root.player ? ((root.player.identity || "") + " " + (root.player.desktopEntry || "")).toLowerCase() : ""
                visible: ShellState.barShowTray && trayStripApple.hasItems
                compact: true
                onHasItemsChanged: root.activeTrayHasItems = hasItems
                Component.onCompleted: root.activeTrayHasItems = hasItems
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
                implicitWidth: 20; implicitHeight: 20; radius: Theme.isSimple ? 0 : 10
                color: apFilesMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apFilesMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: apFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 20; implicitHeight: 20; radius: Theme.isSimple ? 0 : 10
                color: apGearMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apGearMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: apGearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsClicked() }
            }
        }
    }

    // ==================== BAR STYLE 2: MODULAR CLASSIC PILL / FULL BAR ====================
    Component {
        id: classicBarComp

        RowLayout {
            id: classicRow
            spacing: root.hasAnyClassicModule ? 8 : 0
            clip: true

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 22; implicitHeight: 22; radius: Theme.isSimple ? 0 : 11
                color: clLaunchMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: clLaunchMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: clLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
            }

            SpacesChipStrip { Layout.alignment: Qt.AlignVCenter; visible: ShellState.barShowWorkspaces }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowLayout
                implicitHeight: 18; implicitWidth: clLayLbl.implicitWidth + 8; radius: Theme.isSimple ? 0 : 9
                color: clLayMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { id: clLayLbl; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: clLayMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: clLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
                spacing: 4
                Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.m3InkDim }
                Text {
                    Layout.maximumWidth: root.barMode ? 250 : 160
                    elide: Text.ElideRight
                    text: root.activeWindowTitle
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium; color: Theme.m3InkDim
                }
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: ShellState.formatTime(clock.date)
                font.family: Theme.monoFont; font.pixelSize: Theme.fs(13); font.weight: Font.Bold; color: Theme.m3Ink
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowDate
                text: ShellState.formatDate(clock.date)
                font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Medium; color: Theme.m3InkDim
            }

            MediaMiniGroup {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasMedia
                maxTitleWidth: root.barMode ? 210 : 175
            }

            Item { Layout.fillWidth: true; visible: root.barMode }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowSystem
                spacing: 6
                Text { text: "󰍛 " + Math.round(root.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.cpuPercent > 85 ? Theme.m3Error : Theme.m3InkDim }
                Text { text: "󰘚 " + Math.round(root.ramPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.ramPercent > 85 ? Theme.warning : Theme.m3InkDim }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowNetSpeed
                spacing: 5
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3InkDim }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3InkDim }
            }

            VolumePillButton { Layout.alignment: Qt.AlignVCenter; visible: ShellState.barShowVolume && DeviceCaps.hasAudio }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
                implicitHeight: 18; implicitWidth: kbPillRowCl.implicitWidth + 8; radius: Theme.isSimple ? 0 : 9
                color: Theme.m3SurfaceC
                RowLayout {
                    id: kbPillRowCl
                    anchors.centerIn: parent; spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                    Text { text: root.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3Ink }
                }
            }

            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.dnd; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.m3Primary }
            Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.keepAwake; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.m3Primary }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                visible: root.hasBatteryChip
                Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: DeviceCaps.batteryLow ? Theme.m3Error : (DeviceCaps.batteryCharging ? Theme.m3Primary : Theme.m3InkDim) }
                Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(11); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.m3Error : Theme.m3Ink }
            }

            LiveActivityChips { Layout.alignment: Qt.AlignVCenter }

            SystemTrayStrip {
                id: trayStripClassic
                Layout.alignment: Qt.AlignVCenter
                hiddenPlayerHint: root.hasMedia && root.player ? ((root.player.identity || "") + " " + (root.player.desktopEntry || "")).toLowerCase() : ""
                visible: ShellState.barShowTray && trayStripClassic.hasItems
                compact: true
                onHasItemsChanged: root.activeTrayHasItems = hasItems
                Component.onCompleted: root.activeTrayHasItems = hasItems
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
                implicitWidth: 22; implicitHeight: 22; radius: Theme.isSimple ? 0 : 11
                color: filesBtnMouseCl.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: filesBtnMouseCl.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: filesBtnMouseCl; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.barShowQuickIcons
                implicitWidth: 22; implicitHeight: 22; radius: Theme.isSimple ? 0 : 11
                color: gearBtnMouseCl.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: gearBtnMouseCl.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: gearBtnMouseCl; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsClicked() }
            }
        }
    }
}
