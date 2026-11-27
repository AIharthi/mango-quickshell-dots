pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive button with press corner morph (radius 20 -> 12).
Rectangle {
    id: b

    property string text: ""
    property string icon: ""
    property bool primary: false
    property string variant: primary ? "filled" : "tonal" // "filled" | "tonal" | "outlined" | "text" | "danger"
    property bool compact: false
    property bool buttonEnabled: true

    signal clicked()

    readonly property color ink: variant === "filled" ? Theme.m3OnPrimary
        : (variant === "danger" ? Theme.m3OnErrorContainer
        : ((variant === "outlined" || variant === "text") ? Theme.m3Primary : Theme.m3OnSecondaryContainer))

    implicitWidth: Math.max(variant === "text" ? (compact ? 48 : 64) : (compact ? 74 : 108), btnRow.implicitWidth + (compact ? 22 : 30))
    implicitHeight: compact ? 32 : 38
    radius: Theme.r(m.pressed ? 12 : (compact ? 16 : 19))
    opacity: buttonEnabled ? 1.0 : 0.45

    color: {
        if (variant === "filled")
            return m.containsMouse ? Qt.lighter(Theme.m3Primary, 1.08) : Theme.m3Primary;
        if (variant === "danger")
            return m.containsMouse ? Qt.lighter(Theme.m3ErrorContainer, 1.15) : Theme.m3ErrorContainer;
        if (variant === "outlined" || variant === "text")
            return m.containsMouse ? Theme.withAlpha(Theme.m3Primary, 0.12) : "transparent";
        return m.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer;
    }

    border.width: variant === "outlined" ? 1 : 0
    border.color: Theme.m3Outline
    scale: m.pressed ? 0.97 : 1.0

    Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 120 } }
    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

    Row {
        id: btnRow
        anchors.centerIn: parent
        spacing: compact ? 5 : 7

        Text {
            visible: b.icon.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: b.icon
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(b.compact ? 12 : 14)
            color: b.ink
        }

        Text {
            visible: b.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(b.compact ? 11 : 12)
            font.weight: Font.Medium
            color: b.ink
        }
    }

    MouseArea {
        id: m
        anchors.fill: parent
        enabled: b.buttonEnabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: b.clicked()
    }
}
