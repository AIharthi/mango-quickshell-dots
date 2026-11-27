pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."
import "../m3"

Item {
    id: root

    property string layoutMode: "cupertino"       // "cupertino" | "stage" | "cockpit"
    property bool active: false
    property string screenName: ""
    property var player: null

    signal openSettingsRequested(string page)
    signal controlInteractionChanged(bool interacting)

    // --- Shared Live MangoWC Tag State (via MangoState) ---
    readonly property string currentLayout: MangoState.layoutForScreen(root.screenName)
    readonly property var tagsModel: MangoState.tagsForScreen(root.screenName)
    readonly property int totalClients: MangoState.totalClientsForScreen(root.screenName)

    // --- Live Telemetry (streamed by Rust aurora-backend SystemTelemetry) ---
    readonly property real cpuPercent: SystemTelemetry.cpuPercent
    readonly property real ramPercent: SystemTelemetry.memPercent
    readonly property real ramUsedGb: SystemTelemetry.memUsedGb
    readonly property real ramTotalGb: SystemTelemetry.memTotalGb
    readonly property int cpuTempC: SystemTelemetry.cpuTempC
    readonly property real diskPercent: SystemTelemetry.diskPercent
    readonly property string diskFreeLabel: SystemTelemetry.diskFreeLabel

    // --- Shared PipeWire Audio State (via MangoState) ---
    property real _dragRatio: 0.5
    readonly property real volumeLevel: root._dragging ? root._dragRatio : (MangoState.volPercent / 100.0)
    readonly property bool volumeMuted: MangoState.volMuted
    readonly property string defaultSinkLabel: MangoState.defaultSinkLabel
    property bool _dragging: false
    property bool _seeking: false

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
            if (!root._seeking && root.player)
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
        running: root.active && root.isPlaying && (root.layoutMode === "stage" || root.layoutMode === "cockpit") && !root._seeking
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

    function applyVolume(ratio: real): void {
        const cap = ShellState.audioOverAmp ? 1.5 : 1.0;
        const clamped = Math.max(0.0, Math.min(cap, ratio));
        root._dragRatio = clamped;
        MangoState.setVolumeRatio(clamped);
    }

    // --- Reusable Inline Component: Horizontal Metric Cell (for Stage Telemetry Deck) ---
    component MetricCell : ColumnLayout {
        id: mc
        property string label: ""
        property string detail: ""
        property real percent: 0
        property string valueText: "0%"
        property color barColor: Theme.primary

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: mc.label
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            Text {
                elide: Text.ElideRight
                Layout.maximumWidth: 72
                text: mc.detail
                font.family: Theme.monoFont
                font.pixelSize: 9
                color: Theme.fgSurfaceVariant
            }
        }

        Text {
            text: mc.valueText
            font.family: Theme.monoFont
            font.pixelSize: 16
            font.weight: Font.Bold
            color: Theme.fgSurface
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: Theme.surfaceContainerHighest

            Rectangle {
                height: parent.height
                radius: 2
                width: parent.width * (Math.max(0.0, Math.min(100.0, mc.percent)) / 100.0)
                color: mc.barColor

                Behavior on width {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // --- Reusable Inline Component: Activity Ring Gauge ---
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
            spacing: 2

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 50
                implicitHeight: 50

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    antialiasing: true

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const cx = width / 2;
                        const cy = height / 2;
                        const rad = Math.min(cx, cy) - 4;
                        const trackCol = Theme.surfaceContainerHighest;

                        ctx.lineCap = "round";
                        ctx.lineWidth = 5.0;

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
                    font.family: Theme.monoFont
                    font.pixelSize: 10
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

    // --- Reusable Inline Component: Mission Control Spaces Capsule ---
    component SpacesCapsule : Rectangle {
        id: scRoot
        property var model: root.tagsModel
        property string layoutCode: root.currentLayout
        property int winsCount: root.totalClients

        implicitHeight: 44
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

            // Unified pill track wrapping 1..9 workspaces
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 28
                radius: Theme.r(14)
                color: Theme.subCardBg
                border.width: Theme.activeControlBorderWidth
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
                            radius: Theme.r(12)
                            color: {
                                if (spBtn.isUrgent) return Theme.error;
                                if (spBtn.isActive) return Theme.primary;
                                if (spMouse.containsMouse) return Theme.tileActiveBg;
                                if (spBtn.isOccupied) return Theme.controlFillHover;
                                return "transparent";
                            }
                            scale: spMouse.pressed ? 0.92 : 1.0
                            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    text: spBtn.modelData.index
                                    font.family: Theme.monoFont
                                    font.pixelSize: 10
                                    font.weight: spBtn.isActive ? Font.Bold : Font.DemiBold
                                    color: {
                                        if (spBtn.isUrgent) return Theme.fgError;
                                        if (spBtn.isActive) return Theme.fgPrimary;
                                        return spBtn.isOccupied ? Theme.fgSurface : Theme.fgSurfaceVariant;
                                    }
                                }

                                Rectangle {
                                    visible: spBtn.isOccupied && !spBtn.isActive
                                    implicitWidth: 3
                                    implicitHeight: 3
                                    radius: 1.5
                                    color: Theme.fgSurfaceVariant
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
                color: layTagMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                border.width: Theme.activeControlBorderWidth
                border.color: Theme.cardBorder

                Text {
                    id: layTagTxt
                    anchors.centerIn: parent
                    text: scRoot.layoutCode
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: layTagMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
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
                color: winPillMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                border.width: Theme.activeControlBorderWidth
                border.color: Theme.cardBorder

                RowLayout {
                    id: winPillRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: 12; color: winPillMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    Text {
                        text: scRoot.winsCount > 0 ? String(scRoot.winsCount) : "0"
                        font.family: Theme.monoFont
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
                            Qt.callLater(() => Quickshell.execDetached(["mmsg", "dispatch", "toggleoverview"]));
                        else
                            Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
                    }
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: true
        sourceComponent: root.layoutMode === "stage"
            ? stageLayoutComp
            : (root.layoutMode === "cockpit" ? cockpitLayoutComp : cupertinoLayoutComp)
    }

    // ==================== LAYOUT 1: CUPERTINO (macOS Control Center) ====================
    Component {
        id: cupertinoLayoutComp

        RowLayout {
            spacing: 10

        // Left Column: Borderless 2x2 Connectivity/Focus Platter + Snug MediaCard
        ColumnLayout {
            Layout.preferredWidth: 338
            Layout.minimumWidth: 326
            Layout.maximumWidth: 344
            Layout.fillHeight: true
            spacing: 10

            // 2x2 Control Center Platter (borderless elevated tiles + filled icon discs)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 118
                Layout.minimumHeight: 118
                Layout.maximumHeight: 118
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    columns: 2
                    rowSpacing: 7
                    columnSpacing: 7

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
                            color: ccTile.modelData.active
                                ? Theme.tileActiveBg
                                : (ccMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: ccTile.modelData.active ? Theme.activeControlBorderWidth : 0
                            border.color: ccTile.modelData.tint
                            clip: true
                            scale: ccMouse.pressed ? 0.95 : 1.0

                            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
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
                                        color: ccTile.modelData.active
                                            ? Theme.contrastInk(ccTile.modelData.tint)
                                            : Theme.fgSurfaceVariant
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: ccTile.modelData.title
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: ccTile.modelData.active ? Font.Bold : Font.DemiBold
                                        color: Theme.fgSurface
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: ccTile.modelData.sub
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 8
                                        color: Theme.fgSurfaceVariant
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
                                            Qt.callLater(() => root.openSettingsRequested("audio"));
                                        else
                                            MangoState.cycleAudioSink();
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
                Layout.minimumHeight: 154
                player: root.player
                active: root.active && root.layoutMode === "cupertino"
                onSeekingChanged: seeking => root.controlInteractionChanged(seeking)
            }
        }

        // Right Column: Capsule Sliders + Action Tiles, Spaces Strip, Activity Rings
        ColumnLayout {
            id: cupertinoRightCol
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            readonly property int qcH: 118 +
                (DeviceCaps.hasBacklight ? 38 : 0) +
                ((DeviceCaps.hasWifi || DeviceCaps.hasBluetooth) ? 42 : 0)

            QuickControls {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: cupertinoRightCol.qcH
                Layout.minimumHeight: cupertinoRightCol.qcH
                Layout.maximumHeight: cupertinoRightCol.qcH
                active: root.active && root.layoutMode === "cupertino"
                hideHeader: true
                hideStyleFooter: true
                hideDuplicateToggles: true
                tallActionTiles: true
                onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }

            SpacesCapsule {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 44
                Layout.minimumHeight: 44
                Layout.maximumHeight: 44
            }

            // Activity Rings Telemetry Platter
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 96
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    ActivityRing {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        percent: root.cpuPercent
                        ringColor: root.cpuPercent > 85 ? Theme.error : Theme.primary
                        centerLabel: Math.round(root.cpuPercent) + "%"
                        titleLabel: "CPU Load"
                        detailLabel: root.cpuTempC > 0 ? (root.cpuTempC + "°C") : "CPU"
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
                        detailLabel: DeviceCaps.hasBattery ? (DeviceCaps.batteryEta.length > 0 ? (DeviceCaps.batteryStatus + " · " + DeviceCaps.batteryEta) : DeviceCaps.batteryStatus) : (root.diskFreeLabel.length > 0 ? (root.diskFreeLabel + " free") : "Root /")
                    }
                }
            }
        }
        }
    }

    // ==================== LAYOUT 2: STAGE (Artwork Showcase + Controls & Metric Deck) ====================
    Component {
        id: stageLayoutComp

        RowLayout {
            spacing: 10

            // Left Media Showcase Card (Full-bleed top artwork + snug bottom playback bar)
            ClippingRectangle {
                Layout.preferredWidth: 276
                Layout.minimumWidth: 268
                Layout.maximumWidth: 282
                Layout.fillHeight: true
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                contentUnderBorder: false
                contentInsideBorder: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Artwork Showcase Area (M3WavyArc + spinning cookie M3ShapeImage)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        anchors.centerIn: parent
                        width: Math.min(138, parent.height - 14)
                        height: width

                        M3WavyArc {
                            anchors.fill: parent
                            value: (root.trackLength > 0) ? Math.max(0, Math.min(1, root.displayPosition / root.trackLength)) : 0
                            moving: root.active && root.isPlaying && root.layoutMode === "stage"
                            color: Theme.m3Primary
                            track: Theme.m3Track
                        }

                        M3ShapeImage {
                            anchors.centerIn: parent
                            width: Math.round(parent.width * 0.78)
                            height: width
                            kind: Theme.isSimple ? "square" : "cookie"
                            source: root.artUrl
                            empty: Theme.m3PrimaryContainer
                            fallbackGlyph: "󰓇"
                            fallbackColor: Theme.m3OnPrimaryContainer
                            spinning: root.active && root.isPlaying && root.layoutMode === "stage" && ShellState.pillSpinArt
                            spinDurationMs: 24000
                        }
                    }

                    // Player badge (borderless pill, shown only when player connected)
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 10
                        visible: root.hasPlayer
                        implicitHeight: 20
                        implicitWidth: stageBadge.implicitWidth + 12
                        radius: Theme.r(10)
                        color: Theme.m3SecondaryContainer

                        Text {
                            id: stageBadge
                            anchors.centerIn: parent
                            text: root.hasPlayer ? (root.player.identity || "Media") : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.m3OnSecondaryContainer
                        }
                    }
                }

                // Bottom Playback Surface
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.margins: 12
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (root.player && root.player.trackTitle) ? root.player.trackTitle : "Nothing Playing"
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: {
                                if (!root.player)
                                    return "Start Spotify or any MPRIS app";
                                const artist = root.player.trackArtist || "";
                                const album = root.player.trackAlbum || "";
                                if (artist && album)
                                    return artist + " · " + album;
                                return artist || album || "Connected";
                            }
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        M3WavyLine {
                            Layout.fillWidth: true
                            implicitHeight: 18
                            value: (root.trackLength > 0) ? Math.max(0.0, Math.min(1.0, root.displayPosition / root.trackLength)) : 0.0
                            moving: root.active && root.isPlaying && root.layoutMode === "stage"
                            seekable: root.hasPlayer && root.player.canSeek && root.player.positionSupported && root.trackLength > 0
                            color: Theme.m3Primary
                            track: Theme.m3Track
                            onMoved: v => {
                                if (!root.hasPlayer || root.trackLength <= 0) return;
                                const sec = Math.max(0, Math.min(1, v)) * root.trackLength;
                                root.displayPosition = sec;
                                root.player.seek(sec - (root.player.position || 0));
                            }
                            onDraggingChanged: a => {
                                root._seeking = a;
                                root.controlInteractionChanged(a);
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: root.formatTime(root.displayPosition); font.family: Theme.monoFont; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                            Item { Layout.fillWidth: true }
                            Text { text: root.formatTime(root.trackLength); font.family: Theme.monoFont; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                            color: stPrevMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder
                            opacity: (root.hasPlayer && root.player.canGoPrevious) ? 1.0 : 0.45
                            Text { anchors.centerIn: parent; text: "󰒮"; font.family: Theme.iconFont; font.pixelSize: 16; color: Theme.fgSurface }
                            MouseArea { id: stPrevMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoPrevious; cursorShape: Qt.PointingHandCursor; onClicked: root.player.previous() }
                        }

                        Rectangle {
                            implicitWidth: 46; implicitHeight: 34; radius: Theme.r(17)
                            color: stPlayMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                            opacity: (root.hasPlayer && root.player.canTogglePlaying) ? 1.0 : 0.50
                            Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 18; color: Theme.fgPrimary }
                            MouseArea { id: stPlayMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canTogglePlaying; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                        }

                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                            color: stNextMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder
                            opacity: (root.hasPlayer && root.player.canGoNext) ? 1.0 : 0.45
                            Text { anchors.centerIn: parent; text: "󰒭"; font.family: Theme.iconFont; font.pixelSize: 16; color: Theme.fgSurface }
                            MouseArea { id: stNextMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }

        // Right Column: Spaces Strip + Controls Deck + Horizontal Metric Deck
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            SpacesCapsule {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 44
                Layout.minimumHeight: 44
                Layout.maximumHeight: 44
            }

            // Borderless Controls Deck
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                readonly property int deckH: 148 + (DeviceCaps.hasBacklight ? 38 : 0)
                Layout.preferredHeight: deckH
                Layout.minimumHeight: deckH
                Layout.maximumHeight: deckH
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Volume Capsule + Mute Button
                    Item {
                        id: stVolCap
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 32

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.r(16)
                            color: Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth
                            border.color: Theme.cardBorder
                            clip: true

                            Rectangle {
                                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                width: root.volumeLevel <= 0.001 ? 0 : Math.max(parent.height, parent.width * Math.min(1.0, root.volumeLevel))
                                radius: Theme.r(16)
                                color: root.volumeMuted ? Theme.surfaceContainerHighest : Theme.primary
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 6
                                Text {
                                    text: root.volumeMuted ? "󰝟" : "󰕾"
                                    font.family: Theme.iconFont; font.pixelSize: 15
                                    color: root.volumeMuted ? Theme.fgSurfaceVariant : Theme.fgPrimary
                                }
                                Text { text: root.volumeMuted ? "Muted" : "Sound"; Layout.fillWidth: true; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.volumeLevel > 0.25 && !root.volumeMuted ? Theme.fgPrimary : Theme.fgSurface }
                                Text { text: Math.round(root.volumeLevel * 100) + "%"; font.family: Theme.monoFont; font.pixelSize: 10; font.weight: Font.Bold; color: root.volumeLevel > 0.88 && !root.volumeMuted ? Theme.fgPrimary : Theme.fgSurface }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: m => {
                                    root._dragRatio = Math.max(0.0, Math.min(ShellState.audioOverAmp ? 1.5 : 1.0, m.x / stVolCap.width));
                                    root._dragging = true;
                                    root.controlInteractionChanged(true);
                                    root.applyVolume(root._dragRatio);
                                }
                                onPositionChanged: m => { if (pressed) root.applyVolume(m.x / stVolCap.width); }
                                onReleased: { root._dragging = false; root.controlInteractionChanged(false); }
                                onCanceled: { root._dragging = false; root.controlInteractionChanged(false); }
                            }
                        }
                    }

                    // Display Settings Shortcut Row when backlight hardware present
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 30
                        visible: DeviceCaps.hasBacklight
                        radius: Theme.r(15)
                        color: stDispMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                        border.width: Theme.activeControlBorderWidth
                        border.color: Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6
                            Text { text: "󰃠"; font.family: Theme.iconFont; font.pixelSize: 13; color: Theme.fgSurfaceVariant }
                            Text { Layout.fillWidth: true; text: "Display & Brightness"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.fgSurface }
                            Text { text: "Settings"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.primary }
                        }

                        MouseArea {
                            id: stDispMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSettingsRequested("displays")
                        }
                    }

                    // 4 Borderless Quick Action Tiles
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 6

                        Repeater {
                            model: [
                                { id: "dnd",   icon: ShellState.dnd ? "󰂛" : "󰂚", label: "Focus",   active: ShellState.dnd, tint: Theme.secondary },
                                { id: "awake", icon: "󰅶", label: "Awake",   active: ShellState.keepAwake, tint: Theme.warning },
                                { id: "shot",  icon: "󰹑", label: "Capture", active: false, tint: Theme.primary },
                                { id: "game",  icon: "󰊴", label: "Game",    active: ShellState.gameModeActive, tint: Theme.tertiary }
                            ]

                            delegate: Rectangle {
                                id: stAct
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: Theme.r(12)
                                color: stAct.modelData.active
                                    ? Theme.tileActiveBg
                                    : (stActMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                                border.width: stAct.modelData.active ? Theme.activeControlBorderWidth : 0
                                border.color: stAct.modelData.tint
                                scale: stActMouse.pressed ? 0.95 : 1.0

                                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Rectangle {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        radius: Theme.r(10)
                                        color: stAct.modelData.active ? stAct.modelData.tint : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: stAct.modelData.icon
                                            font.family: Theme.iconFont
                                            font.pixelSize: stAct.modelData.active ? 12 : 14
                                            color: stAct.modelData.active
                                                ? Theme.contrastInk(stAct.modelData.tint)
                                                : (stActMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant)
                                        }
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: stAct.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        font.weight: stAct.modelData.active ? Font.Bold : Font.DemiBold
                                        color: Theme.fgSurface
                                    }
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

                    // Bottom Utility Row: Record + Audio Output + Appearance
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: ShellState.recordingActive
                                ? Theme.error
                                : (stRecMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: ShellState.recordingActive ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.error

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: ShellState.recordingActive ? "󰑊 Stop REC" : "󰑊 Record"
                                font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold
                                color: ShellState.recordingActive ? Theme.fgError : Theme.fgSurface
                            }

                            MouseArea {
                                id: stRecMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"])
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1.5
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: stSinkMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 5

                                Text { text: "󰋋"; font.family: Theme.iconFont; font.pixelSize: 11; color: Theme.fgSurfaceVariant }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.defaultSinkLabel
                                    font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.DemiBold
                                    color: Theme.fgSurface
                                }
                            }

                            MouseArea {
                                id: stSinkMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton)
                                        Qt.callLater(() => root.openSettingsRequested("audio"));
                                    else
                                        MangoState.cycleAudioSink();
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: stAppMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                            border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 10
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: "Appearance"
                                font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold
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

            // Horizontal Metric Telemetry Deck (no dead space, separated by hairlines)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 76
                radius: Theme.r(18)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    MetricCell {
                        label: "CPU"
                        detail: root.cpuTempC > 0 ? (root.cpuTempC + "°C") : "Load"
                        percent: root.cpuPercent
                        valueText: Math.round(root.cpuPercent) + "%"
                        barColor: root.cpuPercent > 85 ? Theme.error : Theme.primary
                    }

                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.hairlineBorder }

                    MetricCell {
                        label: "Memory"
                        detail: root.ramUsedGb.toFixed(1) + "G"
                        percent: root.ramPercent
                        valueText: Math.round(root.ramPercent) + "%"
                        barColor: root.ramPercent > 85 ? Theme.warning : Theme.secondary
                    }

                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.hairlineBorder }

                    MetricCell {
                        label: DeviceCaps.hasBattery ? "Battery" : "Disk /"
                        detail: DeviceCaps.hasBattery ? (DeviceCaps.batteryEta.length > 0 ? (DeviceCaps.batteryStatus + " · " + DeviceCaps.batteryEta) : DeviceCaps.batteryStatus) : (root.diskFreeLabel.length > 0 ? (root.diskFreeLabel + " free") : "Root")
                        percent: DeviceCaps.hasBattery ? DeviceCaps.batteryPercent : root.diskPercent
                        valueText: DeviceCaps.hasBattery ? (DeviceCaps.batteryPercent + "%") : (Math.round(root.diskPercent) + "%")
                        barColor: DeviceCaps.hasBattery ? (DeviceCaps.batteryLow ? Theme.error : Theme.success) : Theme.tertiary
                    }
                }
            }
        }
        }
    }

    // ==================== LAYOUT 3: COCKPIT (Telemetry Ribbon + Dual Command Deck) ====================
    Component {
        id: cockpitLayoutComp

        ColumnLayout {
            spacing: 10

        // Top Unified Media + Mission Control Spaces Ribbon (50px snug fit)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 50
            Layout.minimumHeight: 50
            Layout.maximumHeight: 50
            spacing: 10

            // Compact Horizontal Media Capsule
            Rectangle {
                Layout.preferredWidth: 274
                Layout.minimumWidth: 256
                Layout.maximumWidth: 280
                Layout.fillHeight: true
                radius: Theme.r(16)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 8

                    M3ShapeImage {
                        implicitWidth: 36
                        implicitHeight: 36
                        kind: "circle"
                        source: root.artUrl
                        empty: Theme.m3PrimaryContainer
                        fallbackGlyph: "󰓇"
                        fallbackColor: Theme.m3OnPrimaryContainer
                        spinning: root.active && root.isPlaying && root.layoutMode === "cockpit" && ShellState.pillSpinArt
                        spinDurationMs: 14000
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
                        color: ckNextMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                        border.width: Theme.activeControlBorderWidth; border.color: Theme.cardBorder
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

        // Bottom Dual Platter: Full Telemetry Monitor + Borderless Quick Controls
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 220
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
                showFocusAwakeRow: !DeviceCaps.hasExtraQuickControls
                onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }
        }
        }
    }
}
