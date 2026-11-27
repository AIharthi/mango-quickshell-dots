pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../m3"

Item {
    id: root

    property string screenName: ""
    property var player: null
    property string openPanelMode: ""

    readonly property alias leftMask: leftPod
    readonly property alias centerMask: centerPod
    readonly property alias rightMask: rightPod

    signal toggleLeftRequested()
    signal toggleCenterRequested()
    signal toggleControlCenterRequested()
    signal toggleNotificationsRequested()
    signal toggleSpotlightRequested()
    signal openSettingsRequested(string page)
    signal openFilesRequested(string path)
    signal openStoreRequested()

    readonly property var allTags: MangoState.tagsForScreen(root.screenName)
    readonly property string currentLayout: MangoState.layoutForScreen(root.screenName)
    readonly property int activeTagIndex: MangoState.activeTagForScreen(root.screenName)

    readonly property var visibleTags: {
        const arr = root.allTags || [];
        const occupiedOrActive = arr.filter(t => t.is_active || t.is_urgent || t.client_count > 0);
        return occupiedOrActive.length >= 4 ? occupiedOrActive : arr.slice(0, Math.max(4, occupiedOrActive.length));
    }

    readonly property bool hasMedia: ShellState.splitShowMedia
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

    readonly property int podHeight: Math.max(32, ShellState.splitBarHeight)
    readonly property int podRadius: {
        if (Theme.isSimple)
            return 0;
        if (ShellState.splitPodStyle === "compact")
            return Theme.r(10);
        if (ShellState.splitPodStyle === "rounded")
            return Theme.r(14);
        return Theme.r(Math.round(root.podHeight / 2));
    }
    readonly property color glassFill: ShellState.splitBarTranslucent
        ? Theme.m3BarBg
        : Theme.m3Surface
    readonly property color activeGlassFill: Theme.m3PanelBg

    function switchTagRelative(delta: int): void {
        const cur = Math.max(1, Math.min(9, root.activeTagIndex || 1));
        const next = ((cur - 1 + delta + 9) % 9) + 1;
        Quickshell.execDetached(["mmsg", "dispatch", "view," + next + ",0"]);
    }

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // ==================== 1. LEFT POD: PRIMARY LAUNCHER, STRETCHING WORKSPACES & APP ====================
    Rectangle {
        id: leftPod
        anchors.left: parent.left
        anchors.leftMargin: ShellState.splitSideMargin
        anchors.top: parent.top
        anchors.topMargin: ShellState.splitTopMargin
        height: root.podHeight
        width: Math.min(leftRow.implicitWidth + 18, Math.max(180, Math.round(root.width * 0.36)))
        radius: root.podRadius
        color: root.openPanelMode === "left" ? root.activeGlassFill : root.glassFill
        border.width: 1
        border.color: root.openPanelMode === "left" ? Theme.m3Primary : Theme.m3Line
        clip: true

        Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }
        Behavior on border.color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    Qt.callLater(() => root.openSettingsRequested("split"));
                else
                    root.toggleLeftRequested();
            }
        }

        RowLayout {
            id: leftRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 14)
            spacing: 8

            // DarkShadowShell style primary circular launcher / pod menu button
            Rectangle {
                visible: ShellState.splitShowLauncherIcon
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(22, root.podHeight - 8)
                implicitHeight: Math.max(22, root.podHeight - 8)
                radius: Theme.isSimple ? 0 : (spMenuMouse.pressed ? Theme.r(7) : Math.round(implicitHeight / 2))
                color: spMenuMouse.containsMouse ? Qt.lighter(Theme.m3Primary, 1.08) : Theme.m3Primary
                scale: spMenuMouse.pressed ? 0.92 : 1.0

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160; easing.type: Theme.m3Springy } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: ShellState.menuGlyphFor(ShellState.splitMenuIcon)
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: Theme.m3OnPrimary
                }

                MouseArea {
                    id: spMenuMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.callLater(() => root.openSettingsRequested("split"));
                        else
                            root.toggleLeftRequested();
                    }
                }
            }

            // Stretching Active Pill Workspaces Strip (WsStrip style)
            M3WsStrip {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowWorkspaces
                model: root.visibleTags
                barHeight: root.podHeight
                compact: root.podHeight <= 32
                onSwitchRequested: wid => Quickshell.execDetached(["mmsg", "dispatch", "view," + wid + ",0"])
                onRelativeSwitchRequested: delta => root.switchTagRelative(delta)
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: !ShellState.splitShowWorkspaces
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spTagOnly.implicitWidth + 14
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3Primary

                Text {
                    id: spTagOnly
                    anchors.centerIn: parent
                    text: "Space " + root.activeTagIndex
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.m3OnPrimary
                }
            }

            // Tonal Tiling Layout Pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowLayout
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spLayTxt.implicitWidth + 14
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: spLayMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                Text {
                    id: spLayTxt
                    anchors.centerIn: parent
                    text: root.currentLayout
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: spLayMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim
                }

                MouseArea {
                    id: spLayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                }
            }

            // Active App & Window Title
            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 165
                visible: ShellState.splitShowAppTitle && MangoState.activeAppName.length > 0
                elide: Text.ElideRight
                text: {
                    const app = MangoState.activeAppName;
                    const win = MangoState.activeWindowTitle;
                    if (win && win.length > 0 && win.toLowerCase() !== app.toLowerCase())
                        return app + " · " + win;
                    return app;
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Medium
                color: Theme.m3Ink
            }
        }
    }

    // ==================== 2. CENTER POD: DARKSHADOWSHELL DYNISLAND CAPSULE ====================
    Rectangle {
        id: centerPod
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: ShellState.splitTopMargin
        height: root.podHeight
        readonly property int maxCenterWidth: Math.max(150, root.width - leftPod.width - rightPod.width - ShellState.splitSideMargin * 2 - 24)
        width: Math.max(118, Math.min(maxCenterWidth, centerRow.implicitWidth + 18))
        radius: root.podRadius
        color: root.openPanelMode === "center"
            ? root.activeGlassFill
            : (centerMouse.containsMouse ? Theme.m3SurfaceHigh : root.glassFill)
        border.width: 1
        border.color: root.openPanelMode === "center" ? Theme.m3Primary : Theme.m3Line
        clip: true

        Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }
        Behavior on border.color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

        MouseArea {
            id: centerMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    if (root.player && typeof root.player.togglePlaying === "function")
                        root.player.togglePlaying();
                } else if (mouse.button === Qt.RightButton) {
                    Qt.callLater(() => root.openSettingsRequested("split"));
                } else {
                    root.toggleCenterRequested();
                }
            }
        }

        RowLayout {
            id: centerRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, centerPod.width - 12)
            spacing: 7

            // Date label before clock pill (DynIsland "Day, DD/MM" layout)
            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowDate
                text: ShellState.formatDate(clock.date)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Medium
                color: Theme.m3InkDim
            }

            // Signature DarkShadowShell primary Time Pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Math.max(20, root.podHeight - 8)
                implicitWidth: spTimeTxt.implicitWidth + 16
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3Primary

                Text {
                    id: spTimeTxt
                    anchors.centerIn: parent
                    text: ShellState.formatTime(clock.date)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.m3OnPrimary
                }
            }

            // Optional Weather Pill
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.weatherEnabled && ShellState.splitShowWeather && ShellState.weatherAvailable
                spacing: 3
                Text { text: ShellState.weatherIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3InkDim }
                Text { text: ShellState.weatherTemp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: Theme.m3Ink }
            }

            // Circular Spinning Cover Art (M3ShapeImage) + Track + Equalizer
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasMedia
                spacing: 6

                M3ShapeImage {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.max(20, root.podHeight - 8)
                    implicitHeight: Math.max(20, root.podHeight - 8)
                    kind: "circle"
                    source: root.artUrl
                    empty: Theme.m3PrimaryContainer
                    fallbackGlyph: "󰎈"
                    fallbackColor: Theme.m3OnPrimaryContainer
                    spinning: root.visible && root.isPlaying && ShellState.pillSpinArt
                    spinDurationMs: 14000
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 165
                    elide: Text.ElideRight
                    text: root.mediaLabel
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Medium
                    color: root.isPlaying ? Theme.m3Ink : Theme.m3InkDim
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    visible: root.isPlaying && ShellState.pillShowEqualizer && !Theme.reducedMotion

                    Repeater {
                        model: [
                            { minH: 4, maxH: 12, dur: 420 },
                            { minH: 6, maxH: 15, dur: 310 },
                            { minH: 3, maxH: 10, dur: 480 }
                        ]
                        delegate: Rectangle {
                            id: spEqBar
                            required property var modelData
                            width: 2.5
                            height: spEqBar.modelData.minH
                            radius: 1.25
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.m3Primary

                            SequentialAnimation on height {
                                running: root.visible && root.isPlaying && ShellState.pillShowEqualizer && !Theme.reducedMotion
                                loops: Animation.Infinite
                                NumberAnimation { to: spEqBar.modelData.maxH; duration: spEqBar.modelData.dur; easing.type: Easing.InOutSine }
                                NumberAnimation { to: spEqBar.modelData.minH; duration: spEqBar.modelData.dur; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
            }

            // Live Activity Pills (REC, Game, Timer, Stopwatch, FM)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.recordingActive
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spRecRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3ErrorContainer
                RowLayout {
                    id: spRecRow
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
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spTmRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3SecondaryContainer
                RowLayout {
                    id: spTmRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󰔛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3Primary }
                    Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3OnSecondaryContainer }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.stopwatchActive
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spSwRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3SecondaryContainer
                RowLayout {
                    id: spSwRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3Primary }
                    Text { text: ShellState.formatTimer(ShellState.stopwatchElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.m3OnSecondaryContainer }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.gameModeActive
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: Math.max(22, root.podHeight - 10)
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3PrimaryContainer
                Text { anchors.centerIn: parent; text: "󰊴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3OnPrimaryContainer }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.fmOpActive
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spFmRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3SurfaceHigh
                RowLayout {
                    id: spFmRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.m3Primary }
                    Text { text: Math.round(ShellState.fmOpProgress * 100) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.m3Ink }
                }
            }
        }
    }

    // ==================== 3. RIGHT POD: TELEMETRY, TRAY, VOLUME & CONTROL CENTER ====================
    Rectangle {
        id: rightPod
        anchors.right: parent.right
        anchors.rightMargin: ShellState.splitSideMargin
        anchors.top: parent.top
        anchors.topMargin: ShellState.splitTopMargin
        height: root.podHeight
        width: Math.min(rightRow.implicitWidth + 18, Math.max(180, Math.round(root.width * 0.36)))
        radius: root.podRadius
        color: (root.openPanelMode === "controls" || root.openPanelMode === "notifications")
            ? root.activeGlassFill
            : root.glassFill
        border.width: 1
        border.color: (root.openPanelMode === "controls" || root.openPanelMode === "notifications")
            ? Theme.m3Primary
            : Theme.m3Line
        clip: true

        Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }
        Behavior on border.color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton)
                    Qt.callLater(() => root.openSettingsRequested("split"));
                else
                    root.toggleControlCenterRequested();
            }
        }

        RowLayout {
            id: rightRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 14)
            spacing: 5

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowSystem
                spacing: 5
                Text { text: "󰍛 " + Math.round(SystemTelemetry.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: SystemTelemetry.cpuPercent > 85 ? Theme.m3Error : Theme.m3InkDim }
                Text { text: "󰘚 " + Math.round(SystemTelemetry.memPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: SystemTelemetry.memPercent > 85 ? Theme.warning : Theme.m3InkDim }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowNetSpeed
                spacing: 4
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3InkDim }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3InkDim }
            }

            SystemTrayStrip {
                id: trayStripSplit
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowTray && trayStripSplit.hasItems
                compact: true
            }

            // Tonal Volume Pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowVolume && DeviceCaps.hasAudio
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spVolRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: spVolMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC

                RowLayout {
                    id: spVolRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: MangoState.volMuted ? "󰝟" : (MangoState.volPercent <= 50 ? "󰖀" : "󰕾")
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(11)
                        color: MangoState.volMuted ? Theme.m3InkDim : Theme.m3Primary
                    }
                    Text {
                        text: MangoState.volMuted ? "Mute" : (MangoState.volPercent + "%")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: MangoState.volMuted ? Theme.m3InkDim : Theme.m3Ink
                    }
                }

                MouseArea {
                    id: spVolMouse
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

            // Keyboard Layout Pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowKbLayout && MangoState.kbLayoutShort.length > 0
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spKbRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3SurfaceC

                RowLayout {
                    id: spKbRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                    Text { text: MangoState.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3Ink }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.dnd
                implicitWidth: Math.max(20, root.podHeight - 10)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: spDndMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceC
                Text { anchors.centerIn: parent; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3Primary }
                MouseArea { id: spDndMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleDnd() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.keepAwake
                implicitWidth: Math.max(20, root.podHeight - 10)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: spAwakeMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceC
                Text { anchors.centerIn: parent; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3Primary }
                MouseArea { id: spAwakeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleKeepAwake() }
            }

            // Battery Pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowBattery && DeviceCaps.hasBattery
                implicitHeight: Math.max(20, root.podHeight - 10)
                implicitWidth: spBatRow.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: DeviceCaps.batteryLow ? Theme.m3ErrorContainer : Theme.m3SurfaceC

                RowLayout {
                    id: spBatRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: DeviceCaps.batteryLow ? Theme.m3Error : (DeviceCaps.batteryCharging ? Theme.m3Primary : Theme.m3InkDim) }
                    Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.m3OnErrorContainer : Theme.m3Ink }
                }
            }

            // Store Circular Tonal Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowStore
                implicitWidth: Math.max(22, root.podHeight - 9)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: spStoreMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spStoreMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: spStoreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openStoreRequested() }
            }

            // Files Circular Tonal Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowFiles
                implicitWidth: Math.max(22, root.podHeight - 9)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: spFilesMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spFilesMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: spFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openFilesRequested("") }
            }

            // Spotlight Trigger
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(22, root.podHeight - 9)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: root.openPanelMode === "launcher"
                    ? Theme.m3SecondaryContainer
                    : (spSpotMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")
                Text { anchors.centerIn: parent; text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: root.openPanelMode === "launcher" ? Theme.m3OnSecondaryContainer : Theme.m3Ink }
                MouseArea { id: spSpotMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleSpotlightRequested() }
            }

            // Control Center Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(22, root.podHeight - 9)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: root.openPanelMode === "controls"
                    ? Theme.m3Primary
                    : (spCcMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)
                Text {
                    anchors.centerIn: parent
                    text: "󰕰"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(11)
                    color: root.openPanelMode === "controls" ? Theme.m3OnPrimary : Theme.m3Ink
                }
                MouseArea {
                    id: spCcMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.callLater(() => root.openSettingsRequested("split"));
                        else
                            root.toggleControlCenterRequested();
                    }
                }
            }

            // Notifications Button (with unread badge pill)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: ShellState.unreadCount > 0 ? (spNotifRow.implicitWidth + 12) : Math.max(22, root.podHeight - 9)
                implicitHeight: Math.max(22, root.podHeight - 9)
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: root.openPanelMode === "notifications"
                    ? Theme.m3Primary
                    : (ShellState.unreadCount > 0 ? Theme.m3PrimaryContainer : (spNotifMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC))

                RowLayout {
                    id: spNotifRow
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        text: "󰂚"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(11)
                        color: root.openPanelMode === "notifications"
                            ? Theme.m3OnPrimary
                            : (ShellState.unreadCount > 0 ? Theme.m3Primary : Theme.m3InkDim)
                    }

                    Text {
                        visible: ShellState.unreadCount > 0
                        text: String(ShellState.unreadCount)
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: root.openPanelMode === "notifications" ? Theme.m3OnPrimary : Theme.m3OnPrimaryContainer
                    }
                }

                MouseArea {
                    id: spNotifMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleNotificationsRequested()
                }
            }
        }
    }
}
