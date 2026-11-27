pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive 52x32 switch (knob grows from 16 -> 24 -> 28px with check/close glyph).
Rectangle {
    id: root

    property bool checked: false
    property color activeColor: Theme.m3Primary
    signal toggled()

    implicitWidth: 52
    implicitHeight: 32
    radius: Theme.isSimple ? 0 : Theme.r(16)
    color: root.checked
        ? root.activeColor
        : (swMouse.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceHighest)
    border.width: root.checked ? 0 : 2
    border.color: root.checked ? root.activeColor : Theme.m3Outline

    Behavior on color {
        enabled: !Theme.reducedMotion
        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: thumb
        readonly property real d: swMouse.pressed ? 28 : 24
        width: d
        height: d
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? (parent.width - d - 4) : (swMouse.pressed ? 2 : 4)
        radius: Theme.isSimple ? 0 : (d / 2)
        color: root.checked ? Theme.contrastInk(root.activeColor) : Theme.m3Outline

        Behavior on x {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutBack
                easing.overshoot: 1.5
            }
        }
        Behavior on width {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: !Theme.reducedMotion
            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            text: root.checked ? "󰄬" : "󰅖"
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(root.checked ? 12 : 11)
            color: root.checked ? root.activeColor : Theme.m3SurfaceHighest
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
