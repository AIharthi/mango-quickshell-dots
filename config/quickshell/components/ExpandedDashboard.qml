pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../m3"

ColumnLayout {
    id: root

    property bool isOpen: false
    property string screenName: ""
    property string activeTab: "overview"       // "overview" | "files" | "themes" | "launcher" | "notifications"
    property string launcherMode: "apps"
    property bool pinnedOpen: false
    property bool powerMenuOpen: false
    property var player: null

    signal tabSelected(string tab)
    signal togglePinRequested()
    signal togglePowerMenuRequested()
    signal openSettingsRequested(string page)
    signal openFilesRequested(string path)
    signal openKeybindsRequested()
    signal openCaptureHubRequested()
    signal openStoreRequested()
    signal closeRequested()
    signal searchFocusChanged(bool focused)
    signal controlInteractionChanged(bool interacting)

    Behavior on opacity {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    spacing: 10

    SystemClock {
        id: headerClock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // --- Header Bar (Clock/Date left, Segmented Tabs centered, Compact M3 Action Circles right) ---
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 38
        Layout.minimumHeight: 38
        Layout.maximumHeight: 38
        spacing: 8

        // Clock & Date Chip
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: false
            spacing: 6

            Text {
                text: ShellState.formatTime(headerClock.date)
                font.family: Theme.monoFont
                font.pixelSize: 14
                font.weight: Font.Bold
                color: Theme.m3Ink
            }

            Text {
                Layout.maximumWidth: 82
                elide: Text.ElideRight
                text: ShellState.formatDate(headerClock.date)
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Medium
                color: Theme.m3InkDim
            }
        }

        Item { Layout.fillWidth: true }

        // Material 3 Pill Tab Switcher
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: false
            implicitHeight: 36
            implicitWidth: tabRow.implicitWidth + 8
            radius: Theme.r(18)
            color: Theme.m3SurfaceC
            border.width: 1
            border.color: Theme.m3Line

            RowLayout {
                id: tabRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: [
                        { id: "overview",      icon: "󰕮", label: "Hub" },
                        { id: "files",         icon: "󰉋", label: "Files" },
                        { id: "themes",        icon: "󰏘", label: "Themes" },
                        { id: "launcher",      icon: "󰀻", label: "Apps" },
                        { id: "notifications", icon: "󰂚", label: "Alerts" }
                    ]

                    delegate: Rectangle {
                        id: tabBtn
                        required property var modelData
                        readonly property bool isCurrent: root.activeTab === tabBtn.modelData.id
                        readonly property bool hasBadge: tabBtn.modelData.id === "notifications" && ShellState.unreadCount > 0

                        implicitHeight: 28
                        implicitWidth: tabContent.implicitWidth + 14
                        radius: Theme.r(14)
                        color: tabBtn.isCurrent
                            ? Theme.m3Primary
                            : (tabArea.containsMouse ? Theme.m3SurfaceHigh : "transparent")

                        Behavior on color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: tabBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(11)
                                color: tabBtn.isCurrent ? Theme.m3OnPrimary : Theme.m3InkDim
                            }

                            Text {
                                text: tabBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: tabBtn.isCurrent ? Font.Bold : Font.Medium
                                color: tabBtn.isCurrent ? Theme.m3OnPrimary : Theme.m3Ink
                            }

                            Rectangle {
                                visible: tabBtn.hasBadge
                                implicitWidth: 6
                                implicitHeight: 6
                                radius: 3
                                color: tabBtn.isCurrent ? Theme.m3OnPrimary : Theme.m3Error
                            }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.tabSelected(tabBtn.modelData.id)
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Right Action Cluster (M3 Expressive tonal circular buttons)
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: false
            spacing: 5

            // Compact Hub Layout Switcher Circle (LMB cycles Hub layout, RMB -> Settings -> Shell)
            Rectangle {
                id: hubSwitchPill
                implicitHeight: 30
                implicitWidth: 30
                radius: Theme.r(15)
                color: hubSwitchMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
                visible: root.activeTab === "overview"
                scale: hubSwitchMouse.pressed ? 0.92 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                readonly property var curHubObj: {
                    const arr = ShellState.availableHubStyles;
                    for (let i = 0; i < arr.length; i++) {
                        if (arr[i].id === ShellState.hubUiStyle)
                            return arr[i];
                    }
                    return arr[0];
                }

                Text {
                    anchors.centerIn: parent
                    text: hubSwitchPill.curHubObj ? hubSwitchPill.curHubObj.icon : "󰕰"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: hubSwitchMouse.containsMouse ? Theme.m3Primary : Theme.m3Ink
                }

                MouseArea {
                    id: hubSwitchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            Qt.callLater(() => root.openSettingsRequested("island"));
                        else
                            ShellState.cycleHubUiStyle();
                    }
                }
            }

            // Store Quick Button
            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: storeArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
                scale: storeArea.pressed ? 0.92 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰏖"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.m3Ink
                }

                MouseArea {
                    id: storeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.closeRequested();
                        root.openStoreRequested();
                    }
                }
            }

            // Active-only status chips shown outside Overview tab (avoid duplicating Hub toggles)
            Rectangle {
                visible: root.activeTab !== "overview" && ShellState.dnd
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: dndHeaderArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

                Text {
                    anchors.centerIn: parent
                    text: "󰂛"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.m3OnSecondaryContainer
                }

                MouseArea {
                    id: dndHeaderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.toggleDnd()
                }
            }

            Rectangle {
                visible: root.activeTab !== "overview" && ShellState.keepAwake
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: awakeHeaderArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer

                Text {
                    anchors.centerIn: parent
                    text: "󰅶"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.m3OnSecondaryContainer
                }

                MouseArea {
                    id: awakeHeaderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.toggleKeepAwake()
                }
            }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: settingsArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line
                scale: settingsArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.reducedMotion
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰒓"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.m3Ink
                    rotation: settingsArea.containsMouse ? 45 : 0

                    Behavior on rotation {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSettingsRequested("island")
                }
            }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: root.powerMenuOpen
                    ? Theme.m3ErrorContainer
                    : (powerArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC)
                border.width: 1
                border.color: root.powerMenuOpen ? Theme.m3Error : Theme.m3Line
                scale: powerArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.reducedMotion
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: root.powerMenuOpen ? Theme.m3OnErrorContainer : Theme.m3Error
                }

                MouseArea {
                    id: powerArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePowerMenuRequested()
                }
            }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: root.pinnedOpen
                    ? Theme.m3Primary
                    : (pinArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceC)
                border.width: 1
                border.color: root.pinnedOpen ? Theme.m3Primary : Theme.m3Line
                scale: pinArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.reducedMotion
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.pinnedOpen ? "󰐃" : "󰤱"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: root.pinnedOpen ? Theme.m3OnPrimary : Theme.m3Ink
                }

                MouseArea {
                    id: pinArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePinRequested()
                }
            }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: Theme.r(15)
                color: closeArea.containsMouse
                    ? Theme.m3ErrorContainer
                    : Theme.m3SurfaceC
                border.width: 1
                border.color: closeArea.containsMouse ? Theme.m3Error : Theme.m3Line
                scale: closeArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.reducedMotion
                    ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.reducedMotion
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: closeArea.containsMouse ? Theme.m3OnErrorContainer : Theme.m3Ink
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }
    }

    // --- Collapsible Animated Power Action Strip ---
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: root.powerMenuOpen ? 36 : 0
        Layout.maximumHeight: root.powerMenuOpen ? 36 : 0
        opacity: root.powerMenuOpen ? 1.0 : 0.0
        visible: opacity > 0.01
        clip: true

        Behavior on Layout.preferredHeight {
            enabled: !Theme.isSimple
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: !Theme.isSimple
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Loader {
            anchors.fill: parent
            active: root.powerMenuOpen
            source: "PowerMenu.qml"
            onLoaded: {
                if (item)
                    item.actionTriggered.connect(() => root.closeRequested());
            }
        }
    }

    // Keep each visited tab warm until ExpandedDashboard unloads (0ms tab switch lag)
    property bool _overviewLoaded: root.activeTab === "overview"
    property bool _filesLoaded: root.activeTab === "files"
    property bool _themesLoaded: root.activeTab === "themes"
    property bool _launcherLoaded: root.activeTab === "launcher"
    property bool _notifsLoaded: root.activeTab === "notifications"

    function _syncTabLoaded(): void {
        if (root.activeTab === "overview") root._overviewLoaded = true;
        else if (root.activeTab === "files") root._filesLoaded = true;
        else if (root.activeTab === "themes") root._themesLoaded = true;
        else if (root.activeTab === "launcher") root._launcherLoaded = true;
        else if (root.activeTab === "notifications") root._notifsLoaded = true;
    }

    Component.onCompleted: _syncTabLoaded()

    onActiveTabChanged: {
        _syncTabLoaded();
        if (activeTab !== "launcher" && activeTab !== "files" && activeTab !== "notifications")
            searchFocusChanged(false);
        if (activeTab === "notifications")
            ShellState.clearUnread();
    }

    // --- Tab Content Stack (sticky warm URL loaders per visited tab) ---
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Tab 1: Overview Hub (Bento Grid OR Apple Cupertino/Stage/Cockpit Layouts)
        Loader {
            id: overviewLoader
            anchors.fill: parent
            active: root._overviewLoaded
            visible: opacity > 0.01
            opacity: root.activeTab === "overview" ? 1.0 : 0.0
            source: "OverviewHub.qml"

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            onLoaded: {
                if (!item)
                    return;
                item.active = Qt.binding(() => root.isOpen && root.activeTab === "overview");
                item.screenName = Qt.binding(() => root.screenName);
                item.player = Qt.binding(() => root.player);
                item.openSettingsRequested.connect(page => root.openSettingsRequested(page));
                item.controlInteractionChanged.connect(interacting => root.controlInteractionChanged(interacting));
            }
        }

        // Tab 2: Quick File Browser (Rust Backend)
        Loader {
            id: filesTabLoader
            anchors.fill: parent
            active: root._filesLoaded
            visible: opacity > 0.01
            opacity: root.activeTab === "files" ? 1.0 : 0.0
            source: "../files/QuickFilesTab.qml"

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            onLoaded: {
                if (!item)
                    return;
                item.active = Qt.binding(() => root.isOpen && root.activeTab === "files");
                item.searchFocusChanged.connect(focused => root.searchFocusChanged(focused));
                item.openFullManagerRequested.connect(path => {
                    root.closeRequested();
                    root.openFilesRequested(path);
                });
            }
        }

        // Tab 3: Theme & Wallpaper Switcher
        Loader {
            id: themesLoader
            anchors.fill: parent
            active: root._themesLoaded
            visible: opacity > 0.01
            opacity: root.activeTab === "themes" ? 1.0 : 0.0
            source: "ThemeSwitcher.qml"

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            onLoaded: {
                if (!item)
                    return;
                item.active = Qt.binding(() => root.isOpen && root.activeTab === "themes");
                item.openSettingsRequested.connect(page => root.openSettingsRequested(page));
            }
        }

        // Tab 4: Multi-Mode Launcher (Apps, Clipboard, Calc, Commands, Emoji)
        Loader {
            id: launcherLoader
            anchors.fill: parent
            active: root._launcherLoaded
            visible: opacity > 0.01
            opacity: root.activeTab === "launcher" ? 1.0 : 0.0
            source: "AppLauncher.qml"

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            onLoaded: {
                if (!item)
                    return;
                item.initialMode = Qt.binding(() => root.launcherMode);
                item.active = Qt.binding(() => root.isOpen && root.activeTab === "launcher");
                item.searchFocusChanged.connect(focused => root.searchFocusChanged(focused));
                item.closeRequested.connect(() => root.closeRequested());
                item.openSettingsRequested.connect(page => root.openSettingsRequested(page));
                item.openFilesRequested.connect(path => root.openFilesRequested(path));
                item.openKeybindsRequested.connect(() => root.openKeybindsRequested());
                item.openCaptureHubRequested.connect(() => root.openCaptureHubRequested());
                item.openStoreRequested.connect(() => root.openStoreRequested());
            }
        }

        // Tab 5: Alerts, Calendar, Focus Timer & Scratchpad
        Loader {
            id: notificationsLoader
            anchors.fill: parent
            active: root._notifsLoaded
            visible: opacity > 0.01
            opacity: root.activeTab === "notifications" ? 1.0 : 0.0
            source: "NotificationsTab.qml"

            Behavior on opacity {
                enabled: !Theme.reducedMotion
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            onLoaded: {
                if (!item)
                    return;
                item.active = Qt.binding(() => root.isOpen && root.activeTab === "notifications");
                item.inputFocusChanged.connect(focused => root.searchFocusChanged(focused));
            }
        }
    }
}
