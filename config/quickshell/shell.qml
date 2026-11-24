pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "components"
import "settings"
import "files"

ShellRoot {
    id: root

    property bool settingsOpen: false
    property bool _settingsLoaded: false
    property string settingsPage: "appearance"

    property bool filesOpen: false
    property bool _filesLoaded: false
    property string filesStartPath: ""

    property bool keybindsOpen: false
    property bool _keybindsLoaded: false

    property bool windowSwitcherOpen: false
    property bool _windowSwitcherLoaded: false

    property bool powerOverlayOpen: false
    property bool _powerOverlayLoaded: false

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

    function openSettings(page: string): void {
        root.closeFiles();
        root.closeKeybinds();
        root.closeWindowSwitcher();
        root.closePowerOverlay();
        root.settingsPage = (page && page.length > 0) ? page : "appearance";
        root.collapseAll();
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
            root.openSettings("appearance");
    }

    function openFiles(startPath: string): void {
        root.closeSettings();
        root.closeKeybinds();
        root.closeWindowSwitcher();
        root.closePowerOverlay();
        root.filesStartPath = (startPath && startPath.length > 0) ? startPath : "";
        root.collapseAll();
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
        root.closeSettings();
        root.closeFiles();
        root.closeWindowSwitcher();
        root.closePowerOverlay();
        root.collapseAll();
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
        root.closeSettings();
        root.closeFiles();
        root.closeKeybinds();
        root.closePowerOverlay();
        root.collapseAll();
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
        root.closeSettings();
        root.closeFiles();
        root.closeKeybinds();
        root.closeWindowSwitcher();
        root.collapseAll();
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

    Timer {
        id: settingsUnloadTimer
        interval: Theme.reducedMotion ? 10 : 150
        repeat: false
        onTriggered: {
            if (!root.settingsOpen)
                root._settingsLoaded = false;
        }
    }

    Timer {
        id: filesUnloadTimer
        interval: Theme.reducedMotion ? 10 : 150
        repeat: false
        onTriggered: {
            if (!root.filesOpen)
                root._filesLoaded = false;
        }
    }

    Timer {
        id: keybindsUnloadTimer
        interval: Theme.reducedMotion ? 10 : 150
        repeat: false
        onTriggered: {
            if (!root.keybindsOpen)
                root._keybindsLoaded = false;
        }
    }

    Timer {
        id: switcherUnloadTimer
        interval: Theme.reducedMotion ? 10 : 170
        repeat: false
        onTriggered: {
            if (!root.windowSwitcherOpen)
                root._windowSwitcherLoaded = false;
        }
    }

    Timer {
        id: powerUnloadTimer
        interval: Theme.reducedMotion ? 10 : 170
        repeat: false
        onTriggered: {
            if (!root.powerOverlayOpen)
                root._powerOverlayLoaded = false;
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

    // Per-Monitor Dynamic Island & Simple Square Top Bar
    Variants {
        id: screenVariants
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property var modelData
            readonly property alias island: islandItem

            // Extremely Simple Square Top Bar (loaded only in Simple Mode)
            LazyLoader {
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
                        onToggleDashboardRequested: islandItem.toggleDashboard()
                        onToggleLauncherRequested: islandItem.toggleLauncher()
                        onToggleSettingsRequested: root.toggleSettings()
                        onToggleFilesRequested: root.toggleFiles()
                        onToggleNotificationsRequested: islandItem.toggleNotifications()
                    }
                }
            }

            PanelWindow {
                id: islandWindow
                screen: screenScope.modelData

                anchors {
                    top: true
                    left: true
                    right: true
                }

                // Reserve top bar space cleanly: full-width/notch flush modes omit floating pill top margin
                exclusiveZone: Theme.isSimple ? 0 : (
                    ShellState.barUiStyle === "menubar" ? 28 : (
                        ShellState.pillHeight + (
                            (ShellState.barUiStyle === "classic" && (ShellState.islandStyle === "notch" || ShellState.islandStyle === "bar"))
                                ? 2
                                : ShellState.islandTopMargin + 2
                        )
                    )
                )
                exclusionMode: ExclusionMode.Normal
                implicitHeight: 620
                color: "transparent"

                // Only the visible Dynamic Island pill (or active square dropdown in Simple Mode) intercepts mouse events.
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
                }
            }
        }
    }

    // Built-in Hardware-Aware Settings Window (lazy-loaded on demand, unloaded after exit animation)
    LazyLoader {
        id: settingsLoader
        active: root._settingsLoaded

        SettingsWindow {
            isOpen: root.settingsOpen
            activePage: root.settingsPage
            onPageSelected: page => { root.settingsPage = page; }
            onCloseRequested: root.closeSettings()
        }
    }

    // Rust-Backed Dynamic File Manager Window (lazy-loaded on demand, zero idle daemon)
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

    // Keybind Cheat Sheet Modal (lazy-loaded on demand)
    LazyLoader {
        id: keybindsLoader
        active: root._keybindsLoaded

        KeybindSheet {
            isOpen: root.keybindsOpen
            onCloseRequested: root.closeKeybinds()
        }
    }

    // Window Switcher Modal (lazy-loaded on demand)
    LazyLoader {
        id: switcherLoader
        active: root._windowSwitcherLoaded

        WindowSwitcher {
            isOpen: root.windowSwitcherOpen
            onCloseRequested: root.closeWindowSwitcher()
        }
    }

    // Full-Screen Power & Session Overlay (lazy-loaded on demand)
    LazyLoader {
        id: powerOverlayLoader
        active: root._powerOverlayLoaded

        PowerOverlay {
            isOpen: root.powerOverlayOpen
            onCloseRequested: root.closePowerOverlay()
            onLockRequested: lockScreen.lock()
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
            root.collapseAll();
            root.closeSettings();
            root.closeFiles();
            root.closeKeybinds();
            root.closeWindowSwitcher();
            root.closePowerOverlay();
            lockScreen.lock();
        }

        function toggleWindowSwitcher(): void {
            root.toggleWindowSwitcher();
        }

        function togglePowerOverlay(): void {
            root.togglePowerOverlay();
        }

        function toggleGameMode(): void {
            ShellState.toggleGameMode();
        }

        function refreshWeather(): void {
            ShellState.refreshWeather(true);
        }

        function syncSddmTheme(): void {
            Quickshell.execDetached([Quickshell.shellPath("scripts/sync-sddm-theme.sh")]);
        }

        function toggleLauncher(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleLauncher();
        }

        function toggleClipboard(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleClipboard();
        }

        function toggleNotifications(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleNotifications();
        }

        function toggleKeybindSheet(): void {
            root.toggleKeybindSheet();
        }

        function syncRecordingState(): void {
            ShellState.syncRecordingState();
        }

        function toggleThemeTab(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleThemeTab();
        }

        function showOsd(osdType: string): void {
            root.forEachIsland(isl => isl.triggerOsd(osdType));
        }

        function toggleDashboard(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleDashboard();
        }

        function collapse(): void {
            root.collapseAll();
        }

        function setShellMode(mode: string): void {
            Theme.setShellMode(mode);
        }

        function toggleShellMode(mode: string): void {
            Theme.toggleShellMode(mode);
        }

        function cycleShellMode(): void {
            Theme.cycleShellMode();
        }

        function setHubUiStyle(style: string): void {
            ShellState.setHubUiStyle(style);
        }

        function cycleHubUiStyle(): void {
            ShellState.cycleHubUiStyle();
        }

        function setBarUiStyle(style: string): void {
            ShellState.setBarUiStyle(style);
        }

        function cycleBarUiStyle(): void {
            ShellState.cycleBarUiStyle();
        }

        function toggleSettings(): void {
            root.toggleSettings();
        }

        function openSettings(page: string): void {
            root.openSettings(page);
        }

        function openDoctor(): void {
            root.openSettings("system");
        }

        function closeSettings(): void {
            root.closeSettings();
        }

        function toggleFiles(): void {
            root.toggleFiles();
        }

        function openFiles(path: string): void {
            root.openFiles(path);
        }

        function closeFiles(): void {
            root.closeFiles();
        }

        function toggleFilesTab(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleFilesTab();
        }

        function resetFiles(): void {
            ShellState.resetFiles();
        }

        function toggleDnd(): void {
            ShellState.toggleDnd();
        }

        function toggleKeepAwake(): void {
            ShellState.toggleKeepAwake();
        }

        function clearClipboard(): void {
            Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "clear-clipboard"]);
        }

        function randomWallpaper(): void {
            Theme.randomWallpaper();
        }

        function applyVibe(vibeId: string): void {
            Theme.applyVibe(vibeId);
        }

        function applyAccent(hex: string): void {
            Theme.applyAccentColor(hex);
        }

        function applyPreset(presetId: string): void {
            Theme.applyPreset(presetId);
        }

        function toggleDarkLight(): void {
            Theme.toggleScheme();
        }

        function resetAppearance(): void {
            ShellState.resetAppearance();
        }

        function resetBar(): void {
            ShellState.resetBar();
        }

        function resetAllSettings(): void {
            ShellState.resetAllSettings();
        }

        function togglePip(): void {
            ShellState.togglePip();
        }

        function cyclePipCorner(): void {
            ShellState.cyclePipCorner();
        }

        function snapPip(): void {
            ShellState.snapPip();
        }
    }

    IpcHandler {
        target: "aurora"

        function lockSession(): void {
            root.collapseAll();
            root.closeSettings();
            root.closeFiles();
            root.closeKeybinds();
            root.closeWindowSwitcher();
            root.closePowerOverlay();
            lockScreen.lock();
        }

        function toggleWindowSwitcher(): void {
            root.toggleWindowSwitcher();
        }

        function togglePowerOverlay(): void {
            root.togglePowerOverlay();
        }

        function toggleGameMode(): void {
            ShellState.toggleGameMode();
        }

        function refreshWeather(): void {
            ShellState.refreshWeather(true);
        }

        function syncSddmTheme(): void {
            Quickshell.execDetached([Quickshell.shellPath("scripts/sync-sddm-theme.sh")]);
        }

        function toggleLauncher(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleLauncher();
        }

        function toggleClipboard(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleClipboard();
        }

        function toggleNotifications(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleNotifications();
        }

        function toggleKeybindSheet(): void {
            root.toggleKeybindSheet();
        }

        function syncRecordingState(): void {
            ShellState.syncRecordingState();
        }

        function toggleThemeTab(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleThemeTab();
        }

        function showOsd(osdType: string): void {
            root.forEachIsland(isl => isl.triggerOsd(osdType));
        }

        function toggleDashboard(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleDashboard();
        }

        function collapse(): void {
            root.collapseAll();
        }

        function setShellMode(mode: string): void {
            Theme.setShellMode(mode);
        }

        function toggleShellMode(mode: string): void {
            Theme.toggleShellMode(mode);
        }

        function cycleShellMode(): void {
            Theme.cycleShellMode();
        }

        function setHubUiStyle(style: string): void {
            ShellState.setHubUiStyle(style);
        }

        function cycleHubUiStyle(): void {
            ShellState.cycleHubUiStyle();
        }

        function setBarUiStyle(style: string): void {
            ShellState.setBarUiStyle(style);
        }

        function cycleBarUiStyle(): void {
            ShellState.cycleBarUiStyle();
        }

        function toggleSettings(): void {
            root.toggleSettings();
        }

        function openSettings(page: string): void {
            root.openSettings(page);
        }

        function openDoctor(): void {
            root.openSettings("system");
        }

        function closeSettings(): void {
            root.closeSettings();
        }

        function toggleFiles(): void {
            root.toggleFiles();
        }

        function openFiles(path: string): void {
            root.openFiles(path);
        }

        function closeFiles(): void {
            root.closeFiles();
        }

        function toggleFilesTab(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleFilesTab();
        }

        function resetFiles(): void {
            ShellState.resetFiles();
        }

        function toggleDnd(): void {
            ShellState.toggleDnd();
        }

        function toggleKeepAwake(): void {
            ShellState.toggleKeepAwake();
        }

        function clearClipboard(): void {
            Quickshell.execDetached([Quickshell.shellPath("scripts/manage-system.sh"), "clear-clipboard"]);
        }

        function randomWallpaper(): void {
            Theme.randomWallpaper();
        }

        function applyVibe(vibeId: string): void {
            Theme.applyVibe(vibeId);
        }

        function applyAccent(hex: string): void {
            Theme.applyAccentColor(hex);
        }

        function applyPreset(presetId: string): void {
            Theme.applyPreset(presetId);
        }

        function toggleDarkLight(): void {
            Theme.toggleScheme();
        }

        function resetAppearance(): void {
            ShellState.resetAppearance();
        }

        function resetBar(): void {
            ShellState.resetBar();
        }

        function resetAllSettings(): void {
            ShellState.resetAllSettings();
        }

        function togglePip(): void {
            ShellState.togglePip();
        }

        function cyclePipCorner(): void {
            ShellState.cyclePipCorner();
        }

        function snapPip(): void {
            ShellState.snapPip();
        }
    }
}
