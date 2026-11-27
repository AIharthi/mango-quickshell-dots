pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."
import "../m3"

// Material 3 Expressive media card modeled on DarkShadowShell ControlCenter & DynIsland.
ClippingRectangle {
    id: root

    property var player: null
    property bool active: false
    property real displayPosition: 0

    signal seekingChanged(bool seeking)

    readonly property bool hasPlayer: root.player !== null
    readonly property bool isPlaying: root.player !== null && root.player.isPlaying
    readonly property real trackLength: (root.player && root.player.length > 0) ? root.player.length : 0
    readonly property string artUrl: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""
    readonly property bool wideArt: root.width >= 360
    readonly property bool canSeek: root.hasPlayer && !!(root.player.canSeek && root.player.positionSupported && root.trackLength > 0)
    readonly property real progressRatio: (root.trackLength > 0)
        ? Math.max(0.0, Math.min(1.0, root.displayPosition / root.trackLength))
        : 0.0

    function formatTime(secs: real): string {
        if (!secs || secs < 0 || isNaN(secs))
            return "0:00";
        const total = Math.floor(secs);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    function seekToRatio(ratio: real): void {
        if (!root.canSeek)
            return;
        const clamped = Math.max(0.0, Math.min(1.0, ratio));
        const targetSec = clamped * root.trackLength;
        root.displayPosition = targetSec;
        const delta = targetSec - (root.player.position || 0);
        root.player.seek(delta);
    }

    function seekRelative(deltaSec: real): void {
        if (!root.canSeek)
            return;
        const targetSec = Math.max(0, Math.min(root.trackLength, root.displayPosition + deltaSec));
        root.displayPosition = targetSec;
        root.player.seek(targetSec - (root.player.position || 0));
    }

    onPlayerChanged: {
        root.displayPosition = (root.player && root.player.position >= 0) ? root.player.position : 0;
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged(): void {
            if (!wavyProgress.isDragging && root.player)
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
        running: root.active && root.isPlaying && !wavyProgress.isDragging
        onTriggered: {
            if (!root.player)
                return;
            if (root.player.position >= 0 && Math.abs(root.player.position - root.displayPosition) > 2.5) {
                root.displayPosition = root.player.position;
            } else if (root.trackLength > 0) {
                root.displayPosition = Math.min(root.trackLength, root.displayPosition + 1);
            } else {
                root.displayPosition += 1;
            }
        }
    }

    radius: Theme.r(28)
    implicitHeight: Math.max(154, mediaRow.implicitHeight + 24)
    color: Theme.m3SurfaceC
    border.width: 1
    border.color: Theme.m3Line
    contentUnderBorder: false
    contentInsideBorder: true

    // Soft ambient art glow
    Image {
        anchors.fill: parent
        source: root.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize: Qt.size(64, 64)
        opacity: (root.artUrl.length > 0 && status === Image.Ready && !Theme.isSimple && !Theme.isRetro) ? 0.12 : 0.0
        visible: opacity > 0.01
    }

    RowLayout {
        id: mediaRow
        anchors.fill: parent
        anchors.margins: 12
        spacing: 14

        // Left: Cookie-shaped album art inside wavy circular progress ring
        Item {
            id: artFrame
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.wideArt ? 116 : 86
            implicitHeight: root.wideArt ? 116 : 86

            M3WavyArc {
                anchors.fill: parent
                value: root.hasPlayer ? root.progressRatio : 0.0
                moving: root.active && root.isPlaying
                color: Theme.m3Primary
                track: Theme.m3Track
            }

            M3ShapeImage {
                anchors.centerIn: parent
                width: root.wideArt ? 88 : 64
                height: root.wideArt ? 88 : 64
                kind: Theme.isSimple ? "square" : "cookie"
                source: root.artUrl
                empty: Theme.m3PrimaryContainer
                fallbackGlyph: "󰓇"
                fallbackColor: Theme.m3OnPrimaryContainer
                spinning: root.active && root.isPlaying && ShellState.pillSpinArt
                spinDurationMs: 24000
            }
        }

        // Right: Track info + M3WavyLine + 5 morphing M3 transport buttons
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: (root.player && root.player.trackTitle)
                        ? root.player.trackTitle
                        : "Nothing Playing"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                    font.weight: Font.DemiBold
                    color: Theme.m3Ink
                }

                Rectangle {
                    visible: root.hasPlayer
                    implicitHeight: 20
                    implicitWidth: badgeText.implicitWidth + 12
                    radius: Theme.r(10)
                    color: root.isPlaying ? Theme.m3PrimaryContainer : Theme.m3SurfaceHigh

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.hasPlayer ? (root.player.identity || "Media") : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.Bold
                        color: root.isPlaying ? Theme.m3OnPrimaryContainer : Theme.m3InkDim
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: {
                    if (!root.player)
                        return "Open Spotify or any MPRIS player";
                    const artist = root.player.trackArtist || "";
                    const album = root.player.trackAlbum || "";
                    if (artist && album)
                        return artist + "  ·  " + album;
                    return artist || album || "Ready";
                }
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.m3InkDim
            }

            M3WavyLine {
                id: wavyProgress
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 20
                value: root.progressRatio
                moving: root.active && root.isPlaying
                seekable: root.canSeek
                color: Theme.m3Primary
                track: Theme.m3Track
                onMoved: v => root.seekToRatio(v)
                onDraggingChanged: active => root.seekingChanged(active)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.trackLength > 0

                Text {
                    text: root.formatTime(root.displayPosition)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    color: Theme.m3InkDim
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.formatTime(root.trackLength)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    color: Theme.m3InkDim
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 5

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [
                        { id: "prev",   icon: "󰒮", big: false, extra: false },
                        { id: "back",   icon: "󰓕", big: false, extra: true  },
                        { id: "toggle", icon: "",  big: true,  extra: false },
                        { id: "fwd",    icon: "󰓗", big: false, extra: true  },
                        { id: "next",   icon: "󰒭", big: false, extra: false }
                    ]

                    delegate: Rectangle {
                        id: tBtn
                        required property var modelData
                        readonly property bool isBig: tBtn.modelData.big
                        readonly property bool isEnabled: {
                            if (!root.hasPlayer) return false;
                            if (tBtn.modelData.id === "prev") return root.player.canGoPrevious;
                            if (tBtn.modelData.id === "next") return root.player.canGoNext;
                            if (tBtn.modelData.id === "toggle") return root.player.canTogglePlaying;
                            return root.canSeek;
                        }

                        visible: !tBtn.modelData.extra || root.width >= 300
                        implicitWidth: tBtn.isBig ? 52 : 34
                        implicitHeight: 36
                        radius: Theme.isSimple ? 0 : Theme.r(tMouse.pressed ? 11 : (tBtn.isBig && root.isPlaying ? 14 : 18))
                        color: tBtn.isBig
                            ? Theme.m3Primary
                            : (tMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                        opacity: tBtn.isEnabled ? 1.0 : 0.42
                        scale: tMouse.pressed ? 0.92 : 1.0

                        Behavior on radius {
                            enabled: !Theme.reducedMotion
                            NumberAnimation { duration: 240; easing.type: Theme.m3Springy; easing.overshoot: 1.5 }
                        }
                        Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 130 } }
                        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                        Text {
                            anchors.centerIn: parent
                            text: tBtn.isBig ? (root.isPlaying ? "󰏤" : "󰐊") : tBtn.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fs(tBtn.isBig ? 18 : 14)
                            color: tBtn.isBig ? Theme.m3OnPrimary : Theme.m3Ink
                        }

                        MouseArea {
                            id: tMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: tBtn.isEnabled
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                const act = tBtn.modelData.id;
                                if (act === "toggle") root.player.togglePlaying();
                                else if (act === "prev") root.player.previous();
                                else if (act === "next") root.player.next();
                                else if (act === "back") root.seekRelative(-10);
                                else if (act === "fwd") root.seekRelative(10);
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
