pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."

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
            return title + " · " + artist;
        return title || artist || (root.player.identity || "Playing");
    }

    readonly property int podHeight: ShellState.splitBarHeight
    readonly property int podRadius: {
        if (ShellState.splitPodStyle === "compact")
            return Theme.r(8);
        if (ShellState.splitPodStyle === "rounded")
            return Theme.r(12);
        return Theme.r(Math.round(root.podHeight / 2));
    }
    readonly property color glassFill: ShellState.splitBarTranslucent
        ? Theme.withAlpha(Theme.surfaceContainerLowest, Math.min(0.86, ShellState.shellOpacity))
        : Theme.surfaceContainerLowest
    readonly property color activeGlassFill: Theme.withAlpha(Theme.notchBg, 0.96)

    function switchTagRelative(delta: int): void {
        const cur = Math.max(1, Math.min(9, root.activeTagIndex || 1));
        const next = ((cur - 1 + delta + 9) % 9) + 1;
        Quickshell.execDetached(["mmsg", "dispatch", "view," + next + ",0"]);
    }

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // ==================== 1. LEFT POD: SPACES, APP TITLE & QUICK LAUNCH ====================
    Rectangle {
        id: leftPod
        anchors.left: parent.left
        anchors.leftMargin: ShellState.splitSideMargin
        anchors.top: parent.top
        anchors.topMargin: ShellState.splitTopMargin
        height: root.podHeight
        width: Math.min(leftRow.implicitWidth + 18, Math.max(180, Math.round(root.width * 0.35)))
        radius: root.podRadius
        color: root.openPanelMode === "left" ? root.activeGlassFill : root.glassFill
        border.width: root.openPanelMode === "left"
            ? Math.max(1, Theme.activeControlBorderWidth)
            : Math.max(1, Theme.islandBorderWidth)
        border.color: root.openPanelMode === "left"
            ? Theme.primary
            : (Theme.islandBorderWidth > 0 ? Theme.islandBorder : Theme.hairlineBorder)
        clip: true

        // Click anywhere on left pod padding to toggle Left Spaces/Quick Hub
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
            width: Math.min(implicitWidth, parent.width - 16)
            spacing: 7

            // Leading Pod Glyph (LMB: Left Hub, RMB: Split Settings)
            Rectangle {
                visible: ShellState.splitShowLauncherIcon
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(20, root.podHeight - 8)
                implicitHeight: Math.max(20, root.podHeight - 8)
                radius: Math.min(root.podRadius, Theme.r(10))
                color: root.openPanelMode === "left"
                    ? Theme.tileActiveBg
                    : (spMenuMouse.containsMouse ? Theme.controlFillHover : Theme.withAlpha(Theme.fgSurface, 0.06))

                Text {
                    anchors.centerIn: parent
                    text: ShellState.menuGlyphFor(ShellState.splitMenuIcon)
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: root.openPanelMode === "left" ? Theme.primary : Theme.fgSurface
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

            // Workspaces Strip (Scroll wheel cycles 1..9 tags)
            Item {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowWorkspaces
                implicitWidth: wsRow.implicitWidth
                implicitHeight: 20

                WheelHandler {
                    onWheel: event => root.switchTagRelative(event.angleDelta.y > 0 ? -1 : 1)
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.visibleTags

                        delegate: Rectangle {
                            id: spTag
                            required property var modelData
                            readonly property bool isActive: spTag.modelData.is_active
                            readonly property bool isUrgent: spTag.modelData.is_urgent
                            readonly property bool isOccupied: spTag.modelData.client_count > 0

                            width: spTag.isActive ? 20 : 18
                            height: 18
                            radius: Theme.r(6)
                            color: {
                                if (spTag.isUrgent) return Theme.error;
                                if (spTag.isActive) return Theme.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.11);
                                if (spTagMouse.containsMouse) return Theme.controlFillHover;
                                return "transparent";
                            }
                            border.width: spTag.isActive ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: (spTag.isOccupied && !spTag.isActive && !spTag.isUrgent) ? -1 : 0
                                text: spTag.modelData.index
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(10)
                                font.weight: spTag.isActive ? Font.Bold : Font.Medium
                                color: {
                                    if (spTag.isUrgent) return Theme.fgError;
                                    if (spTag.isActive) return Theme.fgSurface;
                                    return spTag.isOccupied ? Theme.fgSurface : Theme.withAlpha(Theme.fgSurfaceVariant, 0.55);
                                }
                            }

                            Rectangle {
                                visible: spTag.isOccupied && !spTag.isActive && !spTag.isUrgent
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 1.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 3
                                height: 3
                                radius: 1.5
                                color: Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: spTagMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + spTag.modelData.index + ",0"])
                            }
                        }
                    }
                }
            }

            // Fallback Tag Badge when Workspaces strip is hidden
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: !ShellState.splitShowWorkspaces
                implicitHeight: 18
                implicitWidth: spTagOnly.implicitWidth + 10
                radius: Theme.r(6)
                color: Theme.withAlpha(Theme.fgSurface, 0.06)

                Text {
                    id: spTagOnly
                    anchors.centerIn: parent
                    text: "Space " + root.activeTagIndex
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }
            }

            // Tiling Layout Badge
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowLayout
                implicitHeight: 18
                implicitWidth: spLayTxt.implicitWidth + 8
                radius: Theme.r(6)
                color: spLayMouse.containsMouse ? Theme.controlFillHover : Theme.withAlpha(Theme.fgSurface, 0.06)

                Text {
                    id: spLayTxt
                    anchors.centerIn: parent
                    text: root.currentLayout
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: spLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                }

                MouseArea {
                    id: spLayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                }
            }

            // Active App Name & Window Title
            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 160
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
                font.pixelSize: Theme.fs(10)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }
        }
    }

    // ==================== 2. CENTER POD: CLOCK, MEDIA, WEATHER & LIVE ACTIVITY ====================
    Rectangle {
        id: centerPod
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: ShellState.splitTopMargin
        height: root.podHeight
        readonly property int maxCenterWidth: Math.max(150, root.width - leftPod.width - rightPod.width - ShellState.splitSideMargin * 2 - 24)
        width: Math.max(116, Math.min(maxCenterWidth, centerRow.implicitWidth + 24))
        radius: root.podRadius
        color: root.openPanelMode === "center"
            ? root.activeGlassFill
            : (centerMouse.containsMouse ? Qt.lighter(root.glassFill, 1.07) : root.glassFill)
        border.width: root.openPanelMode === "center"
            ? Math.max(1, Theme.activeControlBorderWidth)
            : Math.max(1, Theme.islandBorderWidth)
        border.color: root.openPanelMode === "center"
            ? Theme.primary
            : (Theme.islandBorderWidth > 0 ? Theme.islandBorder : Theme.hairlineBorder)
        clip: true

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
            width: Math.min(implicitWidth, centerPod.width - 16)
            spacing: 7

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
                visible: ShellState.splitShowDate
                text: ShellState.formatDate(clock.date)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Medium
                color: Theme.fgSurfaceVariant
            }

            // Optional Weather Badge
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.weatherEnabled && ShellState.splitShowWeather && ShellState.weatherAvailable
                spacing: 3
                Text { text: ShellState.weatherIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                Text { text: ShellState.weatherTemp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            // Circular Vinyl Art + Media Label + Equalizer
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasMedia
                spacing: 6

                ClippingRectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: 9
                    color: Theme.primaryContainer
                    contentUnderBorder: false
                    contentInsideBorder: true

                    rotation: 0
                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 12000
                        loops: Animation.Infinite
                        running: root.visible && root.isPlaying && spMediaImg.visible && ShellState.pillSpinArt && !Theme.reducedMotion
                    }

                    Image {
                        id: spMediaImg
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
                        visible: !spMediaImg.visible
                        text: "󰎈"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgPrimaryContainer
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 165
                    elide: Text.ElideRight
                    text: root.mediaLabel
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Medium
                    color: root.isPlaying ? Theme.fgSurface : Theme.fgSurfaceVariant
                }

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    visible: root.isPlaying && ShellState.pillShowEqualizer && !Theme.reducedMotion

                    Repeater {
                        model: [
                            { minH: 4, maxH: 12, dur: 420 },
                            { minH: 6, maxH: 14, dur: 310 },
                            { minH: 3, maxH: 10, dur: 480 }
                        ]
                        delegate: Rectangle {
                            id: spEqBar
                            required property var modelData
                            width: 2.5
                            height: spEqBar.modelData.minH
                            radius: 1.25
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.primary

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

            // Live Activity Pills (REC, Game, Timer, Stopwatch, FM Progress)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.recordingActive
                implicitHeight: 18
                implicitWidth: spRecRow.implicitWidth + 8
                radius: Theme.r(7)
                color: Theme.withAlpha(Theme.error, 0.22)
                RowLayout {
                    id: spRecRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󰑊"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.error }
                    Text { text: "REC " + ShellState.formatTimer(ShellState.recordingElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.error }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "stop"]) }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.timerActive
                implicitHeight: 18
                implicitWidth: spTmRow.implicitWidth + 8
                radius: Theme.r(7)
                color: Theme.controlFillHover
                RowLayout {
                    id: spTmRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󰔛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.primary }
                    Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgSurface }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.stopwatchActive
                implicitHeight: 18
                implicitWidth: spSwRow.implicitWidth + 8
                radius: Theme.r(7)
                color: Theme.controlFillHover
                RowLayout {
                    id: spSwRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.secondary }
                    Text { text: ShellState.formatTimer(ShellState.stopwatchElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgSurface }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.gameModeActive
                implicitHeight: 18
                implicitWidth: 20
                radius: Theme.r(7)
                color: Theme.tileActiveBg
                Text { anchors.centerIn: parent; text: "󰊴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.primary }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.fmOpActive
                implicitHeight: 18
                implicitWidth: spFmRow.implicitWidth + 8
                radius: Theme.r(7)
                color: Theme.controlFillHover
                RowLayout {
                    id: spFmRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurface }
                    Text { text: Math.round(ShellState.fmOpProgress * 100) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurface }
                }
            }
        }
    }

    // ==================== 3. RIGHT POD: TELEMETRY, SYSTEM STATUS & CONTROL CENTER ====================
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
        border.width: (root.openPanelMode === "controls" || root.openPanelMode === "notifications")
            ? Math.max(1, Theme.activeControlBorderWidth)
            : Math.max(1, Theme.islandBorderWidth)
        border.color: (root.openPanelMode === "controls" || root.openPanelMode === "notifications")
            ? Theme.primary
            : (Theme.islandBorderWidth > 0 ? Theme.islandBorder : Theme.hairlineBorder)
        clip: true

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
            width: Math.min(implicitWidth, parent.width - 16)
            spacing: 6

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowSystem
                spacing: 5
                Text { text: "󰍛 " + Math.round(SystemTelemetry.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: SystemTelemetry.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
                Text { text: "󰘚 " + Math.round(SystemTelemetry.memPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: SystemTelemetry.memPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowNetSpeed
                spacing: 4
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
            }

            SystemTrayStrip {
                id: trayStripSplit
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowTray && trayStripSplit.hasItems
                compact: true
            }

            // Volume Control (LMB: mute, Wheel: +/-5%, RMB: cycle audio output sink)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowVolume && DeviceCaps.hasAudio
                implicitHeight: 20
                implicitWidth: spVolRow.implicitWidth + 8
                radius: Theme.r(6)
                color: spVolMouse.containsMouse ? Theme.controlFillHover : "transparent"

                RowLayout {
                    id: spVolRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: MangoState.volMuted ? "󰝟" : (MangoState.volPercent <= 50 ? "󰖀" : "󰕾")
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(12)
                        color: MangoState.volMuted ? Theme.withAlpha(Theme.fgSurfaceVariant, 0.65) : Theme.fgSurfaceVariant
                    }
                    Text {
                        text: MangoState.volMuted ? "Mute" : (MangoState.volPercent + "%")
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: MangoState.volMuted ? Theme.withAlpha(Theme.fgSurfaceVariant, 0.65) : Theme.fgSurfaceVariant
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

            // Keyboard Layout Badge
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowKbLayout && MangoState.kbLayoutShort.length > 0
                implicitHeight: 18
                implicitWidth: spKbRow.implicitWidth + 8
                radius: Theme.r(5)
                color: Theme.withAlpha(Theme.fgSurface, 0.06)

                RowLayout {
                    id: spKbRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                    Text { text: MangoState.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }
            }

            // Quick DND / Keep Awake status chips
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.dnd
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
                color: spDndMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                MouseArea { id: spDndMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleDnd() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.keepAwake
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
                color: spAwakeMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
                MouseArea { id: spAwakeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleKeepAwake() }
            }

            // Battery
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowBattery && DeviceCaps.hasBattery
                spacing: 3
                Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: DeviceCaps.batteryLow ? Theme.error : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant) }
                Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant }
            }

            // App Store Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowStore
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
                color: spStoreMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spStoreMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: spStoreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openStoreRequested() }
            }

            // Files Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.splitShowFiles
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
                color: spFilesMouse.containsMouse ? Theme.controlFillHover : "transparent"
                Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spFilesMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                MouseArea { id: spFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openFilesRequested("") }
            }

            // Spotlight Trigger
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
                color: root.openPanelMode === "launcher"
                    ? Theme.tileActiveBg
                    : (spSpotMouse.containsMouse ? Theme.controlFillHover : "transparent")
                Text { anchors.centerIn: parent; text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                MouseArea { id: spSpotMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleSpotlightRequested() }
            }

            // Control Center Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22; implicitHeight: 20; radius: Theme.r(6)
                color: root.openPanelMode === "controls"
                    ? Theme.tileActiveBg
                    : (spCcMouse.containsMouse ? Theme.controlFillHover : "transparent")
                Text { anchors.centerIn: parent; text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: root.openPanelMode === "controls" ? Theme.primary : Theme.fgSurface }
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

            // Notifications Button (with unread badge)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: spNotifRow.implicitWidth + 8
                implicitHeight: 20
                radius: Theme.r(6)
                color: root.openPanelMode === "notifications"
                    ? Theme.tileActiveBg
                    : (spNotifMouse.containsMouse ? Theme.controlFillHover : "transparent")

                RowLayout {
                    id: spNotifRow
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        text: "󰂚"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(11)
                        color: root.openPanelMode === "notifications" || ShellState.unreadCount > 0 ? Theme.primary : Theme.fgSurfaceVariant
                    }

                    Text {
                        visible: ShellState.unreadCount > 0
                        text: String(ShellState.unreadCount)
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(8)
                        font.weight: Font.Bold
                        color: Theme.primary
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
