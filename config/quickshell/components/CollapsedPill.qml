pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

    implicitHeight: root.barUiStyle === "menubar" ? Math.max(22, ShellState.pillHeight - 6) : ShellState.pillHeight
    implicitWidth: {
        if (root.barUiStyle === "split" || root.barUiStyle === "menubar" || root.barMode)
            return parent ? parent.width : 640;
        if (root.barUiStyle === "apple")
            return appleRow.implicitWidth;
        return classicRow.implicitWidth;
    }

    // --- Live Modular Widget State ---
    property string monitorName: ""
    property string currentLayout: "T"
    property var tagsModel: [
        { index: 1, is_active: true,  is_urgent: false, client_count: 0 },
        { index: 2, is_active: false, is_urgent: false, client_count: 0 },
        { index: 3, is_active: false, is_urgent: false, client_count: 0 },
        { index: 4, is_active: false, is_urgent: false, client_count: 0 },
        { index: 5, is_active: false, is_urgent: false, client_count: 0 },
        { index: 6, is_active: false, is_urgent: false, client_count: 0 },
        { index: 7, is_active: false, is_urgent: false, client_count: 0 },
        { index: 8, is_active: false, is_urgent: false, client_count: 0 },
        { index: 9, is_active: false, is_urgent: false, client_count: 0 }
    ]
    property string activeWindowTitle: ""
    readonly property real cpuPercent: SystemTelemetry.cpuPercent
    readonly property real ramPercent: SystemTelemetry.memPercent
    property int volPercent: 50
    property bool volMuted: false
    property string kbLayoutShort: ""

    readonly property int activeTagIndex: {
        const arr = root.tagsModel || [];
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].is_active)
                return arr[i].index;
        }
        return 1;
    }

    readonly property var visibleTags: {
        if (root.barMode || root.barUiStyle === "split" || root.barUiStyle === "menubar") {
            const occupiedOrActive = root.tagsModel.filter(t => t.is_active || t.is_urgent || t.client_count > 0);
            if (root.barUiStyle === "split" || root.barUiStyle === "menubar")
                return occupiedOrActive.length >= 4 ? occupiedOrActive : root.tagsModel.slice(0, Math.max(4, occupiedOrActive.length));
            return root.tagsModel;
        }
        const filtered = root.tagsModel.filter(t => t.is_active || t.is_urgent || t.client_count > 0);
        return filtered.length > 0 ? filtered : root.tagsModel.slice(0, 4);
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

    readonly property bool showSpacesEffective: ShellState.barShowWorkspaces || root.barUiStyle === "split" || root.barUiStyle === "menubar" || root.barUiStyle === "apple"
    readonly property bool showWinEffective: ShellState.barShowWindow || root.barUiStyle === "menubar"
    readonly property bool showVolEffective: DeviceCaps.hasAudio && ShellState.barShowVolume
    readonly property bool hasBatteryChip: DeviceCaps.hasBattery && ShellState.barShowBattery
    readonly property bool hasTrayChip: ShellState.barShowTray && (trayStripApple.hasItems || trayStripSplit.hasItems || trayStripMenu.hasItems || trayStripClassic.hasItems)
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

    function parseTagsJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const payload = JSON.parse(trimmed);
            const list = payload.all_tags;
            if (!list || list.length === 0)
                return;
            const targetMon = root.screenName.length > 0 ? root.screenName : root.monitorName;
            let chosen = list[0];
            for (let i = 0; i < list.length; i++) {
                if (list[i].monitor === targetMon) {
                    chosen = list[i];
                    break;
                }
            }
            if (chosen.monitor)
                root.monitorName = chosen.monitor;
            if (chosen.tags && chosen.tags.length > 0) {
                const normalized = [];
                let activeLayout = root.currentLayout;
                for (let j = 0; j < Math.min(9, chosen.tags.length); j++) {
                    const t = chosen.tags[j];
                    if (t.is_active && t.layout)
                        activeLayout = t.layout;
                    normalized.push({
                        index: t.index,
                        is_active: !!t.is_active,
                        is_urgent: !!t.is_urgent,
                        client_count: t.client_count || 0
                    });
                }
                root.currentLayout = activeLayout;
                root.tagsModel = normalized;
            }
        } catch (err) {}
    }

    function parseWinJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            if (d.error || !d.id || (!d.title && !d.appid)) {
                root.activeWindowTitle = "";
                return;
            }
            root.activeWindowTitle = String(d.title || d.appid || "");
        } catch (err) {}
    }

    function parseKbJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            const full = String(d.layout || "").trim();
            if (full.length === 0) {
                root.kbLayoutShort = "";
                return;
            }
            const paren = full.match(/\(([^)]+)\)/);
            if (paren && paren[1])
                root.kbLayoutShort = paren[1].trim().slice(0, 3).toUpperCase();
            else
                root.kbLayoutShort = full.slice(0, 2).toUpperCase();
        } catch (err) {}
    }

    function parseVolOut(raw: string): void {
        const parts = (raw || "").split("---");
        if (parts.length > 0) {
            const m = parts[0].match(/(\d+)%/);
            if (m && m[1])
                root.volPercent = Math.max(0, Math.min(150, parseInt(m[1], 10)));
        }
        if (parts.length > 1)
            root.volMuted = parts[1].toLowerCase().indexOf("yes") !== -1;
    }

    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Process {
        id: tagStream
        command: ["mmsg", "watch", "all-tags"]
        running: root.active && (root.showSpacesEffective || ShellState.barShowLayout)
        stdout: SplitParser { onRead: line => root.parseTagsJson(line) }
    }

    Process {
        id: winStream
        command: ["mmsg", "watch", "focusing-client"]
        running: root.active && root.showWinEffective
        stdout: SplitParser { onRead: line => root.parseWinJson(line) }
    }

    Process {
        id: kbStream
        command: ["mmsg", "watch", "keyboardlayout"]
        running: root.active && ShellState.barShowKbLayout
        stdout: SplitParser { onRead: line => root.parseKbJson(line) }
    }

    Process {
        id: volProc
        command: ["sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null; echo '---'; pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.parseVolOut(text) }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.active && root.showVolEffective
        triggeredOnStart: true
        onTriggered: { if (!volProc.running) volProc.running = true; }
    }

    Timer {
        id: volRefreshTimer
        interval: 120
        repeat: false
        onTriggered: { if (!volProc.running) volProc.running = true; }
    }

    // ==================== REUSABLE COMPACT SUBCOMPONENTS ====================
    component SpacesChipStrip : Row {
        id: scStrip
        property var model: root.visibleTags
        spacing: 3

        Repeater {
            model: scStrip.model

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

    component MediaMiniGroup : RowLayout {
        id: mmg
        property int maxTitleWidth: 165
        spacing: 6

        ClippingRectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 20
            implicitHeight: 20
            radius: Theme.r(10)
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
                sourceSize: Qt.size(48, 48)
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
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
                volRefreshTimer.restart();
            }
            onWheel: wheel => {
                const delta = wheel.angleDelta.y > 0 ? "+5%" : "-5%";
                Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", delta]);
                volRefreshTimer.restart();
            }
        }
    }

    component LiveActivityChips : RowLayout {
        spacing: 5

        // Live Game Mode Badge
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

        // Live Stopwatch
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

        // Opt-In Weather Pill
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

        // Live Recording Pill (semantic red status only for live screen recording)
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

        // Live Focus Timer
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
                Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }

            MouseArea { id: tmMouseC; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.timerClicked() }
        }

        // Unread Notifications Pill
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

        // Live File Manager Op Progress
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

    // ==================== BAR STYLE 1: APPLE DYNAMIC ISLAND CAPSULE ====================
    RowLayout {
        id: appleRow
        anchors.centerIn: parent
        width: root.barMode ? parent.width : implicitWidth
        height: parent.height
        visible: root.barUiStyle === "apple"
        spacing: 8
        clip: true

        // Optional Launcher Quick Icon
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowQuickIcons
            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(10)
            color: apLaunchMouse.containsMouse ? Theme.controlFillHover : "transparent"
            Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: apLaunchMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
            MouseArea { id: apLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
        }

        // Full Workspaces Strip when barShowWorkspaces is ON
        SpacesChipStrip {
            visible: ShellState.barShowWorkspaces
        }

        // Compact Active Space Badge (when barShowWorkspaces is OFF and idle)
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

        // Optional Layout Badge ([T])
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowLayout
            implicitHeight: 18; implicitWidth: apLayLbl.implicitWidth + 8; radius: Theme.r(6)
            color: apLayMouse.containsMouse ? Theme.controlFillHover : "transparent"
            Text { id: apLayLbl; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: apLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
            MouseArea { id: apLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
        }

        // Optional Active Window Title
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

        // Bold Clock + Optional Date
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

        // Live Media Strip when playing
        MediaMiniGroup {
            visible: root.hasMedia
            maxTitleWidth: root.barMode ? 200 : 160
        }

        Item { Layout.fillWidth: true; visible: root.barMode }

        // Optional CPU & RAM Load
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowSystem
            spacing: 6
            Text { text: "󰍛 " + Math.round(root.cpuPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
            Text { text: "󰘚 " + Math.round(root.ramPercent) + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: root.ramPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
        }

        // Optional Live Network Throughput
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowNetSpeed
            spacing: 5
            Text { text: "󰇚 " + SystemTelemetry.netDown; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
            Text { text: "󰕒 " + SystemTelemetry.netUp; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurfaceVariant }
        }

        // Optional Volume & Mute
        VolumePillButton {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowVolume && DeviceCaps.hasAudio
        }

        // Optional Keyboard Layout Code
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

        // Live Activity Badges (Timer, Rec, Game, Weather, Unread)
        LiveActivityChips {
            visible: ShellState.gameModeActive || ShellState.stopwatchActive || ShellState.recordingActive
                || ShellState.timerActive || ShellState.unreadCount > 0 || ShellState.fmOpActive
                || (ShellState.weatherEnabled && ShellState.barShowWeather && ShellState.weatherAvailable)
        }

        // Active Focus/Keep-Awake Indicators (calm monochrome)
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

    // ==================== BAR STYLE 2: SPLIT FLOATING ISLANDS (3 GLASS PODS) ====================
    Item {
        id: splitRow
        anchors.fill: parent
        visible: root.barUiStyle === "split"
        clip: true

        // POD 1 (LEFT): Launcher + Workspaces + Layout + Active Window
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
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: Theme.r(10)
                    color: spLaunchMouse.containsMouse ? Theme.controlFillHover : "transparent"

                    Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spLaunchMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    MouseArea { id: spLaunchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
                }

                SpacesChipStrip { visible: ShellState.barShowWorkspaces }

                Rectangle {
                    visible: !ShellState.barShowWorkspaces
                    implicitHeight: 18
                    implicitWidth: spDotLblSplit.implicitWidth + 10
                    radius: Theme.r(9)
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

                    Text {
                        id: spDotLblSplit
                        anchors.centerIn: parent
                        text: "Tag " + root.activeTagIndex
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    visible: ShellState.barShowLayout
                    implicitHeight: 18
                    implicitWidth: spLayTxt.implicitWidth + 8
                    radius: Theme.r(6)
                    color: spLayMouse.containsMouse ? Theme.controlFillHover : "transparent"

                    Text { id: spLayTxt; anchors.centerIn: parent; text: "[" + root.currentLayout + "]"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: spLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    MouseArea { id: spLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
                }

                Text {
                    visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
                    Layout.maximumWidth: 130
                    elide: Text.ElideRight
                    text: root.activeWindowTitle
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }
            }
        }

        // POD 2 (DEAD-CENTER): Clock + Date + Dynamic Now Playing (click to expand Island)
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
                id: podCenterMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expandRequested()
            }

            RowLayout {
                id: podCenterRow
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
                    visible: ShellState.barShowDate
                    text: ShellState.formatDate(clock.date)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                MediaMiniGroup {
                    visible: root.hasMedia
                    maxTitleWidth: 165
                }
            }
        }

        // POD 3 (RIGHT): Live Activities, System, Volume, KB, Tray, Focus, Battery, Control Center
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
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: Theme.r(10)
                    color: spNotifMouse.containsMouse ? Theme.controlFillHover : "transparent"
                    Text { anchors.centerIn: parent; text: "󰂚"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spNotifMouse.containsMouse || ShellState.unreadCount > 0 ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    MouseArea { id: spNotifMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.notificationsClicked() }
                }

                Rectangle {
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: Theme.r(10)
                    color: spCcMouse.containsMouse ? Theme.controlFillHover : "transparent"
                    Text { anchors.centerIn: parent; text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: spCcMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    MouseArea { id: spCcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.expandRequested() }
                }
            }
        }
    }

    // ==================== BAR STYLE 3: MACOS SEQUOIA TOP MENU BAR ====================
    RowLayout {
        id: menuRow
        anchors.fill: parent
        visible: root.barUiStyle === "menubar"
        spacing: 10
        clip: true

        // Apple/Launcher Menu Icon
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 22
            implicitHeight: 20
            radius: Theme.r(6)
            color: mbAppMouse.containsMouse ? Theme.controlFillHover : "transparent"

            Text { anchors.centerIn: parent; text: "󰀻"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.fgSurface }
            MouseArea { id: mbAppMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launcherClicked() }
        }

        // Bold Active App / Window Title
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 210
            elide: Text.ElideRight
            text: (ShellState.barShowWindow && root.activeWindowTitle.length > 0) ? root.activeWindowTitle : "Aurora"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            font.weight: Font.Bold
            color: Theme.fgSurface
        }

        SpacesChipStrip { visible: ShellState.barShowWorkspaces }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: !ShellState.barShowWorkspaces
            implicitHeight: 18
            implicitWidth: spDotLblMenu.implicitWidth + 10
            radius: Theme.r(6)
            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

            Text {
                id: spDotLblMenu
                anchors.centerIn: parent
                text: String(root.activeTagIndex)
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(9)
                font.weight: Font.DemiBold
                color: Theme.fgSurfaceVariant
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowLayout
            implicitHeight: 18
            implicitWidth: mbLayTxt.implicitWidth + 8
            radius: Theme.r(6)
            color: mbLayMouse.containsMouse ? Theme.controlFillHover : "transparent"
            Text { id: mbLayTxt; anchors.centerIn: parent; text: root.currentLayout; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: mbLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
            MouseArea { id: mbLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
        }

        Item { Layout.fillWidth: true }

        // Center Subtle Now-Playing Capsule when active
        MediaMiniGroup {
            visible: root.hasMedia
            maxTitleWidth: 210
        }

        Item { Layout.fillWidth: true }

        // Right macOS Status Menu Cluster (calm monochrome-first)
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

        LiveActivityChips {}

        VolumePillButton { visible: root.showVolEffective }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
            implicitHeight: 18; implicitWidth: kbPillRowMb.implicitWidth + 8; radius: Theme.r(6)
            color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
            RowLayout {
                id: kbPillRowMb
                anchors.centerIn: parent; spacing: 3
                Text { text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                Text { text: root.kbLayoutShort; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
            }
        }

        Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.dnd; text: "󰂛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }
        Text { Layout.alignment: Qt.AlignVCenter; visible: ShellState.keepAwake; text: "󰅶"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(11); color: Theme.fgSurfaceVariant }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            visible: root.hasBatteryChip
            spacing: 3
            Text { text: DeviceCaps.batteryIcon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: DeviceCaps.batteryLow ? Theme.error : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant) }
            Text { text: DeviceCaps.batteryPercent + "%"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant }
        }

        SystemTrayStrip {
            id: trayStripMenu
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowTray && trayStripMenu.hasItems
            compact: true
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
            color: mbFilesMouse.containsMouse ? Theme.controlFillHover : "transparent"
            Text { anchors.centerIn: parent; text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
            MouseArea { id: mbFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filesClicked() }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: ShellState.barShowQuickIcons
            implicitWidth: 20; implicitHeight: 20; radius: Theme.r(6)
            color: mbGearMouse.containsMouse ? Theme.controlFillHover : "transparent"
            Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
            MouseArea { id: mbGearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsClicked() }
        }

        // Control Center Toggle Icon
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 20
            implicitHeight: 20
            radius: Theme.r(6)
            color: mbCcMouse.containsMouse ? Theme.controlFillHover : "transparent"
            Text { anchors.centerIn: parent; text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
            MouseArea { id: mbCcMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.expandRequested() }
        }

        // Notifications / Date + Clock Trigger
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: mbDateRow.implicitWidth
            implicitHeight: 20

            RowLayout {
                id: mbDateRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    visible: ShellState.barShowDate
                    text: ShellState.formatDate(clock.date)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    color: Theme.fgSurfaceVariant
                }

                Text {
                    text: ShellState.formatTime(clock.date)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(11)
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.notificationsClicked()
            }
        }
    }

    // ==================== BAR STYLE 4: MODULAR CLASSIC PILL / FULL BAR ====================
    RowLayout {
        id: classicRow
        anchors.centerIn: parent
        width: root.barMode ? parent.width : implicitWidth
        height: parent.height
        visible: root.barUiStyle === "classic"
        spacing: root.hasAnyClassicModule ? 8 : 0
        clip: true

        // Launcher Quick Icon
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
            visible: root.hasTrayChip
            compact: true
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
