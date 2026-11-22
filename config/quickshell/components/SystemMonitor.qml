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

    // RAM State
    property real ramPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0

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
        }

        root._prevTotal = totalAll;
        root._prevIdle = idleAll;
    }

    Process {
        id: sysProc
        command: ["sh", "-c", "head -n 1 /proc/stat; echo '---'; grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached):' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                if (parts.length >= 2) {
                    root.parseCpuStat(parts[0].trim());
                    root.parseMeminfo(parts[1].trim());
                }
            }
        }
    }

    Timer {
        interval: 1800
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "󰍛  SYSTEM MONITOR"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitHeight: 16
                implicitWidth: liveText.implicitWidth + 10
                radius: Theme.r(8)
                color: Theme.withAlpha(Theme.success, 0.18)

                Text {
                    id: liveText
                    anchors.centerIn: parent
                    text: "LIVE"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Theme.success
                }
            }
        }

        // --- CPU Usage ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "CPU Load"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Math.round(root.cpuPercent) + "%"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: root.cpuPercent > 85 ? Theme.error : Theme.primary
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
                    width: parent.width * (Math.max(0, Math.min(100, root.cpuPercent)) / 100.0)
                    color: root.cpuPercent > 85 ? Theme.error : Theme.primary

                    Behavior on width {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
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
                    font.family: Theme.fontFamily
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

        Item { Layout.fillHeight: true }
    }
}
