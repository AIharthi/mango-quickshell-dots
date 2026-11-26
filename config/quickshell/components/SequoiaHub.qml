pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property bool isOpen: false
    property string panelMode: "controls"       // "controls" | "notifications" | "launcher" | "osd" | "notification"
    property string launcherMode: "apps"
    property string controlsTab: "controls"     // "controls" | "themes" | "files"
    property bool powerMenuOpen: false
    property string screenName: ""
    property var player: null

    property string osdType: "volume"
    property int osdTriggerSeq: 0
    property var pendingNotif: null
    property int notifTriggerSeq: 0

    signal closeRequested()
    signal openSettingsRequested(string page)
    signal openFilesRequested(string path)
    signal openKeybindsRequested()
    signal openCaptureHubRequested()
    signal openStoreRequested()
    signal switchControlsTab(string tab)
    signal togglePowerMenuRequested()

    property bool _entered: false
    property bool _closing: false
    readonly property bool shown: root.isOpen && root._entered
    readonly property bool isPassive: root.panelMode === "osd" || root.panelMode === "notification"
    readonly property int topBarOffset: ShellState.sequoiaBarHeight + (ShellState.sequoiaBarFloating ? 8 : 0)

    // Keep visited sub-views warm while SequoiaHub is loaded (0ms panel/tab switches)
    property bool _controlsMainLoaded: root.panelMode === "controls" && root.controlsTab === "controls"
    property bool _themesTabLoaded: root.panelMode === "controls" && root.controlsTab === "themes"
    property bool _filesTabLoaded: root.panelMode === "controls" && root.controlsTab === "files"
    property bool _notifsPanelLoaded: root.panelMode === "notifications"
    property bool _launcherPanelLoaded: root.panelMode === "launcher"

    function _syncWarmPanels(): void {
        if (root.panelMode === "controls") {
            if (root.controlsTab === "controls") root._controlsMainLoaded = true;
            else if (root.controlsTab === "themes") root._themesTabLoaded = true;
            else if (root.controlsTab === "files") root._filesTabLoaded = true;
        } else if (root.panelMode === "notifications") {
            root._notifsPanelLoaded = true;
        } else if (root.panelMode === "launcher") {
            root._launcherPanelLoaded = true;
        }
    }

    Timer {
        id: hideWinTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (!root.isOpen)
                root._closing = false;
        }
    }

    Timer {
        id: osdHideTimer
        interval: Math.max(400, ShellState.osdTimeoutMs)
        repeat: false
        onTriggered: {
            if (root.isOpen && root.panelMode === "osd")
                root.closeRequested();
        }
    }

    Timer {
        id: notifHideTimer
        interval: Math.max(1500, ShellState.notifTimeoutMs)
        repeat: false
        onTriggered: {
            if (root.isOpen && root.panelMode === "notification" && !toastHover.hovered)
                root.closeRequested();
        }
    }

    function _armPassiveTimer(): void {
        if (root.panelMode === "osd") {
            notifHideTimer.stop();
            osdHideTimer.interval = Math.max(400, ShellState.osdTimeoutMs);
            osdHideTimer.restart();
        } else if (root.panelMode === "notification") {
            osdHideTimer.stop();
            const expire = (root.pendingNotif && root.pendingNotif.expireTimeout > 0)
                ? Math.max(1500, Math.min(15000, root.pendingNotif.expireTimeout))
                : Math.max(1500, ShellState.notifTimeoutMs);
            notifHideTimer.interval = expire;
            if (!toastHover.hovered)
                notifHideTimer.restart();
        } else {
            osdHideTimer.stop();
            notifHideTimer.stop();
        }
    }

    readonly property bool _needsTags: root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls"
    property bool _countedConsumer: false

    function _syncConsumer(): void {
        if (root._needsTags && !root._countedConsumer) {
            root._countedConsumer = true;
            MangoState.hubConsumers += 1;
        } else if (!root._needsTags && root._countedConsumer) {
            root._countedConsumer = false;
            MangoState.hubConsumers = Math.max(0, MangoState.hubConsumers - 1);
        }
    }

    on_NeedsTagsChanged: _syncConsumer()
    onControlsTabChanged: _syncWarmPanels()
    onIsOpenChanged: {
        if (root.isOpen) {
            hideWinTimer.stop();
            root._closing = false;
            _syncWarmPanels();
            _armPassiveTimer();
            if (!root._entered)
                Qt.callLater(() => { root._entered = true; });
        } else {
            osdHideTimer.stop();
            notifHideTimer.stop();
            if (!Theme.reducedMotion) {
                root._closing = true;
                hideWinTimer.restart();
            } else {
                root._closing = false;
            }
        }
    }
    Component.onDestruction: {
        if (root._countedConsumer) {
            root._countedConsumer = false;
            MangoState.hubConsumers = Math.max(0, MangoState.hubConsumers - 1);
        }
    }

    function triggerOsd(kind: string): void {
        if (root.panelMode === "controls" && root.isOpen)
            return;
        osdOverlay.showOsd(kind || "volume");
        _armPassiveTimer();
    }

    function refreshOsdValue(kind: string): void {
        osdOverlay.refreshOsdValue(kind || "volume");
    }

    function showNotification(notif: var): void {
        if (!notif)
            return;
        osdOverlay.showNotification(notif);
        _armPassiveTimer();
    }

    onOsdTriggerSeqChanged: {
        if (root.panelMode === "osd" || root.isOpen) {
            osdOverlay.showOsd(root.osdType);
            _armPassiveTimer();
        }
    }

    onNotifTriggerSeqChanged: {
        if (root.pendingNotif) {
            osdOverlay.showNotification(root.pendingNotif);
            _armPassiveTimer();
        }
    }

    onPanelModeChanged: {
        _syncWarmPanels();
        if (root.panelMode === "notifications")
            ShellState.clearUnread();
        if (!root.isPassive) {
            osdHideTimer.stop();
            notifHideTimer.stop();
        }
    }

    Component.onCompleted: {
        _syncConsumer();
        _syncWarmPanels();
        if (root.panelMode === "osd") {
            osdOverlay.showOsd(root.osdType);
            _armPassiveTimer();
        } else if (root.panelMode === "notification" && root.pendingNotif) {
            osdOverlay.showNotification(root.pendingNotif);
            _armPassiveTimer();
        }
        if (root.panelMode === "notifications")
            ShellState.clearUnread();
        Qt.callLater(() => { root._entered = true; });
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: root.isOpen || root._closing
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    WlrLayershell.layer: root.panelMode === "launcher" ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "quickshell-sequoia-hub"
    WlrLayershell.keyboardFocus: !root.isOpen || root.isPassive
        ? WlrKeyboardFocus.None
        : ((root.panelMode === "launcher" || root.panelMode === "notifications" || (root.panelMode === "controls" && root.controlsTab === "files"))
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.OnDemand)

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    mask: Region {
        item: !root.isOpen ? emptyMask : (root.isPassive ? toastContainer : backdropItem)
    }

    // Interactive click-outside backdrop below SequoiaBar (click-through immediately when closed)
    Item {
        id: backdropItem
        anchors {
            top: parent.top
            topMargin: root.topBarOffset
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        focus: root.isOpen && !root.isPassive

        Keys.onEscapePressed: root.closeRequested()

        MouseArea {
            anchors.fill: parent
            enabled: root.isOpen && !root.isPassive
            onClicked: root.closeRequested()
        }
    }

    // ==================== 1. TOP-RIGHT CONTROL CENTER POPOVER ====================
    Rectangle {
        id: controlsCard
        visible: root.panelMode === "controls"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 6
        anchors.right: parent.right
        anchors.rightMargin: 10
        width: 392
        height: Math.min(Math.max(200, root.height - root.topBarOffset - 24), controlsCol.implicitHeight + 24)
        radius: Theme.r(20)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)
        transformOrigin: Item.TopRight

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        // Eat inside clicks so backdrop does not dismiss popover
        MouseArea { anchors.fill: parent }

        // Top glass specular sheen when frosted mode is active
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 44
            radius: parent.radius
            visible: Theme.showGlassSheen
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.36) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        ColumnLayout {
            id: controlsCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 10

            // Header: Segmented Tab Pill + Utility Actions
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    implicitHeight: 30
                    implicitWidth: ccSegRow.implicitWidth + 6
                    radius: Theme.r(15)
                    color: Theme.cardBg
                    border.width: Theme.activeControlBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        id: ccSegRow
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: [
                                { id: "controls", icon: "󰕰", label: "Controls" },
                                { id: "themes",   icon: "󰏘", label: "Themes" },
                                { id: "files",    icon: "󰉋", label: "Files" }
                            ]

                            delegate: Rectangle {
                                id: segBtn
                                required property var modelData
                                readonly property bool selected: root.controlsTab === segBtn.modelData.id

                                implicitHeight: 24
                                implicitWidth: segContent.implicitWidth + 12
                                radius: Theme.r(12)
                                color: segBtn.selected
                                    ? Theme.primary
                                    : (segMouse.containsMouse ? Theme.hoverBg : "transparent")

                                RowLayout {
                                    id: segContent
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text { text: segBtn.modelData.icon; font.family: Theme.iconFont; font.pixelSize: 11; color: segBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant }
                                    Text { text: segBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: segBtn.selected ? Font.Bold : Font.Medium; color: segBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant }
                                }

                                MouseArea {
                                    id: segMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.switchControlsTab(segBtn.modelData.id)
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Cycle Sequoia Hub Style (LMB cycle, RMB -> Sequoia Settings)
                Rectangle {
                    visible: root.controlsTab === "controls"
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: ccLayMouse.containsMouse ? Theme.controlFillHover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (ShellState.sequoiaHubStyle === "media") return "󰓇";
                            if (ShellState.sequoiaHubStyle === "compact") return "󰘔";
                            return "󰕰";
                        }
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                        color: ccLayMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: ccLayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                Qt.callLater(() => root.openSettingsRequested("sequoia"));
                            else
                                ShellState.cycleSequoiaHubStyle();
                        }
                    }
                }

                // Store Shortcut
                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: ccStoreMouse.containsMouse ? Theme.controlFillHover : "transparent"
                    Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: 12; color: ccStoreMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    MouseArea { id: ccStoreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); root.openStoreRequested(); } }
                }

                // Sequoia Settings Shortcut
                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: ccSetMouse.containsMouse ? Theme.controlFillHover : "transparent"
                    Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: 12; color: ccSetMouse.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant }
                    MouseArea { id: ccSetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); root.openSettingsRequested("sequoia"); } }
                }

                // Power Strip Toggle
                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(13)
                    color: root.powerMenuOpen ? Theme.error : (ccPwrMouse.containsMouse ? Theme.controlFillHover : "transparent")
                    Text { anchors.centerIn: parent; text: "󰐥"; font.family: Theme.iconFont; font.pixelSize: 12; color: root.powerMenuOpen ? Theme.fgError : (ccPwrMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant) }
                    MouseArea { id: ccPwrMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePowerMenuRequested() }
                }
            }

            // Collapsible Power Menu
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: active ? 36 : 0
                active: root.powerMenuOpen
                visible: active
                source: "PowerMenu.qml"
                onLoaded: {
                    if (item)
                        item.actionTriggered.connect(root.closeRequested);
                }
            }

            // Sub-Tab 1: Sequoia Control Center / Compact Stack / Studio Platter
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.controlsTab === "controls"
                spacing: 8

                // 2x2 Connectivity & Focus Platter (Control Center style)
                Rectangle {
                    visible: ShellState.sequoiaHubStyle === "controlcenter"
                    Layout.fillWidth: true
                    implicitHeight: 112
                    radius: Theme.r(16)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    GridLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: [
                                { id: "sink",  icon: "󰋋", title: "Output",     sub: MangoState.defaultSinkLabel, active: !MangoState.volMuted, tint: Theme.primary },
                                { id: "dnd",   icon: ShellState.dnd ? "󰂛" : "󰂚", title: "Focus", sub: ShellState.dnd ? "DND Active" : "Alerts On", active: ShellState.dnd, tint: Theme.secondary },
                                { id: "awake", icon: "󰅶", title: "Keep Awake", sub: ShellState.keepAwake ? "Idle Paused" : "Auto-Lock On", active: ShellState.keepAwake, tint: Theme.warning },
                                { id: "game",  icon: "󰊴", title: "Game Mode",  sub: ShellState.gameModeActive ? "Boost Active" : "Standard", active: ShellState.gameModeActive, tint: Theme.tertiary }
                            ]

                            delegate: Rectangle {
                                id: sqTile
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.r(11)
                                color: sqTile.modelData.active
                                    ? Theme.tileActiveBg
                                    : (sqTileMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                                border.width: sqTile.modelData.active ? Theme.activeControlBorderWidth : 0
                                border.color: sqTile.modelData.tint

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 7

                                    Rectangle {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        radius: Theme.r(14)
                                        color: sqTile.modelData.active ? sqTile.modelData.tint : Theme.surfaceContainerHighest

                                        Text {
                                            anchors.centerIn: parent
                                            text: sqTile.modelData.icon
                                            font.family: Theme.iconFont
                                            font.pixelSize: 13
                                            color: sqTile.modelData.active ? Theme.contrastInk(sqTile.modelData.tint) : Theme.fgSurfaceVariant
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: sqTile.modelData.title; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: sqTile.modelData.active ? Font.Bold : Font.DemiBold; color: Theme.fgSurface }
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: sqTile.modelData.sub; font.family: Theme.fontFamily; font.pixelSize: 8; color: Theme.fgSurfaceVariant }
                                    }
                                }

                                MouseArea {
                                    id: sqTileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const cid = sqTile.modelData.id;
                                        if (cid === "sink") {
                                            if (mouse.button === Qt.RightButton) {
                                                Qt.callLater(() => {
                                                    root.closeRequested();
                                                    root.openSettingsRequested("audio");
                                                });
                                            } else {
                                                MangoState.cycleAudioSink();
                                            }
                                        } else if (cid === "dnd") {
                                            ShellState.toggleDnd();
                                        } else if (cid === "awake") {
                                            ShellState.toggleKeepAwake();
                                        } else if (cid === "game") {
                                            ShellState.toggleGameMode();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Compact Quick Toggles Row (Compact Stack style)
                RowLayout {
                    visible: ShellState.sequoiaHubStyle === "compact"
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "dnd",   icon: ShellState.dnd ? "󰂛" : "󰂚", label: "Focus", active: ShellState.dnd, tint: Theme.secondary },
                            { id: "awake", icon: "󰅶", label: "Awake", active: ShellState.keepAwake, tint: Theme.warning },
                            { id: "shot",  icon: "󰹑", label: "Capture", active: false, tint: Theme.primary },
                            { id: "game",  icon: "󰊴", label: "Game", active: ShellState.gameModeActive, tint: Theme.tertiary }
                        ]

                        delegate: Rectangle {
                            id: cmpAct
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 42
                            radius: Theme.r(11)
                            color: cmpAct.modelData.active ? Theme.tileActiveBg : (cmpActMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)
                            border.width: cmpAct.modelData.active ? Theme.activeControlBorderWidth : Theme.cardBorderWidth
                            border.color: cmpAct.modelData.active ? cmpAct.modelData.tint : Theme.cardBorder

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { Layout.alignment: Qt.AlignHCenter; text: cmpAct.modelData.icon; font.family: Theme.iconFont; font.pixelSize: 13; color: cmpAct.modelData.active ? cmpAct.modelData.tint : Theme.fgSurfaceVariant }
                                Text { Layout.alignment: Qt.AlignHCenter; text: cmpAct.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: cmpAct.modelData.active ? Font.Bold : Font.Medium; color: Theme.fgSurface }
                            }

                            MouseArea {
                                id: cmpActMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const id = cmpAct.modelData.id;
                                    if (id === "dnd") ShellState.toggleDnd();
                                    else if (id === "awake") ShellState.toggleKeepAwake();
                                    else if (id === "shot") Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--area"]);
                                    else if (id === "game") ShellState.toggleGameMode();
                                }
                            }
                        }
                    }
                }

                // Studio Media Card + Output Switcher (Media Studio style)
                Loader {
                    Layout.fillWidth: true
                    readonly property int cardH: ShellState.sequoiaHubStyle === "media" ? 168 : 134
                    readonly property bool showCard: root.panelMode === "controls" && root.controlsTab === "controls" && ShellState.sequoiaHubStyle === "media"
                    Layout.preferredHeight: showCard ? cardH : 0
                    active: root._controlsMainLoaded && ShellState.sequoiaHubStyle === "media"
                    visible: showCard
                    source: "MediaCard.qml"
                    onLoaded: {
                        if (item) {
                            item.player = Qt.binding(() => root.player);
                            item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                        }
                    }
                }

                Rectangle {
                    visible: ShellState.sequoiaHubStyle === "media"
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(10)
                    color: seqSinkMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 6
                        Text { text: "󰋋"; font.family: Theme.iconFont; font.pixelSize: 12; color: Theme.primary }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: MangoState.defaultSinkLabel; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.fgSurface }
                        Text { text: "Cycle"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                    }

                    MouseArea {
                        id: seqSinkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                Qt.callLater(() => {
                                    root.closeRequested();
                                    root.openSettingsRequested("audio");
                                });
                            } else {
                                MangoState.cycleAudioSink();
                            }
                        }
                    }
                }

                // Sliders + Connectivity Deck (shared QuickControls tuned for Sequoia)
                Loader {
                    id: qcLoader
                    Layout.fillWidth: true
                    readonly property int qcH: (ShellState.sequoiaHubStyle === "compact" ? 104 : 114)
                        + (DeviceCaps.hasBacklight ? 36 : 0)
                        + ((DeviceCaps.hasWifi || DeviceCaps.hasBluetooth) ? 42 : 0)
                    readonly property bool showQc: root.panelMode === "controls" && root.controlsTab === "controls"
                    Layout.preferredHeight: showQc ? qcH : 0
                    active: root._controlsMainLoaded
                    visible: showQc
                    source: "QuickControls.qml"
                    onLoaded: {
                        if (item) {
                            item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                            item.hideHeader = true;
                            item.hideStyleFooter = true;
                            item.hideDuplicateToggles = true;
                            item.tallActionTiles = false;
                            item.openSettingsRequested.connect(page => {
                                root.closeRequested();
                                root.openSettingsRequested(page);
                            });
                        }
                    }
                }

                // Compact Media Strip (for Control Center & Compact Stack)
                Loader {
                    Layout.fillWidth: true
                    readonly property bool showCompactMedia: root.panelMode === "controls"
                        && root.controlsTab === "controls"
                        && ShellState.sequoiaHubStyle !== "media"
                        && (ShellState.sequoiaHubStyle === "controlcenter" || root.player !== null)
                    Layout.preferredHeight: showCompactMedia ? 132 : 0
                    active: root._controlsMainLoaded && ShellState.sequoiaHubStyle !== "media"
                    visible: showCompactMedia
                    source: "MediaCard.qml"
                    onLoaded: {
                        if (item) {
                            item.player = Qt.binding(() => root.player);
                            item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                        }
                    }
                }

                // Spaces Strip (1..9 + Layout + Window Switcher)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Theme.r(14)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 7
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Repeater {
                                model: MangoState.tagsForScreen(root.screenName)

                                delegate: Rectangle {
                                    id: spTag
                                    required property var modelData
                                    readonly property bool isActive: spTag.modelData.is_active
                                    readonly property bool isUrgent: spTag.modelData.is_urgent
                                    readonly property bool isOccupied: spTag.modelData.client_count > 0

                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(8)
                                    color: {
                                        if (spTag.isUrgent) return Theme.error;
                                        if (spTag.isActive) return Theme.primary;
                                        if (spTagMouse.containsMouse) return Theme.tileActiveBg;
                                        if (spTag.isOccupied) return Theme.controlFillHover;
                                        return "transparent";
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: spTag.modelData.index
                                        font.family: Theme.monoFont
                                        font.pixelSize: 10
                                        font.weight: spTag.isActive ? Font.Bold : Font.Medium
                                        color: spTag.isUrgent ? Theme.fgError : (spTag.isActive ? Theme.fgPrimary : (spTag.isOccupied ? Theme.fgSurface : Theme.fgSurfaceVariant))
                                    }

                                    MouseArea {
                                        id: spTagMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + spTag.modelData.index + ",0"])
                                    }
                                }
                            }
                        }

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: Math.max(24, sqLayTxt.implicitWidth + 10)
                            radius: Theme.r(8)
                            color: sqLayMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg

                            Text {
                                id: sqLayTxt
                                anchors.centerIn: parent
                                text: MangoState.layoutForScreen(root.screenName)
                                font.family: Theme.monoFont
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            MouseArea {
                                id: sqLayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"])
                            }
                        }
                    }
                }

                // Compact Telemetry Footer (Control Center & Studio Platter)
                Rectangle {
                    visible: ShellState.sequoiaHubStyle !== "compact"
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(10)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Text {
                            text: "CPU " + Math.round(SystemTelemetry.cpuPercent) + "%"
                                + (SystemTelemetry.cpuTempC > 0 ? (" · " + SystemTelemetry.cpuTempC + "°C") : "")
                            font.family: Theme.monoFont
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: SystemTelemetry.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "RAM " + SystemTelemetry.memUsedGb.toFixed(1) + "/" + SystemTelemetry.memTotalGb.toFixed(0) + "G"
                            font.family: Theme.monoFont
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: SystemTelemetry.memPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: DeviceCaps.hasBattery
                                ? ("BAT " + DeviceCaps.batteryPercent + "%")
                                : ("DISK " + Math.round(SystemTelemetry.diskPercent) + "%")
                            font.family: Theme.monoFont
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: DeviceCaps.hasBattery && DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant
                        }
                    }
                }
            }

            // Sub-Tab 2: Theme & Wallpaper Switcher (sticky warm loader)
            Loader {
                Layout.fillWidth: true
                readonly property bool showThemes: root.panelMode === "controls" && root.controlsTab === "themes"
                Layout.preferredHeight: showThemes ? 420 : 0
                active: root._themesTabLoaded
                visible: showThemes
                source: "ThemeSwitcher.qml"
                onLoaded: {
                    if (item) {
                        item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "themes");
                        item.openSettingsRequested.connect(page => {
                            root.closeRequested();
                            root.openSettingsRequested(page);
                        });
                    }
                }
            }

            // Sub-Tab 3: Quick Files Browser (sticky warm loader)
            Loader {
                Layout.fillWidth: true
                readonly property bool showFiles: root.panelMode === "controls" && root.controlsTab === "files"
                Layout.preferredHeight: showFiles ? 430 : 0
                active: root._filesTabLoaded
                visible: showFiles
                source: "../files/QuickFilesTab.qml"
                onLoaded: {
                    if (item) {
                        item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "files");
                        item.openFullManagerRequested.connect(path => {
                            root.closeRequested();
                            root.openFilesRequested(path);
                        });
                    }
                }
            }
        }
    }

    // ==================== 2. TOP-RIGHT NOTIFICATION & CALENDAR CENTER ====================
    Rectangle {
        visible: root.panelMode === "notifications"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 6
        anchors.right: parent.right
        anchors.rightMargin: 10
        width: 400
        height: Math.min(496, Math.max(320, root.height - root.topBarOffset - 24))
        radius: Theme.r(20)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)
        transformOrigin: Item.TopRight

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        Loader {
            anchors.fill: parent
            anchors.margins: 12
            active: root._notifsPanelLoaded
            visible: root.panelMode === "notifications"
            source: "NotificationsTab.qml"
            onLoaded: {
                if (item)
                    item.active = Qt.binding(() => root.isOpen && root.panelMode === "notifications");
            }
        }
    }

    // ==================== 3. CENTERED FLOATING SPOTLIGHT LAUNCHER ====================
    Rectangle {
        visible: root.panelMode === "launcher"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(56, root.topBarOffset + 36)
        width: Math.min(680, Math.max(420, root.width - 48))
        height: Math.min(476, Math.max(320, root.height - root.topBarOffset - 72))
        radius: Theme.r(22)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        Loader {
            anchors.fill: parent
            anchors.margins: 12
            active: root._launcherPanelLoaded
            visible: root.panelMode === "launcher"
            source: "AppLauncher.qml"
            onLoaded: {
                if (item) {
                    item.initialMode = Qt.binding(() => root.launcherMode);
                    item.active = Qt.binding(() => root.isOpen && root.panelMode === "launcher");
                    item.closeRequested.connect(root.closeRequested);
                    item.openSettingsRequested.connect(page => {
                        root.closeRequested();
                        root.openSettingsRequested(page);
                    });
                    item.openFilesRequested.connect(path => {
                        root.closeRequested();
                        root.openFilesRequested(path);
                    });
                    item.openKeybindsRequested.connect(() => {
                        root.closeRequested();
                        root.openKeybindsRequested();
                    });
                    item.openCaptureHubRequested.connect(() => {
                        root.closeRequested();
                        root.openCaptureHubRequested();
                    });
                    item.openStoreRequested.connect(() => {
                        root.closeRequested();
                        root.openStoreRequested();
                    });
                }
            }
        }
    }

    // ==================== 4. PASSIVE SEQUOIA TOAST NOTIFICATION & HUD OSD ====================
    Item {
        id: toastContainer
        visible: root.isPassive
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: root.panelMode === "notification" ? parent.right : undefined
        anchors.rightMargin: root.panelMode === "notification" ? 12 : 0
        anchors.horizontalCenter: root.panelMode === "osd" ? parent.horizontalCenter : undefined
        width: root.panelMode === "notification" ? 384 : 310
        height: root.panelMode === "notification"
            ? Math.max(76, Math.min(156, Math.round(osdOverlay.notificationHeight) + 22))
            : 58

        HoverHandler {
            id: toastHover
            onHoveredChanged: {
                if (hovered) {
                    notifHideTimer.stop();
                } else if (root.isOpen && root.panelMode === "notification") {
                    notifHideTimer.restart();
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.r(18)
            color: Theme.notchBg
            border.width: Math.max(1, Theme.islandBorderWidth)
            border.color: (root.panelMode === "notification" && osdOverlay.isUrgent) ? Theme.error : Theme.islandBorder
            clip: true

            opacity: root.shown ? 1.0 : 0.0
            Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            OsdOverlay {
                id: osdOverlay
                anchors.fill: parent
                anchors.margins: 10
                mode: root.panelMode === "notification" ? "notification" : "osd"
                active: root.isPassive && root.isOpen
                onDismissRequested: root.closeRequested()
            }
        }
    }
}
