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
        property color barColor: Theme.m3Primary

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: mc.label
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.m3InkDim
            }

            Item { Layout.fillWidth: true }

            Text {
                elide: Text.ElideRight
                Layout.maximumWidth: 76
                text: mc.detail
                font.family: Theme.monoFont
                font.pixelSize: 9
                color: Theme.m3InkDim
            }
        }

        Text {
            text: mc.valueText
            font.family: Theme.monoFont
            font.pixelSize: 16
            font.weight: Font.Bold
            color: Theme.m3Ink
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 5
            radius: 2.5
            color: Theme.m3Track

            Rectangle {
                height: parent.height
                radius: 2.5
                width: parent.width * (Math.max(0.0, Math.min(100.0, mc.percent)) / 100.0)
                color: mc.barColor

                Behavior on width {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // --- Reusable Inline Component: M3 Wavy Activity Ring Gauge ---
    component ActivityRing : Item {
        id: ringItem
        property real percent: 0
        property color ringColor: Theme.m3Primary
        property string centerLabel: "0%"
        property string titleLabel: "CPU"
        property string detailLabel: ""

        clip: true

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 3

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 64
                implicitHeight: 64

                M3WavyArc {
                    anchors.fill: parent
                    value: Math.max(0.0, Math.min(1.0, ringItem.percent / 100.0))
                    moving: root.active && root.layoutMode === "cupertino"
                    color: ringItem.ringColor
                    track: Theme.m3Track
                    thick: 3.5
                }

                Text {
                    anchors.centerIn: parent
                    text: ringItem.centerLabel
                    font.family: Theme.monoFont
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: Theme.m3Ink
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: ringItem.titleLabel
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.m3Ink
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(64, ringItem.width - 8)
                elide: Text.ElideRight
                visible: ringItem.detailLabel.length > 0
                text: ringItem.detailLabel
                font.family: Theme.fontFamily
                font.pixelSize: 9
                color: Theme.m3InkDim
            }
        }
    }

    // --- Reusable Inline Component: Mission Control Spaces Capsule ---
    component SpacesCapsule : Rectangle {
        id: scRoot
        property var model: root.tagsModel
        property string layoutCode: root.currentLayout
        property int winsCount: root.totalClients

        implicitHeight: 46
        radius: Theme.r(23)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line
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
                implicitHeight: 30
                radius: Theme.r(15)
                color: Theme.m3SurfaceHigh
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 3
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
                            radius: Theme.isSimple ? 0 : Theme.r(spBtn.isActive ? 12 : 9)
                            color: {
                                if (spBtn.isUrgent) return Theme.m3Error;
                                if (spBtn.isActive) return Theme.m3Primary;
                                if (spMouse.containsMouse) return Theme.m3SurfaceHighest;
                                if (spBtn.isOccupied) return Theme.m3SecondaryContainer;
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
                                        if (spBtn.isUrgent) return Theme.m3OnErrorContainer;
                                        if (spBtn.isActive) return Theme.m3OnPrimary;
                                        return spBtn.isOccupied ? Theme.m3OnSecondaryContainer : Theme.m3InkDim;
                                    }
                                }

                                Rectangle {
                                    visible: spBtn.isOccupied && !spBtn.isActive
                                    implicitWidth: 3
                                    implicitHeight: 3
                                    radius: 1.5
                                    color: Theme.m3Primary
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
                implicitHeight: 30
                implicitWidth: Math.max(28, layTagTxt.implicitWidth + 12)
                radius: Theme.isSimple ? 0 : Theme.r(15)
                color: layTagMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

                Text {
                    id: layTagTxt
                    anchors.centerIn: parent
                    text: scRoot.layoutCode
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.m3OnSecondaryContainer
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
                implicitHeight: 30
                implicitWidth: winPillRow.implicitWidth + 14
                radius: Theme.isSimple ? 0 : Theme.r(15)
                color: winPillMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                RowLayout {
                    id: winPillRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.m3Primary }
                    Text {
                        text: scRoot.winsCount > 0 ? String(scRoot.winsCount) : "0"
                        font.family: Theme.monoFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.m3Ink
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

    // ==================== LAYOUT 1: CUPERTINO (M3 Control Center) ====================
    Component {
        id: cupertinoLayoutComp

        RowLayout {
            spacing: 10

        // Left Column: Borderless 2x2 Connectivity/Focus Platter + Snug MediaCard
        ColumnLayout {
            Layout.preferredWidth: 342
            Layout.minimumWidth: 326
            Layout.maximumWidth: 350
            Layout.fillHeight: true
            spacing: 10

            // 2x2 Control Center Platter (M3 Expressive morphing tiles + filled icon discs)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 124
                Layout.minimumHeight: 124
                Layout.maximumHeight: 124
                radius: Theme.r(26)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
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
                                active: !root.volumeMuted
                            },
                            {
                                id: "dnd",
                                icon: ShellState.dnd ? "󰂛" : "󰂚",
                                title: "Focus",
                                sub: ShellState.dnd ? "Do Not Disturb" : "Notifications On",
                                active: ShellState.dnd
                            },
                            {
                                id: "awake",
                                icon: "󰅶",
                                title: "Keep Awake",
                                sub: ShellState.keepAwake ? "Idle Paused" : "Auto-Lock On",
                                active: ShellState.keepAwake
                            },
                            {
                                id: "game",
                                icon: "󰊴",
                                title: "Game Mode",
                                sub: ShellState.gameModeActive ? "Boost Active" : "Standard",
                                active: ShellState.gameModeActive
                            }
                        ]

                        delegate: Rectangle {
                            id: ccTile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.isSimple ? 0 : Theme.r(ccMouse.pressed ? 14 : (ccTile.modelData.active ? 22 : 18))
                            color: ccTile.modelData.active
                                ? Theme.m3PrimaryContainer
                                : (ccMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                            clip: true
                            scale: ccMouse.pressed ? 0.96 : 1.0

                            Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 200; easing.type: Theme.m3Springy } }
                            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 8

                                Rectangle {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    radius: Theme.r(16)
                                    color: ccTile.modelData.active
                                        ? Theme.m3Primary
                                        : Theme.m3SurfaceC

                                    Text {
                                        anchors.centerIn: parent
                                        text: ccTile.modelData.icon
                                        font.family: Theme.iconFont
                                        font.pixelSize: 15
                                        color: ccTile.modelData.active
                                            ? Theme.m3OnPrimary
                                            : Theme.m3InkDim
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
                                        font.pixelSize: 11
                                        font.weight: ccTile.modelData.active ? Font.Bold : Font.DemiBold
                                        color: ccTile.modelData.active ? Theme.m3OnPrimaryContainer : Theme.m3Ink
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: ccTile.modelData.sub
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                        color: ccTile.modelData.active ? Theme.withAlpha(Theme.m3OnPrimaryContainer, 0.80) : Theme.m3InkDim
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
                Layout.minimumHeight: 162
                player: root.player
                active: root.active && root.layoutMode === "cupertino"
                onSeekingChanged: seeking => root.controlInteractionChanged(seeking)
            }
        }

        // Right Column: Capsule Sliders + Action Tiles, Spaces Strip, M3WavyArc Activity Rings
        ColumnLayout {
            id: cupertinoRightCol
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            QuickControls {
                id: qcCup
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Math.max(96, qcCup.implicitHeight)
                Layout.minimumHeight: Math.max(96, qcCup.implicitHeight)
                active: root.active && root.layoutMode === "cupertino"
                compactLayout: true
                cupertinoMode: true
                hideHeader: true
                hideStyleFooter: true
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

            // M3 Wavy Activity Rings Telemetry Platter
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 118
                radius: Theme.r(26)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    ActivityRing {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        percent: root.cpuPercent
                        ringColor: root.cpuPercent > 85 ? Theme.m3Error : Theme.m3Primary
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
                            ? (DeviceCaps.batteryLow ? Theme.m3Error : Theme.tertiary)
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

    // ==================== LAYOUT 2: STAGE (Artwork Showcase + M3 Controls & Metric Deck) ====================
    Component {
        id: stageLayoutComp

        RowLayout {
            spacing: 10

            // Left Media Showcase Card
            ClippingRectangle {
                Layout.preferredWidth: 278
                Layout.minimumWidth: 268
                Layout.maximumWidth: 286
                Layout.fillHeight: true
                radius: Theme.r(26)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
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
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Theme.m3Ink
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
                            color: Theme.m3InkDim
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
                            Text { text: root.formatTime(root.displayPosition); font.family: Theme.monoFont; font.pixelSize: 9; color: Theme.m3InkDim }
                            Item { Layout.fillWidth: true }
                            Text { text: root.formatTime(root.trackLength); font.family: Theme.monoFont; font.pixelSize: 9; color: Theme.m3InkDim }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Item { Layout.fillWidth: true }

                        Rectangle {
                            implicitWidth: 36; implicitHeight: 36; radius: Theme.isSimple ? 0 : Theme.r(stPrevMouse.pressed ? 11 : 18)
                            color: stPrevMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                            opacity: (root.hasPlayer && root.player.canGoPrevious) ? 1.0 : 0.42
                            Text { anchors.centerIn: parent; text: "󰒮"; font.family: Theme.iconFont; font.pixelSize: 16; color: Theme.m3Ink }
                            MouseArea { id: stPrevMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoPrevious; cursorShape: Qt.PointingHandCursor; onClicked: root.player.previous() }
                        }

                        Rectangle {
                            implicitWidth: 52; implicitHeight: 36; radius: Theme.isSimple ? 0 : Theme.r(stPlayMouse.pressed ? 11 : (root.isPlaying ? 14 : 18))
                            color: Theme.m3Primary
                            opacity: (root.hasPlayer && root.player.canTogglePlaying) ? 1.0 : 0.45
                            Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Theme.m3Springy } }
                            Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 18; color: Theme.m3OnPrimary }
                            MouseArea { id: stPlayMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canTogglePlaying; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                        }

                        Rectangle {
                            implicitWidth: 36; implicitHeight: 36; radius: Theme.isSimple ? 0 : Theme.r(stNextMouse.pressed ? 11 : 18)
                            color: stNextMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                            opacity: (root.hasPlayer && root.player.canGoNext) ? 1.0 : 0.42
                            Text { anchors.centerIn: parent; text: "󰒭"; font.family: Theme.iconFont; font.pixelSize: 16; color: Theme.m3Ink }
                            MouseArea { id: stNextMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }

        // Right Column: Spaces Strip + M3 Controls Deck + Horizontal Metric Deck
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

            // M3 Expressive Controls Deck
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                readonly property int deckH: stageDeckCol.implicitHeight + 22
                Layout.preferredHeight: deckH
                Layout.minimumHeight: deckH
                Layout.maximumHeight: deckH
                radius: Theme.r(26)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                ColumnLayout {
                    id: stageDeckCol
                    anchors.fill: parent
                    anchors.margins: 11
                    spacing: 9

                    // Real M3CapsuleSlider for Volume
                    M3CapsuleSlider {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        compact: true
                        icon: root.volumeMuted ? "󰝟" : (root.volumeLevel <= 0.45 ? "󰖀" : "󰕾")
                        label: root.volumeMuted ? "Muted" : "Sound"
                        value: root.volumeLevel
                        maxValue: ShellState.audioOverAmp ? 1.5 : 1.0
                        muted: root.volumeMuted
                        activeColor: Theme.m3Primary
                        onMoved: v => {
                            root._dragRatio = v;
                            root._dragging = true;
                            root.applyVolume(v);
                        }
                        onIconClicked: MangoState.toggleMute()
                        onRightClicked: MangoState.cycleAudioSink()
                        onDraggingChanged: d => {
                            root._dragging = d;
                            root.controlInteractionChanged(d);
                        }
                    }

                    // Display Settings Shortcut Row when backlight hardware present
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 32
                        visible: DeviceCaps.hasBacklight
                        radius: Theme.r(16)
                        color: stDispMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6
                            Text { text: "󰃠"; font.family: Theme.iconFont; font.pixelSize: 13; color: Theme.m3Primary }
                            Text { Layout.fillWidth: true; text: "Display & Brightness"; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.m3Ink }
                            Text { text: "Settings"; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.m3Primary }
                        }

                        MouseArea {
                            id: stDispMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSettingsRequested("displays")
                        }
                    }

                    // 4 Morphing M3 Tiles
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 7

                        M3Tile {
                            compact: true
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            icon: ShellState.dnd ? "󰂛" : "󰂚"
                            label: "Focus"
                            active: ShellState.dnd
                            onClicked: ShellState.toggleDnd()
                        }

                        M3Tile {
                            compact: true
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            icon: "󰅶"
                            label: "Awake"
                            active: ShellState.keepAwake
                            onClicked: ShellState.toggleKeepAwake()
                        }

                        M3Tile {
                            compact: true
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            icon: "󰹑"
                            label: "Capture"
                            active: false
                            onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--area"])
                        }

                        M3Tile {
                            compact: true
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            icon: "󰊴"
                            label: "Game"
                            active: ShellState.gameModeActive
                            onClicked: ShellState.toggleGameMode()
                        }
                    }

                    // Bottom Utility Row: Record + Audio Output + Appearance
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 7

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 32
                            radius: Theme.r(16)
                            color: ShellState.recordingActive
                                ? Theme.m3Error
                                : (stRecMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: ShellState.recordingActive ? "󰑊 Stop REC" : "󰑊 Record"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: ShellState.recordingActive ? Theme.m3OnError : Theme.m3Ink
                            }

                            MouseArea {
                                id: stRecMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"])
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1.5
                            implicitHeight: 32
                            radius: Theme.r(16)
                            color: stSinkMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 5

                                Text { text: "󰋋"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.m3Primary }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.defaultSinkLabel
                                    font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold
                                    color: Theme.m3Ink
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
                            implicitHeight: 32
                            radius: Theme.r(16)
                            color: stAppMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 10
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: "Appearance"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold
                                color: Theme.m3OnSecondaryContainer
                            }

                            MouseArea {
                                id: stAppMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.openSettingsRequested("appearance")
                            }
                        }
                    }
                }
            }

            // Horizontal Metric Telemetry Deck
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 80
                radius: Theme.r(24)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
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
                        barColor: root.cpuPercent > 85 ? Theme.m3Error : Theme.m3Primary
                    }

                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.m3Line }

                    MetricCell {
                        label: "Memory"
                        detail: root.ramUsedGb.toFixed(1) + "G"
                        percent: root.ramPercent
                        valueText: Math.round(root.ramPercent) + "%"
                        barColor: root.ramPercent > 85 ? Theme.warning : Theme.secondary
                    }

                    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.m3Line }

                    MetricCell {
                        label: DeviceCaps.hasBattery ? "Battery" : "Disk /"
                        detail: DeviceCaps.hasBattery ? (DeviceCaps.batteryEta.length > 0 ? (DeviceCaps.batteryStatus + " · " + DeviceCaps.batteryEta) : DeviceCaps.batteryStatus) : (root.diskFreeLabel.length > 0 ? (root.diskFreeLabel + " free") : "Root")
                        percent: DeviceCaps.hasBattery ? DeviceCaps.batteryPercent : root.diskPercent
                        valueText: DeviceCaps.hasBattery ? (DeviceCaps.batteryPercent + "%") : (Math.round(root.diskPercent) + "%")
                        barColor: DeviceCaps.hasBattery ? (DeviceCaps.batteryLow ? Theme.m3Error : Theme.tertiary) : Theme.tertiary
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

        // Top Unified Media + Mission Control Spaces Ribbon
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 52
            Layout.minimumHeight: 52
            Layout.maximumHeight: 52
            spacing: 10

            // Compact Horizontal Media Capsule
            Rectangle {
                Layout.preferredWidth: 278
                Layout.minimumWidth: 256
                Layout.maximumWidth: 286
                Layout.fillHeight: true
                radius: Theme.r(24)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
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
                            font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold; color: Theme.m3Ink
                        }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: root.player ? (root.player.trackArtist || root.player.identity || "MPRIS") : "Open Spotify or media"
                            font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.m3InkDim
                        }
                    }

                    Rectangle {
                        implicitWidth: 30; implicitHeight: 30; radius: Theme.r(15)
                        color: Theme.m3Primary
                        opacity: (root.hasPlayer && root.player.canTogglePlaying) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 14; color: Theme.m3OnPrimary }
                        MouseArea { id: ckPlayMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canTogglePlaying; cursorShape: Qt.PointingHandCursor; onClicked: root.player.togglePlaying() }
                    }

                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(14)
                        color: ckNextMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                        opacity: (root.hasPlayer && root.player.canGoNext) ? 1.0 : 0.45
                        Text { anchors.centerIn: parent; text: "󰒭"; font.family: Theme.iconFont; font.pixelSize: 13; color: Theme.m3Ink }
                        MouseArea { id: ckNextMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.hasPlayer && root.player.canGoNext; cursorShape: Qt.PointingHandCursor; onClicked: root.player.next() }
                    }
                }
            }

            SpacesCapsule {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        // Bottom Dual Platter: Full Telemetry Monitor + Compact M3 Quick Controls
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 230
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
                compactLayout: true
                hideStyleFooter: true
                active: root.active && root.layoutMode === "cockpit"
                showFocusAwakeRow: !DeviceCaps.hasExtraQuickControls
                onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }
        }
        }
    }
}
