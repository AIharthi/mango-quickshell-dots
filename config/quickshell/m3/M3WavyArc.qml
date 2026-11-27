pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Material 3 Expressive circular wavy ring (around album art, system meters, timers).
Item {
    id: wa

    property real value: 0.0
    property bool moving: true
    property bool wavy: ShellState.m3WavyProgress && !Theme.isSimple
    property real thick: ShellState.m3WaveThick
    property color color: Theme.m3Primary
    property color track: Theme.m3Track
    property real waves: 14
    property real phase: 0

    Timer {
        interval: 50
        repeat: true
        running: wa.visible && wa.moving && wa.wavy && !Theme.reducedMotion
        onTriggered: wa.phase = (Date.now() % 2200) / 2200 * Math.PI * 2
    }

    onPhaseChanged: cv.requestPaint()
    onValueChanged: cv.requestPaint()
    onThickChanged: cv.requestPaint()
    onWavyChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()
    onTrackChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        onPaint: {
            if (width <= 4 || height <= 4)
                return;
            const c = getContext("2d");
            c.reset();
            const t = Math.max(2, wa.thick);
            const amp = wa.wavy ? (1.6 + t * 0.35) : 0;
            const cx = width / 2, cy = height / 2;
            const r = Math.max(4, Math.min(width, height) / 2 - t / 2 - amp - 1);
            const f = Math.max(0.004, Math.min(1, wa.value));
            const s = -Math.PI / 2;
            const len = Math.PI * 2 * f;

            c.lineCap = "round";
            c.lineWidth = t;

            if (f < 0.99) {
                c.strokeStyle = wa.track;
                c.beginPath();
                c.arc(cx, cy, r, s + len + 0.22, s + Math.PI * 2 - 0.22);
                c.stroke();
            }

            c.strokeStyle = wa.color;
            c.beginPath();
            const n = Math.max(12, Math.round(len * r / 2));
            for (let i = 0; i <= n; i++) {
                const a = s + len * i / n;
                const k = Math.min(1, i / n * 8, (1 - i / n) * 8);
                const rr = r + amp * k * Math.sin(a * wa.waves - wa.phase);
                const x = cx + rr * Math.cos(a), y = cy + rr * Math.sin(a);
                if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
            }
            c.stroke();
        }
    }
}
