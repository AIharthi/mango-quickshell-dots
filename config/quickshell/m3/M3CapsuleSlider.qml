pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 46px tall capsule slider (brightness, volume, microphone) from DarkShadowShell ControlCenter.
Item {
    id: ln

    property string icon: ""
    property string label: ""
    property real value: 0.0
    property real maxValue: 1.0
    property bool muted: false
    property bool compact: false
    property bool sliderEnabled: true
    property bool showPercent: true
    property color activeColor: Theme.m3Primary

    signal moved(real v)
    signal iconClicked()
    signal rightClicked()
    signal draggingChanged(bool dragging)

    implicitHeight: ln.compact ? 38 : 46
    opacity: sliderEnabled ? 1.0 : 0.45

    readonly property real norm: Math.max(0.0, Math.min(1.0, value / Math.max(0.1, maxValue)))
    readonly property int pct: Math.round(value * 100)
    property bool _sized: false
    readonly property real fillRatio: ln.width > 0 ? (fillRect.width / ln.width) : ln.norm
    onWidthChanged: if (!_sized && width > 0) Qt.callLater(function() { ln._sized = true; })

    Rectangle {
        anchors.fill: parent
        radius: Theme.r(Math.round(height / 2))
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        Rectangle {
            id: fillRect
            width: ln.muted ? height : Math.max(height, Math.round(parent.width * ln.norm))
            height: parent.height
            radius: Theme.r(Math.round(height / 2))
            color: ln.muted ? Theme.m3SurfaceHigh : ln.activeColor

            Behavior on width {
                enabled: ln._sized && !lm.pressed && !Theme.reducedMotion
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                enabled: !Theme.reducedMotion
                ColorAnimation { duration: 140 }
            }
        }
    }

    MouseArea {
        id: lm
        anchors.fill: parent
        anchors.leftMargin: ln.height
        enabled: ln.sliderEnabled
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        function at(x) {
            return Math.max(0.0, Math.min(ln.maxValue, ((x + ln.height) / Math.max(1, ln.width)) * ln.maxValue));
        }

        onPressed: function(m) {
            if (m.button === Qt.RightButton) {
                ln.rightClicked();
                return;
            }
            ln.draggingChanged(true);
            ln.moved(at(m.x));
        }
        onPositionChanged: function(m) {
            if (pressed && (m.buttons & Qt.LeftButton))
                ln.moved(at(m.x));
        }
        onReleased: ln.draggingChanged(false)
        onCanceled: ln.draggingChanged(false)
        onWheel: function(e) {
            const delta = (e.pixelDelta && e.pixelDelta.y !== 0) ? (e.pixelDelta.y / 50) : (e.angleDelta.y / 120);
            ln.moved(Math.max(0.0, Math.min(ln.maxValue, ln.value + delta * 0.05)));
        }
    }

    // Left square circular icon tap zone (mute / unmute / output switch)
    Item {
        width: ln.height
        height: ln.height

        Text {
            anchors.centerIn: parent
            text: ln.icon
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(ln.compact ? 15 : 17)
            color: ln.muted ? Theme.m3InkDim : Theme.contrastInk(ln.activeColor)
        }

        MouseArea {
            anchors.fill: parent
            enabled: ln.sliderEnabled
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(m) {
                if (m.button === Qt.RightButton)
                    ln.rightClicked();
                else
                    ln.iconClicked();
            }
        }
    }

    // Optional label + percentage inside right end
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            visible: ln.label.length > 0 && ln.width > 200
            anchors.verticalCenter: parent.verticalCenter
            text: ln.label
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(11)
            font.weight: Font.Medium
            color: ln.fillRatio > 0.72 && !ln.muted ? Theme.contrastInk(ln.activeColor) : Theme.m3InkDim
        }

        Text {
            visible: ln.showPercent
            anchors.verticalCenter: parent.verticalCenter
            text: ln.muted ? "Mute" : (ln.pct + "%")
            font.family: Theme.monoFont
            font.pixelSize: Theme.fs(11)
            font.weight: Font.Bold
            color: ln.fillRatio > 0.85 && !ln.muted ? Theme.contrastInk(ln.activeColor) : Theme.m3Ink
        }
    }
}
