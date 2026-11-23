pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Rectangle {
    id: root

    property bool active: false

    // CPU State
    property real cpuPercent: 0
    property real _prevTotal: 0
    property real _prevIdle: 0
    property var cpuHistory: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    // RAM State
    property real ramPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0

    // Telemetry Footer State
    property int cpuTempC: -1
    property string uptimeLabel: "--"
    property string loadAvgLabel: "0.00"
    property string diskUsedLabel: "--%"

    function parseMeminfo(raw: string): void {
        if (!raw)
            return;
        let totalKb = 0;
        let availKb = -1;
        let freeKb = 0;
        let buffersKb = 0;
        let cachedKb = 0;

        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.startsWith("MemTotal:"))
                totalKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("MemAvailable:"))
                availKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("MemFree:"))
                freeKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("Buffers:"))
                buffersKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
            else if (line.startsWith("Cached:"))
                cachedKb = parseInt(line.replace(/[^0-9]/g, ""), 10) || 0;
        }

        if (totalKb <= 0)
            return;
        if (availKb < 0)
            availKb = freeKb + buffersKb + cachedKb;

        const usedKb = Math.max(0, totalKb - availKb);
        root.ramTotalGb = totalKb / (1024 * 1024);
        root.ramUsedGb = usedKb / (1024 * 1024);
        root.ramPercent = Math.max(0, Math.min(100, (usedKb / totalKb) * 100));
    }

    function parseCpuStat(raw: string): void {
        if (!raw)
            return;
        const firstLine = raw.split("\n")[0] || "";
        if (!firstLine.startsWith("cpu "))
            return;

        const parts = firstLine.trim().split(/\s+/);
        if (parts.length < 5)
            return;

        const user = parseFloat(parts[1]) || 0;
        const nice = parseFloat(parts[2]) || 0;
        const system = parseFloat(parts[3]) || 0;
        const idle = parseFloat(parts[4]) || 0;
        const iowait = parseFloat(parts[5]) || 0;
        const irq = parseFloat(parts[6]) || 0;
        const softirq = parseFloat(parts[7]) || 0;
        const steal = parseFloat(parts[8]) || 0;

        const idleAll = idle + iowait;
        const totalAll = user + nice + system + idleAll + irq + softirq + steal;

        if (root._prevTotal > 0 && totalAll > root._prevTotal) {
            const totalDelta = totalAll - root._prevTotal;
            const idleDelta = idleAll - root._prevIdle;
            const usage = ((totalDelta - idleDelta) / totalDelta) * 100;
            root.cpuPercent = Math.max(0, Math.min(100, usage));
            const nextHist = (root.cpuHistory || []).slice(-23);
            nextHist.push(root.cpuPercent);
            root.cpuHistory = nextHist;
            cpuSpark.requestPaint();
        }

        root._prevTotal = totalAll;
        root._prevIdle = idleAll;
    }

    function parseMeta(raw: string): void {
        if (!raw)
            return;
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line)
                continue;
            if (line.startsWith("UP:")) {
                const secs = Math.floor(parseFloat(line.slice(3)) || 0);
                const d = Math.floor(secs / 86400);
                const h = Math.floor((secs % 86400) / 3600);
                const m = Math.floor((secs % 3600) / 60);
                if (d > 0)
                    root.uptimeLabel = d + "d " + h + "h";
                else if (h > 0)
                    root.uptimeLabel = h + "h " + m + "m";
                else
                    root.uptimeLabel = Math.max(1, m) + "m";
            } else if (line.startsWith("LOAD:")) {
                root.loadAvgLabel = line.slice(5).trim();
            } else if (line.startsWith("DISK:")) {
                root.diskUsedLabel = line.slice(5).trim();
            } else if (line.startsWith("TEMP:")) {
                const rawT = parseInt(line.slice(5), 10) || 0;
                const deg = rawT > 1000 ? Math.round(rawT / 1000) : Math.round(rawT);
                if (deg > 0 && deg < 150)
                    root.cpuTempC = deg;
            }
        }
    }

    Process {
        id: sysProc
        command: [
            "sh", "-c",
            "head -n 1 /proc/stat; echo '---'; grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached):' /proc/meminfo; echo '---'; " +
            "awk '{print \"UP:\" $1}' /proc/uptime 2>/dev/null || true; " +
            "awk '{print \"LOAD:\" $1}' /proc/loadavg 2>/dev/null || true; " +
            "df -P / 2>/dev/null | awk 'NR==2{print \"DISK:\" $5}' || true; " +
            "for t in /sys/class/hwmon/hwmon*/temp1_input /sys/class/thermal/thermal_zone*/temp; do " +
            "[ -r \"$t\" ] && v=$(cat \"$t\" 2>/dev/null) && [ -n \"$v\" ] && [ \"$v\" -gt 10000 ] 2>/dev/null && echo \"TEMP:$v\" && break; done || true"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                if (parts.length >= 2) {
                    root.parseCpuStat(parts[0].trim());
                    root.parseMeminfo(parts[1].trim());
                }
                if (parts.length >= 3) {
                    root.parseMeta(parts[2].trim());
                }
            }
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!sysProc.running)
                sysProc.running = true;
        }
    }

    radius: Theme.r(18)
    color: Theme.cardBg
    border.width: Theme.cardBorderWidth
    border.color: Theme.cardBorder
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: DeviceCaps.hasBattery ? 6 : 8

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

            Rectangle {
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: Theme.success
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
                Layout.minimumHeight: DeviceCaps.hasBattery ? 18 : 26
                Layout.maximumHeight: 104
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
                        text: DeviceCaps.batteryPercent + "% · " + DeviceCaps.batteryStatus
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
                        col: root.cpuTempC >= 80 ? Theme.error : Theme.warning
                    },
                    {
                        icon: "󰓅",
                        lbl: "Load " + root.loadAvgLabel,
                        col: Theme.secondary
                    },
                    {
                        icon: "󰋊",
                        lbl: "Root " + root.diskUsedLabel,
                        col: Theme.primary
                    }
                ]

                delegate: Rectangle {
                    id: metaChip
                    required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 22
                        radius: Theme.r(8)
                        color: Theme.subCardBg
                        border.width: Theme.subBorderWidth
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
