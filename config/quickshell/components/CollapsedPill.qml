pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".."

RowLayout {
    id: root

    property var player: null
    property string screenName: ""
    property bool active: true
    property bool barMode: false

    signal launcherClicked()
    signal settingsClicked()
    signal filesClicked()

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
    property real cpuPercent: 0
    property real _prevTotal: 0
    property real _prevIdle: 0
    property real ramPercent: 0
    property int volPercent: 50
    property bool volMuted: false
    property string kbLayoutShort: ""

    readonly property var visibleTags: {
        if (root.barMode)
            return root.tagsModel;
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

    readonly property bool hasBatteryChip: DeviceCaps.hasBattery && ShellState.barShowBattery
    readonly property bool hasTrayChip: ShellState.barShowTray && trayStrip.hasItems
    readonly property bool hasAnyModule: hasMedia
        || hasBatteryChip
        || ShellState.dnd
        || ShellState.keepAwake
        || ShellState.barShowDate
        || (ShellState.barShowWindow && activeWindowTitle.length > 0)
        || ShellState.barShowWorkspaces
        || ShellState.barShowLayout
        || ShellState.barShowSystem
        || (ShellState.barShowVolume && DeviceCaps.hasAudio)
        || (ShellState.barShowKbLayout && kbLayoutShort.length > 0)
        || hasTrayChip
        || ShellState.barShowQuickIcons
        || ShellState.barShowFiles
        || ShellState.fmOpActive
        || barMode

    spacing: hasAnyModule ? 8 : 0

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
            if (paren && paren[1]) {
                root.kbLayoutShort = paren[1].trim().slice(0, 3).toUpperCase();
            } else {
                root.kbLayoutShort = full.slice(0, 2).toUpperCase();
            }
        } catch (err) {}
    }

    function parseCpuStat(raw: string): void {
        if (!raw)
            return;
        const firstLine = raw.split("\n")[0] || "";
        if (!firstLine.startsWith("cpu "))
            return;
        const parts = firstLine.trim().split(/\s+/);
        if (parts.length < 5)
            return;
        const user = parseFloat(parts[1]) || 0;
        const nice = parseFloat(parts[2]) || 0;
        const system = parseFloat(parts[3]) || 0;
        const idle = parseFloat(parts[4]) || 0;
        const iowait = parseFloat(parts[5]) || 0;
        const irq = parseFloat(parts[6]) || 0;
        const softirq = parseFloat(parts[7]) || 0;
        const steal = parseFloat(parts[8]) || 0;
        const idleAll = idle + iowait;
        const totalAll = user + nice + system + idleAll + irq + softirq + steal;
        if (root._prevTotal > 0 && totalAll > root._prevTotal) {
            const totalDelta = totalAll - root._prevTotal;
            const idleDelta = idleAll - root._prevIdle;
            root.cpuPercent = Math.max(0, Math.min(100, ((totalDelta - idleDelta) / totalDelta) * 100));
        }
        root._prevTotal = totalAll;
        root._prevIdle = idleAll;
    }

    function parseMeminfo(raw: string): void {
        if (!raw)
            return;
        let totalKb = 0;
        let availKb = -1;
        let freeKb = 0;
        let buffersKb = 0;
        let cachedKb = 0;
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.startsWith("MemTotal:"))
                totalKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("MemAvailable:"))
                availKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("MemFree:"))
                freeKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("Buffers:"))
                buffersKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("Cached:"))
                cachedKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
        }
        if (totalKb <= 0)
            return;
        if (availKb < 0)
            availKb = freeKb + buffersKb + cachedKb;
        const usedKb = Math.max(0, totalKb - availKb);
        root.ramPercent = Math.max(0, Math.min(100, (usedKb / totalKb) * 100));
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

    // --- Lazy Streams & Timers (active only when widget is enabled) ---
    SystemClock {
        id: clock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Process {
        id: tagStream
        command: ["mmsg", "watch", "all-tags"]
        running: root.active && (ShellState.barShowWorkspaces || ShellState.barShowLayout)
        stdout: SplitParser {
            onRead: line => root.parseTagsJson(line)
        }
    }

    Process {
        id: winStream
        command: ["mmsg", "watch", "focusing-client"]
        running: root.active && ShellState.barShowWindow
        stdout: SplitParser {
            onRead: line => root.parseWinJson(line)
        }
    }

    Process {
        id: kbStream
        command: ["mmsg", "watch", "keyboardlayout"]
        running: root.active && ShellState.barShowKbLayout
        stdout: SplitParser {
            onRead: line => root.parseKbJson(line)
        }
    }

    Process {
        id: sysProc
        command: ["sh", "-c", "head -n 1 /proc/stat; echo '---'; grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached):' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").split("---");
                if (parts.length >= 2) {
                    root.parseCpuStat(parts[0].trim());
                    root.parseMeminfo(parts[1].trim());
                }
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active && ShellState.barShowSystem
        triggeredOnStart: true
        onTriggered: {
            if (!sysProc.running)
                sysProc.running = true;
        }
    }

    Process {
        id: volProc
        command: ["sh", "-c", "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null; echo '---'; pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.parseVolOut(text)
        }
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.active && ShellState.barShowVolume && DeviceCaps.hasAudio
        triggeredOnStart: true
        onTriggered: {
            if (!volProc.running)
                volProc.running = true;
        }
    }

    Timer {
        id: volRefreshTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (!volProc.running)
                volProc.running = true;
        }
    }

    // ==================== LEFT MODULES ====================
    // Quick Launcher Icon
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowQuickIcons
        implicitWidth: 22
        implicitHeight: 22
        radius: Theme.r(7)
        color: launchBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

        Text {
            anchors.centerIn: parent
            text: "󰀻"
            font.family: Theme.iconFont
            font.pixelSize: 12
            color: Theme.primary
        }

        MouseArea {
            id: launchBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.launcherClicked()
        }
    }

    // Workspaces / Tags Strip
    Row {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowWorkspaces
        spacing: 3

        Repeater {
            model: root.visibleTags

            delegate: Rectangle {
                id: pillTag
                required property var modelData
                readonly property bool isActive: pillTag.modelData.is_active
                readonly property bool isUrgent: pillTag.modelData.is_urgent
                readonly property bool isOccupied: pillTag.modelData.client_count > 0

                width: pillTag.isActive ? 20 : 18
                height: 18
                radius: Theme.r(6)
                color: {
                    if (pillTag.isUrgent)
                        return Theme.error;
                    if (pillTag.isActive)
                        return Theme.primary;
                    if (pillTagMouse.containsMouse)
                        return Theme.hoverBg;
                    if (pillTag.isOccupied)
                        return Theme.withAlpha(Theme.primary, 0.22);
                    return Theme.subCardBg;
                }

                Text {
                    anchors.centerIn: parent
                    text: pillTag.modelData.index
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: pillTag.isActive ? Font.Bold : Font.Medium
                    color: {
                        if (pillTag.isUrgent)
                            return Theme.fgError;
                        if (pillTag.isActive)
                            return Theme.fgPrimary;
                        return pillTag.isOccupied ? Theme.fgSurface : Theme.fgSurfaceVariant;
                    }
                }

                MouseArea {
                    id: pillTagMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + pillTag.modelData.index + ",0"])
                }
            }
        }
    }

    // Layout Badge ([T])
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowLayout
        implicitHeight: 18
        implicitWidth: layPillLbl.implicitWidth + 10
        radius: Theme.r(6)
        color: layPillMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

        Text {
            id: layPillLbl
            anchors.centerIn: parent
            text: "[" + root.currentLayout + "]"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            color: Theme.secondary
        }

        MouseArea {
            id: layPillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
        }
    }

    // Active Window Title
    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowWindow && root.activeWindowTitle.length > 0
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "󰖯"
            font.family: Theme.iconFont
            font.pixelSize: 12
            color: Theme.secondary
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: root.barMode ? 250 : 160
            elide: Text.ElideRight
            maximumLineCount: 1
            text: root.activeWindowTitle
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
            color: Theme.fgSurfaceVariant
        }
    }

    // Expand Left/Center Spacer when Full-Width Bar Mode is active
    Item {
        Layout.fillWidth: true
        visible: root.barMode
    }

    // ==================== CENTER MODULES ====================
    // Bold Clock
    Text {
        id: clockText
        Layout.alignment: Qt.AlignVCenter
        text: ShellState.formatTime(clock.date)
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Bold
        color: Theme.fgSurface
    }

    // Date Chip next to Clock
    Text {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowDate
        text: ShellState.formatDate(clock.date)
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.weight: Font.Medium
        color: Theme.fgSurfaceVariant
    }

    // Collapsible Spotify / MPRIS Mini-Player
    Item {
        id: mediaSection
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: root.hasMedia ? mediaRow.implicitWidth : 0
        implicitHeight: 24
        clip: true
        opacity: root.hasMedia ? 1.0 : 0.0
        visible: implicitWidth > 1

        Behavior on implicitWidth {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: mediaRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 4
                implicitHeight: 4
                radius: Theme.r(2)
                color: root.isPlaying ? Theme.primary : Theme.outline
            }

            ClippingRectangle {
                id: artClip
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 20
                implicitHeight: 20
                radius: Theme.r(10)
                color: Theme.primaryContainer

                rotation: 0
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 12000
                    loops: Animation.Infinite
                    running: root.active && root.isPlaying && root.visible && artImage.visible && ShellState.pillSpinArt && !Theme.reducedMotion
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(48, 48)
                    visible: root.artUrl.length > 0 && status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !artImage.visible
                    text: "󰎈"
                    font.family: Theme.iconFont
                    font.pixelSize: 11
                    color: Theme.fgPrimaryContainer
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: root.barMode ? 210 : 175
                text: root.mediaLabel
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: 11
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
                        id: eqBar
                        required property var modelData
                        width: 2.5
                        height: eqBar.modelData.minH
                        radius: 1.25
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.primary

                        SequentialAnimation on height {
                            running: root.active && root.isPlaying && root.visible && ShellState.pillShowEqualizer && !Theme.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation {
                                to: eqBar.modelData.maxH
                                duration: eqBar.modelData.dur
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: eqBar.modelData.minH
                                duration: eqBar.modelData.dur
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }
            }
        }
    }

    // Expand Center/Right Spacer when Full-Width Bar Mode is active
    Item {
        Layout.fillWidth: true
        visible: root.barMode
    }

    // ==================== RIGHT MODULES ====================
    // CPU & RAM Usage
    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowSystem
        spacing: 5

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "󰍛 " + Math.round(root.cpuPercent) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: root.cpuPercent > 85 ? Theme.error : Theme.primary
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "󰘚 " + Math.round(root.ramPercent) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: root.ramPercent > 85 ? Theme.warning : Theme.secondary
        }
    }

    // Interactive Volume Indicator (click to mute, scroll ±5%)
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowVolume && DeviceCaps.hasAudio
        implicitHeight: 20
        implicitWidth: volRow.implicitWidth + 10
        radius: Theme.r(7)
        color: volMouse.containsMouse ? Theme.hoverBg : "transparent"

        RowLayout {
            id: volRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: root.volMuted ? "󰝟" : (root.volPercent <= 50 ? "󰖀" : "󰕾")
                font.family: Theme.iconFont
                font.pixelSize: 12
                color: root.volMuted ? Theme.error : Theme.primary
            }

            Text {
                text: root.volMuted ? "Mute" : (root.volPercent + "%")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: root.volMuted ? Theme.error : Theme.fgSurfaceVariant
            }
        }

        MouseArea {
            id: volMouse
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

    // Keyboard Layout Badge
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowKbLayout && root.kbLayoutShort.length > 0
        implicitHeight: 18
        implicitWidth: kbPillRow.implicitWidth + 8
        radius: Theme.r(6)
        color: Theme.subCardBg

        RowLayout {
            id: kbPillRow
            anchors.centerIn: parent
            spacing: 3

            Text {
                text: "󰌌"
                font.family: Theme.iconFont
                font.pixelSize: 10
                color: Theme.secondary
            }

            Text {
                text: root.kbLayoutShort
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                color: Theme.fgSurface
            }
        }
    }

    // Active-Only Status Badges (DND / Keep Awake)
    Text {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.dnd
        text: "󰂛"
        font.family: Theme.iconFont
        font.pixelSize: 12
        color: Theme.warning
    }

    Text {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.keepAwake
        text: "󰅶"
        font.family: Theme.iconFont
        font.pixelSize: 12
        color: Theme.tertiary
    }

    // Hardware-Aware Battery Chip (Laptops only)
    RowLayout {
        Layout.alignment: Qt.AlignVCenter
        spacing: 4
        visible: root.hasBatteryChip

        Text {
            text: DeviceCaps.batteryIcon
            font.family: Theme.iconFont
            font.pixelSize: 13
            color: DeviceCaps.batteryLow
                ? Theme.error
                : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant)

            Behavior on color {
                enabled: !Theme.isSimple
                ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        Text {
            text: DeviceCaps.batteryPercent + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: DeviceCaps.batteryLow
                ? Theme.error
                : (DeviceCaps.batteryCharging ? Theme.success : Theme.fgSurfaceVariant)

            Behavior on color {
                enabled: !Theme.isSimple
                ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }

    // Live File Manager Operation Progress Pill (only during copy/move/compress/extract)
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.fmOpActive
        implicitHeight: 20
        implicitWidth: fmOpRow.implicitWidth + 10
        radius: Theme.r(7)
        color: Theme.withAlpha(Theme.primary, 0.22)
        border.width: 1
        border.color: Theme.primary

        RowLayout {
            id: fmOpRow
            anchors.centerIn: parent
            spacing: 4
            Text { text: "󰉋"; font.family: Theme.iconFont; font.pixelSize: 11; color: Theme.primary }
            Text {
                text: Math.round(ShellState.fmOpProgress * 100) + "%"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                color: Theme.primary
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.filesClicked()
        }
    }

    // Inline System Tray (when enabled & populated)
    SystemTrayStrip {
        id: trayStrip
        Layout.alignment: Qt.AlignVCenter
        visible: root.hasTrayChip
        compact: true
    }

    // Quick Files Manager Icon
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowFiles || ShellState.barShowQuickIcons
        implicitWidth: 22
        implicitHeight: 22
        radius: Theme.r(7)
        color: filesBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

        Text {
            anchors.centerIn: parent
            text: "󰉋"
            font.family: Theme.iconFont
            font.pixelSize: 12
            color: filesBtnMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
        }

        MouseArea {
            id: filesBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.filesClicked()
        }
    }

    // Quick Settings Icon
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: ShellState.barShowQuickIcons
        implicitWidth: 22
        implicitHeight: 22
        radius: Theme.r(7)
        color: gearBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

        Text {
            anchors.centerIn: parent
            text: "󰒓"
            font.family: Theme.iconFont
            font.pixelSize: 12
            color: gearBtnMouse.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
        }

        MouseArea {
            id: gearBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.settingsClicked()
        }
    }
}
