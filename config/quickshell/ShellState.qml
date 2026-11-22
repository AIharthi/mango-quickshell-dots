pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- User Preferences (synced via shell-prefs.json) ---
    property bool dnd: false
    property int notifTimeoutMs: 4500
    property bool clock24h: true
    property bool clockShowSeconds: false
    property string dateFormat: "ddd d MMM"
    property bool keepAwake: false
    property string uiFontFamily: "JetBrains Mono"
    property int uiFontSize: 10
    property bool nightLightEnabled: false
    property int nightLightTemp: 4500
    property string defaultTerminal: "foot"
    property string defaultBrowser: "helium"
    property string defaultEditor: "zedit"
    property string defaultFileManager: "pcmanfm"

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
            if (d.notifTimeoutMs !== undefined) root.notifTimeoutMs = Math.max(1500, Math.min(15000, Number(d.notifTimeoutMs)));
            if (d.clock24h !== undefined) root.clock24h = !!d.clock24h;
            if (d.clockShowSeconds !== undefined) root.clockShowSeconds = !!d.clockShowSeconds;
            if (d.dateFormat !== undefined && String(d.dateFormat).length > 0) root.dateFormat = String(d.dateFormat);
            if (d.keepAwake !== undefined) root.keepAwake = !!d.keepAwake;
            if (d.uiFontFamily !== undefined && String(d.uiFontFamily).length > 0) root.uiFontFamily = String(d.uiFontFamily);
            if (d.uiFontSize !== undefined) root.uiFontSize = Math.max(8, Math.min(18, Number(d.uiFontSize)));
            if (d.nightLightEnabled !== undefined) root.nightLightEnabled = !!d.nightLightEnabled;
            if (d.nightLightTemp !== undefined) root.nightLightTemp = Math.max(2500, Math.min(6500, Number(d.nightLightTemp)));
            if (d.defaultTerminal !== undefined && String(d.defaultTerminal).length > 0) root.defaultTerminal = String(d.defaultTerminal);
            if (d.defaultBrowser !== undefined && String(d.defaultBrowser).length > 0) root.defaultBrowser = String(d.defaultBrowser);
            if (d.defaultEditor !== undefined && String(d.defaultEditor).length > 0) root.defaultEditor = String(d.defaultEditor);
            if (d.defaultFileManager !== undefined && String(d.defaultFileManager).length > 0) root.defaultFileManager = String(d.defaultFileManager);
            root.lastError = "";
        } catch (err) {
            prefsRetryTimer.restart();
        }
    }

    function setPref(key: string, value): void {
        if (key === "dnd") root.dnd = !!value;
        else if (key === "notifTimeoutMs") root.notifTimeoutMs = Math.max(1500, Math.min(15000, Number(value)));
        else if (key === "clock24h") root.clock24h = !!value;
        else if (key === "clockShowSeconds") root.clockShowSeconds = !!value;
        else if (key === "dateFormat") root.dateFormat = String(value);
        else if (key === "keepAwake") root.keepAwake = !!value;
        else if (key === "uiFontFamily") root.uiFontFamily = String(value);
        else if (key === "uiFontSize") root.uiFontSize = Math.max(8, Math.min(18, Number(value)));
        else if (key === "nightLightEnabled") root.nightLightEnabled = !!value;
        else if (key === "nightLightTemp") root.nightLightTemp = Math.max(2500, Math.min(6500, Number(value)));
        else if (key === "defaultTerminal") root.defaultTerminal = String(value);
        else if (key === "defaultBrowser") root.defaultBrowser = String(value);
        else if (key === "defaultEditor") root.defaultEditor = String(value);
        else if (key === "defaultFileManager") root.defaultFileManager = String(value);

        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "prefs-set", key, String(value)
        ]);
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
        const updated = [entry].concat(root.notificationHistory || []);
        if (updated.length > 40)
            updated.length = 40;
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
