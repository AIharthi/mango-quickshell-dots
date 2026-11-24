pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: root

    property bool active: false

    readonly property real cpuPercent: SystemTelemetry.cpuPercent
    readonly property var cpuHistory: SystemTelemetry.cpuHistory
    readonly property real ramPercent: SystemTelemetry.memPercent
    readonly property real ramUsedGb: SystemTelemetry.memUsedGb
    readonly property real ramTotalGb: SystemTelemetry.memTotalGb
    readonly property int cpuTempC: SystemTelemetry.cpuTempC
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

    radius: Theme.r(18)
    color: Theme.cardBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 11
        spacing: DeviceCaps.hasBattery ? 5 : 7

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 6

            Text {
                text: "System Monitor"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: SystemTelemetry.netDown.length > 0
                text: "↓" + SystemTelemetry.netDown + " ↑" + SystemTelemetry.netUp
                font.family: Theme.monoFont
                font.pixelSize: 9
                color: Theme.fgSurfaceVariant
            }

            Rectangle {
                implicitHeight: 16
                implicitWidth: upTxt.implicitWidth + 10
                radius: Theme.r(8)
                color: Theme.subCardBg

                Text {
                    id: upTxt
                    anchors.centerIn: parent
                    text: "up " + root.uptimeLabel
                    font.family: Theme.monoFont
                    font.pixelSize: 9
                    color: Theme.fgSurfaceVariant
                }
            }
        }

        // --- CPU Usage + Live Rolling Sparkline ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "CPU Load"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Math.round(root.cpuPercent) + "%"
                    font.family: Theme.monoFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: root.cpuPercent > 85 ? Theme.error : Theme.primary
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: Theme.r(3)
                color: Theme.surfaceContainerHighest

                Rectangle {
                    height: parent.height
                    radius: Theme.r(3)
                    width: parent.width * (Math.max(0, Math.min(100, root.cpuPercent)) / 100.0)
                    color: root.cpuPercent > 85 ? Theme.error : Theme.primary

                    Behavior on width {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }
                }
            }

            Canvas {
                id: cpuSpark
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: DeviceCaps.hasBattery ? 16 : 22
                Layout.preferredHeight: DeviceCaps.hasBattery ? 24 : 34
                Layout.maximumHeight: 54
                antialiasing: true

                readonly property color strokeCol: root.cpuPercent > 85 ? Theme.error : Theme.primary
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
                        if (i === 0)
                            ctx.moveTo(x, y);
                        else
                            ctx.lineTo(x, y);
                    }
                    ctx.strokeStyle = strokeCol;
                    ctx.lineWidth = 1.6;
                    ctx.stroke();

                    ctx.lineTo(width, height);
                    ctx.lineTo(0, height);
                    ctx.closePath();
                    const grad = ctx.createLinearGradient(0, 0, 0, height);
                    grad.addColorStop(0, Qt.rgba(strokeCol.r, strokeCol.g, strokeCol.b, 0.30));
                    grad.addColorStop(1, Qt.rgba(strokeCol.r, strokeCol.g, strokeCol.b, 0.02));
                    ctx.fillStyle = grad;
                    ctx.fill();
                }
            }
        }

        // --- Memory Usage ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Memory"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                    Text {
                        text: root.ramUsedGb.toFixed(1) + " / " + root.ramTotalGb.toFixed(1) + " GB  (" + Math.round(root.ramPercent) + "%)"
                        font.family: Theme.monoFont
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: root.ramPercent > 85 ? Theme.warning : Theme.secondary
                    }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: Theme.r(4)
                color: Theme.surfaceContainerHighest

                Rectangle {
                    height: parent.height
                    radius: Theme.r(4)
                    width: parent.width * (Math.max(0, Math.min(100, root.ramPercent)) / 100.0)
                    color: root.ramPercent > 85 ? Theme.warning : Theme.secondary

                    Behavior on width {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        // --- Hardware-Aware Battery (Laptops only) ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: DeviceCaps.hasBattery

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: DeviceCaps.batteryIcon + "  Battery"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                    Text {
                        text: DeviceCaps.batteryPercent + "% · " + (DeviceCaps.batteryEta.length > 0 ? (DeviceCaps.batteryStatus + " · " + DeviceCaps.batteryEta) : DeviceCaps.batteryStatus)
                        font.family: Theme.monoFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: DeviceCaps.batteryLow
                            ? Theme.error
                            : (DeviceCaps.batteryCharging ? Theme.success : Theme.tertiary)
                    }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: Theme.r(3)
                color: Theme.surfaceContainerHighest

                Rectangle {
                    height: parent.height
                    radius: Theme.r(3)
                    width: parent.width * (Math.max(0, Math.min(100, DeviceCaps.batteryPercent)) / 100.0)
                    color: DeviceCaps.batteryLow
                        ? Theme.error
                        : (DeviceCaps.batteryCharging ? Theme.success : Theme.tertiary)

                    Behavior on width {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        // --- Telemetry Chip Strip (Temp, Load Avg, Root Disk) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    {
                        icon: "󰔏",
                        lbl: root.cpuTempC > 0 ? (root.cpuTempC + "°C") : "--°C",
                        col: root.cpuTempC >= 80 ? Theme.error : Theme.fgSurfaceVariant
                    },
                    {
                        icon: "󰓅",
                        lbl: "Load " + root.loadAvgLabel,
                        col: Theme.fgSurfaceVariant
                    },
                    {
                        icon: "󰋊",
                        lbl: "Root " + root.diskUsedLabel,
                        col: Theme.fgSurfaceVariant
                    }
                ]

                delegate: Rectangle {
                    id: metaChip
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 22
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: Theme.activeControlBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4

                            Item { Layout.fillWidth: true }

                            Text {
                                text: metaChip.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: metaChip.modelData.col
                            }

                            Text {
                                Layout.maximumWidth: Math.max(24, metaChip.width - 28)
                                elide: Text.ElideRight
                                text: metaChip.modelData.lbl
                                font.family: Theme.monoFont
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }
                    }
                }
            }
        }
    }
}
