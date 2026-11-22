import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import ".."

Item {
    id: root

    // --- Public API & Window Integration ---
    readonly property alias maskTarget: islandContainer
    property string screenName: ""
    property string islandState: "collapsed"    // "collapsed" | "osd" | "notification" | "expanded"
    property string activeTab: "overview"       // "overview" | "themes" | "launcher"
    property bool pinnedOpen: false
    property bool powerMenuOpen: false
    property bool launcherSearchFocused: false
    property bool interactiveControlActive: false

    signal openSettingsRequested(string page)

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
        toggleTab("launcher");
    }

    function toggleThemeTab(): void {
        toggleTab("themes");
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
            ? Math.max(2500, Math.min(10000, notif.expireTimeout))
            : 4500;
        notifHideTimer.interval = timeoutMs;
        if (!hoverHandler.hovered)
            notifHideTimer.restart();
    }

    // --- Target Geometry per State ---
    readonly property int expandedWidth: {
        if (root.activeTab === "launcher")
            return 620;
        if (root.activeTab === "themes")
            return 690;
        return 670;
    }

    readonly property int expandedHeight: {
        let h = 400;
        if (root.activeTab === "launcher")
            h = 456;
        else if (root.activeTab === "themes")
            h = 440;
        else
            h = DeviceCaps.hasExtraQuickControls ? 444 : 400;
        return h + (root.powerMenuOpen ? 46 : 0);
    }

    readonly property int targetWidth: {
        if (root.islandState === "collapsed")
            return Math.max(114, Math.min(430, Math.round(collapsedPill.implicitWidth) + 32));
        if (root.islandState === "osd")
            return 320;
        if (root.islandState === "notification")
            return 420;
        return root.expandedWidth;
    }

    readonly property int targetHeight: {
        if (root.islandState === "collapsed")
            return 34;
        if (root.islandState === "osd")
            return 56;
        if (root.islandState === "notification")
            return Math.max(78, Math.min(148, Math.round(osdOverlay.notificationHeight) + 20));
        return root.expandedHeight;
    }

    readonly property int targetRadius: {
        if (Theme.isSimple)
            return 0;
        if (root.islandState === "collapsed")
            return 17;
        if (root.islandState === "osd")
            return 24;
        if (root.islandState === "notification")
            return 24;
        return 26;
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
        interval: 100
        repeat: false
        onTriggered: {
            if (!Theme.isSimple && hoverHandler.hovered && (root.islandState === "collapsed" || root.islandState === "osd")) {
                root.expandTo("overview", false);
            }
        }
    }

    Timer {
        id: hoverCollapseTimer
        interval: 280
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
        interval: 1800
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
        anchors.topMargin: Theme.isSimple ? 32 : 6
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
            enabled: !Theme.isSimple
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 0.42
            }
        }
        Behavior on height {
            enabled: !Theme.isSimple
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 0.42
            }
        }
        Behavior on radius {
            enabled: !Theme.isSimple
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        // Subtle glass specular top sheen in Blur Mode
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(parent.height, 44)
            radius: parent.radius
            visible: Theme.isBlur
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.35) }
                GradientStop { position: 1.0; color: "transparent" }
            }
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
                    if (!Theme.isSimple && (root.islandState === "collapsed" || root.islandState === "osd")) {
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

        // Click on collapsed pill to expand immediately
        TapHandler {
            enabled: !Theme.isSimple && root.islandState === "collapsed"
            onTapped: root.expandTo("overview", false)
        }

        // 1. Collapsed Compact Pill View (Default & Blur modes only)
        CollapsedPill {
            id: collapsedPill
            anchors.centerIn: parent
            player: root.activePlayer
            opacity: (!Theme.isSimple && root.islandState === "collapsed") ? 1.0 : 0.0
            visible: opacity > 0.01

            Behavior on opacity {
                enabled: !Theme.isSimple
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
        }

        // 2. Morphing OSD & Notification View
        OsdOverlay {
            id: osdOverlay
            anchors.fill: parent
            anchors.margins: 10
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
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        // 3. Expanded Interactive Dashboard Hub (lazy-loaded on demand, unloaded after collapse)
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
            interval: 400
            repeat: false
            onTriggered: {
                if (root.islandState !== "expanded") {
                    islandContainer._expandedLoaded = false;
                    gc();
                }
            }
        }

        Loader {
            id: expandedLoader
            anchors.top: parent.top
            anchors.topMargin: 14
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
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
