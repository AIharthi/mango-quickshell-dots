pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."
import "../m3"

// Material 3 Expressive System Monitor card (DarkShadowShell Blob resource trio + live sparkline).
Rectangle {
    id: root

    property bool active: false

    readonly property real cpuPercent: SystemTelemetry.cpuPercent
    readonly property var cpuHistory: SystemTelemetry.cpuHistory
    readonly property real ramPercent: SystemTelemetry.memPercent
    readonly property real ramUsedGb: SystemTelemetry.memUsedGb
    readonly property real ramTotalGb: SystemTelemetry.memTotalGb
    readonly property int cpuTempC: SystemTelemetry.cpuTempC
    readonly property real diskPercent: SystemTelemetry.diskPercent
    readonly property string uptimeLabel: SystemTelemetry.uptimeLabel
    readonly property string loadAvgLabel: SystemTelemetry.loadLabel
    readonly property string diskUsedLabel: SystemTelemetry.diskLabel

    onActiveChanged: {
        if (root.active)
            cpuSpark.requestPaint();
    }

    Connections {
        target: SystemTelemetry
        function onCpuHistoryChanged(): void {
            if (root.active)
                cpuSpark.requestPaint();
        }
    }

    radius: Theme.r(26)
    color: Theme.m3SurfaceC
    border.width: 1
    border.color: Theme.m3Line
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 6

            Text {
                text: "System"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: Font.Bold
                color: Theme.m3InkDim
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: SystemTelemetry.netDown.length > 0
                text: "↓ " + SystemTelemetry.netDown + "  ↑ " + SystemTelemetry.netUp
                font.family: Theme.monoFont
                font.pixelSize: Theme.fs(9)
                color: Theme.m3InkDim
            }

            Rectangle {
                implicitHeight: 18
                implicitWidth: upTxt.implicitWidth + 12
                radius: Theme.r(9)
                color: Theme.m3SurfaceHigh

                Text {
                    id: upTxt
                    anchors.centerIn: parent
                    text: "up " + root.uptimeLabel
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fs(9)
                    color: Theme.m3InkDim
                }
            }
        }

        // DarkShadowShell Overview M3Blob Resource Trio (pentagon CPU, cookie RAM, circle Disk/Temp)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 8

            Repeater {
                model: [
                    {
                        shape: "pentagon",
                        label: "CPU",
                        val: Math.round(root.cpuPercent) + "%",
                        sub: root.cpuTempC > 0 ? (root.cpuTempC + "°C") : ("Load " + root.loadAvgLabel),
                        hot: root.cpuPercent > 85
                    },
                    {
                        shape: "cookie",
                        label: "RAM",
                        val: Math.round(root.ramPercent) + "%",
                        sub: root.ramUsedGb.toFixed(1) + "/" + root.ramTotalGb.toFixed(0) + "G",
                        hot: root.ramPercent > 85
                    },
                    {
                        shape: DeviceCaps.hasBattery ? "flower" : "circle",
                        label: DeviceCaps.hasBattery ? "Battery" : "Disk",
                        val: DeviceCaps.hasBattery ? (DeviceCaps.batteryPercent + "%") : (Math.round(root.diskPercent) + "%"),
                        sub: DeviceCaps.hasBattery ? DeviceCaps.batteryStatus : root.diskUsedLabel,
                        hot: DeviceCaps.hasBattery ? DeviceCaps.batteryLow : (root.diskPercent > 90)
                    }
                ]

                delegate: Rectangle {
                    id: metricTile
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 88
                    radius: Theme.r(18)
                    color: Theme.m3SurfaceHigh

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 3

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 46
                            implicitHeight: 46

                            M3Blob {
                                anchors.fill: parent
                                kind: metricTile.modelData.shape
                                color: metricTile.modelData.hot ? Theme.m3ErrorContainer : Theme.m3PrimaryContainer
                            }

                            Text {
                                anchors.centerIn: parent
                                text: metricTile.modelData.val
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(11)
                                font.weight: Font.Bold
                                color: metricTile.modelData.hot ? Theme.m3OnErrorContainer : Theme.m3OnPrimaryContainer
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: metricTile.modelData.label + " · " + metricTile.modelData.sub
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.m3InkDim
                        }
                    }
                }
            }
        }

        // Live CPU Sparkline
        Canvas {
            id: cpuSpark
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 20
            Layout.preferredHeight: 30
            Layout.maximumHeight: 44
            renderStrategy: Canvas.Cooperative

            readonly property color strokeCol: root.cpuPercent > 85 ? Theme.m3Error : Theme.m3Primary
            onStrokeColChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const pts = root.cpuHistory || [];
                if (pts.length < 2 || width <= 4 || height <= 4)
                    return;
                const padY = 2;
                const usableH = height - padY * 2;
                const stepX = width / Math.max(1, pts.length - 1);

                ctx.beginPath();
                for (let i = 0; i < pts.length; i++) {
                    const x = i * stepX;
                    const y = height - padY - (Math.max(0, Math.min(100, pts[i])) / 100.0) * usableH;
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.strokeStyle = strokeCol;
                ctx.lineWidth = 2.0;
                ctx.stroke();

                ctx.lineTo(width, height);
                ctx.lineTo(0, height);
                ctx.closePath();
                const grad = ctx.createLinearGradient(0, 0, 0, height);
                grad.addColorStop(0, Qt.rgba(strokeCol.r, strokeCol.g, strokeCol.b, 0.28));
                grad.addColorStop(1, Qt.rgba(strokeCol.r, strokeCol.g, strokeCol.b, 0.02));
                ctx.fillStyle = grad;
                ctx.fill();
            }
        }
    }
}
