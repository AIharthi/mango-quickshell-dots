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

    // ==================== 1. LEFT POD POPOVER: DYNISLAND SYSTEM RINGS & SPACES ====================
    Rectangle {
        visible: root.panelMode === "left"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.left: parent.left
        anchors.leftMargin: ShellState.splitSideMargin
        width: Math.min(420, Math.max(300, root.width - ShellState.splitSideMargin * 2))
        height: Math.min(Math.max(220, root.height - root.topBarOffset - 24), leftHubCol.implicitHeight + 28)
        radius: Theme.r(30)
        color: Theme.m3PanelBg
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.95)
        transformOrigin: Item.TopLeft

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 190; easing.type: Theme.m3Springy } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: leftHubCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitWidth: 32; implicitHeight: 32; radius: Theme.r(16)
                    color: Theme.m3PrimaryContainer
                    Text { anchors.centerIn: parent; text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.m3OnPrimaryContainer }
                }

                Text { Layout.fillWidth: true; text: "Spaces & System"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); font.weight: Font.DemiBold; color: Theme.m3Ink }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: lhLayTxt.implicitWidth + 16
                    radius: Theme.r(14)
                    color: lhLayMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer
                    Text { id: lhLayTxt; anchors.centerIn: parent; text: "Layout: " + MangoState.layoutForScreen(root.screenName); font.family: Theme.monoFont; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.m3OnSecondaryContainer }
                    MouseArea { id: lhLayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["mmsg", "dispatch", "switch_layout"]) }
                }
            }

            // DarkShadowShell DynIsland System 3 WavyArc Gauges
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { label: "CPU", val: Math.round(SystemTelemetry.cpuPercent), ratio: SystemTelemetry.cpuPercent / 100.0 },
                        { label: "RAM", val: Math.round(SystemTelemetry.memPercent), ratio: SystemTelemetry.memPercent / 100.0 },
                        { label: DeviceCaps.hasBattery ? "Battery" : "Disk", val: DeviceCaps.hasBattery ? DeviceCaps.batteryPercent : Math.round(SystemTelemetry.diskPercent), ratio: (DeviceCaps.hasBattery ? DeviceCaps.batteryPercent : SystemTelemetry.diskPercent) / 100.0 }
                    ]

                    delegate: Rectangle {
                        id: gItem
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 112
                        radius: Theme.r(22)
                        color: Theme.m3SurfaceC

                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            width: 72
                            height: 72

                            M3WavyArc {
                                anchors.fill: parent
                                value: gItem.modelData.ratio
                                moving: root.isOpen && root.panelMode === "left"
                                wavy: ShellState.m3WavyProgress && !Theme.isSimple
                                thick: 3.5
                                color: Theme.m3Primary
                                track: Theme.m3Track
                            }

                            Text {
                                anchors.centerIn: parent
                                text: gItem.modelData.val + "%"
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(13)
                                font.weight: Font.Bold
                                color: Theme.m3Ink
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: gItem.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Medium
                            color: Theme.m3InkDim
                        }
                    }
                }
            }

            // Focused Window Readout
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fwRow.implicitHeight + 16
                radius: Theme.r(20)
                color: Theme.m3SurfaceC

                RowLayout {
                    id: fwRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Text { text: "󰖯"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.m3Primary }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: MangoState.activeAppName.length > 0 ? MangoState.activeAppName : "Desktop"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.weight: Font.DemiBold; color: Theme.m3Ink }
                        Text { Layout.fillWidth: true; elide: Text.ElideRight; text: MangoState.activeWindowTitle.length > 0 ? MangoState.activeWindowTitle : "No active window focused"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.m3InkDim }
                    }
                }
            }

            // Interactive 3x3 M3 Spaces Grid
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: wsGrid.implicitHeight + 18
                radius: Theme.r(22)
                color: Theme.m3SurfaceC

                GridLayout {
                    id: wsGrid
                    anchors.fill: parent
                    anchors.margins: 9
                    columns: 3
                    rowSpacing: 7
                    columnSpacing: 7

                    Repeater {
                        model: MangoState.tagsForScreen(root.screenName)

                        delegate: Rectangle {
                            id: lgTag
                            required property var modelData
                            readonly property bool isActive: lgTag.modelData.is_active
                            readonly property bool isUrgent: lgTag.modelData.is_urgent
                            readonly property bool isOccupied: lgTag.modelData.client_count > 0

                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: Theme.r(lgTagMouse.pressed ? 10 : (lgTag.isActive ? 18 : 12))
                            color: {
                                if (lgTag.isUrgent) return Theme.m3Error;
                                if (lgTag.isActive) return Theme.m3Primary;
                                if (lgTag.isOccupied) return Theme.m3SecondaryContainer;
                                return lgTagMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh;
                            }

                            Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Theme.m3Springy } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    text: "Space " + lgTag.modelData.index
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(10)
                                    font.weight: lgTag.isActive ? Font.Bold : Font.Medium
                                    color: lgTag.isUrgent ? Theme.m3OnErrorContainer : (lgTag.isActive ? Theme.m3OnPrimary : (lgTag.isOccupied ? Theme.m3OnSecondaryContainer : Theme.m3Ink))
                                }
                                Text {
                                    visible: lgTag.modelData.client_count > 0
                                    text: String(lgTag.modelData.client_count)
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fs(9)
                                    font.weight: Font.Bold
                                    color: lgTag.isActive ? Theme.m3OnPrimary : Theme.m3Primary
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

            // Quick Actions 2x3 M3 Tiles
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8

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
                        implicitHeight: 50
                        radius: Theme.r(qaMouse.pressed ? 12 : 20)
                        color: qaMouse.containsMouse ? Theme.m3SecondaryContainer : Theme.m3SurfaceC

                        Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160 } }
                        Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 140 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: qaTile.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.m3Primary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: qaTile.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Medium; color: Theme.m3Ink }
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
                spacing: 8

                M3Btn {
                    Layout.fillWidth: true
                    icon: "󰒓"
                    text: "Split Settings"
                    onClicked: { root.closeRequested(); root.openSettingsRequested("split"); }
                }

                M3Btn {
                    implicitWidth: 44
                    icon: "󰌌"
                    onClicked: { root.closeRequested(); root.openKeybindsRequested(); }
                }

                M3Btn {
                    implicitWidth: 44
                    variant: "danger"
                    icon: "󰐥"
                    onClicked: { root.closeRequested(); Quickshell.execDetached(["qs", "ipc", "call", "island", "togglePowerOverlay"]); }
                }
            }
        }
    }

    // ==================== 2. CENTER POD POPOVER: MEDIA, FOCUS TIMER & AGENDA ====================
    Rectangle {
        visible: root.panelMode === "center"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(472, Math.max(360, root.width - ShellState.splitSideMargin * 2))
        height: Math.min(Math.max(220, root.height - root.topBarOffset - 24), centerHubCol.implicitHeight + 28)
        radius: Theme.r(30)
        color: Theme.m3PanelBg
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        opacity: root.shown ? 1.0 : 0.0
        scale: root.shown ? 1.0 : (Theme.reducedMotion ? 1.0 : 0.95)
        transformOrigin: Item.Top

        Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 190; easing.type: Theme.m3Springy } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: centerHubCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitWidth: 32; implicitHeight: 32; radius: Theme.r(16)
                    color: Theme.m3PrimaryContainer
                    Text { anchors.centerIn: parent; text: "󰓇"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(14); color: Theme.m3OnPrimaryContainer }
                }

                Text { Layout.fillWidth: true; text: "Media, Focus & Agenda"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(14); font.weight: Font.DemiBold; color: Theme.m3Ink }

                M3Btn {
                    compact: true
                    icon: "󰂚"
                    text: "Calendar"
                    onClicked: root.openNotificationsRequested()
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
                                implicitWidth: 34; implicitHeight: 24; radius: Theme.r(12)
                                color: ftMinMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                                Text { anchors.centerIn: parent; text: ftMinChip.modelData + "m"; font.family: Theme.monoFont; font.pixelSize: Theme.fs(9); font.weight: Font.Medium; color: Theme.m3Ink }
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

    // ==================== 3. DARKSHADOWSHELL CONTROL CENTER DRAWER ====================
    Rectangle {
        id: controlsCard
        visible: root.panelMode === "controls"
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: parent.right
        anchors.rightMargin: ShellState.splitSideMargin
        readonly property int targetControlsWidth: root.controlsTab === "files"
            ? 680
            : (root.controlsTab === "themes" ? 560 : 456)
        readonly property int maxDrawerH: Math.max(260, root.height - root.topBarOffset - 22)
        readonly property int tabViewportH: Math.min(500, Math.max(280, root.height - root.topBarOffset - 96))
        width: Math.min(Math.max(360, root.width - ShellState.splitSideMargin * 2), targetControlsWidth)
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

            // DarkShadowShell ControlCenter Header: Close button, 4 Pill Tabs, Settings & Power
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                    color: ccClsMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                    Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.m3Ink }
                    MouseArea { id: ccClsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
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
                            id: ccTab
                            required property var modelData
                            readonly property bool active: root.controlsTab === ccTab.modelData.id
                            implicitHeight: 34
                            implicitWidth: ccTabTxt.implicitWidth + 18
                            radius: Theme.r(17)
                            color: ccTab.active
                                ? Theme.m3Primary
                                : (ccTabMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC)

                            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 160 } }

                            Text {
                                id: ccTabTxt
                                anchors.centerIn: parent
                                text: ccTab.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: Font.Medium
                                color: ccTab.active ? Theme.m3OnPrimary : Theme.m3Ink
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

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: Theme.r(17)
                    color: ccGearMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                    Text { anchors.centerIn: parent; text: "󰒓"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.m3Ink }
                    MouseArea { id: ccGearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSettingsRequested("split") }
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

            // Sub-Tab 1: Control Center (Sliders + Wide Tiles + 4-col M3 Tiles + Music Card + Spaces Strip)
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
                            && (ShellState.splitHubStyle === "controlcenter" || ShellState.splitHubStyle === "media" || root.player !== null)
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

                    // Compact Workspaces + Store Strip
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
                                        id: spCcTag
                                        required property var modelData
                                        readonly property bool isActive: spCcTag.modelData.is_active
                                        readonly property bool isUrgent: spCcTag.modelData.is_urgent
                                        readonly property bool isOccupied: spCcTag.modelData.client_count > 0

                                        Layout.fillWidth: true
                                        implicitHeight: 26
                                        radius: Theme.r(spCcTag.isActive ? 13 : 9)
                                        color: {
                                            if (spCcTag.isUrgent) return Theme.m3Error;
                                            if (spCcTag.isActive) return Theme.m3Primary;
                                            if (spCcTagMouse.containsMouse) return Theme.m3SurfaceHighest;
                                            return spCcTag.isOccupied ? Theme.m3SecondaryContainer : "transparent";
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: spCcTag.modelData.index
                                            font.family: Theme.monoFont
                                            font.pixelSize: Theme.fs(10)
                                            font.weight: spCcTag.isActive ? Font.Bold : Font.Medium
                                            color: spCcTag.isUrgent ? Theme.m3OnErrorContainer : (spCcTag.isActive ? Theme.m3OnPrimary : (spCcTag.isOccupied ? Theme.m3OnSecondaryContainer : Theme.m3InkDim))
                                        }

                                        MouseArea {
                                            id: spCcTagMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Quickshell.execDetached(["mmsg", "dispatch", "view," + spCcTag.modelData.index + ",0"])
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                implicitWidth: 28; implicitHeight: 28; radius: Theme.r(14)
                                color: spCcStoreM.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer
                                Text { anchors.centerIn: parent; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(12); color: Theme.m3OnSecondaryContainer }
                                MouseArea { id: spCcStoreM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openStoreRequested() }
                            }
                        }
                    }
                }
            }

            // Sub-Tab 2: DarkShadowShell Overview (Hero Clock + Calendar + 3 M3Blob Gauges)
            Flickable {
                visible: root.controlsTab === "overview"
                Layout.fillWidth: true
                Layout.preferredHeight: visible
                    ? Math.min(overviewTab.implicitHeight, Math.max(200, controlsCard.maxDrawerH - (root.powerMenuOpen ? 124 : 76)))
                    : 0
                contentWidth: width
                contentHeight: overviewTab.implicitHeight
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                M3OverviewTab {
                    id: overviewTab
                    width: parent.width
                    active: root.isOpen && root.panelMode === "controls" && root.controlsTab === "overview"
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
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: parent.right
        anchors.rightMargin: ShellState.splitSideMargin
        width: Math.min(720, Math.max(360, root.width - ShellState.splitSideMargin * 2))
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

    // ==================== 5. CENTERED FLOATING M3 LAUNCHER ====================
    Rectangle {
        visible: root.panelMode === "launcher"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(56, root.topBarOffset + 32)
        width: Math.min(700, Math.max(420, root.width - 48))
        height: Math.min(500, Math.max(320, root.height - root.topBarOffset - 72))
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

    // ==================== 6. PASSIVE TOAST NOTIFICATION & HUD OSD ====================
    Item {
        id: toastContainer
        visible: root.isPassive
        anchors.top: parent.top
        anchors.topMargin: root.topBarOffset + 8
        anchors.right: root.panelMode === "notification" ? parent.right : undefined
        anchors.rightMargin: root.panelMode === "notification" ? ShellState.splitSideMargin : 0
        anchors.horizontalCenter: root.panelMode === "osd" ? parent.horizontalCenter : undefined
        width: root.panelMode === "notification" ? 420 : 320
        height: root.panelMode === "notification"
            ? Math.max(82, Math.min(164, Math.round(osdOverlay.notificationHeight) + 24))
            : 60

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
