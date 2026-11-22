pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "components"
import "settings"

ShellRoot {
    id: root

    property bool settingsOpen: false
    property bool _settingsLoaded: false
    property string settingsPage: "appearance"

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

    Timer {
        id: settingsUnloadTimer
        interval: Theme.isSimple ? 10 : 250
        repeat: false
        onTriggered: {
            if (!root.settingsOpen) {
                root._settingsLoaded = false;
                gc();
            }
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
            if (!ShellState.dnd)
                root.forEachIsland(isl => isl.showNotification(notification));
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
                        top: true
                        left: true
                        right: true
                    }

                    exclusiveZone: 28
                    exclusionMode: ExclusionMode.Normal
                    implicitHeight: 28
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

                // Fixed 40px exclusive zone in Default/Blur modes; 0 in Simple Mode (SimpleBar owns the 28px zone).
                exclusiveZone: Theme.isSimple ? 0 : 40
                exclusionMode: ExclusionMode.Normal
                implicitHeight: 540
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

    IpcHandler {
        target: "island"

        function toggleLauncher(): void {
            const isl = root.primaryIsland();
            if (isl)
                isl.toggleLauncher();
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

        function toggleSettings(): void {
            root.toggleSettings();
        }

        function openSettings(page: string): void {
            root.openSettings(page);
        }

        function closeSettings(): void {
            root.closeSettings();
        }

        function toggleDnd(): void {
            ShellState.toggleDnd();
        }

        function toggleKeepAwake(): void {
            ShellState.toggleKeepAwake();
        }
    }
}
