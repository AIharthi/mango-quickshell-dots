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
    signal openCaptureHubRequested()
    signal openStoreRequested()

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

    function toggleSnippets(): void {
        if (root.islandState === "expanded" && root.activeTab === "launcher" && root.launcherMode !== "snippets") {
            root.launcherMode = "snippets";
            return;
        }
        root.launcherMode = "snippets";
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
    readonly property int _extraControlsHeight:
        (DeviceCaps.hasBacklight ? 38 : 0) + ((DeviceCaps.hasWifi || DeviceCaps.hasBluetooth) ? 42 : 0)

    readonly property int expandedWidth: {
        let w = 760;
        if (root.activeTab === "launcher")
            w = 780;
        return Math.min(w, Math.max(360, Math.round(root.width) - 24));
    }

    readonly property int expandedHeight: {
        let h = 510;
        if (root.activeTab === "launcher") {
            h = 580;
        } else if (root.activeTab === "notifications") {
            h = 536;
        } else if (root.activeTab === "files" || root.activeTab === "themes") {
            h = 510;
        } else {
            const hubStyle = ShellState.hubUiStyle;
            if (hubStyle === "cupertino")
                h = 424 + root._extraControlsHeight;
            else if (hubStyle === "stage")
                h = 432 + (DeviceCaps.hasBacklight ? 44 : 0);
            else if (hubStyle === "cockpit")
                h = 444 + root._extraControlsHeight;
            else
                h = 492 + root._extraControlsHeight;
        }
        return Math.min(h + (root.powerMenuOpen ? 48 : 0), Math.max(280, Math.round(root.height) - ShellState.islandTopMargin - 24));
    }

    readonly property int notchPad: (!Theme.isSimple && !isSplitBar && ShellState.islandStyle === "notch") ? 14 : 0
    readonly property bool isSplitBar: !Theme.isSimple && ShellState.barUiStyle === "split"
    readonly property bool isApplePill: !Theme.isSimple && ShellState.barUiStyle === "apple"
    readonly property bool splitCollapsed: isSplitBar && islandState === "collapsed"

    readonly property int targetWidth: {
        if (root.islandState === "collapsed") {
            if (root.isSplitBar)
                return Math.max(480, Math.round(root.width) - Math.max(12, ShellState.islandTopMargin * 3));
            if (ShellState.islandStyle === "bar")
                return Math.max(320, Math.round(root.width) - ShellState.islandTopMargin * 2);
            return Math.max(128, Math.min(Math.round(root.width) - 32, Math.round(collapsedPill.implicitWidth) + 28));
        }
        if (root.islandState === "osd")
            return 340;
        if (root.islandState === "notification")
            return 436;
        return root.expandedWidth;
    }

    readonly property int targetHeight: {
        if (root.islandState === "collapsed") {
            if (root.isSplitBar)
                return ShellState.pillHeight;
            return ShellState.pillHeight + root.notchPad;
        }
        if (root.islandState === "osd")
            return 62 + root.notchPad;
        if (root.islandState === "notification")
            return Math.max(82, Math.min(156, Math.round(osdOverlay.notificationHeight) + 22)) + root.notchPad;
        return root.expandedHeight + root.notchPad;
    }

    readonly property int targetRadius: {
        if (Theme.isSimple)
            return 0;
        if (root.islandState === "collapsed") {
            if (root.isSplitBar)
                return 0;
            if (ShellState.islandStyle === "bar")
                return Math.round(Theme.r(12));
            return Math.round(Theme.r(Math.round(ShellState.pillHeight / 2) + 1));
        }
        if (root.islandState === "osd" || root.islandState === "notification")
            return Math.round(Theme.r(26));
        return Math.round(Theme.r(30));
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

        color: root.splitCollapsed
            ? "transparent"
            : (root.islandState === "collapsed" ? Theme.m3BarBg : Theme.m3PanelBg)
        border.width: root.splitCollapsed ? 0 : Math.max(1, Theme.islandBorderWidth)
        border.color: root.splitCollapsed ? "transparent" : Theme.islandBorder

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
            visible: Theme.showGlassSheen && !root.splitCollapsed
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
            visible: Theme.showNeonAccentBar && !root.splitCollapsed
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
            visible: Theme.showRetroStripe && !root.splitCollapsed
            color: Theme.primary
        }

        // Obsidian OLED top hairline rim
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            visible: Theme.showOledRim && !root.splitCollapsed
            color: Theme.withAlpha(Theme.primary, 0.35)
        }

        // Subtle Apple Inner Edge Rim (keeps pill/expanded silhouette crisp even with borderStyle: "none")
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.09)
            visible: !Theme.isSimple && !root.splitCollapsed && Theme.islandBorderWidth === 0
            z: 5
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
            enabled: !Theme.isSimple && !root.splitCollapsed && root.islandState === "collapsed"
            onClicked: root.expandTo("overview", false)
        }

        // 1. Collapsed Compact Pill / Split Islands / Modular Bar
        CollapsedPill {
            id: collapsedPill
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(root.notchPad / 2)
            width: (root.isSplitBar || ShellState.islandStyle === "bar")
                ? Math.max(0, parent.width - (root.isSplitBar ? 0 : 24))
                : implicitWidth
            screenName: root.screenName
            active: !Theme.isSimple && root.islandState === "collapsed"
            barMode: root.isSplitBar || ShellState.islandStyle === "bar"
            barUiStyle: ShellState.barUiStyle
            player: root.activePlayer
            opacity: (!Theme.isSimple && root.islandState === "collapsed") ? 1.0 : 0.0
            visible: opacity > 0.01

            onExpandRequested: root.expandTo("overview", true)
            onLauncherClicked: root.toggleLauncher()
            onSettingsClicked: root.openSettingsRequested("island")
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

        // 3. Expanded Interactive Dashboard Hub (lazy URL-loaded on demand, kept warm 90s after close)
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
            interval: 90000
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
            source: "ExpandedDashboard.qml"

            onLoaded: {
                if (!item)
                    return;
                item.isOpen = Qt.binding(() => root.islandState === "expanded");
                item.screenName = Qt.binding(() => root.screenName);
                item.activeTab = Qt.binding(() => root.activeTab);
                item.launcherMode = Qt.binding(() => root.launcherMode);
                item.pinnedOpen = Qt.binding(() => root.pinnedOpen);
                item.powerMenuOpen = Qt.binding(() => root.powerMenuOpen);
                item.player = Qt.binding(() => root.activePlayer);
                item.opacity = Qt.binding(() => root.islandState === "expanded" ? 1.0 : 0.0);
                item.visible = Qt.binding(() => item.opacity > 0.01);

                item.tabSelected.connect(tab => {
                    root.activeTab = tab;
                    if (tab === "launcher")
                        root.pinnedOpen = true;
                });
                item.togglePinRequested.connect(() => { root.pinnedOpen = !root.pinnedOpen; });
                item.togglePowerMenuRequested.connect(() => { root.powerMenuOpen = !root.powerMenuOpen; });
                item.openSettingsRequested.connect(page => root.openSettingsRequested(page));
                item.openFilesRequested.connect(path => root.openFilesRequested(path));
                item.openKeybindsRequested.connect(() => root.openKeybindsRequested());
                item.openCaptureHubRequested.connect(() => root.openCaptureHubRequested());
                item.openStoreRequested.connect(() => root.openStoreRequested());
                item.closeRequested.connect(() => root.collapse());
                item.searchFocusChanged.connect(focused => { root.launcherSearchFocused = focused; });
                item.controlInteractionChanged.connect(interacting => {
                    root.interactiveControlActive = interacting;
                    if (!interacting && !hoverHandler.hovered && !root.pinnedOpen
                        && root.islandState === "expanded" && root.activeTab !== "launcher") {
                        hoverCollapseTimer.restart();
                    }
                });
            }
        }
    }
}
