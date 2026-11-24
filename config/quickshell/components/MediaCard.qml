pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."

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

    property int _eqPhase: 0
    Timer {
        interval: 260
        repeat: true
        running: root.active && root.isPlaying && !Theme.reducedMotion
        onTriggered: root._eqPhase = (root._eqPhase + 1) % 6
    }

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
            if (!seekArea.pressed && root.player)
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
        running: root.active && root.isPlaying && !seekArea.pressed
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

    radius: Theme.r(18)
    color: Theme.cardBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder
    contentUnderBorder: false
    contentInsideBorder: true

    // Soft faded album art atmosphere
    Image {
        anchors.fill: parent
        source: root.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(96, 96)
        opacity: (root.artUrl.length > 0 && status === Image.Ready && !Theme.isSimple && !Theme.isRetro) ? 0.14 : 0.0
        visible: opacity > 0.01
    }

    // Subtle top ambient gradient wash
    Rectangle {
        anchors.fill: parent
        visible: !Theme.isSimple
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, root.isPlaying ? 0.15 : 0.07) }
            GradientStop { position: 0.65; color: "transparent" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // --- Header + Album Info ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 10

            ClippingRectangle {
                implicitWidth: 52
                implicitHeight: 52
                radius: Theme.r(12)
                color: Theme.primaryContainer
                border.width: Theme.activeControlBorderWidth
                border.color: Theme.primary
                contentUnderBorder: false
                contentInsideBorder: true

                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(120, 120)
                    visible: root.artUrl.length > 0 && status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !coverImg.visible
                    text: "󰓇"
                    font.family: Theme.iconFont
                    font.pixelSize: 22
                    color: Theme.fgPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        visible: root.hasPlayer
                        implicitHeight: 16
                        implicitWidth: badgeText.implicitWidth + 10
                        radius: Theme.r(8)
                        color: root.isPlaying
                            ? Theme.tileActiveBg
                            : Theme.subCardBg
                        border.width: Theme.activeControlBorderWidth
                        border.color: Theme.primary

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: root.hasPlayer
                                ? (root.player.identity || "Media")
                                : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: root.isPlaying ? Theme.fgSurface : Theme.fgSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // 4-Bar Animated Equalizer when playing
                    Row {
                        visible: root.isPlaying
                        spacing: 2
                        Layout.alignment: Qt.AlignVCenter

                        Repeater {
                            model: [
                                [5, 11, 8, 13, 6, 10],
                                [10, 6, 13, 8, 12, 5],
                                [7, 13, 6, 11, 8, 13],
                                [12, 8, 10, 5, 13, 7]
                            ]

                            delegate: Rectangle {
                                id: eqBar
                                required property var modelData
                                width: 2.5
                                height: Theme.reducedMotion ? 9 : eqBar.modelData[root._eqPhase % 6]
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.r(1.5)
                                color: Theme.primary

                                Behavior on height {
                                    enabled: !Theme.reducedMotion
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: (root.player && root.player.trackTitle)
                        ? root.player.trackTitle
                        : "Nothing Playing"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.player)
                            return "Open Spotify or any MPRIS player";
                        const artist = root.player.trackArtist || "";
                        const album = root.player.trackAlbum || "";
                        if (artist && album)
                            return artist + " · " + album;
                        return artist || album || "Ready";
                    }
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurfaceVariant
                }
            }
        }

        // --- Interactive Track Progress Bar ---
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 3

            Item {
                id: seekBar
                Layout.fillWidth: true
                implicitHeight: 14

                readonly property real progressRatio: (root.trackLength > 0)
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
                        width: parent.width * seekBar.progressRatio
                        radius: Theme.r(2.5)
                        color: Theme.primary

                        Behavior on width {
                            enabled: !seekArea.pressed && !Theme.isSimple
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Rectangle {
                    width: seekArea.containsMouse || seekArea.pressed ? 12 : 0
                    height: width
                    radius: Theme.r(width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(parent.width - width, parent.width * seekBar.progressRatio - width / 2))
                    color: Theme.primary
                    visible: root.hasPlayer && root.trackLength > 0

                    Behavior on width {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.hasPlayer && root.player.canSeek && root.player.positionSupported && root.trackLength > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

                    function seekToMouse(mx: real): void {
                        const ratio = Math.max(0.0, Math.min(1.0, mx / width));
                        const targetSec = ratio * root.trackLength;
                        root.displayPosition = targetSec;
                        const delta = targetSec - (root.player.position || 0);
                        root.player.seek(delta);
                    }

                    onPressed: mouse => {
                        root.seekingChanged(true);
                        seekToMouse(mouse.x);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            seekToMouse(mouse.x);
                    }
                    onReleased: root.seekingChanged(false)
                    onCanceled: root.seekingChanged(false)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: root.formatTime(root.displayPosition)
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.formatTime(root.trackLength)
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }
            }
        }

        // --- Transport Controls (Prev / Play-Pause / Next) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 12

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: Theme.r(17)
                color: prevArea.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                border.width: Theme.activeControlBorderWidth
                border.color: Theme.cardBorder
                opacity: (root.hasPlayer && root.player.canGoPrevious) ? 1.0 : 0.45
                scale: prevArea.pressed ? 0.90 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰒮"
                    font.family: Theme.iconFont
                    font.pixelSize: 16
                    color: Theme.fgSurface
                }

                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.hasPlayer && root.player.canGoPrevious
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.player.previous()
                }
            }

            // Play / Pause
            Rectangle {
                implicitWidth: 46
                implicitHeight: 34
                radius: Theme.r(17)
                color: playArea.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                opacity: (root.hasPlayer && root.player.canTogglePlaying) ? 1.0 : 0.50
                scale: playArea.pressed ? 0.90 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    anchors.centerIn: parent
                    text: root.isPlaying ? "󰏤" : "󰐊"
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                    color: Theme.fgPrimary
                }

                MouseArea {
                    id: playArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.hasPlayer && root.player.canTogglePlaying
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.player.togglePlaying()
                }
            }

            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: Theme.r(17)
                color: nextArea.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                border.width: Theme.activeControlBorderWidth
                border.color: Theme.cardBorder
                opacity: (root.hasPlayer && root.player.canGoNext) ? 1.0 : 0.45
                scale: nextArea.pressed ? 0.90 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰒭"
                    font.family: Theme.iconFont
                    font.pixelSize: 16
                    color: Theme.fgSurface
                }

                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.hasPlayer && root.player.canGoNext
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.player.next()
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
