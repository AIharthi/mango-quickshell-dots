pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    // --- Demand-driven Compositor Watchers (single shared stream per topic) ---
    property int hubConsumers: 0

    readonly property bool needTags: Theme.isSimple
        || ShellState.barUiStyle === "split"
        || (ShellState.barUiStyle === "menubar" && (ShellState.sequoiaShowWorkspaces || ShellState.sequoiaShowLayout))
        || ((ShellState.barUiStyle === "apple" || ShellState.barUiStyle === "classic")
            && (ShellState.barShowWorkspaces || ShellState.barShowLayout || !ShellState.pillShowMedia))
        || root.hubConsumers > 0

    readonly property bool needWindow: (Theme.isSimple && ShellState.barShowWindow)
        || (ShellState.barUiStyle === "menubar" && ShellState.sequoiaShowAppTitle)
        || (ShellState.barUiStyle !== "menubar" && ShellState.barShowWindow)

    readonly property bool needKb: ShellState.barShowKbLayout

    readonly property bool needVolume: (Theme.isSimple && ShellState.barShowVolume)
        || (ShellState.barUiStyle === "menubar" && ShellState.sequoiaShowVolume)
        || (ShellState.barUiStyle !== "menubar" && ShellState.barShowVolume)
        || root.hubConsumers > 0

    // --- Tag & Layout State (per monitor) ---
    readonly property var _defaultTags: [
        { index: 1, is_active: true,  is_urgent: false, client_count: 0 },
        { index: 2, is_active: false, is_urgent: false, client_count: 0 },
        { index: 3, is_active: false, is_urgent: false, client_count: 0 },
        { index: 4, is_active: false, is_urgent: false, client_count: 0 },
        { index: 5, is_active: false, is_urgent: false, client_count: 0 },
        { index: 6, is_active: false, is_urgent: false, client_count: 0 },
        { index: 7, is_active: false, is_urgent: false, client_count: 0 },
        { index: 8, is_active: false, is_urgent: false, client_count: 0 },
        { index: 9, is_active: false, is_urgent: false, client_count: 0 }
    ]

    property var monitorMap: ({})
    property string primaryMonitor: ""
    property string activeWindowTitle: ""
    property string activeAppName: "Aurora"
    property string kbLayoutShort: ""

    // --- Reactive PipeWire Audio State (zero polling when PipeWire ready) ---
    property int _fallbackVolPct: 50
    property bool _fallbackVolMuted: false
    property bool _fallbackMicMuted: false
    property string _fallbackSinkLabel: "Audio Output"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(o => o !== null && o !== undefined)
    }

    readonly property bool _pwSinkReady: Pipewire.ready
        && Pipewire.defaultAudioSink !== null
        && Pipewire.defaultAudioSink.ready
        && Pipewire.defaultAudioSink.audio !== null

    readonly property bool _pwSourceReady: Pipewire.ready
        && Pipewire.defaultAudioSource !== null
        && Pipewire.defaultAudioSource.ready
        && Pipewire.defaultAudioSource.audio !== null

    readonly property int volPercent: root._pwSinkReady
        ? Math.max(0, Math.min(150, Math.round(Number(Pipewire.defaultAudioSink.audio.volume || 0) * 100)))
        : root._fallbackVolPct

    readonly property bool volMuted: root._pwSinkReady
        ? (!!Pipewire.defaultAudioSink.audio.muted || root.volPercent <= 0)
        : root._fallbackVolMuted

    readonly property bool micMuted: root._pwSourceReady
        ? !!Pipewire.defaultAudioSource.audio.muted
        : root._fallbackMicMuted

    readonly property string defaultSinkLabel: (Pipewire.ready && Pipewire.defaultAudioSink)
        ? String(Pipewire.defaultAudioSink.description || Pipewire.defaultAudioSink.nickname || Pipewire.defaultAudioSink.name || "Audio Output")
        : root._fallbackSinkLabel

    function _entryForScreen(screenName: string): var {
        const map = root.monitorMap || {};
        if (screenName && screenName.length > 0 && map[screenName])
            return map[screenName];
        if (root.primaryMonitor.length > 0 && map[root.primaryMonitor])
            return map[root.primaryMonitor];
        return null;
    }

    function tagsForScreen(screenName: string): var {
        const ent = _entryForScreen(screenName);
        return (ent && ent.tags) ? ent.tags : root._defaultTags;
    }

    function layoutForScreen(screenName: string): string {
        const ent = _entryForScreen(screenName);
        return (ent && ent.layout) ? ent.layout : "T";
    }

    function activeTagForScreen(screenName: string): int {
        const ent = _entryForScreen(screenName);
        return (ent && ent.activeTag) ? ent.activeTag : 1;
    }

    function totalClientsForScreen(screenName: string): int {
        const ent = _entryForScreen(screenName);
        return (ent && typeof ent.totalClients === "number") ? ent.totalClients : 0;
    }

    function _prettifyAppId(rawId: string, rawTitle: string): string {
        let s = String(rawId || "").trim();
        if (s.length === 0)
            s = String(rawTitle || "").trim();
        if (s.length === 0)
            return "Aurora";
        if (s.indexOf(".") !== -1 && s.indexOf(" ") === -1) {
            const parts = s.split(".");
            const last = parts[parts.length - 1];
            if (last && last.length > 1)
                s = last;
        }
        s = s.replace(/[-_]+/g, " ").trim();
        if (s.length === 0)
            return "Aurora";
        const words = s.split(/\s+/);
        const out = [];
        for (let i = 0; i < Math.min(2, words.length); i++) {
            const w = words[i];
            if (w.length > 0)
                out.push(w.charAt(0).toUpperCase() + w.slice(1));
        }
        return out.join(" ");
    }

    function setVolumeRatio(ratio: real): void {
        const cap = ShellState.audioOverAmp ? 1.5 : 1.0;
        const clamped = Math.max(0.0, Math.min(cap, ratio));
        if (root._pwSinkReady) {
            Pipewire.defaultAudioSink.audio.volume = clamped;
            if (clamped > 0.001 && Pipewire.defaultAudioSink.audio.muted)
                Pipewire.defaultAudioSink.audio.muted = false;
            return;
        }
        const pct = Math.round(clamped * 100);
        root._fallbackVolPct = pct;
        root._fallbackVolMuted = pct <= 0;
        Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", pct + "%"]);
        volFallbackRefresh.restart();
    }

    function adjustVolumePct(deltaPct: int): void {
        const cap = ShellState.audioOverAmp ? 150 : 100;
        const nextPct = Math.max(0, Math.min(cap, root.volPercent + deltaPct));
        setVolumeRatio(nextPct / 100.0);
    }

    function toggleMute(): void {
        if (root._pwSinkReady) {
            Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted;
            return;
        }
        Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]);
        volFallbackRefresh.restart();
    }

    function toggleMicMute(): void {
        if (root._pwSourceReady) {
            Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted;
            return;
        }
        Quickshell.execDetached(["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"]);
        volFallbackRefresh.restart();
    }

    function cycleAudioSink(): void {
        if (Pipewire.ready && Pipewire.nodes && Pipewire.nodes.values) {
            const vals = Pipewire.nodes.values;
            const sinks = [];
            for (let i = 0; i < vals.length; i++) {
                const n = vals[i];
                if (n && n.isSink && !n.isStream && n.audio)
                    sinks.push(n);
            }
            if (sinks.length >= 2) {
                const curId = Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.id : -1;
                let idx = -1;
                for (let j = 0; j < sinks.length; j++) {
                    if (sinks[j].id === curId) {
                        idx = j;
                        break;
                    }
                }
                const nxt = sinks[(idx + 1) % sinks.length];
                if (nxt) {
                    Pipewire.preferredDefaultAudioSink = nxt;
                    return;
                }
            }
        }
        if (!sinkCycleFallbackProc.running)
            sinkCycleFallbackProc.running = true;
    }

    function refreshAudioFallback(): void {
        if (!root._pwSinkReady && DeviceCaps.hasAudio && !volFallbackProc.running)
            volFallbackProc.running = true;
    }

    function parseTagsJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const payload = JSON.parse(trimmed);
            const list = payload.all_tags;
            if (!list || list.length === 0)
                return;
            const nextMap = {};
            let firstMon = "";
            for (let i = 0; i < list.length; i++) {
                const entry = list[i];
                const mon = String(entry.monitor || ("mon-" + i));
                if (firstMon.length === 0)
                    firstMon = mon;
                const rawTags = entry.tags || [];
                const normalized = [];
                let activeLayout = "T";
                let activeIdx = 1;
                let totalCli = 0;
                for (let j = 0; j < Math.min(9, rawTags.length); j++) {
                    const t = rawTags[j];
                    const cli = t.client_count || 0;
                    totalCli += cli;
                    if (t.is_active) {
                        activeIdx = t.index || (j + 1);
                        if (t.layout)
                            activeLayout = String(t.layout);
                    }
                    normalized.push({
                        index: t.index,
                        is_active: !!t.is_active,
                        is_urgent: !!t.is_urgent,
                        client_count: cli
                    });
                }
                nextMap[mon] = {
                    monitor: mon,
                    layout: activeLayout,
                    activeTag: activeIdx,
                    totalClients: totalCli,
                    tags: normalized.length > 0 ? normalized : root._defaultTags
                };
            }
            if (firstMon.length > 0)
                root.primaryMonitor = firstMon;
            root.monitorMap = nextMap;
        } catch (err) {}
    }

    function parseWinJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            if (d.error || !d.id || (!d.title && !d.appid)) {
                root.activeWindowTitle = "";
                root.activeAppName = "Aurora";
                return;
            }
            const title = String(d.title || d.appid || "");
            root.activeWindowTitle = title;
            root.activeAppName = root._prettifyAppId(String(d.appid || ""), title);
        } catch (err) {}
    }

    function parseKbJson(raw: string): void {
        const trimmed = (raw || "").trim();
        if (trimmed.length === 0)
            return;
        try {
            const d = JSON.parse(trimmed);
            const full = String(d.layout || "").trim();
            if (full.length === 0) {
                root.kbLayoutShort = "";
                return;
            }
            const paren = full.match(/\(([^)]+)\)/);
            if (paren && paren[1])
                root.kbLayoutShort = paren[1].trim().slice(0, 3).toUpperCase();
            else
                root.kbLayoutShort = full.slice(0, 2).toUpperCase();
        } catch (err) {}
    }

    Process {
        id: tagStream
        command: ["mmsg", "watch", "all-tags"]
        running: root.needTags
        stdout: SplitParser { onRead: line => root.parseTagsJson(line) }
        onExited: {
            if (root.needTags)
                tagRestartTimer.restart();
        }
    }

    Timer {
        id: tagRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.needTags && !tagStream.running)
                tagStream.running = true;
        }
    }

    Process {
        id: winStream
        command: ["mmsg", "watch", "focusing-client"]
        running: root.needWindow
        stdout: SplitParser { onRead: line => root.parseWinJson(line) }
        onExited: {
            if (root.needWindow)
                winRestartTimer.restart();
        }
    }

    Timer {
        id: winRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.needWindow && !winStream.running)
                winStream.running = true;
        }
    }

    Process {
        id: kbStream
        command: ["mmsg", "watch", "keyboardlayout"]
        running: root.needKb
        stdout: SplitParser { onRead: line => root.parseKbJson(line) }
        onExited: {
            if (root.needKb)
                kbRestartTimer.restart();
        }
    }

    Timer {
        id: kbRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.needKb && !kbStream.running)
                kbStream.running = true;
        }
    }

    // Fallback audio poll ONLY when Quickshell.Services.Pipewire is not ready
    Process {
        id: volFallbackProc
        command: [
            "sh", "-c",
            "pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null; echo '---MUTE---'; pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null; echo '---MIC---'; pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null; echo '---SINK---'; def=$(pactl get-default-sink 2>/dev/null || true); [ -n \"$def\" ] && pactl list sinks 2>/dev/null | awk -v d=\"$def\" '$1==\"Name:\" {m=($2==d)} m && /Description:/ {sub(/.*Description: /, \"\"); print; exit}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text || "";
                const parts = raw.split("---MUTE---");
                if (parts.length > 0) {
                    const m = parts[0].match(/(\d+)%/);
                    if (m && m[1])
                        root._fallbackVolPct = Math.max(0, Math.min(150, parseInt(m[1], 10)));
                }
                if (parts.length > 1) {
                    const micSplit = parts[1].split("---MIC---");
                    root._fallbackVolMuted = (micSplit[0] || "").toLowerCase().indexOf("yes") !== -1;
                    if (micSplit.length > 1) {
                        const sinkSplit = micSplit[1].split("---SINK---");
                        root._fallbackMicMuted = (sinkSplit[0] || "").toLowerCase().indexOf("yes") !== -1;
                        if (sinkSplit.length > 1) {
                            const lbl = (sinkSplit[1] || "").trim();
                            if (lbl.length > 0)
                                root._fallbackSinkLabel = lbl;
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: !root._pwSinkReady && root.needVolume && DeviceCaps.hasAudio
        triggeredOnStart: true
        onTriggered: root.refreshAudioFallback()
    }

    Timer {
        id: volFallbackRefresh
        interval: 120
        repeat: false
        onTriggered: root.refreshAudioFallback()
    }

    Process {
        id: sinkCycleFallbackProc
        command: [
            "sh", "-c",
            "cur=$(pactl get-default-sink 2>/dev/null); mapfile -t s < <(pactl list short sinks 2>/dev/null | awk '{print $2}'); [ ${#s[@]} -lt 2 ] && exit 0; for i in \"${!s[@]}\"; do if [ \"${s[$i]}\" = \"$cur\" ]; then next=$(( (i + 1) % ${#s[@]} )); pactl set-default-sink \"${s[$next]}\"; break; fi; done"
        ]
        onExited: root.refreshAudioFallback()
    }
}
