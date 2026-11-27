pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive quick-toggle tile: pill -> squircle -> tight squircle morph with OutBack spring.
Rectangle {
    id: tl

    property string icon: ""
    property string label: ""
    property string sub: ""
    property bool active: false
    property color accentColor: Theme.m3Primary
    property bool tileEnabled: true

    signal clicked()
    signal rightClicked()

    implicitHeight: 68
    radius: Theme.r(tm.pressed ? 14 : (tl.active ? 22 : 34))
    opacity: tileEnabled ? 1.0 : 0.45
    color: tl.active
        ? tl.accentColor
        : (tm.containsMouse ? Theme.m3SurfaceHigh : Theme.m3SurfaceC)
    border.width: Theme.isSimple ? 1 : (Theme.activeControlBorderWidth > 0 && tl.active ? Theme.activeControlBorderWidth : 1)
    border.color: tl.active ? tl.accentColor : Theme.m3Line
    scale: tm.pressed ? 0.95 : 1.0

    Behavior on radius {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 260; easing.type: Theme.m3Springy; easing.overshoot: 1.8 }
    }
    Behavior on color {
        enabled: !Theme.reducedMotion
        ColorAnimation { duration: 150 }
    }
    Behavior on scale {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
    }

    readonly property color inkCol: tl.active ? Theme.contrastInk(tl.accentColor) : Theme.m3Ink

    Column {
        anchors.centerIn: parent
        width: Math.max(20, tl.width - 12)
        spacing: 4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tl.icon
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(19)
            color: tl.inkCol
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: tl.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            font.weight: Font.Medium
            color: tl.inkCol
        }

        Text {
            visible: tl.sub.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: tl.sub
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(9)
            color: tl.active ? Theme.withAlpha(tl.inkCol, 0.80) : Theme.m3InkDim
        }
    }

    MouseArea {
        id: tm
        anchors.fill: parent
        enabled: tl.tileEnabled
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                tl.rightClicked();
            else
                tl.clicked();
        }
    }
}
