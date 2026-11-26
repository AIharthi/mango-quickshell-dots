pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property bool isOpen: false
    property string panelMode: "controls"       // "left" | "center" | "controls" | "notifications" | "launcher" | "osd" | "notification"
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
    signal openNotificationsRequested()
    signal switchControlsTab(string tab)
    signal togglePowerMenuRequested()

    property bool _entered: false
    property bool _closing: false
    readonly property bool shown: root.isOpen && root._entered
    readonly property bool isPassive: root.panelMode === "osd" || root.panelMode === "notification"
    readonly property int topBarOffset: ShellState.splitTopMargin + ShellState.splitBarHeight

    // Sticky warm loaders for sub-views while SplitHub stays loaded (0ms switches)
    property bool _leftPanelLoaded: root.panelMode === "left"
    property bool _centerPanelLoaded: root.panelMode === "center"
    property bool _controlsMainLoaded: root.panelMode === "controls" && root.controlsTab === "controls"
    property bool _themesTabLoaded: root.panelMode === "controls" && root.controlsTab === "themes"
    property bool _filesTabLoaded: root.panelMode === "controls" && root.controlsTab === "files"
    property bool _notifsPanelLoaded: root.panelMode === "notifications"
    property bool _launcherPanelLoaded: root.panelMode === "launcher"

    function _syncWarmPanels(): void {
        if (root.panelMode === "left") {
            root._leftPanelLoaded = true;
        } else if (root.panelMode === "center") {
            root._centerPanelLoaded = true;
        } else if (root.panelMode === "controls") {
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

    readonly property bool _needsTags: root.isOpen && (
        root.panelMode === "left" || (root.panelMode === "controls" && root.controlsTab === "controls")
    )
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
    WlrLayershell.namespace: "quickshell-split-hub"
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

    // ==================== 1. LEFT POD POPOVER: SPACES & QUICK HUB ====================
    Rectangle {
        visible: root.panelMode === "left"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 6
        anchors.left: parent.left
        anchors.leftMargin: ShellState.splitSideMargin
        width: Math.min(356, Math.max(280, root.width - ShellState.splitSideMargin * 2))
        height: Math.min(Math.max(200, root.height - root.topBarOffset - 24), leftHubCol.implicitHeight + 24)
        radius: Theme.r(20)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)
        transformOrigin: Item.TopLeft

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: leftHubCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.primary }
                Text { Layout.fillWidth: true; text: "Spaces & Quick Hub"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.Bold; color: Theme.fgSurface }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: lhLayTxt.implicitWidth + 12
                    radius: Theme.r(8)
                    color: lhLayMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    Text { id: lhLayTxt; anchors.centerIn: parent; text: "Layout: " + MangoState.layoutForScreen(root.screenName); font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.primary }
                    MouseArea { id: lhLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
                }
            }

            // Focused Window Readout
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fwRow.implicitHeight + 12
                radius: Theme.r(12)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                RowLayout {
                    id: fwRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.primary }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: MangoState.activeAppName.length > 0 ? MangoState.activeAppName : "Desktop"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: MangoState.activeWindowTitle.length > 0 ? MangoState.activeWindowTitle : "No active window focused"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                    }
                }
            }

            // Interactive 3x3 Spaces Grid
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wsGrid.implicitHeight + 16
                radius: Theme.r(14)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                GridLayout {
                    id: wsGrid
                    anchors.fill: parent
                    anchors.margins: 8
                    columns: 3
                    rowSpacing: 6
                    columnSpacing: 6

                    Repeater {
                        model: MangoState.tagsForScreen(root.screenName)

                        delegate: Rectangle {
                            id: lgTag
                            required property var modelData
                            readonly property bool isActive: lgTag.modelData.is_active
                            readonly property bool isUrgent: lgTag.modelData.is_urgent
                            readonly property bool isOccupied: lgTag.modelData.client_count > 0

                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Theme.r(9)
                            color: {
                                if (lgTag.isUrgent) return Theme.error;
                                if (lgTag.isActive) return Theme.primary;
                                if (lgTagMouse.containsMouse) return Theme.hoverBg;
                                return Theme.subCardBg;
                            }
                            border.width: lgTag.isOccupied && !lgTag.isActive ? 1 : 0
                            border.color: Theme.withAlpha(Theme.primary, 0.45)

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "Space " + lgTag.modelData.index
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: lgTag.isActive ? Font.Bold : Font.DemiBold
                                    color: lgTag.isUrgent ? Theme.fgError : (lgTag.isActive ? Theme.fgPrimary : Theme.fgSurface)
                                }
                                Text {
                                    visible: lgTag.modelData.client_count > 0
                                    text: String(lgTag.modelData.client_count)
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fs(8)
                                    font.weight: Font.Bold
                                    color: lgTag.isActive ? Theme.fgPrimary : Theme.primary
                                }
                            }

                            MouseArea {
                                id: lgTagMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + lgTag.modelData.index + ",0"])
                            }
                        }
                    }
                }
            }

            // Quick Actions 2x3 Grid
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 6
                columnSpacing: 6

                Repeater {
                    model: [
                        { id: "launcher", icon: "󰍉", label: "Spotlight" },
                        { id: "windows",  icon: "󰖯", label: "Windows" },
                        { id: "files",    icon: "󰉋", label: "Files" },
                        { id: "store",    icon: "󰏖", label: "App Store" },
                        { id: "captures", icon: "󰹑", label: "Captures" },
                        { id: "debloat",  icon: "󰃢", label: "Debloater" }
                    ]

                    delegate: Rectangle {
                        id: qaTile
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: Theme.r(11)
                        color: qaMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                        border.width: Theme.cardBorderWidth
                        border.color: qaMouse.containsMouse ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: qaTile.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.primary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: qaTile.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.fgSurface }
                        }

                        MouseArea {
                            id: qaMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const aid = qaTile.modelData.id;
                                root.closeRequested();
                                if (aid === "launcher") Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleLauncher"]);
                                else if (aid === "windows") Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
                                else if (aid === "files") root.openFilesRequested("");
                                else if (aid === "store") root.openStoreRequested();
                                else if (aid === "captures") root.openCaptureHubRequested();
                                else if (aid === "debloat") root.openSettingsRequested("debloat");
                            }
                        }
                    }
                }
            }

            // Footer: Split Settings + Keybinds + Power
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: lfSetMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    Text { anchors.centerIn: parent; text: "󰒓 Split Settings"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: Theme.fgSurface }
                    MouseArea { id: lfSetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); root.openSettingsRequested("split"); } }
                }

                Rectangle {
                    implicitWidth: 32; implicitHeight: 30; radius: Theme.r(9)
                    color: lfKeyMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    Text { anchors.centerIn: parent; text: "󰌌"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
                    MouseArea { id: lfKeyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); root.openKeybindsRequested(); } }
                }

                Rectangle {
                    implicitWidth: 32; implicitHeight: 30; radius: Theme.r(9)
                    color: lfPwrMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.2) : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    Text { anchors.centerIn: parent; text: "󰐥"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.error }
                    MouseArea { id: lfPwrMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.closeRequested(); Quickshell.execDetached(["qs", "ipc", "call", "island", "togglePowerOverlay"]); } }
                }
            }
        }
    }

    // ==================== 2. CENTER POD POPOVER: MEDIA, FOCUS TIMER & AGENDA ====================
    Rectangle {
        visible: root.panelMode === "center"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(436, Math.max(340, root.width - ShellState.splitSideMargin * 2))
        height: Math.min(Math.max(220, root.height - root.topBarOffset - 24), centerHubCol.implicitHeight + 24)
        radius: Theme.r(20)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)
        transformOrigin: Item.Top

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: centerHubCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { text: "󰓇"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(14); color: Theme.primary }
                Text { Layout.fillWidth: true; text: "Media, Focus & Agenda"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.Bold; color: Theme.fgSurface }

                Rectangle {
                    implicitWidth: chAlTxt.implicitWidth + 14
                    implicitHeight: 24
                    radius: Theme.r(8)
                    color: chAlMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    Text { id: chAlTxt; anchors.centerIn: parent; text: "󰂚 Open Calendar"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.primary }
                    MouseArea { id: chAlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openNotificationsRequested() }
                }
            }

            // Now Playing Media Card
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: item ? Math.max(158, Math.ceil(item.implicitHeight)) : 162
                active: root._centerPanelLoaded
                visible: root.panelMode === "center"
                source: "MediaCard.qml"
                onLoaded: {
                    if (item) {
                        item.player = Qt.binding(() => root.player);
                        item.active = Qt.binding(() => root.isOpen && root.panelMode === "center");
                    }
                }
            }

            // Audio Output Device Switcher
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Theme.r(10)
                color: chSinkMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6
                    Text { text: "󰋋"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.primary }
                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: MangoState.defaultSinkLabel; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.DemiBold; color: Theme.fgSurface }
                    Text { text: "Click to cycle"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                }

                MouseArea {
                    id: chSinkMouse
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

            // Focus Timer & Stopwatch Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: ftCol.implicitHeight + 16
                radius: Theme.r(14)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                ColumnLayout {
                    id: ftCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text { text: "󰔛"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.primary }
                        Text { text: "Focus Timer"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }
                        Item { Layout.fillWidth: true }
                        Text { text: ShellState.formatTimer(ShellState.timerRemainingSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(13); font.weight: Font.Bold; color: ShellState.timerActive ? Theme.primary : Theme.fgSurface }

                        Rectangle {
                            implicitWidth: ftGoTxt.implicitWidth + 14
                            implicitHeight: 22
                            radius: Theme.r(7)
                            color: Theme.primary
                            Text { id: ftGoTxt; anchors.centerIn: parent; text: ShellState.timerActive ? "Pause" : "Start"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgPrimary }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleTimer() }
                        }

                        Repeater {
                            model: [5, 15, 25]
                            delegate: Rectangle {
                                id: ftMinChip
                                required property int modelData
                                implicitWidth: 28; implicitHeight: 22; radius: Theme.r(7)
                                color: ftMinMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                                border.width: Theme.subBorderWidth; border.color: Theme.cardBorder
                                Text { anchors.centerIn: parent; text: ftMinChip.modelData + "m"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(8); color: Theme.fgSurface }
                                MouseArea { id: ftMinMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.resetTimer(ftMinChip.modelData * 60) }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairlineBorder }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text { text: "󱎫"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.secondary }
                        Text { text: "Stopwatch"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }
                        Item { Layout.fillWidth: true }
                        Text { text: ShellState.formatTimer(ShellState.stopwatchElapsedSec); font.family: Theme.monoFont; font.pixelSize: Theme.fs(12); font.weight: Font.Bold; color: ShellState.stopwatchActive ? Theme.secondary : Theme.fgSurface }

                        Rectangle {
                            implicitWidth: swGoTxt.implicitWidth + 14
                            implicitHeight: 22
                            radius: Theme.r(7)
                            color: ShellState.stopwatchActive ? Theme.secondary : Theme.subCardBg
                            border.width: 1; border.color: ShellState.stopwatchActive ? Theme.secondary : Theme.cardBorder
                            Text { id: swGoTxt; anchors.centerIn: parent; text: ShellState.stopwatchActive ? "Stop" : "Run"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: ShellState.stopwatchActive ? Theme.contrastInk(Theme.secondary) : Theme.fgSurface }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.toggleStopwatch() }
                        }

                        Rectangle {
                            implicitWidth: swRstTxt.implicitWidth + 12
                            implicitHeight: 22
                            radius: Theme.r(7)
                            color: Theme.subCardBg
                            border.width: 1; border.color: Theme.cardBorder
                            Text { id: swRstTxt; anchors.centerIn: parent; text: "Reset"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.resetStopwatch() }
                        }
                    }
                }
            }

            // Compact Weather + Agenda Footer
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                radius: Theme.r(10)
                color: Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Text { text: ShellState.weatherAvailable ? ShellState.weatherIcon : "󰖐"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.primary }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: ShellState.weatherAvailable
                            ? (ShellState.weatherTemp + " · " + ShellState.weatherCondition + (ShellState.weatherCity ? (" (" + ShellState.weatherCity + ")") : ""))
                            : "Weather & Calendar ready in Notification Center"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                    Text {
                        text: ShellState.unreadCount > 0 ? (ShellState.unreadCount + " unread") : "0 unread"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(9)
                        color: ShellState.unreadCount > 0 ? Theme.primary : Theme.fgSurfaceVariant
                    }
                }
            }
        }
    }

    // ==================== 3. TOP-RIGHT SEQUOIA CONTROL CENTER POPOVER ====================
    Rectangle {
        id: controlsCard
        visible: root.panelMode === "controls"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 6
        anchors.right: parent.right
        anchors.rightMargin: ShellState.splitSideMargin
        readonly property int targetControlsWidth: root.controlsTab === "files"
            ? 680
            : (root.controlsTab === "themes" ? 560 : 416)
        readonly property int tabViewportH: Math.min(460, Math.max(280, root.height - root.topBarOffset - 92))
        width: Math.min(Math.max(340, root.width - ShellState.splitSideMargin * 2), targetControlsWidth)
        height: Math.min(Math.max(200, root.height - root.topBarOffset - 24), controlsCol.implicitHeight + 24)
        radius: Theme.r(20)
        color: Theme.notchBg
        border.width: Math.max(1, Theme.islandBorderWidth)
        border.color: Theme.islandBorder
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.96)
        transformOrigin: Item.TopRight

        Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: controlsCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 10

            // Header: Segmented Tabs + Store / Settings / Power
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
                                { id: "controls", label: "Controls" },
                                { id: "themes",   label: "Themes" },
                                { id: "files",    label: "Files" }
                            ]

                            delegate: Rectangle {
                                id: ccTab
                                required property var modelData
                                readonly property bool active: root.controlsTab === ccTab.modelData.id
                                implicitHeight: 24
                                implicitWidth: ccTabTxt.implicitWidth + 14
                                radius: Theme.r(12)
                                color: ccTab.active ? Theme.primary : (ccTabMouse.containsMouse ? Theme.controlFillHover : "transparent")

                                Text {
                                    id: ccTabTxt
                                    anchors.centerIn: parent
                                    text: ccTab.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: ccTab.active ? Font.Bold : Font.Medium
                                    color: ccTab.active ? Theme.fgPrimary : Theme.fgSurfaceVariant
                                }

                                MouseArea {
                                    id: ccTabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.switchControlsTab(ccTab.modelData.id)
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 28; implicitHeight: 28; radius: Theme.r(9)
                    color: ccStMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                    border.width: Theme.cardBorderWidth; border.color: Theme.cardBorder
                    Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.primary }
                    MouseArea { id: ccStMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openStoreRequested() }
                }

                Rectangle {
                    implicitWidth: 28; implicitHeight: 28; radius: Theme.r(9)
                    color: ccGearMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                    border.width: Theme.cardBorderWidth; border.color: Theme.cardBorder
                    Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.fgSurface }
                    MouseArea { id: ccGearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSettingsRequested("split") }
                }

                Rectangle {
                    implicitWidth: 28; implicitHeight: 28; radius: Theme.r(9)
                    color: root.powerMenuOpen ? Theme.withAlpha(Theme.error, 0.22) : (ccPwrMouse.containsMouse ? Theme.hoverBg : Theme.cardBg)
                    border.width: Theme.cardBorderWidth; border.color: root.powerMenuOpen ? Theme.error : Theme.cardBorder
                    Text { anchors.centerIn: parent; text: "󰐥"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: root.powerMenuOpen ? Theme.error : Theme.fgSurface }
                    MouseArea { id: ccPwrMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePowerMenuRequested() }
                }
            }

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

            // Sub-Tab 1: Control Center / Compact Stack / Studio Platter
            Flickable {
                visible: root.controlsTab === "controls"
                Layout.fillWidth: true
                Layout.preferredHeight: visible
                    ? Math.min(controlsInnerCol.implicitHeight, Math.max(180, root.height - root.topBarOffset - (root.powerMenuOpen ? 132 : 86)))
                    : 0
                contentWidth: width
                contentHeight: controlsInnerCol.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: controlsInnerCol
                    width: parent.width
                    spacing: 8

                // 2x2 Connectivity & Focus Platter
                Rectangle {
                    visible: ShellState.splitHubStyle === "controlcenter"
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
                                color: sqTile.modelData.active ? Theme.tileActiveBg : (sqTileMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                                border.width: sqTile.modelData.active ? Theme.activeControlBorderWidth : 0
                                border.color: sqTile.modelData.tint

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 7
                                    Rectangle {
                                        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(14)
                                        color: sqTile.modelData.active ? sqTile.modelData.tint : Theme.surfaceContainerHighest
                                        Text { anchors.centerIn: parent; text: sqTile.modelData.icon; font.family: Theme.iconFont; font.pixelSize: 13; color: sqTile.modelData.active ? Theme.contrastInk(sqTile.modelData.tint) : Theme.fgSurfaceVariant }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: sqTile.modelData.title; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: sqTile.modelData.active ? Font.Bold : Font.DemiBold; color: Theme.fgSurface }
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: sqTile.modelData.sub; font.family: Theme.fontFamily; font.pixelSize: 8; color: Theme.fgSurfaceVariant }
                                    }
                                }

                                MouseArea {
                                    id: sqTileMouse
                                    anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        const cid = sqTile.modelData.id;
                                        if (cid === "sink") {
                                            if (mouse.button === Qt.RightButton)
                                                Qt.callLater(() => { root.closeRequested(); root.openSettingsRequested("audio"); });
                                            else
                                                MangoState.cycleAudioSink();
                                        } else if (cid === "dnd") ShellState.toggleDnd();
                                        else if (cid === "awake") ShellState.toggleKeepAwake();
                                        else if (cid === "game") ShellState.toggleGameMode();
                                    }
                                }
                            }
                        }
                    }
                }

                // Compact Stack Toggles
                RowLayout {
                    visible: ShellState.splitHubStyle === "compact"
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
                            Layout.fillWidth: true; implicitHeight: 42; radius: Theme.r(11)
                            color: cmpAct.modelData.active ? Theme.tileActiveBg : (cmpActMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)
                            border.width: cmpAct.modelData.active ? Theme.activeControlBorderWidth : Theme.cardBorderWidth
                            border.color: cmpAct.modelData.active ? cmpAct.modelData.tint : Theme.cardBorder
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 2
                                Text { Layout.alignment: Qt.AlignHCenter; text: cmpAct.modelData.icon; font.family: Theme.iconFont; font.pixelSize: 13; color: cmpAct.modelData.active ? cmpAct.modelData.tint : Theme.fgSurfaceVariant }
                                Text { Layout.alignment: Qt.AlignHCenter; text: cmpAct.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 9; font.weight: cmpAct.modelData.active ? Font.Bold : Font.Medium; color: Theme.fgSurface }
                            }
                            MouseArea {
                                id: cmpActMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
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

                // Studio Platter MediaCard
                Loader {
                    Layout.fillWidth: true
                    readonly property bool showStudio: root.panelMode === "controls" && root.controlsTab === "controls" && ShellState.splitHubStyle === "media"
                    Layout.preferredHeight: showStudio ? (item ? Math.max(166, Math.ceil(item.implicitHeight)) : 168) : 0
                    active: root._controlsMainLoaded && ShellState.splitHubStyle === "media"
                    visible: showStudio
                    source: "MediaCard.qml"
                    onLoaded: {
                        if (item) {
                            item.player = Qt.binding(() => root.player);
                            item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    readonly property int qcH: (ShellState.splitHubStyle === "compact" ? 104 : 114)
                        + (DeviceCaps.hasBacklight ? 38 : 0)
                        + ((DeviceCaps.hasWifi || DeviceCaps.hasBluetooth) ? 42 : 0)
                    readonly property bool showQc: root.panelMode === "controls" && root.controlsTab === "controls"
                    Layout.preferredHeight: showQc ? (item ? Math.max(92, Math.ceil(item.implicitHeight)) : qcH) : 0
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

                Loader {
                    Layout.fillWidth: true
                    readonly property bool showCompactMedia: root.panelMode === "controls"
                        && root.controlsTab === "controls"
                        && ShellState.splitHubStyle !== "media"
                        && (ShellState.splitHubStyle === "controlcenter" || root.player !== null)
                    Layout.preferredHeight: showCompactMedia ? (item ? Math.max(158, Math.ceil(item.implicitHeight)) : 160) : 0
                    active: root._controlsMainLoaded && ShellState.splitHubStyle !== "media"
                    visible: showCompactMedia
                    source: "MediaCard.qml"
                    onLoaded: {
                        if (item) {
                            item.player = Qt.binding(() => root.player);
                            item.active = Qt.binding(() => root.isOpen && root.panelMode === "controls" && root.controlsTab === "controls");
                        }
                    }
                }

                // Telemetry Strip
                Rectangle {
                    visible: ShellState.splitHubStyle !== "compact"
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: Theme.r(10)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                        Text { text: "CPU " + Math.round(SystemTelemetry.cpuPercent) + "%" + (SystemTelemetry.cpuTempC > 0 ? (" · " + SystemTelemetry.cpuTempC + "°C") : ""); font.family: Theme.monoFont; font.pixelSize: 9; font.weight: Font.DemiBold; color: SystemTelemetry.cpuPercent > 85 ? Theme.error : Theme.fgSurfaceVariant }
                        Item { Layout.fillWidth: true }
                        Text { text: "RAM " + SystemTelemetry.memUsedGb.toFixed(1) + "/" + SystemTelemetry.memTotalGb.toFixed(0) + "G"; font.family: Theme.monoFont; font.pixelSize: 9; font.weight: Font.DemiBold; color: SystemTelemetry.memPercent > 85 ? Theme.warning : Theme.fgSurfaceVariant }
                        Item { Layout.fillWidth: true }
                        Text { text: DeviceCaps.hasBattery ? ("BAT " + DeviceCaps.batteryPercent + "%") : ("DISK " + Math.round(SystemTelemetry.diskPercent) + "%"); font.family: Theme.monoFont; font.pixelSize: 9; font.weight: Font.DemiBold; color: DeviceCaps.hasBattery && DeviceCaps.batteryLow ? Theme.error : Theme.fgSurfaceVariant }
                    }
                }
                }
            }

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

    // ==================== 4. TOP-RIGHT NOTIFICATION & CALENDAR CENTER ====================
    Rectangle {
        visible: root.panelMode === "notifications"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 6
        anchors.right: parent.right
        anchors.rightMargin: ShellState.splitSideMargin
        width: Math.min(720, Math.max(360, root.width - ShellState.splitSideMargin * 2))
        height: Math.min(504, Math.max(320, root.height - root.topBarOffset - 24))
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

    // ==================== 5. CENTERED FLOATING SPOTLIGHT LAUNCHER ====================
    Rectangle {
        visible: root.panelMode === "launcher"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(56, root.topBarOffset + 32)
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

    // ==================== 6. PASSIVE TOAST NOTIFICATION & HUD OSD ====================
    Item {
        id: toastContainer
        visible: root.isPassive
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: root.panelMode === "notification" ? parent.right : undefined
        anchors.rightMargin: root.panelMode === "notification" ? ShellState.splitSideMargin : 0
        anchors.horizontalCenter: root.panelMode === "osd" ? parent.horizontalCenter : undefined
        width: root.panelMode === "notification" ? 384 : 310
        height: root.panelMode === "notification"
            ? Math.max(76, Math.min(156, Math.round(osdOverlay.notificationHeight) + 22))
            : 58

        HoverHandler {
            id: toastHover
            onHoveredChanged: {
                if (hovered)
                    notifHideTimer.stop();
                else if (root.isOpen && root.panelMode === "notification")
                    notifHideTimer.restart();
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
