pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive wavy progress line with upright bar handle and optional drag seeking.
Item {
    id: wl

    property real value: 0.0
    property bool moving: true
    property bool wavy: ShellState.m3WavyProgress && !Theme.isSimple
    property real thick: ShellState.m3WaveThick
    property color color: Theme.m3Primary
    property color track: Theme.m3Track
    property bool handle: true
    property bool seekable: false
    property real phase: 0

    readonly property bool isDragging: drag.pressed
    readonly property real shown: drag.pressed ? drag.v : value

    signal moved(real v)
    signal draggingChanged(bool active)

    implicitHeight: 18

    Timer {
        interval: 50
        repeat: true
        running: wl.visible && wl.moving && wl.wavy && !Theme.reducedMotion
        onTriggered: wl.phase = (Date.now() % 1600) / 1600 * Math.PI * 2
    }

    onPhaseChanged: cv.requestPaint()
    onShownChanged: cv.requestPaint()
    onThickChanged: cv.requestPaint()
    onWavyChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()
    onTrackChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            if (width <= 2 || height <= 2)
                return;
            const c = getContext("2d");
            c.reset();
            const w = width, mid = height / 2, t = Math.max(2, wl.thick);
            const f = Math.max(0, Math.min(1, wl.shown));
            const hx = Math.max(t / 2, (w - t) * f);
            const gap = wl.handle ? 7 : 4;

            c.lineCap = "round";
            c.lineWidth = t;

            // Inactive track + terminal dot
            if (hx + gap + t < w - t / 2) {
                c.strokeStyle = wl.track;
                c.beginPath();
                c.moveTo(hx + gap + t / 2, mid);
                c.lineTo(w - t / 2, mid);
                c.stroke();

                c.fillStyle = wl.color;
                c.beginPath();
                c.arc(w - t / 2, mid, Math.max(1.5, t / 2 - 0.5), 0, Math.PI * 2);
                c.fill();
            }

            // Active wavy (or flat) segment
            const amp = wl.wavy ? Math.min(Math.max(0.5, mid - t / 2 - 1), 2.2 + t * 0.45) * Math.sin(Math.PI * f) : 0;
            const wlen = 20 + t * 2.5;
            const endX = hx - (wl.handle ? gap : 0);
            if (endX > t / 2) {
                c.strokeStyle = wl.color;
                c.beginPath();
                for (let x = t / 2; x <= endX; x += 2) {
                    const y = mid + amp * Math.sin(x / wlen * Math.PI * 2 - wl.phase);
                    if (x === t / 2) c.moveTo(x, y); else c.lineTo(x, y);
                }
                c.stroke();
            }

            // Upright M3 handle bar
            if (wl.handle) {
                c.strokeStyle = wl.color;
                c.lineWidth = Math.max(3, t);
                c.beginPath();
                c.moveTo(hx, mid - height / 2 + 2);
                c.lineTo(hx, mid + height / 2 - 2);
                c.stroke();
            }
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        enabled: wl.seekable
        cursorShape: wl.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
        property real v: 0

        function at(x) {
            return Math.max(0, Math.min(1, x / Math.max(1, width)));
        }
        onPressed: function(m) {
            v = at(m.x);
            wl.draggingChanged(true);
        }
        onPositionChanged: function(m) {
            if (pressed)
                v = at(m.x);
        }
        onReleased: {
            wl.draggingChanged(false);
            wl.moved(v);
        }
        onCanceled: wl.draggingChanged(false)
    }
}
