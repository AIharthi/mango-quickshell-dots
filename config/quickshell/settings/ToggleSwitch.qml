import QtQuick
import ".."

Rectangle {
    id: root

    property bool checked: false
    property color activeColor: Theme.primary
    signal toggled()

    implicitWidth: 44
    implicitHeight: 24
    radius: Theme.r(12)
    color: root.checked
        ? root.activeColor
        : (swMouse.containsMouse ? Theme.hoverBg : Theme.surfaceContainerHighest)
    border.width: Theme.isSimple ? 1 : 0
    border.color: root.checked ? root.activeColor : Theme.outlineVariant
    scale: swMouse.pressed ? 0.94 : 1.0

    Behavior on color {
        enabled: !Theme.isSimple
        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        enabled: !Theme.isSimple
        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: thumb
        width: 18
        height: 18
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? (parent.width - width - 3) : 3
        radius: Theme.r(9)
        color: root.checked ? Theme.fgPrimary : Theme.fgSurfaceVariant

        Behavior on x {
            enabled: !Theme.isSimple
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }
        Behavior on color {
            enabled: !Theme.isSimple
            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: swMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
