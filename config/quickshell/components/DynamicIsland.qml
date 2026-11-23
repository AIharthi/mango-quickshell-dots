pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import ".."

Item {
    id: root

    // --- Public API & Window Integration ---
    readonly property alias maskTarget: islandContainer
    property string screenName: ""
    property string islandState: "collapsed"    // "collapsed" | "osd" | "notification" | "expanded"
    property string activeTab: "overview"       // "overview" | "files" | "themes" | "launcher" | "notifications"
    property string launcherMode: "apps"
    property bool pinnedOpen: false
    property bool powerMenuOpen: false
    property bool launcherSearchFocused: false
    property bool interactiveControlActive: false

    signal openSettingsRequested(string page)
    signal openFilesRequested(string path)
    signal openKeybindsRequested()

    readonly property bool needsKeyboardFocus:
        (islandState === "expanded" && activeTab === "launcher") || launcherSearchFocused

    // --- Spotify-first MPRIS Player Resolution ---
    readonly property var activePlayer: {
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
            const idStr = ((p.identity || "") + " " + (p.dbusName || "") + " " + (p.desktopEntry || "")).toLowerCase();
            const isSpotify = idStr.indexOf("spotify") !== -1;
            const hasTrack = (p.trackTitle && p.trackTitle.length > 0);

            if (isSpotify) {
                if (p.isPlaying)
                    playingSpotify = playingSpotify || p;
                else if (hasTrack)
                    idleSpotify = idleSpotify || p;
            } else {
                if (p.isPlaying)
                    playingFallback = playingFallback || p;
                else if (hasTrack)
                    idleFallback = idleFallback || p;
            }
        }
        return playingSpotify || idleSpotify || playingFallback || idleFallback || null;
    }

    // --- State Machine Actions ---
    function collapse(): void {
        hoverExpandTimer.stop();
        hoverCollapseTimer.stop();
        osdHideTimer.stop();
        notifHideTimer.stop();
        root.pinnedOpen = false;
        root.powerMenuOpen = false;
        root.launcherSearchFocused = false;
        root.interactiveControlActive = false;
        root.islandState = "collapsed";
    }

    function expandTo(tab: string, pin: bool): void {
        hoverExpandTimer.stop();
        hoverCollapseTimer.stop();
        osdHideTimer.stop();
        notifHideTimer.stop();
        root.activeTab = tab;
        root.pinnedOpen = pin;
        root.islandState = "expanded";
    }

    function toggleTab(tab: string): void {
        if (root.islandState === "expanded" && root.activeTab === tab) {
            collapse();
        } else {
            expandTo(tab, true);
        }
    }

    function toggleLauncher(): void {
        if (root.islandState === "expanded" && root.activeTab === "launcher" && root.launcherMode !== "apps") {
            root.launcherMode = "apps";
            return;
        }
        root.launcherMode = "apps";
        toggleTab("launcher");
    }

    function toggleClipboard(): void {
        if (root.islandState === "expanded" && root.activeTab === "launcher" && root.launcherMode !== "clip") {
            root.launcherMode = "clip";
            return;
        }
        root.launcherMode = "clip";
        toggleTab("launcher");
    }

    function toggleThemeTab(): void {
        toggleTab("themes");
    }

    function toggleFilesTab(): void {
        toggleTab("files");
    }

    function toggleNotifications(): void {
        toggleTab("notifications");
    }

    function toggleDashboard(): void {
        if (root.islandState === "expanded")
            collapse();
        else
            expandTo("overview", true);
    }

    function triggerOsd(osdType: string): void {
        // If user is actively interacting inside expanded dashboard, still refresh values silently
        if (root.islandState === "expanded") {
            osdOverlay.refreshOsdValue(osdType);
            return;
        }
        if (!ShellState.osdEnabled)
            return;
        hoverCollapseTimer.stop();
        notifHideTimer.stop();
        osdOverlay.showOsd(osdType);
        root.islandState = "osd";
        osdHideTimer.restart();
    }

    function showNotification(notif: var): void {
        if (!notif)
            return;
        osdOverlay.showNotification(notif);
        if (root.islandState === "expanded")
            return;
        osdHideTimer.stop();
        root.islandState = "notification";
        const timeoutMs = (notif.expireTimeout && notif.expireTimeout > 0)
            ? Math.max(1500, Math.min(15000, notif.expireTimeout))
            : ShellState.notifTimeoutMs;
        notifHideTimer.interval = timeoutMs;
        if (!hoverHandler.hovered)
            notifHideTimer.restart();
    }

    // --- Target Geometry per State ---
    readonly property int expandedWidth: {
        if (root.activeTab === "launcher")
            return 650;
        if (root.activeTab === "notifications")
            return 720;
        if (root.activeTab === "files")
            return 700;
        if (root.activeTab === "themes")
            return 700;
        return 720;
    }

    readonly property int expandedHeight: {
        let h = 464;
        if (root.activeTab === "launcher")
            h = 472;
        else if (root.activeTab === "notifications")
            h = 474;
        else if (root.activeTab === "files")
            h = 444;
        else if (root.activeTab === "themes")
            h = 440;
        else
            h = DeviceCaps.hasExtraQuickControls ? 504 : 464;
        return h + (root.powerMenuOpen ? 46 : 0);
    }

    readonly property int notchPad: (!Theme.isSimple && ShellState.islandStyle === "notch") ? 14 : 0

    readonly property int targetWidth: {
        if (root.islandState === "collapsed") {
            if (ShellState.islandStyle === "bar")
                return Math.max(320, Math.round(root.width) - ShellState.islandTopMargin * 2);
            return Math.max(114, Math.min(Math.round(root.width) - 32, Math.round(collapsedPill.implicitWidth) + 32));
        }
        if (root.islandState === "osd")
            return 320;
        if (root.islandState === "notification")
            return 420;
        return root.expandedWidth;
    }

    readonly property int targetHeight: {
        if (root.islandState === "collapsed")
            return ShellState.pillHeight + root.notchPad;
        if (root.islandState === "osd")
            return 56 + root.notchPad;
        if (root.islandState === "notification")
            return Math.max(78, Math.min(148, Math.round(osdOverlay.notificationHeight) + 20)) + root.notchPad;
        return root.expandedHeight + root.notchPad;
    }

    readonly property int targetRadius: {
        if (Theme.isSimple)
            return 0;
        if (root.islandState === "collapsed")
            return ShellState.islandStyle === "bar"
                ? Math.round(Theme.r(12))
                : Math.round(Theme.r(Math.round(ShellState.pillHeight / 2) + 1));
        if (root.islandState === "osd" || root.islandState === "notification")
            return Math.round(Theme.r(24));
        return Math.round(Theme.r(26));
    }

    Connections {
        target: Theme
        function onShellModeChanged(): void {
            if (Theme.isSimple && root.islandState === "expanded")
                root.collapse();
        }
    }

    Keys.onEscapePressed: root.collapse()

    // --- Timers ---
    Timer {
        id: hoverExpandTimer
        interval: ShellState.islandHoverDelayMs
        repeat: false
        onTriggered: {
            if (!Theme.isSimple && ShellState.islandHoverExpand && hoverHandler.hovered && (root.islandState === "collapsed" || root.islandState === "osd")) {
                root.expandTo("overview", false);
            }
        }
    }

    Timer {
        id: hoverCollapseTimer
        interval: ShellState.islandCollapseDelayMs
        repeat: false
        onTriggered: {
            if (!hoverHandler.hovered && !root.pinnedOpen && !root.interactiveControlActive
                && root.islandState === "expanded" && root.activeTab !== "launcher") {
                root.collapse();
            }
        }
    }

    Timer {
        id: osdHideTimer
        interval: ShellState.osdTimeoutMs
        repeat: false
        onTriggered: {
            if (root.islandState === "osd")
                root.islandState = "collapsed";
        }
    }

    Timer {
        id: notifHideTimer
        interval: 4500
        repeat: false
        onTriggered: {
            if (root.islandState === "notification" && !hoverHandler.hovered)
                root.islandState = "collapsed";
        }
    }

    // --- Main Morphing Floating Pill / Square Dropdown Container ---
    Rectangle {
        id: islandContainer
        readonly property bool hiddenInSimple: Theme.isSimple && root.islandState === "collapsed"

        anchors.top: parent.top
        anchors.topMargin: Theme.isSimple
            ? (ShellState.simpleBarPosition === "bottom" ? 8 : (ShellState.simpleBarHeight + 4))
            : (root.notchPad > 0 ? -root.notchPad : ShellState.islandTopMargin)
        anchors.horizontalCenter: parent.horizontalCenter

        width: hiddenInSimple ? 0 : root.targetWidth
        height: hiddenInSimple ? 0 : root.targetHeight
        radius: root.targetRadius
        visible: !hiddenInSimple
        clip: true

        color: Theme.notchBg
        border.width: Theme.islandBorderWidth
        border.color: Theme.islandBorder

        Behavior on width {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on height {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
        Behavior on radius {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        // Signature Visual Mode Finishes (Frosted Glass, Cyber Neon, Tactile Stripe, Obsidian Rim)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(parent.height, 48)
            radius: parent.radius
            visible: Theme.showGlassSheen
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.40) }
                GradientStop { position: 1.0; color: "transparent" }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.60)
            }
        }

        // Cyber Neon HUD ambient wash + prismatic top energy line
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(parent.height, 56)
            radius: parent.radius
            visible: Theme.showNeonAccentBar
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.withAlpha(Theme.primary, 0.14) }
                GradientStop { position: 1.0; color: "transparent" }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Theme.primary }
                    GradientStop { position: 0.5; color: Theme.secondary }
                    GradientStop { position: 1.0; color: Theme.tertiary }
                }
            }
        }

        // Tactile / Neo-Brutalist bold top hardware accent band
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 3
            visible: Theme.showRetroStripe
            color: Theme.primary
        }

        // Obsidian OLED top hairline rim
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            visible: Theme.showOledRim
            color: Theme.withAlpha(Theme.primary, 0.35)
        }

        // Subtle urgent bottom accent for critical notifications (no outer outline)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 2
            visible: root.islandState === "notification" && osdOverlay.isUrgent
            color: Theme.error
            z: 10
        }

        HoverHandler {
            id: hoverHandler
            onHoveredChanged: {
                if (hovered) {
                    hoverCollapseTimer.stop();
                    if (!Theme.isSimple && ShellState.islandHoverExpand && (root.islandState === "collapsed" || root.islandState === "osd")) {
                        hoverExpandTimer.restart();
                    } else if (root.islandState === "notification") {
                        notifHideTimer.stop();
                    }
                } else {
                    hoverExpandTimer.stop();
                    if (root.islandState === "expanded" && !root.pinnedOpen
                        && !root.interactiveControlActive && root.activeTab !== "launcher") {
                        hoverCollapseTimer.restart();
                    } else if (root.islandState === "notification") {
                        notifHideTimer.restart();
                    }
                }
            }
        }

        // Click background area of collapsed pill/bar to expand immediately
        // (Placed behind CollapsedPill so interactive pill buttons consume their own clicks.)
        MouseArea {
            anchors.fill: parent
            enabled: !Theme.isSimple && root.islandState === "collapsed"
            onClicked: root.expandTo("overview", false)
        }

        // 1. Collapsed Compact Pill / Modular Bar View (Default & Blur modes only)
        CollapsedPill {
            id: collapsedPill
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(root.notchPad / 2)
            width: ShellState.islandStyle === "bar" ? Math.max(0, parent.width - 24) : implicitWidth
            screenName: root.screenName
            active: !Theme.isSimple && root.islandState === "collapsed"
            barMode: ShellState.islandStyle === "bar"
            player: root.activePlayer
            opacity: (!Theme.isSimple && root.islandState === "collapsed") ? 1.0 : 0.0
            visible: opacity > 0.01

            onLauncherClicked: root.toggleLauncher()
            onSettingsClicked: root.openSettingsRequested("appearance")
            onFilesClicked: root.openFilesRequested("")
            onNotificationsClicked: root.toggleNotifications()
            onTimerClicked: root.toggleNotifications()

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }
        }

        // 2. Morphing OSD & Notification View
        OsdOverlay {
            id: osdOverlay
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 10 + root.notchPad
            mode: root.islandState === "notification" ? "notification" : "osd"
            active: root.islandState === "osd" || root.islandState === "notification"
            opacity: active ? 1.0 : 0.0
            visible: opacity > 0.01

            onDismissRequested: {
                notifHideTimer.stop();
                osdHideTimer.stop();
                root.islandState = "collapsed";
            }

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }

        // 3. Expanded Interactive Dashboard Hub (lazy-loaded on demand, kept warm 60s)
        property bool _expandedLoaded: false

        Connections {
            target: root
            function onIslandStateChanged(): void {
                if (root.islandState === "expanded") {
                    expandedUnloadTimer.stop();
                    islandContainer._expandedLoaded = true;
                } else if (islandContainer._expandedLoaded) {
                    expandedUnloadTimer.restart();
                }
            }
        }

        Timer {
            id: expandedUnloadTimer
            interval: 60000
            repeat: false
            onTriggered: {
                if (root.islandState !== "expanded")
                    islandContainer._expandedLoaded = false;
            }
        }

        Loader {
            id: expandedLoader
            anchors.top: parent.top
            anchors.topMargin: 14 + root.notchPad
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.expandedWidth - 28
            height: root.expandedHeight - 28
            active: islandContainer._expandedLoaded
            visible: active

            sourceComponent: ExpandedDashboard {
                anchors.fill: parent
                isOpen: root.islandState === "expanded"
                screenName: root.screenName
                activeTab: root.activeTab
                launcherMode: root.launcherMode
                pinnedOpen: root.pinnedOpen
                powerMenuOpen: root.powerMenuOpen
                player: root.activePlayer
                opacity: root.islandState === "expanded" ? 1.0 : 0.0
                visible: opacity > 0.01

                onTabSelected: tab => {
                    root.activeTab = tab;
                    if (tab === "launcher")
                        root.pinnedOpen = true;
                }
                onTogglePinRequested: root.pinnedOpen = !root.pinnedOpen
                onTogglePowerMenuRequested: root.powerMenuOpen = !root.powerMenuOpen
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
                onOpenFilesRequested: path => root.openFilesRequested(path)
                onOpenKeybindsRequested: root.openKeybindsRequested()
                onCloseRequested: root.collapse()
                onSearchFocusChanged: focused => { root.launcherSearchFocused = focused; }
                onControlInteractionChanged: interacting => {
                    root.interactiveControlActive = interacting;
                    if (!interacting && !hoverHandler.hovered && !root.pinnedOpen
                        && root.islandState === "expanded" && root.activeTab !== "launcher") {
                        hoverCollapseTimer.restart();
                    }
                }

                Behavior on opacity {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
