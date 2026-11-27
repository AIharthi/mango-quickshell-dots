pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Mpris
import "components"
import "settings"
import "files"

ShellRoot {
    id: root

    // --- Modal Lazy States ---
    property bool settingsOpen: false
    property bool _settingsLoaded: false
    property string settingsPage: "appearance"

    property bool storeOpen: false
    property bool _storeLoaded: false

    property bool filesOpen: false
    property bool _filesLoaded: false
    property string filesStartPath: ""

    property bool keybindsOpen: false
    property bool _keybindsLoaded: false

    property bool windowSwitcherOpen: false
    property bool _windowSwitcherLoaded: false

    property bool powerOverlayOpen: false
    property bool _powerOverlayLoaded: false

    property bool captureHubOpen: false
    property bool _captureHubLoaded: false

    // --- Sequoia Dedicated Hub State (active only when barUiStyle === "menubar") ---
    readonly property bool isSequoiaActive: !Theme.isSimple && ShellState.barUiStyle === "menubar"
    property bool sequoiaHubOpen: false
    property bool _sequoiaHubLoaded: false
    property string sequoiaHubMode: "controls"      // "controls" | "notifications" | "launcher" | "osd" | "notification"
    property string sequoiaLauncherMode: "apps"
    property string sequoiaControlsTab: "controls"  // "controls" | "themes" | "files"
    property bool sequoiaPowerMenuOpen: false
    property string sequoiaScreenName: ""
    property string sequoiaOsdType: "volume"
    property int sequoiaOsdSeq: 0
    property var sequoiaPendingNotif: null
    property int sequoiaNotifSeq: 0

    // --- Split Islands Dedicated Hub State (active only when barUiStyle === "split") ---
    readonly property bool isSplitActive: !Theme.isSimple && ShellState.barUiStyle === "split"
    property bool splitHubOpen: false
    property bool _splitHubLoaded: false
    property string splitHubMode: "controls"        // "left" | "center" | "controls" | "notifications" | "launcher" | "osd" | "notification"
    property string splitLauncherMode: "apps"
    property string splitControlsTab: "controls"    // "controls" | "themes" | "files"
    property bool splitPowerMenuOpen: false
    property string splitScreenName: ""
    property string splitOsdType: "volume"
    property int splitOsdSeq: 0
    property var splitPendingNotif: null
    property int splitNotifSeq: 0

    readonly property var activePlayer: (root.isSequoiaActive || root.isSplitActive) ? root._resolveActivePlayer() : null

    onIsSequoiaActiveChanged: {
        if (!root.isSequoiaActive) {
            root.sequoiaHubOpen = false;
            root.sequoiaPowerMenuOpen = false;
            root._sequoiaHubLoaded = false;
            sequoiaUnloadTimer.stop();
        }
    }

    onIsSplitActiveChanged: {
        if (!root.isSplitActive) {
            root.splitHubOpen = false;
            root.splitPowerMenuOpen = false;
            root._splitHubLoaded = false;
            splitUnloadTimer.stop();
        }
    }

    function _resolveActivePlayer(): var {
        const players = Mpris.players.values;
        if (!players || players.length === 0)
            return null;

        let playingSpotify = null;
        let idleSpotify = null;
        let playingFallback = null;
        let idleFallback = null;

        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!p)
                continue;
            const idStr = ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase();
            const isSpotify = idStr.includes("spotify");
            const hasTrack = (p.trackTitle && p.trackTitle.length > 0);
            if (isSpotify) {
                if (p.isPlaying && !playingSpotify) playingSpotify = p;
                else if (hasTrack && !idleSpotify) idleSpotify = p;
            } else {
                if (p.isPlaying && !playingFallback) playingFallback = p;
                else if (hasTrack && !idleFallback) idleFallback = p;
            }
        }
        return playingSpotify || playingFallback || idleSpotify || idleFallback || null;
    }

    function primaryScreenName(): string {
        if (Quickshell.screens && Quickshell.screens.length > 0 && Quickshell.screens[0])
            return Quickshell.screens[0].name || "";
        return "";
    }

    function primaryIsland(): var {
        const list = screenVariants.instances;
        if (!list || list.length === 0)
            return null;
        return list[0].island || null;
    }

    function forEachIsland(fn: var): void {
        const list = screenVariants.instances;
        if (!list)
            return;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].island)
                fn(list[i].island);
        }
    }

    function collapseAll(): void {
        forEachIsland(isl => isl.collapse());
    }

    function _closeOtherModals(keep: string): void {
        if (keep !== "settings") root.closeSettings();
        if (keep !== "store") root.closeStore();
        if (keep !== "files") root.closeFiles();
        if (keep !== "keybinds") root.closeKeybinds();
        if (keep !== "switcher") root.closeWindowSwitcher();
        if (keep !== "power") root.closePowerOverlay();
        if (keep !== "capture") root.closeCaptureHub();
        if (keep !== "sequoia") root.closeSequoiaHub();
        if (keep !== "split") root.closeSplitHub();
        root.collapseAll();
    }

    function openSettings(page: string): void {
        root._closeOtherModals("settings");
        root.settingsPage = (page && page.length > 0)
            ? page
            : (root.isSequoiaActive ? "sequoia" : (root.isSplitActive ? "split" : "appearance"));
        settingsUnloadTimer.stop();
        root._settingsLoaded = true;
        root.settingsOpen = true;
    }

    function closeSettings(): void {
        root.settingsOpen = false;
        if (root._settingsLoaded)
            settingsUnloadTimer.restart();
    }

    function toggleSettings(): void {
        if (root.settingsOpen)
            root.closeSettings();
        else
            root.openSettings(root.isSequoiaActive ? "sequoia" : (root.isSplitActive ? "split" : "appearance"));
    }

    function openStore(): void {
        root._closeOtherModals("store");
        storeUnloadTimer.stop();
        root._storeLoaded = true;
        root.storeOpen = true;
    }

    function closeStore(): void {
        root.storeOpen = false;
        if (root._storeLoaded)
            storeUnloadTimer.restart();
    }

    function toggleStore(): void {
        if (root.storeOpen)
            root.closeStore();
        else
            root.openStore();
    }

    function openFiles(startPath: string): void {
        root._closeOtherModals("files");
        root.filesStartPath = (startPath && startPath.length > 0) ? startPath : "";
        filesUnloadTimer.stop();
        root._filesLoaded = true;
        root.filesOpen = true;
    }

    function closeFiles(): void {
        root.filesOpen = false;
        if (root._filesLoaded)
            filesUnloadTimer.restart();
    }

    function toggleFiles(): void {
        if (root.filesOpen)
            root.closeFiles();
        else
            root.openFiles("");
    }

    function openKeybinds(): void {
        root._closeOtherModals("keybinds");
        keybindsUnloadTimer.stop();
        root._keybindsLoaded = true;
        root.keybindsOpen = true;
    }

    function closeKeybinds(): void {
        root.keybindsOpen = false;
        if (root._keybindsLoaded)
            keybindsUnloadTimer.restart();
    }

    function toggleKeybindSheet(): void {
        if (root.keybindsOpen)
            root.closeKeybinds();
        else
            root.openKeybinds();
    }

    function openWindowSwitcher(): void {
        root._closeOtherModals("switcher");
        switcherUnloadTimer.stop();
        root._windowSwitcherLoaded = true;
        root.windowSwitcherOpen = true;
    }

    function closeWindowSwitcher(): void {
        root.windowSwitcherOpen = false;
        if (root._windowSwitcherLoaded)
            switcherUnloadTimer.restart();
    }

    function toggleWindowSwitcher(): void {
        if (root.windowSwitcherOpen)
            root.closeWindowSwitcher();
        else
            root.openWindowSwitcher();
    }

    function openPowerOverlay(): void {
        root._closeOtherModals("power");
        powerUnloadTimer.stop();
        root._powerOverlayLoaded = true;
        root.powerOverlayOpen = true;
    }

    function closePowerOverlay(): void {
        root.powerOverlayOpen = false;
        if (root._powerOverlayLoaded)
            powerUnloadTimer.restart();
    }

    function togglePowerOverlay(): void {
        if (root.powerOverlayOpen)
            root.closePowerOverlay();
        else
            root.openPowerOverlay();
    }

    function openCaptureHub(): void {
        root._closeOtherModals("capture");
        captureHubUnloadTimer.stop();
        root._captureHubLoaded = true;
        root.captureHubOpen = true;
    }

    function closeCaptureHub(): void {
        root.captureHubOpen = false;
        if (root._captureHubLoaded)
            captureHubUnloadTimer.restart();
    }

    function toggleCaptureHub(): void {
        if (root.captureHubOpen)
            root.closeCaptureHub();
        else
            root.openCaptureHub();
    }

    // --- Sequoia Hub Control ---
    function closeSequoiaHub(): void {
        root.sequoiaHubOpen = false;
        root.sequoiaPowerMenuOpen = false;
        if (root._sequoiaHubLoaded)
            sequoiaUnloadTimer.restart();
    }

    function openSequoiaControls(tab: string, screenName: string): void {
        if (!root.isSequoiaActive)
            return;
        root._closeOtherModals("sequoia");
        sequoiaUnloadTimer.stop();
        root.sequoiaScreenName = (screenName && screenName.length > 0) ? screenName : root.primaryScreenName();
        root.sequoiaControlsTab = (tab && tab.length > 0) ? tab : "controls";
        root.sequoiaPowerMenuOpen = false;
        root.sequoiaHubMode = "controls";
        root._sequoiaHubLoaded = true;
        root.sequoiaHubOpen = true;
    }

    function toggleSequoiaControls(tab: string, screenName: string): void {
        const wantTab = (tab && tab.length > 0) ? tab : "controls";
        if (root.sequoiaHubOpen && root.sequoiaHubMode === "controls" && root.sequoiaControlsTab === wantTab)
            root.closeSequoiaHub();
        else
            root.openSequoiaControls(wantTab, screenName);
    }

    function openSequoiaNotifications(screenName: string): void {
        if (!root.isSequoiaActive)
            return;
        root._closeOtherModals("sequoia");
        sequoiaUnloadTimer.stop();
        root.sequoiaScreenName = (screenName && screenName.length > 0) ? screenName : root.primaryScreenName();
        root.sequoiaPowerMenuOpen = false;
        root.sequoiaHubMode = "notifications";
        ShellState.clearUnread();
        root._sequoiaHubLoaded = true;
        root.sequoiaHubOpen = true;
    }

    function toggleSequoiaNotifications(screenName: string): void {
        if (root.sequoiaHubOpen && root.sequoiaHubMode === "notifications")
            root.closeSequoiaHub();
        else
            root.openSequoiaNotifications(screenName);
    }

    function openSequoiaLauncher(mode: string): void {
        if (!root.isSequoiaActive)
            return;
        root._closeOtherModals("sequoia");
        sequoiaUnloadTimer.stop();
        root.sequoiaLauncherMode = (mode && mode.length > 0) ? mode : "apps";
        root.sequoiaPowerMenuOpen = false;
        root.sequoiaHubMode = "launcher";
        root._sequoiaHubLoaded = true;
        root.sequoiaHubOpen = true;
    }

    function toggleSequoiaLauncher(mode: string): void {
        const wantMode = (mode && mode.length > 0) ? mode : "apps";
        if (root.sequoiaHubOpen && root.sequoiaHubMode === "launcher" && root.sequoiaLauncherMode === wantMode)
            root.closeSequoiaHub();
        else
            root.openSequoiaLauncher(wantMode);
    }

    function showSequoiaOsd(osdType: string): void {
        if (!root.isSequoiaActive || !ShellState.osdEnabled)
            return;
        if (root.sequoiaHubOpen && (root.sequoiaHubMode === "controls" || root.sequoiaHubMode === "notifications" || root.sequoiaHubMode === "launcher"))
            return;
        sequoiaUnloadTimer.stop();
        root.sequoiaHubMode = "osd";
        root.sequoiaOsdType = (osdType && osdType.length > 0) ? osdType : "volume";
        root.sequoiaOsdSeq += 1;
        root._sequoiaHubLoaded = true;
        root.sequoiaHubOpen = true;
    }

    function showSequoiaNotification(notif: var): void {
        if (!root.isSequoiaActive || !notif)
            return;
        if (root.sequoiaHubOpen && (root.sequoiaHubMode === "controls" || root.sequoiaHubMode === "notifications" || root.sequoiaHubMode === "launcher"))
            return;
        sequoiaUnloadTimer.stop();
        root.sequoiaHubMode = "notification";
        root.sequoiaPendingNotif = notif;
        root.sequoiaNotifSeq += 1;
        root._sequoiaHubLoaded = true;
        root.sequoiaHubOpen = true;
    }

    // --- Split Islands Hub Control ---
    function closeSplitHub(): void {
        root.splitHubOpen = false;
        root.splitPowerMenuOpen = false;
        if (root._splitHubLoaded)
            splitUnloadTimer.restart();
    }

    function _openSplitMode(mode: string, tab: string, lmode: string, screenName: string): void {
        if (!root.isSplitActive)
            return;
        root._closeOtherModals("split");
        splitUnloadTimer.stop();
        root.splitScreenName = (screenName && screenName.length > 0) ? screenName : root.primaryScreenName();
        if (tab && tab.length > 0)
            root.splitControlsTab = tab;
        if (lmode && lmode.length > 0)
            root.splitLauncherMode = lmode;
        root.splitPowerMenuOpen = false;
        root.splitHubMode = mode;
        if (mode === "notifications")
            ShellState.clearUnread();
        root._splitHubLoaded = true;
        root.splitHubOpen = true;
    }

    function toggleSplitLeft(screenName: string): void {
        if (root.splitHubOpen && root.splitHubMode === "left")
            root.closeSplitHub();
        else
            root._openSplitMode("left", "", "", screenName);
    }

    function toggleSplitCenter(screenName: string): void {
        if (root.splitHubOpen && root.splitHubMode === "center")
            root.closeSplitHub();
        else
            root._openSplitMode("center", "", "", screenName);
    }

    function toggleSplitControls(tab: string, screenName: string): void {
        const wantTab = (tab && tab.length > 0) ? tab : "controls";
        if (root.splitHubOpen && root.splitHubMode === "controls" && root.splitControlsTab === wantTab)
            root.closeSplitHub();
        else
            root._openSplitMode("controls", wantTab, "", screenName);
    }

    function toggleSplitNotifications(screenName: string): void {
        if (root.splitHubOpen && root.splitHubMode === "notifications")
            root.closeSplitHub();
        else
            root._openSplitMode("notifications", "", "", screenName);
    }

    function toggleSplitLauncher(mode: string): void {
        const wantMode = (mode && mode.length > 0) ? mode : "apps";
        if (root.splitHubOpen && root.splitHubMode === "launcher" && root.splitLauncherMode === wantMode)
            root.closeSplitHub();
        else
            root._openSplitMode("launcher", "", wantMode, "");
    }

    function showSplitOsd(osdType: string): void {
        if (!root.isSplitActive || !ShellState.osdEnabled)
            return;
        if (root.splitHubOpen && (root.splitHubMode === "left" || root.splitHubMode === "center" || root.splitHubMode === "controls" || root.splitHubMode === "notifications" || root.splitHubMode === "launcher"))
            return;
        splitUnloadTimer.stop();
        root.splitHubMode = "osd";
        root.splitOsdType = (osdType && osdType.length > 0) ? osdType : "volume";
        root.splitOsdSeq += 1;
        root._splitHubLoaded = true;
        root.splitHubOpen = true;
    }

    function showSplitNotification(notif: var): void {
        if (!root.isSplitActive || !notif)
            return;
        if (root.splitHubOpen && (root.splitHubMode === "left" || root.splitHubMode === "center" || root.splitHubMode === "controls" || root.splitHubMode === "notifications" || root.splitHubMode === "launcher"))
            return;
        splitUnloadTimer.stop();
        root.splitHubMode = "notification";
        root.splitPendingNotif = notif;
        root.splitNotifSeq += 1;
        root._splitHubLoaded = true;
        root.splitHubOpen = true;
    }

    // --- Shared IPC Dispatchers (Sequoia Hub vs Split Hub vs Dynamic Island) ---
    function dispatchDashboard(): void {
        if (root.isSequoiaActive) {
            root.toggleSequoiaControls("controls", "");
            return;
        }
        if (root.isSplitActive) {
            root.toggleSplitControls("controls", "");
            return;
        }
        const isl = root.primaryIsland();
        if (isl) isl.toggleDashboard();
    }

    function dispatchLauncher(mode: string): void {
        if (root.isSequoiaActive) {
            const norm = (mode === "clipboard") ? "clip" : mode;
            root.toggleSequoiaLauncher(norm);
            return;
        }
        if (root.isSplitActive) {
            const norm = (mode === "clipboard") ? "clip" : mode;
            root.toggleSplitLauncher(norm);
            return;
        }
        const isl = root.primaryIsland();
        if (!isl) return;
        if (mode === "clipboard") isl.toggleClipboard();
        else if (mode === "snippets") isl.toggleSnippets();
        else isl.toggleLauncher();
    }

    function dispatchNotifications(): void {
        if (root.isSequoiaActive) {
            root.toggleSequoiaNotifications("");
            return;
        }
        if (root.isSplitActive) {
            root.toggleSplitNotifications("");
            return;
        }
        const isl = root.primaryIsland();
        if (isl) isl.toggleNotifications();
    }

    function dispatchThemeTab(): void {
        if (root.isSequoiaActive) {
            root.toggleSequoiaControls("themes", "");
            return;
        }
        if (root.isSplitActive) {
            root.toggleSplitControls("themes", "");
            return;
        }
        const isl = root.primaryIsland();
        if (isl) isl.toggleThemeTab();
    }

    function dispatchFilesTab(): void {
        if (root.isSequoiaActive) {
            root.toggleSequoiaControls("files", "");
            return;
        }
        if (root.isSplitActive) {
            root.toggleSplitControls("files", "");
            return;
        }
        const isl = root.primaryIsland();
        if (isl) isl.toggleFilesTab();
    }

    function dispatchOsd(osdType: string): void {
        if (root.isSequoiaActive) {
            root.showSequoiaOsd(osdType);
            return;
        }
        if (root.isSplitActive) {
            root.showSplitOsd(osdType);
            return;
        }
        root.forEachIsland(isl => isl.triggerOsd(osdType));
    }

    function dispatchCollapse(): void {
        root.closeSequoiaHub();
        root.closeSplitHub();
        root.collapseAll();
    }

    // --- Unload Timers (modal windows unload cleanly after exit fade; Sequoia stays warm) ---
    Timer {
        id: settingsUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.settingsOpen)
                root._settingsLoaded = false;
        }
    }

    Timer {
        id: storeUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.storeOpen)
                root._storeLoaded = false;
        }
    }

    Timer {
        id: filesUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.filesOpen)
                root._filesLoaded = false;
        }
    }

    Timer {
        id: keybindsUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.keybindsOpen)
                root._keybindsLoaded = false;
        }
    }

    Timer {
        id: switcherUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.windowSwitcherOpen)
                root._windowSwitcherLoaded = false;
        }
    }

    Timer {
        id: powerUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.powerOverlayOpen)
                root._powerOverlayLoaded = false;
        }
    }

    Timer {
        id: captureHubUnloadTimer
        interval: Theme.reducedMotion ? 10 : 160
        repeat: false
        onTriggered: {
            if (!root.captureHubOpen)
                root._captureHubLoaded = false;
        }
    }

    Timer {
        id: sequoiaUnloadTimer
        interval: 120000
        repeat: false
        onTriggered: {
            if (!root.sequoiaHubOpen)
                root._sequoiaHubLoaded = false;
        }
    }

    Timer {
        id: splitUnloadTimer
        interval: 120000
        repeat: false
        onTriggered: {
            if (!root.splitHubOpen)
                root._splitHubLoaded = false;
        }
    }

    // Event-driven Picture-in-Picture window watcher (zero idle CPU)
    Process {
        id: pipWatcher
        command: [Quickshell.shellPath("scripts/manage-pip.sh"), "watch"]
        running: ShellState.pipAutoManage
        onExited: {
            if (ShellState.pipAutoManage)
                pipRestartTimer.restart();
        }
    }

    Timer {
        id: pipRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (ShellState.pipAutoManage && !pipWatcher.running)
                pipWatcher.running = true;
        }
    }

    NotificationServer {
        id: notifServer
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        persistenceSupported: false

        onNotification: notification => {
            notification.tracked = true;
            ShellState.recordNotification(notification);
            const allowBanner = !ShellState.dnd || (ShellState.dndAllowCritical && Number(notification.urgency || 0) === 2);
            if (allowBanner) {
                if (root.isSequoiaActive)
                    root.showSequoiaNotification(notification);
                else if (root.isSplitActive)
                    root.showSplitNotification(notification);
                else
                    root.forEachIsland(isl => isl.showNotification(notification));
                if (ShellState.notifSoundEnabled && !ShellState.dnd) {
                    Quickshell.execDetached([
                        "sh", "-c",
                        "for s in /usr/share/sounds/freedesktop/stereo/message-new-instant.oga /usr/share/sounds/freedesktop/stereo/message.oga /usr/share/sounds/freedesktop/stereo/bell.oga; do [ -f \"$s\" ] || continue; if command -v paplay >/dev/null 2>&1; then paplay \"$s\"; elif command -v pw-play >/dev/null 2>&1; then pw-play \"$s\"; fi; break; done"
                    ]);
                }
            }
        }
    }

    // Per-monitor exclusive top shell architecture (Mode A Simple / Mode B Sequoia / Mode C Split / Mode D Dynamic Island)
    Variants {
        id: screenVariants
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property var modelData
            readonly property var island: (islandLoader.item && islandLoader.item.island) ? islandLoader.item.island : null

            // Mode A: Minimal Flat Edge Bar
            LazyLoader {
                id: simpleBarLoader
                active: Theme.isSimple

                PanelWindow {
                    screen: screenScope.modelData

                    anchors {
                        top: ShellState.simpleBarPosition !== "bottom"
                        bottom: ShellState.simpleBarPosition === "bottom"
                        left: true
                        right: true
                    }

                    exclusiveZone: ShellState.simpleBarHeight
                    exclusionMode: ExclusionMode.Normal
                    implicitHeight: ShellState.simpleBarHeight
                    color: "transparent"

                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "quickshell-simple-bar"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    SimpleBar {
                        anchors.fill: parent
                        active: Theme.isSimple
                        screenName: screenScope.modelData ? screenScope.modelData.name : ""
                        onToggleDashboardRequested: if (screenScope.island) screenScope.island.toggleDashboard()
                        onToggleLauncherRequested: if (screenScope.island) screenScope.island.toggleLauncher()
                        onToggleSettingsRequested: root.toggleSettings()
                        onToggleFilesRequested: root.toggleFiles()
                        onToggleNotificationsRequested: if (screenScope.island) screenScope.island.toggleNotifications()
                    }
                }
            }

            // Mode B: Stationary macOS Sequoia Top Menu Bar
            LazyLoader {
                id: sequoiaBarLoader
                active: root.isSequoiaActive

                PanelWindow {
                    id: sequoiaBarWin
                    screen: screenScope.modelData

                    anchors {
                        top: true
                        left: true
                        right: true
                    }

                    exclusiveZone: ShellState.sequoiaBarHeight + (ShellState.sequoiaBarFloating ? 6 : 0)
                    exclusionMode: ExclusionMode.Normal
                    implicitHeight: ShellState.sequoiaBarHeight + (ShellState.sequoiaBarFloating ? 8 : 0)
                    color: "transparent"

                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "quickshell-sequoia-bar"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    IdleInhibitor {
                        enabled: ShellState.keepAwake && (Quickshell.screens.length === 0 || screenScope.modelData === Quickshell.screens[0])
                        window: sequoiaBarWin
                    }

                    SequoiaBar {
                        anchors.fill: parent
                        screenName: screenScope.modelData ? screenScope.modelData.name : ""
                        player: root.activePlayer
                        openPanelMode: root.sequoiaHubOpen ? root.sequoiaHubMode : ""
                        onToggleControlCenterRequested: root.toggleSequoiaControls("controls", screenScope.modelData ? screenScope.modelData.name : "")
                        onToggleNotificationsRequested: root.toggleSequoiaNotifications(screenScope.modelData ? screenScope.modelData.name : "")
                        onToggleSpotlightRequested: root.toggleSequoiaLauncher("apps")
                        onOpenSettingsRequested: page => root.openSettings(page)
                        onOpenFilesRequested: path => root.openFiles(path)
                        onOpenStoreRequested: root.openStore()
                    }
                }
            }

            // Mode C: Stationary Split Islands (3 Glass Pods with click-through gaps)
            LazyLoader {
                id: splitBarLoader
                active: root.isSplitActive

                PanelWindow {
                    id: splitBarWin
                    screen: screenScope.modelData

                    anchors {
                        top: true
                        left: true
                        right: true
                    }

                    exclusiveZone: ShellState.splitBarHeight + ShellState.splitTopMargin + 2
                    exclusionMode: ExclusionMode.Normal
                    implicitHeight: ShellState.splitBarHeight + ShellState.splitTopMargin + 4
                    color: "transparent"

                    mask: Region {
                        Region { item: splitBarItem.leftMask }
                        Region { item: splitBarItem.centerMask }
                        Region { item: splitBarItem.rightMask }
                    }

                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "quickshell-split-bar"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    IdleInhibitor {
                        enabled: ShellState.keepAwake && (Quickshell.screens.length === 0 || screenScope.modelData === Quickshell.screens[0])
                        window: splitBarWin
                    }

                    SplitBar {
                        id: splitBarItem
                        anchors.fill: parent
                        screenName: screenScope.modelData ? screenScope.modelData.name : ""
                        player: root.activePlayer
                        openPanelMode: root.splitHubOpen ? root.splitHubMode : ""
                        onToggleLeftRequested: root.toggleSplitLeft(screenScope.modelData ? screenScope.modelData.name : "")
                        onToggleCenterRequested: root.toggleSplitCenter(screenScope.modelData ? screenScope.modelData.name : "")
                        onToggleControlCenterRequested: root.toggleSplitControls("controls", screenScope.modelData ? screenScope.modelData.name : "")
                        onToggleNotificationsRequested: root.toggleSplitNotifications(screenScope.modelData ? screenScope.modelData.name : "")
                        onToggleSpotlightRequested: root.toggleSplitLauncher("apps")
                        onOpenSettingsRequested: page => root.openSettings(page)
                        onOpenFilesRequested: path => root.openFiles(path)
                        onOpenStoreRequested: root.openStore()
                    }
                }
            }

            // Mode D (or Simple Mode popup layer): Morphing Dynamic Island / Modular Pill
            LazyLoader {
                id: islandLoader
                active: Theme.isSimple || (ShellState.barUiStyle !== "menubar" && ShellState.barUiStyle !== "split")

                PanelWindow {
                    id: islandWindow
                    readonly property alias island: islandItem
                    screen: screenScope.modelData

                    anchors {
                        top: true
                        left: true
                        right: true
                    }

                    exclusiveZone: Theme.isSimple ? 0 : (
                        ShellState.pillHeight + (
                            (ShellState.barUiStyle === "classic" && (ShellState.islandStyle === "notch" || ShellState.islandStyle === "bar"))
                                ? 2
                                : ShellState.islandTopMargin + 2
                        )
                    )
                    exclusionMode: ExclusionMode.Normal
                    implicitHeight: 660
                    color: "transparent"

                    mask: Region {
                        item: islandItem.maskTarget
                    }

                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "quickshell-island"
                    WlrLayershell.keyboardFocus: islandItem.needsKeyboardFocus
                        ? WlrKeyboardFocus.Exclusive
                        : WlrKeyboardFocus.None

                    IdleInhibitor {
                        enabled: ShellState.keepAwake && (Quickshell.screens.length === 0 || screenScope.modelData === Quickshell.screens[0])
                        window: islandWindow
                    }

                    DynamicIsland {
                        id: islandItem
                        anchors.fill: parent
                        screenName: screenScope.modelData ? screenScope.modelData.name : ""
                        onOpenSettingsRequested: page => root.openSettings(page)
                        onOpenFilesRequested: path => root.openFiles(path)
                        onOpenKeybindsRequested: root.openKeybinds()
                        onOpenCaptureHubRequested: root.openCaptureHub()
                        onOpenStoreRequested: root.openStore()
                    }
                }
            }
        }
    }

    // Dedicated Sequoia Control Center / Notifications / Spotlight / OSD Hub (on demand)
    LazyLoader {
        id: sequoiaHubLoader
        active: root._sequoiaHubLoaded && root.isSequoiaActive

        SequoiaHub {
            isOpen: root.sequoiaHubOpen
            panelMode: root.sequoiaHubMode
            launcherMode: root.sequoiaLauncherMode
            controlsTab: root.sequoiaControlsTab
            powerMenuOpen: root.sequoiaPowerMenuOpen
            screenName: root.sequoiaScreenName
            player: root.activePlayer
            osdType: root.sequoiaOsdType
            osdTriggerSeq: root.sequoiaOsdSeq
            pendingNotif: root.sequoiaPendingNotif
            notifTriggerSeq: root.sequoiaNotifSeq

            onCloseRequested: root.closeSequoiaHub()
            onOpenSettingsRequested: page => {
                root.closeSequoiaHub();
                root.openSettings(page);
            }
            onOpenFilesRequested: path => {
                root.closeSequoiaHub();
                root.openFiles(path);
            }
            onOpenKeybindsRequested: {
                root.closeSequoiaHub();
                root.openKeybinds();
            }
            onOpenCaptureHubRequested: {
                root.closeSequoiaHub();
                root.openCaptureHub();
            }
            onOpenStoreRequested: {
                root.closeSequoiaHub();
                root.openStore();
            }
            onSwitchControlsTab: tab => {
                root.sequoiaPowerMenuOpen = false;
                root.sequoiaControlsTab = tab;
            }
            onTogglePowerMenuRequested: root.sequoiaPowerMenuOpen = !root.sequoiaPowerMenuOpen
        }
    }

    // Dedicated Split Islands Per-Pod Hub (Left Spaces, Center Media/Focus, Right Control Center/Notifications, Spotlight, OSD)
    LazyLoader {
        id: splitHubLoader
        active: root._splitHubLoaded && root.isSplitActive

        SplitHub {
            isOpen: root.splitHubOpen
            panelMode: root.splitHubMode
            launcherMode: root.splitLauncherMode
            controlsTab: root.splitControlsTab
            powerMenuOpen: root.splitPowerMenuOpen
            screenName: root.splitScreenName
            player: root.activePlayer
            osdType: root.splitOsdType
            osdTriggerSeq: root.splitOsdSeq
            pendingNotif: root.splitPendingNotif
            notifTriggerSeq: root.splitNotifSeq

            onCloseRequested: root.closeSplitHub()
            onOpenSettingsRequested: page => {
                root.closeSplitHub();
                root.openSettings(page);
            }
            onOpenFilesRequested: path => {
                root.closeSplitHub();
                root.openFiles(path);
            }
            onOpenKeybindsRequested: {
                root.closeSplitHub();
                root.openKeybinds();
            }
            onOpenCaptureHubRequested: {
                root.closeSplitHub();
                root.openCaptureHub();
            }
            onOpenStoreRequested: {
                root.closeSplitHub();
                root.openStore();
            }
            onOpenNotificationsRequested: root.toggleSplitNotifications(root.splitScreenName)
            onSwitchControlsTab: tab => {
                root.splitPowerMenuOpen = false;
                root.splitControlsTab = tab;
            }
            onTogglePowerMenuRequested: root.splitPowerMenuOpen = !root.splitPowerMenuOpen
        }
    }

    // Hardware-Aware Settings Window (compiled only when opened)
    LazyLoader {
        id: settingsLoader
        active: root._settingsLoaded

        SettingsWindow {
            isOpen: root.settingsOpen
            activePage: root.settingsPage
            onPageSelected: page => { root.settingsPage = page; }
            onCloseRequested: root.closeSettings()
            onOpenStoreRequested: root.openStore()
        }
    }

    // Native Aurora App Store Window
    LazyLoader {
        id: storeLoader
        active: root._storeLoaded

        StoreWindow {
            isOpen: root.storeOpen
            onCloseRequested: root.closeStore()
            onOpenSettingsRequested: page => root.openSettings(page)
        }
    }

    // Rust-Backed Dynamic File Manager Window
    LazyLoader {
        id: filesLoader
        active: root._filesLoaded

        FileManagerWindow {
            isOpen: root.filesOpen
            initialPath: root.filesStartPath
            onCloseRequested: root.closeFiles()
            onOpenSettingsRequested: page => root.openSettings(page)
        }
    }

    // Keybind Cheat Sheet Modal
    LazyLoader {
        id: keybindsLoader
        active: root._keybindsLoaded

        KeybindSheet {
            isOpen: root.keybindsOpen
            onCloseRequested: root.closeKeybinds()
        }
    }

    // Window Switcher Modal
    LazyLoader {
        id: switcherLoader
        active: root._windowSwitcherLoaded

        WindowSwitcher {
            isOpen: root.windowSwitcherOpen
            onCloseRequested: root.closeWindowSwitcher()
        }
    }

    // Full-Screen Power & Session Overlay
    LazyLoader {
        id: powerOverlayLoader
        active: root._powerOverlayLoaded

        PowerOverlay {
            isOpen: root.powerOverlayOpen
            onCloseRequested: root.closePowerOverlay()
            onLockRequested: lockScreen.lock()
        }
    }

    // Rust-Backed Capture Studio Modal
    LazyLoader {
        id: captureHubLoader
        active: root._captureHubLoaded

        CaptureHubModal {
            isOpen: root.captureHubOpen
            onCloseRequested: root.closeCaptureHub()
            onOpenFilesRequested: path => root.openFiles(path)
        }
    }

    // Native Polkit Authentication Agent Modal
    PolkitModal {}

    // Native Wayland Lock Screen + Idle Power Manager
    LockScreen {
        id: lockScreen
    }

    IpcHandler {
        target: "island"

        function lockSession(): void {
            root._closeOtherModals("");
            lockScreen.lock();
        }

        function toggleCaptureHub(): void { root.toggleCaptureHub(); }
        function toggleSnippets(): void { root.dispatchLauncher("snippets"); }
        function toggleWindowSwitcher(): void { root.toggleWindowSwitcher(); }
        function togglePowerOverlay(): void { root.togglePowerOverlay(); }
        function toggleGameMode(): void { ShellState.toggleGameMode(); }
        function refreshWeather(): void { ShellState.refreshWeather(true); }
        function syncSddmTheme(): void { Quickshell.execDetached([Quickshell.shellPath("scripts/sync-sddm-theme.sh")]); }
        function toggleLauncher(): void { root.dispatchLauncher("apps"); }
        function toggleClipboard(): void { root.dispatchLauncher("clipboard"); }
        function toggleNotifications(): void { root.dispatchNotifications(); }
        function toggleKeybindSheet(): void { root.toggleKeybindSheet(); }
        function syncRecordingState(): void { ShellState.syncRecordingState(); }
        function toggleEthShare(): void { ShellState.toggleEthShare(); }
        function openNetwork(): void { root.openSettings("network"); }
        function toggleThemeTab(): void { root.dispatchThemeTab(); }
        function showOsd(osdType: string): void { root.dispatchOsd(osdType); }
        function toggle(): void { root.dispatchDashboard(); }
        function toggleDashboard(): void { root.dispatchDashboard(); }
        function collapse(): void { root.dispatchCollapse(); }
        function setShellMode(mode: string): void { Theme.setShellMode(mode); }
        function toggleShellMode(mode: string): void { Theme.toggleShellMode(mode); }
        function cycleShellMode(): void { Theme.cycleShellMode(); }
        function setHubUiStyle(style: string): void { ShellState.setHubUiStyle(style); }
        function cycleHubUiStyle(): void { ShellState.cycleHubUiStyle(); }
        function toggleSplitLeft(): void { root.toggleSplitLeft(""); }
        function toggleSplitCenter(): void { root.toggleSplitCenter(""); }
        function setSequoiaHubStyle(style: string): void { ShellState.setSequoiaHubStyle(style); }
        function cycleSequoiaHubStyle(): void { ShellState.cycleSequoiaHubStyle(); }
        function setSplitHubStyle(style: string): void { ShellState.setSplitHubStyle(style); }
        function cycleSplitHubStyle(): void { ShellState.cycleSplitHubStyle(); }
        function setBarUiStyle(style: string): void { ShellState.setBarUiStyle(style); }
        function cycleBarUiStyle(): void { ShellState.cycleBarUiStyle(); }
        function toggleSettings(): void { root.toggleSettings(); }
        function openSettings(page: string): void { root.openSettings(page); }
        function openDoctor(): void { root.openSettings("system"); }
        function closeSettings(): void { root.closeSettings(); }
        function toggleStore(): void { root.toggleStore(); }
        function openStore(): void { root.openStore(); }
        function closeStore(): void { root.closeStore(); }
        function toggleFiles(): void { root.toggleFiles(); }
        function openFiles(path: string): void { root.openFiles(path); }
        function closeFiles(): void { root.closeFiles(); }
        function toggleFilesTab(): void { root.dispatchFilesTab(); }
        function resetFiles(): void { ShellState.resetFiles(); }
        function toggleDnd(): void { ShellState.toggleDnd(); }
        function toggleKeepAwake(): void { ShellState.toggleKeepAwake(); }
        function clearClipboard(): void { Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "clear-clipboard"]); }
        function randomWallpaper(): void { Theme.randomWallpaper(); }
        function applyVibe(vibeId: string): void { Theme.applyVibe(vibeId); }
        function applyAccent(hex: string): void { Theme.applyAccentColor(hex); }
        function applyPreset(presetId: string): void { Theme.applyPreset(presetId); }
        function toggleDarkLight(): void { Theme.toggleScheme(); }
        function resetAppearance(): void { ShellState.resetAppearance(); }
        function resetBar(): void { ShellState.resetBar(); }
        function resetIsland(): void { ShellState.resetIsland(); }
        function resetSequoia(): void { ShellState.resetSequoia(); }
        function resetSplit(): void { ShellState.resetSplit(); }
        function resetAllSettings(): void { ShellState.resetAllSettings(); }
        function togglePip(): void { ShellState.togglePip(); }
        function cyclePipCorner(): void { ShellState.cyclePipCorner(); }
        function snapPip(): void { ShellState.snapPip(); }
    }

    IpcHandler {
        target: "aurora"

        function lockSession(): void {
            root._closeOtherModals("");
            lockScreen.lock();
        }

        function toggleCaptureHub(): void { root.toggleCaptureHub(); }
        function toggleSnippets(): void { root.dispatchLauncher("snippets"); }
        function toggleWindowSwitcher(): void { root.toggleWindowSwitcher(); }
        function togglePowerOverlay(): void { root.togglePowerOverlay(); }
        function toggleGameMode(): void { ShellState.toggleGameMode(); }
        function refreshWeather(): void { ShellState.refreshWeather(true); }
        function syncSddmTheme(): void { Quickshell.execDetached([Quickshell.shellPath("scripts/sync-sddm-theme.sh")]); }
        function toggleLauncher(): void { root.dispatchLauncher("apps"); }
        function toggleClipboard(): void { root.dispatchLauncher("clipboard"); }
        function toggleNotifications(): void { root.dispatchNotifications(); }
        function toggleKeybindSheet(): void { root.toggleKeybindSheet(); }
        function syncRecordingState(): void { ShellState.syncRecordingState(); }
        function toggleEthShare(): void { ShellState.toggleEthShare(); }
        function openNetwork(): void { root.openSettings("network"); }
        function toggleThemeTab(): void { root.dispatchThemeTab(); }
        function showOsd(osdType: string): void { root.dispatchOsd(osdType); }
        function toggle(): void { root.dispatchDashboard(); }
        function toggleDashboard(): void { root.dispatchDashboard(); }
        function collapse(): void { root.dispatchCollapse(); }
        function setShellMode(mode: string): void { Theme.setShellMode(mode); }
        function toggleShellMode(mode: string): void { Theme.toggleShellMode(mode); }
        function cycleShellMode(): void { Theme.cycleShellMode(); }
        function setHubUiStyle(style: string): void { ShellState.setHubUiStyle(style); }
        function cycleHubUiStyle(): void { ShellState.cycleHubUiStyle(); }
        function toggleSplitLeft(): void { root.toggleSplitLeft(""); }
        function toggleSplitCenter(): void { root.toggleSplitCenter(""); }
        function setSequoiaHubStyle(style: string): void { ShellState.setSequoiaHubStyle(style); }
        function cycleSequoiaHubStyle(): void { ShellState.cycleSequoiaHubStyle(); }
        function setSplitHubStyle(style: string): void { ShellState.setSplitHubStyle(style); }
        function cycleSplitHubStyle(): void { ShellState.cycleSplitHubStyle(); }
        function setBarUiStyle(style: string): void { ShellState.setBarUiStyle(style); }
        function cycleBarUiStyle(): void { ShellState.cycleBarUiStyle(); }
        function toggleSettings(): void { root.toggleSettings(); }
        function openSettings(page: string): void { root.openSettings(page); }
        function openDoctor(): void { root.openSettings("system"); }
        function closeSettings(): void { root.closeSettings(); }
        function toggleStore(): void { root.toggleStore(); }
        function openStore(): void { root.openStore(); }
        function closeStore(): void { root.closeStore(); }
        function toggleFiles(): void { root.toggleFiles(); }
        function openFiles(path: string): void { root.openFiles(path); }
        function closeFiles(): void { root.closeFiles(); }
        function toggleFilesTab(): void { root.dispatchFilesTab(); }
        function resetFiles(): void { ShellState.resetFiles(); }
        function toggleDnd(): void { ShellState.toggleDnd(); }
        function toggleKeepAwake(): void { ShellState.toggleKeepAwake(); }
        function clearClipboard(): void { Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "clear-clipboard"]); }
        function randomWallpaper(): void { Theme.randomWallpaper(); }
        function applyVibe(vibeId: string): void { Theme.applyVibe(vibeId); }
        function applyAccent(hex: string): void { Theme.applyAccentColor(hex); }
        function applyPreset(presetId: string): void { Theme.applyPreset(presetId); }
        function toggleDarkLight(): void { Theme.toggleScheme(); }
        function resetAppearance(): void { ShellState.resetAppearance(); }
        function resetBar(): void { ShellState.resetBar(); }
        function resetIsland(): void { ShellState.resetIsland(); }
        function resetSequoia(): void { ShellState.resetSequoia(); }
        function resetSplit(): void { ShellState.resetSplit(); }
        function resetAllSettings(): void { ShellState.resetAllSettings(); }
        function togglePip(): void { ShellState.togglePip(); }
        function cyclePipCorner(): void { ShellState.cyclePipCorner(); }
        function snapPip(): void { ShellState.snapPip(); }
    }
}
