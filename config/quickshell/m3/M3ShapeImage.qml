pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Picture clipped into an M3Blob shape (circle, cookie, verysunny, etc.) with optional smooth rotation.
Item {
    id: si

    property string source: ""
    property string kind: "cookie"
    property color empty: Theme.m3SurfaceHigh
    property string fallbackGlyph: "󰎆"
    property color fallbackColor: Theme.m3InkDim
    property bool spinning: false
    property int spinDurationMs: 26000
    property string loaded: ""
    property real ratio: 1.0
    property string held: ""

    RotationAnimation on rotation {
        from: 0
        to: 360
        duration: si.spinDurationMs
        loops: Animation.Infinite
        running: si.spinning && si.visible && !Theme.reducedMotion && !Theme.isSimple
        onRunningChanged: {
            if (!running && (Theme.isSimple || Theme.reducedMotion))
                si.rotation = 0;
        }
    }

    onVisibleChanged: {
        if (visible && si.loaded !== "" && si.loaded === si.source)
            cv.requestPaint();
    }

    Image {
        id: probe
        visible: false
        asynchronous: true
        cache: true
        sourceSize: Qt.size(160, 160)
        source: si.source
        onStatusChanged: {
            if (status === Image.Ready && implicitWidth > 0) {
                si.ratio = implicitHeight / implicitWidth;
                if (si.source.length > 0) {
                    if (cv.isImageLoaded(si.source)) {
                        si.loaded = si.source;
                        cv.requestPaint();
                    } else {
                        cv.loadImage(si.source);
                    }
                }
            }
        }
    }

    M3Blob {
        id: shape
        anchors.fill: parent
        kind: si.kind
        color: si.empty
        visible: si.loaded === "" || si.loaded !== si.source
        onSqrChanged: cv.requestPaint()

        Text {
            anchors.centerIn: parent
            text: si.fallbackGlyph
            font.family: Theme.iconFont
            font.pixelSize: Math.max(10, Math.round(Math.min(parent.width, parent.height) * 0.42))
            color: si.fallbackColor
        }
    }

    Canvas {
        id: cv
        anchors.fill: parent
        visible: si.loaded !== "" && si.loaded === si.source
        renderStrategy: Canvas.Cooperative

        onImageLoaded: {
            if (si.source !== "" && isImageLoaded(si.source)) {
                si.loaded = si.source;
                requestPaint();
            }
        }
        onPaint: {
            if (width <= 1 || height <= 1)
                return;
            const c = getContext("2d");
            c.reset();
            if (si.source === "" || !isImageLoaded(si.source))
                return;
            shape.trace(c, width, height, 1);
            c.clip();
            const iw = width;
            const ih = width * si.ratio;
            const k = Math.max(width / Math.max(1, iw), height / Math.max(1, ih));
            c.drawImage(si.source, (width - iw * k) / 2, (height - ih * k) / 2, iw * k, ih * k);
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    onSourceChanged: {
        if (held !== "" && held !== source)
            cv.unloadImage(held);
        held = source;
        if (source === "") {
            loaded = "";
            return;
        }
        if (cv.isImageLoaded(source)) {
            loaded = source;
            cv.requestPaint();
        } else {
            cv.loadImage(source);
        }
    }

    onKindChanged: cv.requestPaint()

    Component.onCompleted: {
        if (source !== "") {
            held = source;
            if (cv.isImageLoaded(source)) {
                loaded = source;
                cv.requestPaint();
            } else {
                cv.loadImage(source);
            }
        }
    }

    Component.onDestruction: {
        if (held !== "")
            cv.unloadImage(held);
    }
}
