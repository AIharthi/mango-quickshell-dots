import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "components"

ShellRoot {
    id: root

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
            island.showNotification(notification);
        }
    }

    // Extremely Simple Square Top Bar (loaded only in Simple Mode)
    Loader {
        id: simpleBarLoader
        active: Theme.isSimple

        sourceComponent: PanelWindow {
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
                onToggleDashboardRequested: island.toggleDashboard()
                onToggleLauncherRequested: island.toggleLauncher()
            }
        }
    }

    PanelWindow {
        id: islandWindow

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
            item: island.maskTarget
        }

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-island"
        WlrLayershell.keyboardFocus: island.needsKeyboardFocus
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None

        DynamicIsland {
            id: island
            anchors.fill: parent
        }
    }

    IpcHandler {
        target: "island"

        function toggleLauncher(): void {
            island.toggleLauncher();
        }

        function toggleThemeTab(): void {
            island.toggleThemeTab();
        }

        function showOsd(osdType: string): void {
            island.triggerOsd(osdType);
        }

        function toggleDashboard(): void {
            island.toggleDashboard();
        }

        function collapse(): void {
            island.collapse();
        }

        function setShellMode(mode: string): void {
            Theme.setShellMode(mode);
        }

        function toggleShellMode(mode: string): void {
            Theme.toggleShellMode(mode);
        }
    }
}
