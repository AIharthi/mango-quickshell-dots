pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Hardware Capability Flags (populated by scripts/detect-hardware.sh) ---
    property bool probed: false
    property bool hasWifi: false
    property bool hasBluetooth: false
    property bool hasBacklight: false
    property bool hasBattery: false
    property string batteryPath: ""
    property bool hasTouchpad: false
    property bool hasWlrRandr: false
    property bool hasAudio: false
    property bool hasPavucontrol: false
    property bool hasLocker: false
    property string lockerCmd: ""
    property string deviceType: "desktop"       // "desktop" | "laptop"
    property string hostname: ""
    property string distro: "Linux"
    property string kernel: ""

    readonly property bool hasExtraQuickControls: hasBacklight || hasWifi || hasBluetooth

    // --- Battery State (only polled when hasBattery is true) ---
    property int batteryPercent: 100
    property string batteryStatus: "Full"
    property bool batteryCharging: false
    property bool batteryLow: false

    readonly property string batteryIcon: {
        if (root.batteryCharging)
            return "󰂄";
        if (root.batteryPercent >= 90)
            return "󰁹";
        if (root.batteryPercent >= 65)
            return "󰂁";
        if (root.batteryPercent >= 35)
            return "󰁾";
        return "󰁻";
    }

    function refresh(): void {
        if (!probeProc.running)
            probeProc.running = true;
    }

    function refreshBattery(): void {
        if (!root.hasBattery || root.batteryPath.length === 0)
            return;
        if (!batteryProc.running) {
            batteryProc.command = [
                "sh", "-c",
                "cat \"$1/capacity\" 2>/dev/null; echo '---'; cat \"$1/status\" 2>/dev/null",
                "_", root.batteryPath
            ];
            batteryProc.running = true;
        }
    }

    onHasBatteryChanged: {
        if (root.hasBattery && root.batteryPath.length > 0)
            refreshBattery();
    }

    onBatteryPathChanged: {
        if (root.hasBattery && root.batteryPath.length > 0)
            refreshBattery();
    }

    Component.onCompleted: refresh()

    Process {
        id: probeProc
        command: [Quickshell.shellPath("scripts/detect-hardware.sh")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const data = JSON.parse(raw);
                    root.probed = !!data.probed;
                    root.hasWifi = !!data.hasWifi;
                    root.hasBluetooth = !!data.hasBluetooth;
                    root.hasBacklight = !!data.hasBacklight;
                    root.hasBattery = !!data.hasBattery;
                    root.batteryPath = data.batteryPath || "";
                    root.hasTouchpad = !!data.hasTouchpad;
                    root.hasWlrRandr = !!data.hasWlrRandr;
                    root.hasAudio = !!data.hasAudio;
                    root.hasPavucontrol = !!data.hasPavucontrol;
                    root.hasLocker = !!data.hasLocker;
                    root.lockerCmd = data.lockerCmd || "";
                    root.deviceType = data.deviceType || "desktop";
                    root.hostname = data.hostname || "";
                    root.distro = data.distro || "Linux";
                    root.kernel = data.kernel || "";
                    if (root.hasBattery && root.batteryPath.length > 0)
                        root.refreshBattery();
                } catch (err) {}
            }
        }
    }

    Process {
        id: batteryProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").split("---");
                if (parts.length < 2)
                    return;
                const cap = parseInt(parts[0].trim(), 10);
                const status = parts[1].trim() || "Unknown";
                if (!isNaN(cap))
                    root.batteryPercent = Math.max(0, Math.min(100, cap));
                root.batteryStatus = status;
                root.batteryCharging = (status === "Charging" || status === "Full");
                root.batteryLow = (!root.batteryCharging && root.batteryPercent <= 20);
            }
        }
    }

    Timer {
        interval: 20000
        repeat: true
        running: root.hasBattery && root.batteryPath.length > 0
        triggeredOnStart: true
        onTriggered: root.refreshBattery()
    }
}
