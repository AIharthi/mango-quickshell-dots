pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- User Preferences (synced via shell-prefs.json) ---
    property bool dnd: false
    property bool dndAllowCritical: true
    property bool notifSoundEnabled: false
    property int notifTimeoutMs: 4500
    property int notifMaxHistory: 40
    property bool clock24h: true
    property bool clockShowSeconds: false
    property string dateFormat: "ddd d MMM"
    property bool keepAwake: false
    property string uiFontFamily: "JetBrains Mono"
    property int uiFontSize: 10
    property string iconTheme: "Adwaita"
    property string matugenType: "scheme-tonal-spot"
    property real matugenContrast: 0.0
    property string wallpaperTransition: "grow"
    property int wallpaperFps: 60
    property real wallpaperDuration: 0.85
    property string wallpaperResize: "crop"
    property bool nightLightEnabled: false
    property int nightLightTemp: 4500
    property string defaultTerminal: "foot"
    property string defaultBrowser: "helium"
    property string defaultEditor: "zedit"
    property string defaultFileManager: "pcmanfm"

    // --- Shell, Island, Bar & Accessibility ---
    property bool islandHoverExpand: true
    property int islandHoverDelayMs: 220
    property int islandCollapseDelayMs: 700
    property bool pillShowMedia: true
    property bool pillSpinArt: true
    property bool pillShowEqualizer: true
    property bool osdEnabled: true
    property int osdTimeoutMs: 1800
    property int simpleBarHeight: 28
    property string simpleBarPosition: "top"
    property bool simpleBarShowLayout: true
    property bool simpleBarShowDate: true
    property bool reducedMotion: false
    property bool highContrast: false
    property bool audioOverAmp: false

    // --- Screenshots ---
    property string screenshotDir: "~/Pictures/Screenshots"
    property bool screenshotCopyClipboard: true
    property bool screenshotNotify: true
    property int screenshotDelay: 0

    // --- Session Notification History ---
    property var notificationHistory: []
    property int unreadCount: 0
    property int _nextNotifUid: 1
    property string lastError: ""

    function applyPrefsJson(raw: string): void {
        const text = (raw || "").trim();
        if (text.length === 0) {
            prefsRetryTimer.restart();
            return;
        }
        try {
            const d = JSON.parse(text);
            if (d.dnd !== undefined) root.dnd = !!d.dnd;
            if (d.dndAllowCritical !== undefined) root.dndAllowCritical = !!d.dndAllowCritical;
            if (d.notifSoundEnabled !== undefined) root.notifSoundEnabled = !!d.notifSoundEnabled;
            if (d.notifTimeoutMs !== undefined) root.notifTimeoutMs = Math.max(1500, Math.min(15000, Number(d.notifTimeoutMs)));
            if (d.notifMaxHistory !== undefined) root.notifMaxHistory = Math.max(10, Math.min(200, Number(d.notifMaxHistory)));
            if (d.clock24h !== undefined) root.clock24h = !!d.clock24h;
            if (d.clockShowSeconds !== undefined) root.clockShowSeconds = !!d.clockShowSeconds;
            if (d.dateFormat !== undefined && String(d.dateFormat).length > 0) root.dateFormat = String(d.dateFormat);
            if (d.keepAwake !== undefined) root.keepAwake = !!d.keepAwake;
            if (d.uiFontFamily !== undefined && String(d.uiFontFamily).length > 0) root.uiFontFamily = String(d.uiFontFamily);
            if (d.uiFontSize !== undefined) root.uiFontSize = Math.max(8, Math.min(18, Number(d.uiFontSize)));
            if (d.iconTheme !== undefined && String(d.iconTheme).length > 0) root.iconTheme = String(d.iconTheme);
            if (d.matugenType !== undefined && String(d.matugenType).length > 0) root.matugenType = String(d.matugenType);
            if (d.matugenContrast !== undefined) root.matugenContrast = Math.max(-1.0, Math.min(1.0, Number(d.matugenContrast)));
            if (d.wallpaperTransition !== undefined && String(d.wallpaperTransition).length > 0) root.wallpaperTransition = String(d.wallpaperTransition);
            if (d.wallpaperFps !== undefined) root.wallpaperFps = Math.max(24, Math.min(240, Number(d.wallpaperFps)));
            if (d.wallpaperDuration !== undefined) root.wallpaperDuration = Math.max(0.1, Math.min(3.0, Number(d.wallpaperDuration)));
            if (d.wallpaperResize !== undefined && String(d.wallpaperResize).length > 0) root.wallpaperResize = String(d.wallpaperResize);
            if (d.nightLightEnabled !== undefined) root.nightLightEnabled = !!d.nightLightEnabled;
            if (d.nightLightTemp !== undefined) root.nightLightTemp = Math.max(2500, Math.min(6500, Number(d.nightLightTemp)));
            if (d.defaultTerminal !== undefined && String(d.defaultTerminal).length > 0) root.defaultTerminal = String(d.defaultTerminal);
            if (d.defaultBrowser !== undefined && String(d.defaultBrowser).length > 0) root.defaultBrowser = String(d.defaultBrowser);
            if (d.defaultEditor !== undefined && String(d.defaultEditor).length > 0) root.defaultEditor = String(d.defaultEditor);
            if (d.defaultFileManager !== undefined && String(d.defaultFileManager).length > 0) root.defaultFileManager = String(d.defaultFileManager);
            if (d.islandHoverExpand !== undefined) root.islandHoverExpand = !!d.islandHoverExpand;
            if (d.islandHoverDelayMs !== undefined) root.islandHoverDelayMs = Math.max(50, Math.min(1500, Number(d.islandHoverDelayMs)));
            if (d.islandCollapseDelayMs !== undefined) root.islandCollapseDelayMs = Math.max(200, Math.min(4000, Number(d.islandCollapseDelayMs)));
            if (d.pillShowMedia !== undefined) root.pillShowMedia = !!d.pillShowMedia;
            if (d.pillSpinArt !== undefined) root.pillSpinArt = !!d.pillSpinArt;
            if (d.pillShowEqualizer !== undefined) root.pillShowEqualizer = !!d.pillShowEqualizer;
            if (d.osdEnabled !== undefined) root.osdEnabled = !!d.osdEnabled;
            if (d.osdTimeoutMs !== undefined) root.osdTimeoutMs = Math.max(800, Math.min(6000, Number(d.osdTimeoutMs)));
            if (d.simpleBarHeight !== undefined) root.simpleBarHeight = Math.max(22, Math.min(44, Number(d.simpleBarHeight)));
            if (d.simpleBarPosition !== undefined) root.simpleBarPosition = (String(d.simpleBarPosition) === "bottom" ? "bottom" : "top");
            if (d.simpleBarShowLayout !== undefined) root.simpleBarShowLayout = !!d.simpleBarShowLayout;
            if (d.simpleBarShowDate !== undefined) root.simpleBarShowDate = !!d.simpleBarShowDate;
            if (d.reducedMotion !== undefined) root.reducedMotion = !!d.reducedMotion;
            if (d.highContrast !== undefined) root.highContrast = !!d.highContrast;
            if (d.audioOverAmp !== undefined) root.audioOverAmp = !!d.audioOverAmp;
            if (d.screenshotDir !== undefined && String(d.screenshotDir).length > 0) root.screenshotDir = String(d.screenshotDir);
            if (d.screenshotCopyClipboard !== undefined) root.screenshotCopyClipboard = !!d.screenshotCopyClipboard;
            if (d.screenshotNotify !== undefined) root.screenshotNotify = !!d.screenshotNotify;
            if (d.screenshotDelay !== undefined) root.screenshotDelay = Math.max(0, Math.min(10, Number(d.screenshotDelay)));
            root.lastError = "";
        } catch (err) {
            prefsRetryTimer.restart();
        }
    }

    function setPref(key: string, value): void {
        if (key === "dnd") root.dnd = !!value;
        else if (key === "dndAllowCritical") root.dndAllowCritical = !!value;
        else if (key === "notifSoundEnabled") root.notifSoundEnabled = !!value;
        else if (key === "notifTimeoutMs") root.notifTimeoutMs = Math.max(1500, Math.min(15000, Number(value)));
        else if (key === "notifMaxHistory") root.notifMaxHistory = Math.max(10, Math.min(200, Number(value)));
        else if (key === "clock24h") root.clock24h = !!value;
        else if (key === "clockShowSeconds") root.clockShowSeconds = !!value;
        else if (key === "dateFormat") root.dateFormat = String(value);
        else if (key === "keepAwake") root.keepAwake = !!value;
        else if (key === "uiFontFamily") root.uiFontFamily = String(value);
        else if (key === "uiFontSize") root.uiFontSize = Math.max(8, Math.min(18, Number(value)));
        else if (key === "iconTheme") root.iconTheme = String(value);
        else if (key === "matugenType") root.matugenType = String(value);
        else if (key === "matugenContrast") root.matugenContrast = Math.max(-1.0, Math.min(1.0, Number(value)));
        else if (key === "wallpaperTransition") root.wallpaperTransition = String(value);
        else if (key === "wallpaperFps") root.wallpaperFps = Math.max(24, Math.min(240, Number(value)));
        else if (key === "wallpaperDuration") root.wallpaperDuration = Math.max(0.1, Math.min(3.0, Number(value)));
        else if (key === "wallpaperResize") root.wallpaperResize = String(value);
        else if (key === "nightLightEnabled") root.nightLightEnabled = !!value;
        else if (key === "nightLightTemp") root.nightLightTemp = Math.max(2500, Math.min(6500, Number(value)));
        else if (key === "defaultTerminal") root.defaultTerminal = String(value);
        else if (key === "defaultBrowser") root.defaultBrowser = String(value);
        else if (key === "defaultEditor") root.defaultEditor = String(value);
        else if (key === "defaultFileManager") root.defaultFileManager = String(value);
        else if (key === "islandHoverExpand") root.islandHoverExpand = !!value;
        else if (key === "islandHoverDelayMs") root.islandHoverDelayMs = Math.max(50, Math.min(1500, Number(value)));
        else if (key === "islandCollapseDelayMs") root.islandCollapseDelayMs = Math.max(200, Math.min(4000, Number(value)));
        else if (key === "pillShowMedia") root.pillShowMedia = !!value;
        else if (key === "pillSpinArt") root.pillSpinArt = !!value;
        else if (key === "pillShowEqualizer") root.pillShowEqualizer = !!value;
        else if (key === "osdEnabled") root.osdEnabled = !!value;
        else if (key === "osdTimeoutMs") root.osdTimeoutMs = Math.max(800, Math.min(6000, Number(value)));
        else if (key === "simpleBarHeight") root.simpleBarHeight = Math.max(22, Math.min(44, Number(value)));
        else if (key === "simpleBarPosition") root.simpleBarPosition = (String(value) === "bottom" ? "bottom" : "top");
        else if (key === "simpleBarShowLayout") root.simpleBarShowLayout = !!value;
        else if (key === "simpleBarShowDate") root.simpleBarShowDate = !!value;
        else if (key === "reducedMotion") root.reducedMotion = !!value;
        else if (key === "highContrast") root.highContrast = !!value;
        else if (key === "audioOverAmp") root.audioOverAmp = !!value;
        else if (key === "screenshotDir") root.screenshotDir = String(value);
        else if (key === "screenshotCopyClipboard") root.screenshotCopyClipboard = !!value;
        else if (key === "screenshotNotify") root.screenshotNotify = !!value;
        else if (key === "screenshotDelay") root.screenshotDelay = Math.max(0, Math.min(10, Number(value)));

        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "prefs-set", key, String(value)
        ]);
    }

    function resetPrefs(): void {
        if (!resetProc.running)
            resetProc.running = true;
    }

    function setFont(family: string, size: int): void {
        const cleanFam = (family || "").trim();
        const clampedSize = Math.max(8, Math.min(18, size));
        if (cleanFam.length === 0)
            return;
        root.uiFontFamily = cleanFam;
        root.uiFontSize = clampedSize;
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "set-font", cleanFam, String(clampedSize)
        ]);
    }

    function setNightLight(enabled: bool, temp: int): void {
        const clampedTemp = Math.max(2500, Math.min(6500, temp));
        root.nightLightEnabled = enabled;
        root.nightLightTemp = clampedTemp;
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "night-light", enabled ? "on" : "off", String(clampedTemp)
        ]);
    }

    function toggleDnd(): void {
        setPref("dnd", !root.dnd);
    }

    function toggleKeepAwake(): void {
        setPref("keepAwake", !root.keepAwake);
    }

    function recordNotification(notif): void {
        if (!notif)
            return;
        const entry = {
            uid: root._nextNotifUid++,
            summary: String(notif.summary || "Notification"),
            body: String(notif.body || ""),
            appName: String(notif.appName || "System"),
            urgency: Number(notif.urgency || 0),
            timeStr: formatTime(new Date())
        };
        const cap = Math.max(10, Math.min(200, root.notifMaxHistory));
        const updated = [entry].concat(root.notificationHistory || []);
        if (updated.length > cap)
            updated.length = cap;
        root.notificationHistory = updated;
        root.unreadCount = root.unreadCount + 1;
    }

    function dismissNotification(uid: int): void {
        root.notificationHistory = (root.notificationHistory || []).filter(item => item.uid !== uid);
    }

    function clearHistory(): void {
        root.notificationHistory = [];
        root.unreadCount = 0;
    }

    function clearUnread(): void {
        root.unreadCount = 0;
    }

    function formatTime(dt): string {
        if (!dt)
            return "";
        const fmt = root.clock24h
            ? (root.clockShowSeconds ? "HH:mm:ss" : "HH:mm")
            : (root.clockShowSeconds ? "hh:mm:ss AP" : "hh:mm AP");
        return Qt.formatDateTime(dt, fmt);
    }

    function formatDate(dt): string {
        if (!dt)
            return "";
        return Qt.formatDateTime(dt, root.dateFormat.length > 0 ? root.dateFormat : "ddd d MMM");
    }

    Component.onCompleted: {
        initProc.running = true;
    }

    Process {
        id: initProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "prefs-get"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyPrefsJson(text)
        }
    }

    Process {
        id: resetProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "prefs-reset"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyPrefsJson(text)
        }
    }

    FileView {
        id: prefsFile
        path: Quickshell.shellPath("shell-prefs.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.applyPrefsJson(text())
    }

    Timer {
        id: prefsRetryTimer
        interval: 80
        repeat: false
        onTriggered: prefsFile.reload()
    }
}
