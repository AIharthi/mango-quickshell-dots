pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".."

Item {
    id: root

    property string layoutMode: "cupertino"       // "cupertino" | "stage" | "cockpit"
    property bool active: false
    property string screenName: ""
    property var player: null

    signal openSettingsRequested(string page)
    signal controlInteractionChanged(bool interacting)

    // --- Live MangoWC Tag Stream ---
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
    readonly property int totalClients: {
        let sum = 0;
        const arr = root.tagsModel || [];
        for (let i = 0; i < arr.length; i++)
            sum += (arr[i].client_count || 0);
        return sum;
    }

    // --- Live Telemetry (for Cupertino & Stage Activity Rings) ---
    property real cpuPercent: 0
    property real _prevTotal: 0
    property real _prevIdle: 0
    property real ramPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property int cpuTempC: -1
    property real diskPercent: 0

    // --- Live Audio State (for Connectivity Platter & Stage Volume) ---
    property real volumeLevel: 0.5
    property bool volumeMuted: false
    property string defaultSinkLabel: "Audio Output"
    property bool _dragging: false

    // --- Live MPRIS Helpers (for Stage & Cockpit hero players) ---
    readonly property bool hasPlayer: root.player !== null
    readonly property bool isPlaying: root.player !== null && root.player.isPlaying
    readonly property real trackLength: (root.player && root.player.length > 0) ? root.player.length : 0
    readonly property string artUrl: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
    property real displayPosition: 0

    function formatTime(secs: real): string {
        if (!secs || secs < 0 || isNaN(secs))
            return "0:00";
        const total = Math.floor(secs);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    onPlayerChanged: {
        root.displayPosition = (root.player && root.player.position >= 0) ? root.player.position : 0;
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged(): void {
            if (!stageSeekMouse.pressed && root.player)
                root.displayPosition = root.player.position;
        }
        function onPostTrackChanged(): void {
            if (root.player)
                root.displayPosition = root.player.position || 0;
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.isPlaying && (root.layoutMode === "stage" || root.layoutMode === "cockpit") && !stageSeekMouse.pressed
        onTriggered: {
            if (!root.player)
                return;
            if (root.player.position >= 0 && Math.abs(root.player.position - root.displayPosition) > 2.5)
                root.displayPosition = root.player.position;
            else if (root.trackLength > 0)
                root.displayPosition = Math.min(root.trackLength, root.displayPosition + 1);
            else
                root.displayPosition += 1;
        }
    }

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

    function parseTelemetry(raw: string): void {
        const parts = (raw || "").split("---");
        if (parts.length >= 1) {
            const firstLine = (parts[0].trim().split("\n")[0] || "");
            if (firstLine.startsWith("cpu ")) {
                const cols = firstLine.trim().split(/\s+/);
                if (cols.length >= 5) {
                    const user = parseFloat(cols[1]) || 0;
                    const nice = parseFloat(cols[2]) || 0;
                    const sys = parseFloat(cols[3]) || 0;
                    const idle = parseFloat(cols[4]) || 0;
                    const iowait = parseFloat(cols[5]) || 0;
                    const irq = parseFloat(cols[6]) || 0;
                    const softirq = parseFloat(cols[7]) || 0;
                    const steal = parseFloat(cols[8]) || 0;
                    const idleAll = idle + iowait;
                    const totalAll = user + nice + sys + idleAll + irq + softirq + steal;
                    if (root._prevTotal > 0 && totalAll > root._prevTotal) {
                        const dTot = totalAll - root._prevTotal;
                        const dIdle = idleAll - root._prevIdle;
                        root.cpuPercent = Math.max(0, Math.min(100, ((dTot - dIdle) / dTot) * 100));
                    }
                    root._prevTotal = totalAll;
                    root._prevIdle = idleAll;
                }
            }
        }
        if (parts.length >= 2) {
            let totalKb = 0;
            let availKb = -1;
            let freeKb = 0;
            let buffersKb = 0;
            let cachedKb = 0;
            const lines = parts[1].trim().split("\n");
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i];
                if (ln.startsWith("MemTotal:")) totalKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("MemAvailable:")) availKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("MemFree:")) freeKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("Buffers:")) buffersKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("Cached:")) cachedKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
            }
            if (totalKb > 0) {
                if (availKb < 0)
                    availKb = freeKb + buffersKb + cachedKb;
                const usedKb = Math.max(0, totalKb - availKb);
                root.ramTotalGb = totalKb / (1024 * 1024);
                root.ramUsedGb = usedKb / (1024 * 1024);
                root.ramPercent = Math.max(0, Math.min(100, (usedKb / totalKb) * 100));
            }
        }
        if (parts.length >= 3) {
            const metaLines = parts[2].trim().split("\n");
            for (let j = 0; j < metaLines.length; j++) {
                const ml = metaLines[j].trim();
                if (ml.startsWith("DISK:")) {
                    root.diskPercent = Math.max(0, Math.min(100, parseFloat(ml.slice(5)) || 0));
                } else if (ml.startsWith("TEMP:")) {
                    const rt = parseInt(ml.slice(5), 10) || 0;
                    const deg = rt > 1000 ? Math.round(rt / 1000) : Math.round(rt);
                    if (deg > 0 && deg < 150)
                        root.cpuTempC = deg;
                }
            }
        }
    }

    function applyVolume(ratio: real): void {
        const cap = ShellState.audioOverAmp ? 1.5 : 1.0;
        const clamped = Math.max(0.0, Math.min(cap, ratio));
        root.volumeLevel = clamped;
        if (!volThrottle.running)
            volThrottle.start();
    }

    Timer {
        id: volThrottle
        interval: 60
        repeat: false
        onTriggered: {
            const pct = Math.round(root.volumeLevel * 100);
            Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", pct + "%"]);
        }
    }

    Process {
        id: tagStream
        command: ["mmsg", "watch", "all-tags"]
        running: root.active
        stdout: SplitParser {
            onRead: line => root.parseTagsJson(line)
        }
    }

    Process {
        id: metaProc
        command: [
            "sh", "-c",
            "head -n 1 /proc/stat; echo '---'; grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached):' /proc/meminfo; echo '---'; " +
            "df -P / 2>/dev/null | awk 'NR==2{print \"DISK:\" $5}' || true; " +
            "for t in /sys/class/hwmon/hwmon*/temp1_input /sys/class/thermal/thermal_zone*/temp; do " +
            "[ -r \"$t\" ] && v=$(cat \"$t\" 2>/dev/null) && [ -n \"$v\" ] && [ \"$v\" -gt 10000 ] 2>/dev/null && echo \"TEMP:$v\" && break; done || true; " +
            "echo '---VOL---'; pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null || true; echo '---MUTE---'; pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null || true; echo '---SINK---'; " +
            "def=$(pactl get-default-sink 2>/dev/null || true); " +
            "[ -n \"$def\" ] && pactl list sinks 2>/dev/null | awk -v d=\"$def\" '$1==\"Name:\" {m=($2==d)} m && /Description:/ {sub(/.*Description: /, \"\"); print; exit}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text || "";
                const volSplit = raw.split("---VOL---");
                root.parseTelemetry(volSplit[0] || "");
                if (volSplit.length >= 2) {
                    const mSplit = volSplit[1].split("---MUTE---");
                    const vm = (mSplit[0] || "").match(/(\d+)%/);
                    if (vm && vm[1] && !root._dragging)
                        root.volumeLevel = Math.max(0.0, Math.min(1.5, parseInt(vm[1], 10) / 100.0));
                    if (mSplit.length >= 2) {
                        const sSplit = mSplit[1].split("---SINK---");
                        root.volumeMuted = (sSplit[0] || "").toLowerCase().indexOf("yes") !== -1;
                        if (sSplit.length >= 2) {
                            const lbl = (sSplit[1] || "").trim();
                            if (lbl.length > 0)
                                root.defaultSinkLabel = lbl;
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 1800
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!metaProc.running)
                metaProc.running = true;
        }
    }

    Process {
        id: sinkCycleProc
        command: [
            "sh", "-c",
            "cur=$(pactl get-default-sink 2>/dev/null); mapfile -t s < <(pactl list short sinks 2>/dev/null | awk '{print $2}'); [ ${#s[@]} -lt 2 ] && exit 0; for i in \"${!s[@]}\"; do if [ \"${s[$i]}\" = \"$cur\" ]; then next=$(( (i + 1) % ${#s[@]} )); pactl set-default-sink \"${s[$next]}\"; break; fi; done"
        ]
        onExited: {
            if (!metaProc.running)
                metaProc.running = true;
        }
    }

    // --- Reusable Inline Component: Apple Activity Ring Gauge ---
    component ActivityRing : Item {
        id: ringItem
        property real percent: 0
        property color ringColor: Theme.primary
        property string centerLabel: "0%"
        property string titleLabel: "CPU"
        property string detailLabel: ""

        clip: true
        onPercentChanged: ringCanvas.requestPaint()
        onRingColorChanged: ringCanvas.requestPaint()

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 3

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 58
                implicitHeight: 58

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    antialiasing: true

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const cx = width / 2;
                        const cy = height / 2;
                        const rad = Math.min(cx, cy) - 5;
                        const trackCol = Theme.surfaceContainerHighest;

                        ctx.lineCap = "round";
                        ctx.lineWidth = 6.0;

                        ctx.beginPath();
                        ctx.arc(cx, cy, rad, 0, Math.PI * 2, false);
                        ctx.strokeStyle = Qt.rgba(trackCol.r, trackCol.g, trackCol.b, 0.72);
                        ctx.stroke();

                        const frac = Math.max(0.02, Math.min(1.0, ringItem.percent / 100.0));
                        const startA = -Math.PI / 2;
                        const endA = startA + frac * Math.PI * 2;
                        ctx.beginPath();
                        ctx.arc(cx, cy, rad, startA, endA, false);
                        ctx.strokeStyle = ringItem.ringColor;
                        ctx.stroke();
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: ringItem.centerLabel
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: ringItem.titleLabel
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurface
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(60, ringItem.width - 8)
                elide: Text.ElideRight
                visible: ringItem.detailLabel.length > 0
                text: ringItem.detailLabel
                font.family: Theme.fontFamily
                font.pixelSize: 9
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- Reusable Inline Component: Apple Mission Control Spaces Capsule ---
    component SpacesCapsule : Rectangle {
        id: scRoot
        property var model: root.tagsModel
        property string layoutCode: root.currentLayout
        property int winsCount: root.totalClients

        implicitHeight: 46
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            // Unified Apple pill track wrapping 1..9 workspaces
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 30
                radius: Theme.r(15)
                color: Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 2

                    Repeater {
                        model: scRoot.model

                        delegate: Rectangle {
                            id: spBtn
                            required property var modelData
                            readonly property bool isActive: spBtn.modelData.is_active
                            readonly property bool isUrgent: spBtn.modelData.is_urgent
                            readonly property bool isOccupied: spBtn.modelData.client_count > 0

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumWidth: 16
                            radius: Theme.r(13)
                            color: {
                                if (spBtn.isUrgent) return Theme.error;
                                if (spBtn.isActive) return Theme.primary;
                                if (spMouse.containsMouse) return Theme.hoverBg;
                                if (spBtn.isOccupied) return Theme.withAlpha(Theme.primary, 0.16);
                                return "transparent";
                            }
                            scale: spMouse.pressed ? 0.92 : 1.0
                            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    text: spBtn.modelData.index
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: spBtn.isActive ? Font.Bold : Font.DemiBold
                                    color: spBtn.isActive ? Theme.fgPrimary : (spBtn.isOccupied ? Theme.fgSurface : Theme.fgSurfaceVariant)
                                }

                                Rectangle {
                                    visible: spBtn.isOccupied && !spBtn.isActive
                                    implicitWidth: 4
                                    implicitHeight: 4
                                    radius: 2
                                    color: Theme.secondary
                                }
                            }

                            MouseArea {
                                id: spMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + spBtn.modelData.index + ",0"])
                            }
                        }
                    }
                }
            }

            // Layout Pill
            Rectangle {
                Layout.fillHeight: false
                implicitHeight: 28
                implicitWidth: Math.max(24, layTagTxt.implicitWidth + 10)
                radius: Theme.r(14)
                color: layTagMouse.containsMouse ? Theme.activeBg : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                Text {
                    id: layTagTxt
                    anchors.centerIn: parent
                    text: scRoot.layoutCode
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.primary
                }

                MouseArea {
                    id: layTagMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                }
            }

            // Window Switcher Pill
            Rectangle {
                Layout.fillHeight: false
                implicitHeight: 28
                implicitWidth: winPillRow.implicitWidth + 12
                radius: Theme.r(14)
                color: winPillMouse.containsMouse ? Theme.withAlpha(Theme.secondary, 0.24) : Theme.subCardBg
                border.width: Theme.cardBorderWidth
                border.color: winPillMouse.containsMouse ? Theme.secondary : Theme.cardBorder

                RowLayout {
                    id: winPillRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.secondary }
                    Text {
                        text: scRoot.winsCount > 0 ? String(scRoot.winsCount) : "0"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }
                }

                MouseArea {
                    id: winPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Quickshell.execDetached(["mmsg", "dispatch", "toggleoverview"]);
                        else
                            Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
                    }
                }
            }
        }
    }

    // ==================== LAYOUT 1: CUPERTINO (macOS Control Center) ====================
    RowLayout {
        anchors.fill: parent
        visible: root.layoutMode === "cupertino"
        spacing: 10

        // Left Column: 2x2 Connectivity/Focus Platter + MediaCard
        ColumnLayout {
            Layout.preferredWidth: 312
            Layout.minimumWidth: 300
            Layout.maximumWidth: 316
            Layout.fillHeight: true
            spacing: 10

            // 2x2 Apple Connectivity & Focus Grid Platter
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 122
                Layout.minimumHeight: 122
                Layout.maximumHeight: 122
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8

                    Repeater {
                        model: [
                            {
                                id: "sink",
                                icon: "󰋋",
                                title: "Output",
                                sub: root.defaultSinkLabel,
                                active: !root.volumeMuted,
                                tint: Theme.primary
                            },
                            {
                                id: "dnd",
                                icon: ShellState.dnd ? "󰂛" : "󰂚",
                                title: "Focus",
                                sub: ShellState.dnd ? "Do Not Disturb" : "Notifications On",
                                active: ShellState.dnd,
                                tint: Theme.secondary
                            },
                            {
                                id: "awake",
                                icon: "󰅶",
                                title: "Keep Awake",
                                sub: ShellState.keepAwake ? "Idle Paused" : "Auto-Lock On",
                                active: ShellState.keepAwake,
                                tint: Theme.warning
                            },
                            {
                                id: "game",
                                icon: "󰊴",
                                title: "Game Mode",
                                sub: ShellState.gameModeActive ? "Boost Active" : "Standard",
                                active: ShellState.gameModeActive,
                                tint: Theme.tertiary
                            }
                        ]

                        delegate: Rectangle {
                            id: ccTile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.r(12)
                            color: ccMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                            border.width: ccTile.modelData.active ? 1 : Theme.cardBorderWidth
                            border.color: ccTile.modelData.active ? Theme.withAlpha(ccTile.modelData.tint, 0.55) : Theme.cardBorder
                            clip: true
                            scale: ccMouse.pressed ? 0.95 : 1.0

                            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Rectangle {
                                    implicitWidth: 30
                                    implicitHeight: 30
                                    radius: Theme.r(15)
                                    color: ccTile.modelData.active
                                        ? ccTile.modelData.tint
                                        : Theme.surfaceContainerHighest

                                    Text {
                                        anchors.centerIn: parent
                                        text: ccTile.modelData.icon
                                        font.family: Theme.iconFont
                                        font.pixelSize: 14
                                        color: ccTile.modelData.active ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: ccTile.modelData.title
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: Theme.fgSurface
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: ccTile.modelData.sub
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        color: ccTile.modelData.active ? ccTile.modelData.tint : Theme.fgSurfaceVariant
                                    }
                                }
                            }

                            MouseArea {
                                id: ccMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    const cid = ccTile.modelData.id;
                                    if (cid === "sink") {
                                        if (mouse.button === Qt.RightButton)
                                            root.openSettingsRequested("audio");
                                        else if (!sinkCycleProc.running)
                                            sinkCycleProc.running = true;
                                    } else if (cid === "dnd") {
                                        ShellState.toggleDnd();
                                    } else if (cid === "awake") {
                                        ShellState.toggleKeepAwake();
                                    } else if (cid === "game") {
                                        ShellState.toggleGameMode();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Now Playing Media Platter
            MediaCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 200
                player: root.player
                active: root.active && root.layoutMode === "cupertino"
                onSeekingChanged: seeking => root.controlInteractionChanged(seeking)
            }
        }

        // Right Column: Apple Quick Controls + Spaces Capsule & Activity Rings
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            QuickControls {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: DeviceCaps.hasExtraQuickControls ? 248 : 210
                Layout.minimumHeight: DeviceCaps.hasExtraQuickControls ? 244 : 206
                Layout.maximumHeight: DeviceCaps.hasExtraQuickControls ? 252 : 214
                active: root.active && root.layoutMode === "cupertino"
                onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }

            SpacesCapsule {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 46
                Layout.minimumHeight: 46
                Layout.maximumHeight: 46
            }

            // Apple Activity Rings Telemetry Platter
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 118
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    ActivityRing {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        percent: root.cpuPercent
                        ringColor: root.cpuPercent > 85 ? Theme.error : Theme.primary
                        centerLabel: Math.round(root.cpuPercent) + "%"
                        titleLabel: "CPU Load"
                        detailLabel: root.cpuTempC > 0 ? (root.cpuTempC + "°C") : "Live"
                    }

                    ActivityRing {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        percent: root.ramPercent
                        ringColor: root.ramPercent > 85 ? Theme.warning : Theme.secondary
                        centerLabel: Math.round(root.ramPercent) + "%"
                        titleLabel: "Memory"
                        detailLabel: root.ramUsedGb.toFixed(1) + " / " + root.ramTotalGb.toFixed(0) + "G"
                    }

                    ActivityRing {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        percent: DeviceCaps.hasBattery ? DeviceCaps.batteryPercent : root.diskPercent
                        ringColor: DeviceCaps.hasBattery
                            ? (DeviceCaps.batteryLow ? Theme.error : Theme.success)
                            : Theme.tertiary
                        centerLabel: DeviceCaps.hasBattery
                            ? (DeviceCaps.batteryPercent + "%")
                            : (Math.round(root.diskPercent) + "%")
                        titleLabel: DeviceCaps.hasBattery ? "Battery" : "Disk /"
                        detailLabel: DeviceCaps.hasBattery ? DeviceCaps.batteryStatus : "Mounted"
                    }
                }
            }
        }
    }

    // ==================== LAYOUT 2: STAGE (Apple Music Hero + Live Pods) ====================
    RowLayout {
        anchors.fill: parent
        visible: root.layoutMode === "stage"
        spacing: 10

        // Left Hero Stage: Large Album Art, Lyrics-feel Typography & Scrubber
        ClippingRectangle {
            Layout.preferredWidth: 294
            Layout.minimumWidth: 286
            Layout.maximumWidth: 298
            Layout.fillHeight: true
            radius: Theme.r(20)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            contentUnderBorder: false
            contentInsideBorder: true

            Image {
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(160, 160)
                opacity: (root.artUrl.length > 0 && status === Image.Ready && !Theme.isSimple) ? 0.18 : 0.0
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.16) }
                    GradientStop { position: 0.6; color: "transparent" }
                    GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainerLowest, 0.45) }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false

                    Rectangle {
                        implicitHeight: 20
                        implicitWidth: stageBadge.implicitWidth + 12
                        radius: Theme.r(10)
                        color: root.isPlaying ? Theme.withAlpha(Theme.primary, 0.25) : Theme.subCardBg
                        border.width: 1
                        border.color: root.isPlaying ? Theme.withAlpha(Theme.primary, 0.50) : Theme.cardBorder

                        Text {
                            id: stageBadge
                            anchors.centerIn: parent
                            text: root.hasPlayer ? (root.player.identity || "NOW PLAYING").toUpperCase() : "STAGE PLAYER"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: root.isPlaying ? Theme.primary : Theme.fgSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.isPlaying ? "● LIVE" : "READY"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: root.isPlaying ? Theme.success : Theme.fgSurfaceVariant
                    }
                }

                Item { Layout.fillHeight: true }

                ClippingRectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 104
                    implicitHeight: 104
                    radius: Theme.r(20)
                    color: Theme.primaryContainer
                    border.width: root.isPlaying ? 2 : 0
                    border.color: Theme.primary
                    contentUnderBorder: false
                    contentInsideBorder: true

                    Image {
                        id: stageArtImg
                        anchors.fill: parent
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(220, 220)
                        visible: root.artUrl.length > 0 && status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !stageArtImg.visible
                        text: "󰓇"
                        font.family: Theme.iconFont
                        font.pixelSize: 42
                        color: Theme.fgPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: (root.player && root.player.trackTitle) ? root.player.trackTitle : "Nothing Playing"
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: {
                            if (!root.player)
                                return "Start Spotify or any MPRIS app";
                            return root.player.trackArtist || root.player.trackAlbum || "Connected";
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurfaceVariant
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 4

                    Item {
                        id: stageSeekItem
                        Layout.fillWidth: true
                        implicitHeight: 14
                        readonly property real ratio: (root.trackLength > 0)
                            ? Math.max(0.0, Math.min(1.0, root.displayPosition / root.trackLength))
                            : 0.0

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 5
                            radius: Theme.r(2.5)
                            color: Theme.surfaceContainerHighest

                            Rectangle {
                                height: parent.height
                                width: parent.width * stageSeekItem.ratio
                                radius: Theme.r(2.5)
                                color: Theme.primary
                            }
                        }

                        MouseArea {
                            id: stageSeekMouse
                            anchors.fill: parent
                            enabled: root.hasPlayer && root.player.canSeek && root.player.positionSupported && root.trackLength > 0
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            function seekAt(mx: real): void {
                                const r = Math.max(0.0, Math.min(1.0, mx / width));
                                const sec = r * root.trackLength;
                                root.displayPosition = sec;
                                root.player.seek(sec - (root.player.position || 0));
                            }
                            onPressed: m => { root.controlInteractionChanged(true); seekAt(m.x); }
                            onPositionChanged: m => { if (pressed) seekAt(m.x); }
                            onReleased: root.controlInteractionChanged(false)
                            onCanceled: root.controlInteractionChanged(false)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: root.formatTime(root.displayPosition); font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                        Item { Layout.fillWidth: true }
                        Text { text: root.formatTime(root.trackLength); font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 14
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: Theme.r(18)
                        color: stPrevMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        opacity: (root.hasPlayer && root.player.canGoPrevious) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰒮"; font.family: Theme.iconFont; font.pixelSize: 17; color: Theme.fgSurface }
                        MouseArea { id: stPrevMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoPrevious; cursorShape: Qt.PointingHandCursor; onClicked: root.player.previous() }
                    }

                    Rectangle {
                        implicitWidth: 48; implicitHeight: 40; radius: Theme.r(20)
                        color: stPlayMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                        opacity: (root.hasPlayer && root.player.canTogglePlaying) ? 1.0 : 0.50
                        Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 20; color: Theme.fgPrimary }
                        MouseArea { id: stPlayMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canTogglePlaying; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                    }

                    Rectangle {
                        implicitWidth: 36; implicitHeight: 36; radius: Theme.r(18)
                        color: stNextMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        opacity: (root.hasPlayer && root.player.canGoNext) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰒭"; font.family: Theme.iconFont; font.pixelSize: 17; color: Theme.fgSurface }
                        MouseArea { id: stNextMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
                    }

                    Item { Layout.fillWidth: true }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Right Column: Spaces Strip + Quick Control Capsule Card + Activity Rings
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            SpacesCapsule {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 46
                Layout.minimumHeight: 46
                Layout.maximumHeight: 46
            }

            // Clean Audio & Action Platter
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 158
                Layout.minimumHeight: 158
                Layout.maximumHeight: 158
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Apple Capsule Volume Slider
                    Item {
                        id: stVolCap
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 34

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.r(17)
                            color: Theme.subCardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder
                            clip: true

                            Rectangle {
                                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                width: root.volumeLevel <= 0.001 ? 0 : Math.max(parent.height, parent.width * Math.min(1.0, root.volumeLevel))
                                radius: Theme.r(17)
                                color: root.volumeMuted ? Theme.surfaceContainerHighest : Theme.primary
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 6
                                Text {
                                    text: root.volumeMuted ? "󰝟" : "󰕾"
                                    font.family: Theme.iconFont; font.pixelSize: 15
                                    color: root.volumeMuted ? Theme.error : Theme.fgPrimary
                                }
                                Text { text: root.volumeMuted ? "Muted" : "Sound"; Layout.fillWidth: true; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.volumeLevel > 0.25 && !root.volumeMuted ? Theme.fgPrimary : Theme.fgSurface }
                                Text { text: Math.round(root.volumeLevel * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.volumeLevel > 0.88 && !root.volumeMuted ? Theme.fgPrimary : Theme.fgSurface }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: m => { root._dragging = true; root.controlInteractionChanged(true); root.applyVolume(m.x / stVolCap.width); }
                                onPositionChanged: m => { if (pressed) root.applyVolume(m.x / stVolCap.width); }
                                onReleased: { root._dragging = false; root.controlInteractionChanged(false); }
                                onCanceled: { root._dragging = false; root.controlInteractionChanged(false); }
                            }
                        }
                    }

                    // 4 Balanced Apple Action Pills
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "dnd",   icon: "󰂛", label: "Focus",   active: ShellState.dnd, tint: Theme.secondary },
                                { id: "awake", icon: "󰅶", label: "Awake",   active: ShellState.keepAwake, tint: Theme.warning },
                                { id: "shot",  icon: "󰹑", label: "Capture", active: false, tint: Theme.primary },
                                { id: "game",  icon: "󰊴", label: "Game",    active: ShellState.gameModeActive, tint: Theme.tertiary }
                            ]

                            delegate: Rectangle {
                                id: stAct
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: Theme.r(12)
                                color: stAct.modelData.active ? Theme.withAlpha(stAct.modelData.tint, 0.24) : (stActMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                border.width: stAct.modelData.active ? 1 : Theme.cardBorderWidth
                                border.color: stAct.modelData.active ? stAct.modelData.tint : Theme.cardBorder

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Text { Layout.alignment: Qt.AlignHCenter; text: stAct.modelData.icon; font.family: Theme.iconFont; font.pixelSize: 14; color: stAct.modelData.active ? stAct.modelData.tint : Theme.fgSurfaceVariant }
                                    Text { Layout.alignment: Qt.AlignHCenter; text: stAct.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; color: stAct.modelData.active ? stAct.modelData.tint : Theme.fgSurface }
                                }

                                MouseArea {
                                    id: stActMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const sid = stAct.modelData.id;
                                        if (sid === "dnd") ShellState.toggleDnd();
                                        else if (sid === "awake") ShellState.toggleKeepAwake();
                                        else if (sid === "shot") Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--area"]);
                                        else if (sid === "game") ShellState.toggleGameMode();
                                    }
                                }
                            }
                        }
                    }

                    // Bottom bar: Recording + Settings link
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: ShellState.recordingActive ? Theme.withAlpha(Theme.error, 0.24) : (stRecMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: ShellState.recordingActive ? 1 : Theme.cardBorderWidth
                            border.color: ShellState.recordingActive ? Theme.error : Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                text: ShellState.recordingActive ? "󰑊 Stop Recording" : "󰑊 Record Screen"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: ShellState.recordingActive ? Theme.error : Theme.fgSurface
                            }

                            MouseArea {
                                id: stRecMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"])
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: stAppMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                            border.width: Theme.cardBorderWidth; border.color: Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                text: "Appearance →"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: Theme.primary
                            }

                            MouseArea {
                                id: stAppMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.openSettingsRequested("appearance")
                            }
                        }
                    }
                }
            }

            // Activity Rings
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 136
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    ActivityRing {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        percent: root.cpuPercent
                        ringColor: root.cpuPercent > 85 ? Theme.error : Theme.primary
                        centerLabel: Math.round(root.cpuPercent) + "%"
                        titleLabel: "CPU Load"
                        detailLabel: root.cpuTempC > 0 ? (root.cpuTempC + "°C") : "Live"
                    }

                    ActivityRing {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        percent: root.ramPercent
                        ringColor: root.ramPercent > 85 ? Theme.warning : Theme.secondary
                        centerLabel: Math.round(root.ramPercent) + "%"
                        titleLabel: "Memory"
                        detailLabel: root.ramUsedGb.toFixed(1) + "G"
                    }

                    ActivityRing {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        percent: DeviceCaps.hasBattery ? DeviceCaps.batteryPercent : root.diskPercent
                        ringColor: DeviceCaps.hasBattery ? Theme.success : Theme.tertiary
                        centerLabel: DeviceCaps.hasBattery ? (DeviceCaps.batteryPercent + "%") : (Math.round(root.diskPercent) + "%")
                        titleLabel: DeviceCaps.hasBattery ? "Battery" : "Disk /"
                        detailLabel: DeviceCaps.hasBattery ? DeviceCaps.batteryStatus : "Root"
                    }
                }
            }
        }
    }

    // ==================== LAYOUT 3: COCKPIT (Pro Telemetry Ribbon + Dual Platters) ====================
    ColumnLayout {
        anchors.fill: parent
        visible: root.layoutMode === "cockpit"
        spacing: 10

        // Top Unified Media + Mission Control Spaces Ribbon (explicitly locked to 60px!)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 60
            Layout.minimumHeight: 60
            Layout.maximumHeight: 60
            spacing: 10

            // Compact Horizontal Media Capsule
            Rectangle {
                Layout.preferredWidth: 270
                Layout.minimumWidth: 250
                Layout.maximumWidth: 276
                Layout.fillHeight: true
                radius: Theme.r(16)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    ClippingRectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: Theme.r(10)
                        color: Theme.primaryContainer
                        contentUnderBorder: false
                        contentInsideBorder: true

                        Image {
                            id: ckArtImg
                            anchors.fill: parent
                            source: root.artUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(96, 96)
                            visible: root.artUrl.length > 0 && status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !ckArtImg.visible
                            text: "󰓇"
                            font.family: Theme.iconFont; font.pixelSize: 19; color: Theme.fgPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: (root.player && root.player.trackTitle) ? root.player.trackTitle : "Nothing Playing"
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold; color: Theme.fgSurface
                        }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: root.player ? (root.player.trackArtist || root.player.identity || "MPRIS") : "Open Spotify or media"
                            font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(14)
                        color: ckPlayMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                        opacity: (root.hasPlayer && root.player.canTogglePlaying) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 14; color: Theme.fgPrimary }
                        MouseArea { id: ckPlayMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canTogglePlaying; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                    }

                    Rectangle {
                        implicitWidth: 26; implicitHeight: 26; radius: Theme.r(13)
                        color: ckNextMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        opacity: (root.hasPlayer && root.player.canGoNext) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰒭"; font.family: Theme.iconFont; font.pixelSize: 13; color: Theme.fgSurface }
                        MouseArea { id: ckNextMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
                    }
                }
            }

            SpacesCapsule {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        // Bottom Dual Platter: Full Pro System Monitor + Apple Quick Controls
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 240
            spacing: 10

            SystemMonitor {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                active: root.active && root.layoutMode === "cockpit"
            }

            QuickControls {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                active: root.active && root.layoutMode === "cockpit"
                onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }
        }
    }
}
