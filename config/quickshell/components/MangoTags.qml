pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../m3"

// Material 3 Expressive MangoWC Workspaces card with morphing active tile radius.
Rectangle {
    id: root

    property bool active: false
    property string screenName: ""
    readonly property string currentLayout: MangoState.layoutForScreen(root.screenName)
    readonly property int totalClients: MangoState.totalClientsForScreen(root.screenName)
    readonly property var tagsModel: MangoState.tagsForScreen(root.screenName)

    radius: Theme.r(26)
    color: Theme.m3SurfaceC
    border.width: 1
    border.color: Theme.m3Line
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false

            Text {
                text: "Workspaces"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.m3InkDim
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitHeight: 24
                implicitWidth: layoutLabel.implicitWidth + 16
                radius: Theme.r(12)
                color: layoutArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

                Text {
                    id: layoutLabel
                    anchors.centerIn: parent
                    text: "Layout: " + root.currentLayout
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.m3OnSecondaryContainer
                }

                MouseArea {
                    id: layoutArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 5
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: root.tagsModel

                delegate: Rectangle {
                    id: tagBtn
                    required property var modelData
                    readonly property bool isActive: tagBtn.modelData.is_active
                    readonly property bool isUrgent: tagBtn.modelData.is_urgent
                    readonly property bool isOccupied: tagBtn.modelData.client_count > 0

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 44
                    radius: Theme.isSimple ? 0 : Theme.r(tagMouse.pressed ? 10 : (tagBtn.isActive ? 22 : 12))
                    scale: tagMouse.pressed ? 0.92 : 1.0

                    Behavior on radius {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 240; easing.type: Theme.m3Springy; easing.overshoot: 1.5 }
                    }
                    Behavior on scale {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        enabled: !Theme.reducedMotion
                        ColorAnimation { duration: 150 }
                    }

                    color: {
                        if (tagBtn.isUrgent)
                            return Theme.m3Error;
                        if (tagBtn.isActive)
                            return Theme.m3Primary;
                        if (tagBtn.isOccupied)
                            return tagMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer;
                        return tagMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh;
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 1

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tagBtn.modelData.index
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fs(13)
                            font.weight: Font.Bold
                            color: {
                                if (tagBtn.isUrgent) return Theme.m3OnErrorContainer;
                                if (tagBtn.isActive) return Theme.m3OnPrimary;
                                return tagBtn.isOccupied ? Theme.m3OnSecondaryContainer : Theme.m3InkDim;
                            }
                        }

                        Rectangle {
                            visible: tagBtn.isOccupied && !tagBtn.isActive
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 12
                            height: 3
                            radius: 1.5
                            color: tagBtn.isUrgent ? Theme.m3OnErrorContainer : Theme.m3Primary
                        }
                    }

                    MouseArea {
                        id: tagMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                Quickshell.execDetached(["mmsg", "dispatch", "toggletag," + tagBtn.modelData.index + ",0"]);
                            else
                                Quickshell.execDetached(["mmsg", "dispatch", "view," + tagBtn.modelData.index + ",0"]);
                        }
                    }
                }
            }

            // 10th Overview Tile
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 44
                radius: Theme.r(ovMouse.pressed ? 10 : 14)
                color: ovMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceHigh
                scale: ovMouse.pressed ? 0.92 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰕮"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(14)
                        color: ovMouse.containsMouse ? Theme.m3OnSecondaryContainer : Theme.m3Primary
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.totalClients > 0 ? (root.totalClients + " win") : "Grid"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(8)
                        font.weight: Font.Medium
                        color: Theme.m3InkDim
                    }
                }

                MouseArea {
                    id: ovMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["mmsg", "dispatch", "toggleoverview"])
                }
            }
        }
    }
}
