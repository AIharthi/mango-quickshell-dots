pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import ".."

RowLayout {
    id: root

    property var player: null

    readonly property bool hasMedia: root.player !== null
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

    spacing: hasMedia ? 10 : 0

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // --- Bold Compact Clock ---
    Text {
        id: clockText
        Layout.alignment: Qt.AlignVCenter
        text: Qt.formatDateTime(clock.date, "HH:mm")
        font.family: Theme.fontFamily
        font.pixelSize: 13
        font.weight: Font.Bold
        color: Theme.fgSurface
    }

    // --- Collapsible Spotify / MPRIS Mini-Player ---
    Item {
        id: mediaSection
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: root.hasMedia ? mediaRow.implicitWidth : 0
        implicitHeight: 24
        clip: true
        opacity: root.hasMedia ? 1.0 : 0.0
        visible: implicitWidth > 1

        Behavior on implicitWidth {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: mediaRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Subtle divider between Clock and Media
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 4
                implicitHeight: 4
                radius: 2
                color: root.isPlaying ? Theme.primary : Theme.outline
            }

            // Rotating Album Art Circle
            ClippingRectangle {
                id: artClip
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: Theme.primaryContainer

                rotation: 0
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 12000
                    loops: Animation.Infinite
                    running: root.isPlaying && root.visible
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

                // Fallback music icon when trackArtUrl is absent or loading
                Text {
                    anchors.centerIn: parent
                    visible: !artImage.visible
                    text: "󰎈"
                    font.family: Theme.iconFont
                    font.pixelSize: 12
                    color: Theme.fgPrimaryContainer
                }
            }

            // Elided Track Title & Artist
            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 215
                text: root.mediaLabel
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: root.isPlaying ? Theme.fgSurface : Theme.fgSurfaceVariant
            }

            // Animated 3-bar mini equalizer when playing (saneAspect Dynamic Island style)
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                visible: root.isPlaying

                Repeater {
                    model: [
                        { minH: 4, maxH: 13, dur: 420 },
                        { minH: 6, maxH: 16, dur: 310 },
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
                            running: root.isPlaying && root.visible
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
}
