pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property bool isOpen: true
    property string activePage: "appearance"
    property bool _entered: false
    readonly property bool shown: root.isOpen && root._entered

    signal pageSelected(string page)
    signal closeRequested()

    Component.onCompleted: Qt.callLater(() => { root._entered = true; })

    readonly property var navItems: {
        const items = [
            { id: "appearance", label: "Appearance", icon: "󰏘", source: "AppearancePage.qml", sub: "Modes, Matugen palette, cursor & animations" },
            { id: "windows",    label: "Windows",    icon: "󰖲", source: "WindowsPage.qml",    sub: "Tiling layouts, focus behavior & snapping" }
        ];
        if (DeviceCaps.hasAudio)
            items.push({ id: "audio", label: "Audio", icon: "󰋋", source: "AudioPage.qml", sub: "Output sinks, microphones & volume" });
        if (DeviceCaps.hasWlrRandr)
            items.push({ id: "displays", label: "Displays", icon: "󰍹", source: "DisplayPage.qml", sub: "Resolution, refresh rate & scaling" });
        if (DeviceCaps.hasWifi)
            items.push({ id: "network", label: "Network", icon: "󰤨", source: "NetworkPage.qml", sub: "Wi-Fi radio & nearby networks" });
        if (DeviceCaps.hasBluetooth)
            items.push({ id: "bluetooth", label: "Bluetooth", icon: "󰂯", source: "BluetoothPage.qml", sub: "Adapter power & paired devices" });
        items.push({ id: "input",  label: "Input",  icon: "󰌌", source: "InputPage.qml",  sub: "Keyboard layouts, pointer speed & trackpad" });
        items.push({ id: "system", label: "System", icon: "󰋼", source: "SystemPage.qml", sub: "Hardware probe, power & local.conf" });
        return items;
    }

    readonly property int currentNavIndex: {
        for (let i = 0; i < navItems.length; i++) {
            if (navItems[i].id === root.activePage)
                return i;
        }
        return 0;
    }

    readonly property var currentNavItem: navItems[currentNavIndex]
    readonly property string resolvedPage: currentNavItem.id
    readonly property string pageSource: currentNavItem.source

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.keyboardFocus: root.isOpen
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    FocusScope {
        anchors.fill: parent
        focus: root.isOpen

        Keys.onEscapePressed: root.closeRequested()

        // Dimmed scrim backdrop (click outside to close)
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, Theme.isSimple ? 0.56 : 0.44)
            opacity: root.shown ? 1.0 : 0.0

            Behavior on opacity {
                enabled: !Theme.isSimple
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.isOpen
                onClicked: root.closeRequested()
            }
        }

        // Centered Settings Dialog
        Rectangle {
            id: dialog
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.shown ? 0 : (Theme.isSimple ? 0 : 14)
            width: Math.min(parent.width - 48, 840)
            height: Math.min(parent.height - 48, 570)
            radius: Theme.r(22)
            color: Theme.notchBg
            border.width: Theme.islandBorderWidth
            border.color: Theme.islandBorder
            clip: true

            opacity: root.shown ? 1.0 : 0.0
            scale: root.shown ? 1.0 : (Theme.isSimple ? 1.0 : 0.93)

            Behavior on opacity {
                enabled: !Theme.isSimple
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.isSimple
                NumberAnimation {
                    duration: 240
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.45
                }
            }
            Behavior on anchors.verticalCenterOffset {
                enabled: !Theme.isSimple
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // Eat clicks inside dialog so backdrop MouseArea does not close it
            MouseArea {
                anchors.fill: parent
            }

            // Subtle glass specular top sheen in Blur Mode
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 48
                radius: parent.radius
                visible: Theme.isBlur
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.30) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // --- Left Navigation Sidebar ---
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 196
                    color: Theme.isSimple ? Theme.surfaceContainerLow : Theme.withAlpha(Theme.surfaceContainerLow, Theme.isBlur ? 0.45 : 0.72)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // App Title & Device Chip
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            RowLayout {
                                spacing: 8

                                Text {
                                    text: "󰒓"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 16
                                    color: Theme.primary
                                }

                                Text {
                                    text: "Settings"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: Theme.r(8)
                                color: Theme.subCardBg
                                border.width: Theme.cardBorderWidth
                                border.color: Theme.cardBorder

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    Text {
                                        text: DeviceCaps.deviceType === "laptop" ? "󰌢" : "󰍹"
                                        font.family: Theme.iconFont
                                        font.pixelSize: 12
                                        color: Theme.secondary
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (DeviceCaps.deviceType === "laptop" ? "Laptop" : "Desktop")
                                            + (DeviceCaps.hostname.length > 0 ? (" · " + DeviceCaps.hostname) : "")
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        color: Theme.fgSurfaceVariant
                                    }
                                }
                            }
                        }

                        // Dynamic Navigation Links with Sliding Selection Indicator
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: navCol.implicitHeight

                            Rectangle {
                                id: navIndicator
                                x: 0
                                y: root.currentNavIndex * 38
                                width: parent.width
                                height: 34
                                radius: Theme.r(10)
                                color: Theme.primary
                                border.width: Theme.isSimple ? 1 : 0
                                border.color: Theme.primary

                                Behavior on y {
                                    enabled: !Theme.isSimple
                                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                }
                            }

                            ColumnLayout {
                                id: navCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                spacing: 4

                                Repeater {
                                    model: root.navItems

                                    delegate: Rectangle {
                                        id: navBtn
                                        required property var modelData
                                        readonly property bool isSelected: root.resolvedPage === navBtn.modelData.id

                                        Layout.fillWidth: true
                                        implicitHeight: 34
                                        radius: Theme.r(10)
                                        color: (!navBtn.isSelected && navMouse.containsMouse) ? Theme.hoverBg : "transparent"
                                        scale: navMouse.pressed ? 0.97 : 1.0

                                        Behavior on color {
                                            enabled: !Theme.isSimple
                                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                                        }
                                        Behavior on scale {
                                            enabled: !Theme.isSimple
                                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 9

                                            Text {
                                                text: navBtn.modelData.icon
                                                font.family: Theme.iconFont
                                                font.pixelSize: 14
                                                color: navBtn.isSelected ? Theme.fgPrimary : Theme.fgSurfaceVariant

                                                Behavior on color {
                                                    enabled: !Theme.isSimple
                                                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: navBtn.modelData.label
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12
                                                font.weight: navBtn.isSelected ? Font.Bold : Font.Medium
                                                color: navBtn.isSelected ? Theme.fgPrimary : Theme.fgSurface

                                                Behavior on color {
                                                    enabled: !Theme.isSimple
                                                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: navMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.pageSelected(navBtn.modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Active Mode Pill in Footer
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 28
                            radius: Theme.r(9)
                            color: Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                spacing: 6

                                Text {
                                    text: "Mode:"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: Theme.shellMode.toUpperCase()
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }
                            }
                        }
                    }
                }

                // Vertical Hairline Divider
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Theme.isSimple ? Theme.outlineVariant : Theme.withAlpha(Theme.outlineVariant, 0.45)
                }

                // --- Right Content Area ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Page Header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 16
                        Layout.bottomMargin: 10
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: root.currentNavItem.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                text: root.currentNavItem.sub
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: Theme.r(14)
                            color: closeBtnMouse.containsMouse
                                ? Theme.withAlpha(Theme.error, 0.22)
                                : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder
                            scale: closeBtnMouse.pressed ? 0.90 : 1.0

                            Behavior on color {
                                enabled: !Theme.isSimple
                                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
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
                                color: closeBtnMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: closeBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeRequested()
                            }
                        }
                    }

                    // Horizontal Hairline Divider
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.isSimple ? Theme.outlineVariant : Theme.withAlpha(Theme.outlineVariant, 0.35)
                    }

                    // Scrollable Page Container with Animated Page Entry
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 16

                        Flickable {
                            id: scrollFlick
                            anchors.fill: parent
                            clip: true
                            contentWidth: width
                            contentHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
                            boundsBehavior: Flickable.StopAtBounds

                            Loader {
                                id: pageLoader
                                width: scrollFlick.width
                                source: root.pageSource

                                ParallelAnimation {
                                    id: pageEnterAnim
                                    NumberAnimation {
                                        target: pageLoader
                                        property: "opacity"
                                        from: 0.0
                                        to: 1.0
                                        duration: 180
                                        easing.type: Easing.OutCubic
                                    }
                                    NumberAnimation {
                                        target: pageLoader
                                        property: "y"
                                        from: 10
                                        to: 0
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                onLoaded: {
                                    scrollFlick.contentY = 0;
                                    if (!Theme.isSimple) {
                                        pageEnterAnim.restart();
                                    } else {
                                        pageLoader.opacity = 1.0;
                                        pageLoader.y = 0;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
