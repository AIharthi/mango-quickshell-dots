pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

RowLayout {
    id: root

    property string label: ""
    property string displayValue: ""
    property bool controlEnabled: true
    property color accentColor: Theme.primary

    signal decremented()
    signal incremented()

    Layout.fillWidth: true
    spacing: 8
    opacity: root.controlEnabled ? 1.0 : 0.45

    Text {
        Layout.fillWidth: true
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(11)
        color: Theme.fgSurface
    }

    Rectangle {
        implicitWidth: 26
        implicitHeight: 24
        radius: Theme.r(7)
        color: minusMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        scale: minusMouse.pressed ? 0.92 : 1.0

        Behavior on color {
            enabled: !Theme.reducedMotion
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "-"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            font.weight: Font.Bold
            color: Theme.fgSurface
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

    Text {
        Layout.preferredWidth: 58
        horizontalAlignment: Text.AlignHCenter
        text: root.displayValue
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(11)
        font.weight: Font.Bold
        color: root.accentColor
    }

    Rectangle {
        implicitWidth: 26
        implicitHeight: 24
        radius: Theme.r(7)
        color: plusMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        scale: plusMouse.pressed ? 0.92 : 1.0

        Behavior on color {
            enabled: !Theme.reducedMotion
            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: "+"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(12)
            font.weight: Font.Bold
            color: Theme.fgSurface
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
