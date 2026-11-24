pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpuPercent: 0
    property var cores: []
    property real freqGhz: 0.0
    property real memUsedGb: 0.0
    property real memTotalGb: 0.0
    property int memPercent: 0
    property int swapPercent: 0
    property real netRxBps: 0
    property real netTxBps: 0
    property string netDown: "0B/s"
    property string netUp: "0B/s"
    property string netIface: ""
    property int diskPercent: 0
    property string diskLabel: "--%"
    property string diskFreeLabel: ""
    property int cpuTempC: -1
    property int gpuTempC: -1
    property int uptimeSec: 0
    property string uptimeLabel: "--"
    property string loadLabel: "0.00"
    property real batteryWatts: 0.0
    property string batteryEta: ""
    property int batteryHealth: 100
    property var cpuHistory: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    property bool _usingFallback: false
    property bool _sawStreamData: false
    property real _prevTotal: 0
    property real _prevIdle: 0

    function _pushCpuHistory(pct: int): void {
        const nextHist = (root.cpuHistory || []).slice(-23);
        nextHist.push(Math.max(0, Math.min(100, pct)));
        root.cpuHistory = nextHist;
    }

    function _applyLine(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            root._sawStreamData = true;
            root._usingFallback = false;
            if (typeof d.cpuPercent === "number") {
                const cp = Math.max(0, Math.min(100, Math.round(d.cpuPercent)));
                root.cpuPercent = cp;
                root._pushCpuHistory(cp);
            }
            if (Array.isArray(d.cores))
                root.cores = d.cores;
            if (typeof d.freqGhz === "number")
                root.freqGhz = d.freqGhz;
            if (typeof d.memUsedGb === "number")
                root.memUsedGb = d.memUsedGb;
            if (typeof d.memTotalGb === "number")
                root.memTotalGb = d.memTotalGb;
            if (typeof d.memPercent === "number")
                root.memPercent = Math.max(0, Math.min(100, Math.round(d.memPercent)));
            if (typeof d.swapPercent === "number")
                root.swapPercent = Math.max(0, Math.min(100, Math.round(d.swapPercent)));
            if (typeof d.netRxBps === "number")
                root.netRxBps = d.netRxBps;
            if (typeof d.netTxBps === "number")
                root.netTxBps = d.netTxBps;
            if (d.netDown !== undefined)
                root.netDown = String(d.netDown || "0B/s");
            if (d.netUp !== undefined)
                root.netUp = String(d.netUp || "0B/s");
            if (d.netIface !== undefined)
                root.netIface = String(d.netIface || "");
            if (typeof d.diskPercent === "number")
                root.diskPercent = Math.max(0, Math.min(100, Math.round(d.diskPercent)));
            if (d.diskLabel)
                root.diskLabel = String(d.diskLabel);
            if (d.diskFreeLabel !== undefined)
                root.diskFreeLabel = String(d.diskFreeLabel || "");
            if (typeof d.cpuTempC === "number")
                root.cpuTempC = d.cpuTempC > 0 ? Math.round(d.cpuTempC) : -1;
            if (typeof d.gpuTempC === "number")
                root.gpuTempC = d.gpuTempC > 0 ? Math.round(d.gpuTempC) : -1;
            if (typeof d.uptimeSec === "number")
                root.uptimeSec = Math.round(d.uptimeSec);
            if (d.uptimeLabel)
                root.uptimeLabel = String(d.uptimeLabel);
            if (d.loadLabel)
                root.loadLabel = String(d.loadLabel);
            if (d.battery && typeof d.battery === "object") {
                if (typeof d.battery.powerWatts === "number")
                    root.batteryWatts = d.battery.powerWatts;
                if (d.battery.etaLabel !== undefined)
                    root.batteryEta = String(d.battery.etaLabel || "");
                if (typeof d.battery.healthPercent === "number")
                    root.batteryHealth = Math.round(d.battery.healthPercent);
            }
        } catch (err) {}
    }

    function _parseFallback(raw: string): void {
        const parts = (raw || "").split("---");
        if (parts.length >= 1) {
            const firstLine = (parts[0].trim().split("\n")[0] || "");
            if (firstLine.startsWith("cpu ")) {
                const c = firstLine.trim().split(/\s+/);
                if (c.length >= 5) {
                    const user = parseFloat(c[1]) || 0;
                    const nice = parseFloat(c[2]) || 0;
                    const sys = parseFloat(c[3]) || 0;
                    const idle = parseFloat(c[4]) || 0;
                    const iowait = parseFloat(c[5]) || 0;
                    const irq = parseFloat(c[6]) || 0;
                    const softirq = parseFloat(c[7]) || 0;
                    const steal = parseFloat(c[8]) || 0;
                    const idleAll = idle + iowait;
                    const totalAll = user + nice + sys + idleAll + irq + softirq + steal;
                    if (root._prevTotal > 0 && totalAll > root._prevTotal) {
                        const dt = totalAll - root._prevTotal;
                        const di = idleAll - root._prevIdle;
                        const cp = Math.max(0, Math.min(100, Math.round(((dt - di) / dt) * 100)));
                        root.cpuPercent = cp;
                        root._pushCpuHistory(cp);
                    }
                    root._prevTotal = totalAll;
                    root._prevIdle = idleAll;
                }
            }
        }
        if (parts.length >= 2) {
            let totalKb = 0;
            let availKb = -1;
            let freeKb = 0;
            let buffersKb = 0;
            let cachedKb = 0;
            const lines = parts[1].trim().split("\n");
            for (let i = 0; i < lines.length; i++) {
                const ln = lines[i];
                if (ln.startsWith("MemTotal:")) totalKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("MemAvailable:")) availKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("MemFree:")) freeKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("Buffers:")) buffersKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
                else if (ln.startsWith("Cached:")) cachedKb = parseInt(ln.replace(/[^0-9]/g, ""), 10) || 0;
            }
            if (totalKb > 0) {
                if (availKb < 0)
                    availKb = freeKb + buffersKb + cachedKb;
                const usedKb = Math.max(0, totalKb - availKb);
                root.memTotalGb = totalKb / (1024 * 1024);
                root.memUsedGb = usedKb / (1024 * 1024);
                root.memPercent = Math.max(0, Math.min(100, Math.round((usedKb / totalKb) * 100)));
            }
        }
    }

    Process {
        id: streamProc
        command: [Quickshell.shellPath("bin/aurora-backend"), "telemetry", "--watch", "2000"]
        running: true
        stdout: SplitParser {
            onRead: line => root._applyLine(line)
        }
        onExited: {
            if (!root._sawStreamData) {
                root._usingFallback = true;
            } else {
                root._sawStreamData = false;
                restartTimer.restart();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 2500
        repeat: false
        onTriggered: {
            if (!streamProc.running && !root._usingFallback)
                streamProc.running = true;
        }
    }

    Process {
        id: fallbackProc
        command: ["sh", "-c", "head -n 1 /proc/stat; echo '---'; grep -E '^(MemTotal|MemAvailable|MemFree|Buffers|Cached):' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: root._parseFallback(text)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root._usingFallback
        triggeredOnStart: true
        onTriggered: {
            if (!fallbackProc.running)
                fallbackProc.running = true;
        }
    }
}
