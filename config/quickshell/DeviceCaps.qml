pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Hardware Capability Flags (populated by scripts/detect-hardware.sh) ---
    property bool probed: false
    property bool hasWifi: false
    property bool hasWifiHw: false
    property bool hasBluetooth: false
    property bool hasBacklight: false
    property bool hasBattery: false
    property string batteryPath: ""
    property var batteryPaths: []
    property bool hasTouchpad: false
    property bool hasWlrRandr: false
    property bool hasAudio: false
    property bool hasPavucontrol: false
    property bool hasNightLight: false
    property string nightLightCmd: ""
    property bool hasPowerProfiles: false
    property bool hasXdgMime: false
    property bool hasNetwork: true
    property bool hasNmcli: false
    property bool hasDdcutil: false
    property bool hasOpenRc: false
    property bool hasSystemd: false
    property bool hasClipboard: false
    property bool hasSpeakerTest: false
    property bool hasFoot: false
    property bool hasKitty: false
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
    property bool _warned15: false
    property bool _warned5: false

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
        if (!root.hasBattery)
            return;
        if (!batteryProc.running)
            batteryProc.running = true;
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
                    root.hasWifiHw = !!data.hasWifiHw;
                    root.hasBluetooth = !!data.hasBluetooth;
                    root.hasBacklight = !!data.hasBacklight;
                    root.hasBattery = !!data.hasBattery;
                    root.batteryPath = data.batteryPath || "";
                    root.batteryPaths = Array.isArray(data.batteryPaths) ? data.batteryPaths : [];
                    root.hasTouchpad = !!data.hasTouchpad;
                    root.hasWlrRandr = !!data.hasWlrRandr;
                    root.hasAudio = !!data.hasAudio;
                    root.hasPavucontrol = !!data.hasPavucontrol;
                    root.hasNightLight = !!data.hasNightLight;
                    root.nightLightCmd = data.nightLightCmd || "";
                    root.hasPowerProfiles = !!data.hasPowerProfiles;
                    root.hasXdgMime = !!data.hasXdgMime;
                    root.hasNetwork = (data.hasNetwork !== undefined) ? !!data.hasNetwork : true;
                    root.hasNmcli = !!data.hasNmcli;
                    root.hasDdcutil = !!data.hasDdcutil;
                    root.hasOpenRc = !!data.hasOpenRc;
                    root.hasSystemd = !!data.hasSystemd;
                    root.hasClipboard = !!data.hasClipboard;
                    root.hasSpeakerTest = !!data.hasSpeakerTest;
                    root.hasFoot = !!data.hasFoot;
                    root.hasKitty = !!data.hasKitty;
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
        command: [Quickshell.shellPath("scripts/detect-hardware.sh"), "--battery"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (typeof d.percent === "number")
                        root.batteryPercent = Math.max(0, Math.min(100, Math.round(d.percent)));
                    const st = String(d.status || "Unknown");
                    root.batteryStatus = st;
                    root.batteryCharging = (d.charging !== undefined) ? !!d.charging : (st === "Charging" || st === "Full");
                    root.batteryLow = (!root.batteryCharging && root.batteryPercent <= 20);
                    if (root.batteryCharging) {
                        root._warned15 = false;
                        root._warned5 = false;
                    } else if (root.batteryPercent <= 5 && !root._warned5) {
                        root._warned5 = true;
                        root._warned15 = true;
                        Quickshell.execDetached([
                            "sh", "-c",
                            "command -v notify-send >/dev/null 2>&1 && notify-send -a 'Battery' -u critical \"Critical Battery (" + root.batteryPercent + "%)\" 'Connect charger immediately to prevent shutdown.'"
                        ]);
                    } else if (root.batteryPercent <= 15 && !root._warned15) {
                        root._warned15 = true;
                        Quickshell.execDetached([
                            "sh", "-c",
                            "command -v notify-send >/dev/null 2>&1 && notify-send -a 'Battery' -u normal \"Low Battery (" + root.batteryPercent + "%)\" 'Battery is running low. Plug in charger soon.'"
                        ]);
                    }
                } catch (err) {}
            }
        }
    }

    Timer {
        interval: 20000
        repeat: true
        running: root.hasBattery
        triggeredOnStart: true
        onTriggered: root.refreshBattery()
    }
}
