pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../m3"

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

    // ==================== 1. TOP-RIGHT M3 CONTROL CENTER DRAWER ====================
    Rectangle {
        id: controlsCard
        visible: root.panelMode === "controls"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: parent.right
        anchors.rightMargin: 12
        readonly property int targetControlsWidth: root.controlsTab === "files"
            ? 680
            : (root.controlsTab === "themes" ? 560 : 456)
        readonly property int maxDrawerH: Math.max(260, root.height - root.topBarOffset - 22)
        readonly property int tabViewportH: Math.min(500, Math.max(280, root.height - root.topBarOffset - 96))
        width: Math.min(Math.max(360, root.width - 24), targetControlsWidth)
        height: Math.min(maxDrawerH, controlsCol.implicitHeight + 28)
        radius: Theme.r(32)
        color: Theme.m3PanelBg
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.95)
        transformOrigin: Item.TopRight

        Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 200; easing.type: Theme.m3Springy } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: controlsCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                    color: sqClsMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                    Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.m3Ink }
                    MouseArea { id: sqClsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    id: ccSegRow
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "controls", label: "Controls" },
                            { id: "overview", label: "Overview" },
                            { id: "themes",   label: "Themes" },
                            { id: "files",    label: "Files" }
                        ]

                        delegate: Rectangle {
                            id: segBtn
                            required property var modelData
                            readonly property bool selected: root.controlsTab === segBtn.modelData.id

                            implicitHeight: 34
                            implicitWidth: segTxt.implicitWidth + 18
                            radius: Theme.r(17)
                            color: segBtn.selected
                                ? Theme.m3Primary
                                : (segMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC)

                            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 160 } }

                            Text {
                                id: segTxt
                                anchors.centerIn: parent
                                text: segBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Medium
                                color: segBtn.selected ? Theme.m3OnPrimary : Theme.m3Ink
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

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                    color: ccSetMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                    Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.m3Ink }
                    MouseArea { id: ccSetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); root.openSettingsRequested("sequoia"); } }
                }

                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                    color: root.powerMenuOpen ? Theme.m3ErrorContainer : (ccPwrMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC)
                    Text { anchors.centerIn: parent; text: "󰐥"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: root.powerMenuOpen ? Theme.m3OnErrorContainer : Theme.m3Error }
                    MouseArea { id: ccPwrMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePowerMenuRequested() }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: active ? 40 : 0
                active: root.powerMenuOpen
                visible: active
                source: "PowerMenu.qml"
                onLoaded: {
                    if (item)
                        item.actionTriggered.connect(root.closeRequested);
                }
            }

            Flickable {
                visible: root.controlsTab === "controls"
                Layout.fillWidth: true
                Layout.preferredHeight: visible
                    ? Math.min(controlsInnerCol.implicitHeight, Math.max(200, controlsCard.maxDrawerH - (root.powerMenuOpen ? 124 : 76)))
                    : 0
                contentWidth: width
                contentHeight: controlsInnerCol.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: controlsInnerCol
                    width: parent.width
                    spacing: 10

                    Loader {
                        id: qcLoader
                        Layout.fillWidth: true
                        readonly property int qcH: 250
                            + (DeviceCaps.hasBacklight ? 56 : 0)
                            + ((DeviceCaps.hasWifi || DeviceCaps.hasBluetooth) ? 72 : 0)
                        readonly property bool showQc: root.panelMode === "controls" && root.controlsTab === "controls"
                        Layout.preferredHeight: showQc ? (item ? Math.max(120, Math.ceil(item.implicitHeight)) : qcH) : 0
                        active: root._controlsMainLoaded
                        visible: showQc
                        source: "QuickControls.qml"
                        onLoaded: {
                            if (item) {
                                item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                                item.hideHeader = true;
                                item.hideStyleFooter = true;
                                item.hideDuplicateToggles = true;
                                item.tallActionTiles = true;
                                item.openSettingsRequested.connect(page => {
                                    root.closeRequested();
                                    root.openSettingsRequested(page);
                                });
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        readonly property bool showMedia: root.panelMode === "controls"
                            && root.controlsTab === "controls"
                            && (ShellState.sequoiaHubStyle === "controlcenter" || ShellState.sequoiaHubStyle === "media")
                        Layout.preferredHeight: showMedia ? (item ? Math.max(158, Math.ceil(item.implicitHeight)) : 162) : 0
                        active: root._controlsMainLoaded
                        visible: showMedia
                        source: "MediaCard.qml"
                        onLoaded: {
                            if (item) {
                                item.player = Qt.binding(() => root.player);
                                item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                            }
                        }
                    }

                    // Spaces + Store Strip
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Theme.r(21)
                        color: Theme.m3SurfaceC
                        border.width: 1
                        border.color: Theme.m3Line

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Repeater {
                                    model: MangoState.tagsForScreen(root.screenName)

                                    delegate: Rectangle {
                                        id: spTag
                                        required property var modelData
                                        readonly property bool isActive: spTag.modelData.is_active
                                        readonly property bool isUrgent: spTag.modelData.is_urgent
                                        readonly property bool isOccupied: spTag.modelData.client_count > 0

                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        radius: Theme.r(spTag.isActive ? 13 : 9)
                                        color: {
                                            if (spTag.isUrgent) return Theme.m3Error;
                                            if (spTag.isActive) return Theme.m3Primary;
                                            if (spTagMouse.containsMouse) return Theme.m3SurfaceHighest;
                                            return spTag.isOccupied ? Theme.m3SecondaryContainer : "transparent";
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: spTag.modelData.index
                                            font.family: Theme.monoFont
                                            font.pixelSize: Theme.fs(10)
                                            font.weight: spTag.isActive ? Font.Bold : Font.Medium
                                            color: spTag.isUrgent ? Theme.m3OnErrorContainer : (spTag.isActive ? Theme.m3OnPrimary : (spTag.isOccupied ? Theme.m3OnSecondaryContainer : Theme.m3InkDim))
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
                                implicitWidth: 28; implicitHeight: 28; radius: Theme.r(14)
                                color: ccStM.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer
                                Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.m3OnSecondaryContainer }
                                MouseArea { id: ccStM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); root.openStoreRequested(); } }
                            }
                        }
                    }
                }
            }

            Flickable {
                visible: root.controlsTab === "overview"
                Layout.fillWidth: true
                Layout.preferredHeight: visible
                    ? Math.min(seqOverviewTab.implicitHeight, Math.max(200, controlsCard.maxDrawerH - (root.powerMenuOpen ? 124 : 76)))
                    : 0
                contentWidth: width
                contentHeight: seqOverviewTab.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                M3OverviewTab {
                    id: seqOverviewTab
                    width: parent.width
                    active: root.isOpen && root.panelMode === "controls" && root.controlsTab === "overview"
                }
            }

            // Sub-Tab 2: Theme & Wallpaper Switcher (sticky warm loader)
            Loader {
                Layout.fillWidth: true
                readonly property bool showThemes: root.panelMode === "controls" && root.controlsTab === "themes"
                Layout.preferredHeight: showThemes ? controlsCard.tabViewportH : 0
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
                Layout.preferredHeight: showFiles ? controlsCard.tabViewportH : 0
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
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: parent.right
        anchors.rightMargin: 12
        width: Math.min(720, Math.max(360, root.width - 24))
        height: Math.min(548, Math.max(320, root.height - root.topBarOffset - 24))
        radius: Theme.r(32)
        color: Theme.m3PanelBg
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.95)
        transformOrigin: Item.TopRight

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 190; easing.type: Theme.m3Springy } }

        MouseArea { anchors.fill: parent }

        Loader {
            anchors.fill: parent
            anchors.margins: 14
            active: root._notifsPanelLoaded
            visible: root.panelMode === "notifications"
            source: "NotificationsTab.qml"
            onLoaded: {
                if (item)
                    item.active = Qt.binding(() => root.isOpen && root.panelMode === "notifications");
            }
        }
    }

    // ==================== 3. CENTERED FLOATING M3 LAUNCHER ====================
    Rectangle {
        visible: root.panelMode === "launcher"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(52, root.topBarOffset + 28)
        width: Math.min(780, Math.max(460, root.width - 48))
        height: Math.min(580, Math.max(380, root.height - root.topBarOffset - 56))
        radius: Theme.r(34)
        color: Theme.m3PanelBg
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.95)

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 190; easing.type: Theme.m3Springy } }

        MouseArea { anchors.fill: parent }

        Loader {
            anchors.fill: parent
            anchors.margins: 14
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
        width: root.panelMode === "notification" ? 420 : 320
        height: root.panelMode === "notification"
            ? Math.max(82, Math.min(164, Math.round(osdOverlay.notificationHeight) + 24))
            : 60

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
            radius: Theme.r(28)
            color: Theme.m3PanelBg
            border.width: 1
            border.color: (root.panelMode === "notification" && osdOverlay.isUrgent) ? Theme.m3Error : Theme.m3Line
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
