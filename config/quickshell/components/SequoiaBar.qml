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

    readonly property bool hasMedia: ShellState.sequoiaShowMedia
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

    readonly property string menuGlyph: ShellState.menuGlyphFor(ShellState.sequoiaMenuIcon)

    function switchTagRelative(delta: int): void {
        const cur = Math.max(1, Math.min(9, root.activeTagIndex || 1));
        const next = ((cur - 1 + delta + 9) % 9) + 1;
        Quickshell.execDetached(["mmsg", "dispatch", "view," + next + ",0"]);
    }

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Rectangle {
        id: barSurface
        anchors.fill: parent
        anchors.leftMargin: ShellState.sequoiaBarFloating ? 8 : 0
        anchors.rightMargin: ShellState.sequoiaBarFloating ? 8 : 0
        anchors.topMargin: ShellState.sequoiaBarFloating ? 4 : 0
        anchors.bottomMargin: ShellState.sequoiaBarFloating ? 4 : 0
        radius: ShellState.sequoiaBarFloating ? Theme.r(Math.round(height / 2)) : 0
        color: ShellState.sequoiaBarTranslucent
            ? Theme.m3BarBg
            : Theme.m3Surface
        border.width: ShellState.sequoiaBarFloating ? 1 : 0
        border.color: Theme.m3Line
        clip: true

        // Crisp 1px bottom hairline in flush bar mode
        Rectangle {
            visible: !ShellState.sequoiaBarFloating
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.m3Line
            z: 5
        }

        // Left: Menu Icon + Bold Active App + Workspaces + Layout
        RowLayout {
            id: leftCluster
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            spacing: 8

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(22, barSurface.height - 6)
                implicitHeight: Math.max(22, barSurface.height - 6)
                radius: Theme.isSimple ? 0 : (menuBtnMouse.pressed ? Theme.r(7) : Math.round(implicitHeight / 2))
                color: menuBtnMouse.containsMouse ? Qt.lighter(Theme.m3Primary, 1.08) : Theme.m3Primary

                Text {
                    anchors.centerIn: parent
                    text: root.menuGlyph
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: Theme.m3OnPrimary
                }

                MouseArea {
                    id: menuBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.callLater(() => root.openSettingsRequested("sequoia"));
                        else
                            root.toggleSpotlightRequested();
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 150
                visible: ShellState.sequoiaShowAppTitle
                elide: Text.ElideRight
                text: MangoState.activeAppName
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.fgSurface
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 165
                visible: ShellState.sequoiaShowAppTitle
                    && MangoState.activeWindowTitle.length > 0
                    && MangoState.activeWindowTitle.toLowerCase() !== MangoState.activeAppName.toLowerCase()
                elide: Text.ElideRight
                text: MangoState.activeWindowTitle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Medium
                color: Theme.fgSurfaceVariant
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowAppTitle && (ShellState.sequoiaShowWorkspaces || ShellState.sequoiaShowLayout)
                implicitWidth: 1
                implicitHeight: 12
                color: Theme.hairlineBorder
            }

            M3WsStrip {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowWorkspaces
                model: root.visibleTags
                barHeight: barSurface.height
                compact: barSurface.height <= 30
                onSwitchRequested: wid => Quickshell.execDetached(["mmsg", "dispatch", "view," + wid + ",0"])
                onRelativeSwitchRequested: delta => root.switchTagRelative(delta)
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowLayout
                implicitHeight: Math.max(18, barSurface.height - 8)
                implicitWidth: mbLayTxt.implicitWidth + 12
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: mbLayMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line

                Text {
                    id: mbLayTxt
                    anchors.centerIn: parent
                    text: root.currentLayout
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    font.weight: Font.Bold
                    color: mbLayMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim
                }

                MouseArea {
                    id: mbLayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                }
            }
        }

        // Center: Now-Playing M3 Capsule (disappears automatically if overlapping side clusters)
        Rectangle {
            id: centerMediaPill
            anchors.centerIn: parent
            readonly property int availWidth: Math.max(0, barSurface.width - leftCluster.implicitWidth - rightCluster.implicitWidth - 48)
            visible: root.hasMedia && availWidth >= 120
            implicitHeight: Math.max(20, barSurface.height - 6)
            width: Math.min(availWidth, centerMediaRow.implicitWidth + 14)
            radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
            color: centerMediaMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC

            RowLayout {
                id: centerMediaRow
                anchors.centerIn: parent
                width: Math.min(implicitWidth, centerMediaPill.width - 10)
                spacing: 6

                M3ShapeImage {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.max(18, barSurface.height - 8)
                    implicitHeight: Math.max(18, barSurface.height - 8)
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
                    Layout.maximumWidth: 210
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
                            { minH: 3, maxH: 10, dur: 420 },
                            { minH: 5, maxH: 13, dur: 310 },
                            { minH: 3, maxH: 9,  dur: 480 }
                        ]
                        delegate: Rectangle {
                            id: seqEqBar
                            required property var modelData
                            width: 2
                            height: seqEqBar.modelData.minH
                            radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.m3Primary

                            SequentialAnimation on height {
                                running: root.visible && root.isPlaying && ShellState.pillShowEqualizer && !Theme.reducedMotion
                                loops: Animation.Infinite
                                NumberAnimation { to: seqEqBar.modelData.maxH; duration: seqEqBar.modelData.dur; easing.type: Easing.InOutSine }
                                NumberAnimation { to: seqEqBar.modelData.minH; duration: seqEqBar.modelData.dur; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                }
            }

            MouseArea {
                id: centerMediaMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        if (root.player && typeof root.player.togglePlaying === "function")
                            root.player.togglePlaying();
                    } else {
                        root.toggleControlCenterRequested();
                    }
                }
            }
        }

        // Right: Status Menu Cluster + Store + Spotlight + Control Center + Clock/Alerts
        RowLayout {
            id: rightCluster
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 10
            spacing: 6

            // Live Recording Pill (semantic red only for active recording)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.recordingActive
                implicitHeight: 19
                implicitWidth: seqRecRow.implicitWidth + 10
                radius: Theme.r(8)
                color: Theme.withAlpha(Theme.error, 0.22)

                RowLayout {
                    id: seqRecRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󰑊"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(9); color: Theme.error }
                    Text { text: "REC " + ShellState.formatTimer(ShellState.recordingElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.error }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "stop"])
                }
            }

            // Live Game Mode Badge
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.gameModeActive
                implicitHeight: 19
                implicitWidth: seqGmRow.implicitWidth + 10
                radius: Theme.r(8)
                color: seqGmMouse.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover

                RowLayout {
                    id: seqGmRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󰊴"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                    Text { text: "Game"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }

                MouseArea { id: seqGmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleGameMode() }
            }

            // Live Focus Timer / Stopwatch / File Op / Weather
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.timerActive
                implicitHeight: 19
                implicitWidth: seqTimerRow.implicitWidth + 10
                radius: Theme.r(8)
                color: seqTimerMouse.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover

                RowLayout {
                    id: seqTimerRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󰔛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                    Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }

                MouseArea { id: seqTimerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleNotificationsRequested() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.stopwatchActive
                implicitHeight: 19
                implicitWidth: seqSwRow.implicitWidth + 10
                radius: Theme.r(8)
                color: seqSwMouse.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover

                RowLayout {
                    id: seqSwRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                    Text { text: ShellState.formatTimer(ShellState.stopwatchElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }

                MouseArea { id: seqSwMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleNotificationsRequested() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.fmOpActive
                implicitHeight: 19
                implicitWidth: seqFmOpRow.implicitWidth + 10
                radius: Theme.r(8)
                color: seqFmOpMouse.containsMouse ? Theme.tileActiveBg : Theme.controlFillHover

                RowLayout {
                    id: seqFmOpRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                    Text { text: Math.round(ShellState.fmOpProgress * 100) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }

                MouseArea { id: seqFmOpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openFilesRequested("") }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable
                implicitHeight: 19
                implicitWidth: seqWeatherRow.implicitWidth + 8
                radius: Theme.r(8)
                color: seqWeatherMouse.containsMouse ? Theme.controlFillHover : "transparent"

                RowLayout {
                    id: seqWeatherRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text { text: ShellState.weatherIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                    Text { text: ShellState.weatherTemp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                }

                MouseArea { id: seqWeatherMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleNotificationsRequested() }
            }

            // Optional CPU & RAM Load
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowSystem
                spacing: 6
                Text { text: "󰍛 " + Math.round(SystemTelemetry.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: SystemTelemetry.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
                Text { text: "󰘚 " + Math.round(SystemTelemetry.memPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: SystemTelemetry.memPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
            }

            // Optional Live Network Throughput
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowNetSpeed
                spacing: 5
                Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
                Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
            }

            // System Tray
            SystemTrayStrip {
                id: trayStripSeq
                Layout.alignment: Qt.AlignVCenter
                hiddenPlayerHint: root.hasMedia && root.player ? ((root.player.identity || "") + " " + (root.player.desktopEntry || "")).toLowerCase() : ""
                visible: ShellState.sequoiaShowTray && trayStripSeq.hasItems
                compact: true
            }

            // Volume Control
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowVolume && DeviceCaps.hasAudio
                implicitHeight: Math.max(20, barSurface.height - 6)
                implicitWidth: seqVolRow.implicitWidth + 10
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: seqVolMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"

                RowLayout {
                    id: seqVolRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: MangoState.volMuted ? "󰝟" : (MangoState.volPercent <= 50 ? "󰖀" : "󰕾")
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(12)
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
                    id: seqVolMouse
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
                visible: ShellState.barShowKbLayout && MangoState.kbLayoutShort.length > 0
                implicitHeight: Math.max(18, barSurface.height - 8)
                implicitWidth: seqKbRow.implicitWidth + 10
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: Theme.m3SurfaceC

                RowLayout {
                    id: seqKbRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                    Text { text: MangoState.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.m3Ink }
                }
            }

            // Active Focus / Keep Awake Monochrome Toggles
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.dnd
                implicitWidth: Math.max(20, barSurface.height - 6)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: seqDndMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
                Text { anchors.centerIn: parent; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3Primary }
                MouseArea { id: seqDndMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleDnd() }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.keepAwake
                implicitWidth: Math.max(20, barSurface.height - 6)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: seqAwakeMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC
                Text { anchors.centerIn: parent; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.m3Primary }
                MouseArea { id: seqAwakeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleKeepAwake() }
            }

            // Battery
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowBattery && DeviceCaps.hasBattery
                spacing: 3
                Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: DeviceCaps.batteryLow ? Theme.m3Error : (DeviceCaps.batteryCharging ? Theme.m3Primary : Theme.m3InkDim) }
                Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.m3Error : Theme.m3Ink }
            }

            // Store Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowStore
                implicitWidth: Math.max(20, barSurface.height - 6)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: seqStoreMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent"
                Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: seqStoreMouse.containsMouse ? Theme.m3Ink : Theme.m3InkDim }
                MouseArea { id: seqStoreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openStoreRequested() }
            }

            // Spotlight Search Button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: ShellState.sequoiaShowSpotlightIcon
                implicitWidth: Math.max(20, barSurface.height - 6)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: root.openPanelMode === "launcher"
                    ? Theme.m3SecondaryContainer
                    : (seqSpotMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")
                Text { anchors.centerIn: parent; text: "󰍉"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: root.openPanelMode === "launcher" ? Theme.m3OnSecondaryContainer : Theme.m3Ink }
                MouseArea { id: seqSpotMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleSpotlightRequested() }
            }

            // Control Center Button (LMB toggles Control Center, RMB opens Sequoia Settings)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(20, barSurface.height - 6)
                implicitHeight: implicitWidth
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: root.openPanelMode === "controls"
                    ? Theme.m3Primary
                    : (seqCcMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)

                Text {
                    anchors.centerIn: parent
                    text: "󰕰"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: root.openPanelMode === "controls" ? Theme.m3OnPrimary : Theme.m3Ink
                }

                MouseArea {
                    id: seqCcMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.callLater(() => root.openSettingsRequested("sequoia"));
                        else
                            root.toggleControlCenterRequested();
                    }
                }
            }

            // Date & Clock Pill / Notification Center Trigger (clean neutral bar ink)
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: seqDateRow.implicitWidth + 12
                implicitHeight: Math.max(20, barSurface.height - 6)
                radius: Theme.isSimple ? 0 : Math.round(implicitHeight / 2)
                color: root.openPanelMode === "notifications"
                    ? Theme.m3SecondaryContainer
                    : (seqDateMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")

                RowLayout {
                    id: seqDateRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        visible: ShellState.sequoiaShowDate
                        text: ShellState.formatDate(clock.date)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Medium
                        color: root.openPanelMode === "notifications" ? Theme.m3OnSecondaryContainer : Theme.m3InkDim
                    }

                    Text {
                        visible: ShellState.sequoiaShowDate
                        text: "·"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.openPanelMode === "notifications" ? Theme.m3OnSecondaryContainer : Theme.m3InkDim
                    }

                    Text {
                        id: seqClkTxt
                        text: ShellState.formatTime(clock.date)
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.Bold
                        color: root.openPanelMode === "notifications" ? Theme.m3OnSecondaryContainer : Theme.m3Ink
                    }

                    Rectangle {
                        visible: ShellState.unreadCount > 0
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: Theme.m3Primary
                    }
                }

                MouseArea {
                    id: seqDateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleNotificationsRequested()
                }
            }
        }
    }
}
