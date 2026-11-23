pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../files"

ColumnLayout {
    id: root

    property bool isOpen: false
    property string screenName: ""
    property string activeTab: "overview"       // "overview" | "files" | "themes" | "launcher"
    property bool pinnedOpen: false
    property bool powerMenuOpen: false
    property var player: null

    signal tabSelected(string tab)
    signal togglePinRequested()
    signal togglePowerMenuRequested()
    signal openSettingsRequested(string page)
    signal openFilesRequested(string path)
    signal closeRequested()
    signal searchFocusChanged(bool focused)
    signal controlInteractionChanged(bool interacting)

    spacing: 12

    SystemClock {
        id: headerClock
        precision: ShellState.clockShowSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    // --- Header Bar (Clock/Date left, Segmented Tabs dead-center, Pin/Close right) ---
    Item {
        Layout.fillWidth: true
        implicitHeight: 32

        // Clock & Date Chip
        RowLayout {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: ShellState.formatTime(headerClock.date)
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Theme.fgSurface
            }

            Text {
                text: ShellState.formatDate(headerClock.date)
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgSurfaceVariant
            }
        }

        // Segmented Tab Switcher (mathematically centered)
        Rectangle {
            anchors.centerIn: parent
            height: 30
            width: tabRow.implicitWidth + 6
            radius: Theme.r(15)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: tabRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: [
                        { id: "overview", icon: "󰕮", label: "Hub" },
                        { id: "files",    icon: "󰉋", label: "Files" },
                        { id: "themes",   icon: "󰏘", label: "Themes" },
                        { id: "launcher", icon: "󰀻", label: "Apps" }
                    ]

                    delegate: Rectangle {
                        id: tabBtn
                        required property var modelData
                        readonly property bool isCurrent: root.activeTab === tabBtn.modelData.id

                        implicitHeight: 24
                        implicitWidth: tabContent.implicitWidth + 18
                        radius: Theme.r(12)
                        color: tabBtn.isCurrent
                            ? Theme.primary
                            : (tabArea.containsMouse ? Theme.hoverBg : "transparent")

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: tabBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 12
                                color: tabBtn.isCurrent ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }

                            Text {
                                text: tabBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: tabBtn.isCurrent ? Font.Bold : Font.Medium
                                color: tabBtn.isCurrent ? Theme.fgPrimary : Theme.fgSurfaceVariant
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

        // Settings + Power + Pin & Close Buttons
        RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Active-only status chips (click to turn off)
            Rectangle {
                visible: ShellState.dnd
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: dndHeaderArea.containsMouse ? Theme.hoverBg : Theme.withAlpha(Theme.warning, 0.16)
                border.width: Theme.cardBorderWidth
                border.color: Theme.withAlpha(Theme.warning, 0.45)

                Text {
                    anchors.centerIn: parent
                    text: "󰂛"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.warning
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
                visible: ShellState.keepAwake
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: awakeHeaderArea.containsMouse ? Theme.hoverBg : Theme.withAlpha(Theme.tertiary, 0.16)
                border.width: Theme.cardBorderWidth
                border.color: Theme.withAlpha(Theme.tertiary, 0.45)

                Text {
                    anchors.centerIn: parent
                    text: "󰅶"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.tertiary
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
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: settingsArea.containsMouse ? Theme.hoverBg : Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                scale: settingsArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰒓"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: settingsArea.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
                    rotation: settingsArea.containsMouse ? 45 : 0

                    Behavior on rotation {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSettingsRequested("appearance")
                }
            }

            Rectangle {
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: root.powerMenuOpen
                    ? Theme.withAlpha(Theme.error, 0.22)
                    : (powerArea.containsMouse ? Theme.hoverBg : Theme.cardBg)
                border.width: Theme.cardBorderWidth
                border.color: root.powerMenuOpen ? Theme.error : Theme.cardBorder
                scale: powerArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰐥"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: (root.powerMenuOpen || powerArea.containsMouse) ? Theme.error : Theme.fgSurfaceVariant
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
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: root.pinnedOpen
                    ? Theme.activeBg
                    : (pinArea.containsMouse ? Theme.hoverBg : Theme.cardBg)
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                scale: pinArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.pinnedOpen ? "󰐃" : "󰤱"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: root.pinnedOpen ? Theme.primary : Theme.fgSurfaceVariant
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
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.r(14)
                color: closeArea.containsMouse
                    ? Theme.withAlpha(Theme.error, 0.22)
                    : Theme.cardBg
                border.width: Theme.cardBorderWidth
                border.color: Theme.cardBorder
                scale: closeArea.pressed ? 0.92 : 1.0

                Behavior on color {
                    enabled: !Theme.isSimple
                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    enabled: !Theme.isSimple
                    NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: closeArea.containsMouse ? Theme.error : Theme.fgSurfaceVariant
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
        Layout.preferredHeight: root.powerMenuOpen ? 34 : 0
        opacity: root.powerMenuOpen ? 1.0 : 0.0
        visible: opacity > 0.01
        clip: true

        Behavior on Layout.preferredHeight {
            enabled: !Theme.isSimple
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: !Theme.isSimple
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        PowerMenu {
            anchors.fill: parent
            onActionTriggered: root.closeRequested()
        }
    }

    property string _prevTab: activeTab
    property string _fadingTab: ""

    onActiveTabChanged: {
        if (_prevTab !== activeTab) {
            _fadingTab = _prevTab;
            _prevTab = activeTab;
            tabUnloadTimer.restart();
            if (activeTab !== "launcher" && activeTab !== "files")
                searchFocusChanged(false);
        }
    }

    Timer {
        id: tabUnloadTimer
        interval: 200
        repeat: false
        onTriggered: root._fadingTab = ""
    }

    // --- Tab Content Stack (lazy-loaded per active tab) ---
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Tab 1: Overview Hub (Media + SysMon + MangoWC Tags + Quick Controls)
        Loader {
            id: overviewLoader
            anchors.fill: parent
            active: root.activeTab === "overview" || root._fadingTab === "overview"
            visible: opacity > 0.01
            opacity: root.activeTab === "overview" ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            sourceComponent: GridLayout {
                columns: 2
                rowSpacing: 10
                columnSpacing: 10

                MediaCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 162
                    player: root.player
                    active: root.isOpen && root.activeTab === "overview"
                    onSeekingChanged: seeking => root.controlInteractionChanged(seeking)
                }

                SystemMonitor {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 162
                    active: root.isOpen && root.activeTab === "overview"
                }

                MangoTags {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: DeviceCaps.hasExtraQuickControls ? 196 : 152
                    screenName: root.screenName
                    active: root.isOpen && root.activeTab === "overview"
                }

                QuickControls {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: DeviceCaps.hasExtraQuickControls ? 196 : 152
                    active: root.isOpen && root.activeTab === "overview"
                    onDraggingChanged: dragging => root.controlInteractionChanged(dragging)
                    onOpenSettingsRequested: page => root.openSettingsRequested(page)
                }
            }
        }

        // Tab 2: Quick File Browser (Rust Backend)
        Loader {
            id: filesTabLoader
            anchors.fill: parent
            active: root.activeTab === "files" || root._fadingTab === "files"
            visible: opacity > 0.01
            opacity: root.activeTab === "files" ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            sourceComponent: QuickFilesTab {
                active: root.isOpen && root.activeTab === "files"
                onSearchFocusChanged: focused => root.searchFocusChanged(focused)
                onOpenFullManagerRequested: path => {
                    root.closeRequested();
                    root.openFilesRequested(path);
                }
            }
        }

        // Tab 3: Theme & Wallpaper Switcher
        Loader {
            id: themesLoader
            anchors.fill: parent
            active: root.activeTab === "themes" || root._fadingTab === "themes"
            visible: opacity > 0.01
            opacity: root.activeTab === "themes" ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            sourceComponent: ThemeSwitcher {
                active: root.isOpen && root.activeTab === "themes"
                onOpenSettingsRequested: page => root.openSettingsRequested(page)
            }
        }

        // Tab 3: Fuzzy App Launcher
        Loader {
            id: launcherLoader
            anchors.fill: parent
            active: root.activeTab === "launcher" || root._fadingTab === "launcher"
            visible: opacity > 0.01
            opacity: root.activeTab === "launcher" ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            sourceComponent: AppLauncher {
                active: root.isOpen && root.activeTab === "launcher"
                onSearchFocusChanged: focused => root.searchFocusChanged(focused)
                onCloseRequested: root.closeRequested()
            }
        }
    }
}
