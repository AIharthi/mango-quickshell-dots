pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive thick split-track slider with upright bar handle and drag value pill.
Item {
    id: sl

    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0.01
    property string unit: ""
    property real dragValue: 0
    property bool dragging: false
    property bool sliderEnabled: true

    readonly property real shown: dragging ? dragValue : (isFinite(value) ? value : from)
    readonly property real pos: to > from ? Math.max(0, Math.min(1, (shown - from) / (to - from))) : 0
    readonly property real hx: Math.max(0, (sl.width - 4) * sl.pos)

    signal moved(real v)
    signal released(real v)

    implicitWidth: 200
    implicitHeight: 32
    opacity: sliderEnabled ? 1.0 : 0.45

    // Active filled left track
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: 0
        width: Math.max(0, sl.hx - 5)
        height: 14
        radius: Theme.r(7)
        color: Theme.m3Primary

        Behavior on width {
            enabled: !sl.dragging && !Theme.reducedMotion
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    // Inactive right track + terminal stop dot
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: sl.hx + 9
        width: Math.max(0, sl.width - x)
        height: 14
        radius: Theme.r(7)
        color: Theme.m3SurfaceHighest

        Behavior on x {
            enabled: !sl.dragging && !Theme.reducedMotion
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Rectangle {
            visible: parent.width > 14
            anchors.right: parent.right
            anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 4
            radius: Theme.r(2)
            color: Theme.m3Primary
        }
    }

    // Upright handle + drag value tooltip
    Rectangle {
        width: 4
        height: sl.dragging ? 32 : 26
        radius: Theme.r(2)
        color: Theme.m3Primary
        anchors.verticalCenter: parent.verticalCenter
        x: sl.hx

        Behavior on x {
            enabled: !sl.dragging && !Theme.reducedMotion
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: !Theme.reducedMotion
            NumberAnimation { duration: 110 }
        }

        Rectangle {
            visible: sl.dragging
            anchors.horizontalCenter: parent.horizontalCenter
            y: -34
            width: Math.max(36, vt.implicitWidth + 16)
            height: 26
            radius: Theme.r(13)
            color: Theme.m3InverseSurface
            z: 20

            Text {
                id: vt
                anchors.centerIn: parent
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.m3InverseInk
                text: (Math.abs(sl.step) >= 1 ? String(Math.round(sl.shown)) : Number(sl.shown).toFixed(2)) + sl.unit
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: sl.sliderEnabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        function updateVal(mx) {
            const p = Math.max(0, Math.min(1, mx / Math.max(1, sl.width)));
            const raw = sl.from + p * (sl.to - sl.from);
            const nv = Math.max(sl.from, Math.min(sl.to, Math.round(raw / sl.step) * sl.step));
            if (nv !== sl.dragValue) {
                sl.dragValue = nv;
                sl.moved(nv);
            }
        }

        onPressed: function(mouse) {
            sl.dragging = true;
            updateVal(mouse.x);
        }
        onPositionChanged: function(mouse) {
            if (sl.dragging)
                updateVal(mouse.x);
        }
        onReleased: {
            sl.dragging = false;
            sl.released(sl.dragValue);
        }
        onCanceled: {
            sl.dragging = false;
        }
    }
}
