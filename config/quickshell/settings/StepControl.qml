pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

// Material 3 Expressive stepper control with morphing pill buttons and tonal value readout.
RowLayout {
    id: root

    property string label: ""
    property string displayValue: ""
    property bool controlEnabled: true
    property color accentColor: Theme.m3Primary

    signal decremented()
    signal incremented()

    Layout.fillWidth: true
    spacing: 8
    opacity: root.controlEnabled ? 1.0 : 0.45

    Text {
        Layout.fillWidth: true
        text: root.label
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(12)
        font.weight: Font.Medium
        color: Theme.m3Ink
    }

    Rectangle {
        implicitWidth: 32
        implicitHeight: 30
        radius: Theme.r(minusMouse.pressed ? 8 : 15)
        color: minusMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceHigh
        border.width: Theme.subBorderWidth
        border.color: Theme.m3Line
        scale: minusMouse.pressed ? 0.92 : 1.0

        Behavior on color {
            enabled: !Theme.reducedMotion
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "󰍴"
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(13)
            color: minusMouse.containsMouse ? Theme.m3OnSecondaryContainer : Theme.m3Ink
        }

        MouseArea {
            id: minusMouse
            anchors.fill: parent
            enabled: root.controlEnabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.decremented()
        }
    }

    Rectangle {
        Layout.preferredWidth: Math.max(64, valTxt.implicitWidth + 16)
        implicitHeight: 30
        radius: Theme.r(15)
        color: Theme.m3PrimaryContainer

        Text {
            id: valTxt
            anchors.centerIn: parent
            text: root.displayValue
            font.family: Theme.monoFont
            font.pixelSize: Theme.fs(11)
            font.weight: Font.Bold
            color: Theme.m3OnPrimaryContainer
        }
    }

    Rectangle {
        implicitWidth: 32
        implicitHeight: 30
        radius: Theme.r(plusMouse.pressed ? 8 : 15)
        color: plusMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceHigh
        border.width: Theme.subBorderWidth
        border.color: Theme.m3Line
        scale: plusMouse.pressed ? 0.92 : 1.0

        Behavior on color {
            enabled: !Theme.reducedMotion
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on radius {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "󰐕"
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(13)
            color: plusMouse.containsMouse ? Theme.m3OnSecondaryContainer : Theme.m3Ink
        }

        MouseArea {
            id: plusMouse
            anchors.fill: parent
            enabled: root.controlEnabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.incremented()
        }
    }
}
