pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root

    property string activePage: "appearance"
    signal pageSelected(string page)
    signal closeRequested()

    readonly property var navItems: {
        const items = [
            { id: "appearance", label: "Appearance", icon: "󰏘", source: "AppearancePage.qml", sub: "Modes, Matugen palette & MangoWC effects" }
        ];
        if (DeviceCaps.hasAudio)
            items.push({ id: "audio", label: "Audio", icon: "󰋋", source: "AudioPage.qml", sub: "Output sinks, microphones & volume" });
        if (DeviceCaps.hasWlrRandr)
            items.push({ id: "displays", label: "Displays", icon: "󰍹", source: "DisplayPage.qml", sub: "Resolution, refresh rate & scaling" });
        if (DeviceCaps.hasWifi)
            items.push({ id: "network", label: "Network", icon: "󰤨", source: "NetworkPage.qml", sub: "Wi-Fi radio & nearby networks" });
        if (DeviceCaps.hasBluetooth)
            items.push({ id: "bluetooth", label: "Bluetooth", icon: "󰂯", source: "BluetoothPage.qml", sub: "Adapter power & paired devices" });
        items.push({ id: "input",  label: "Input",  icon: "󰌌", source: "InputPage.qml",  sub: "Keyboard layouts, mouse & trackpad" });
        items.push({ id: "system", label: "System", icon: "󰋼", source: "SystemPage.qml", sub: "Hardware probe, power & local.conf" });
        return items;
    }

    readonly property var currentNavItem: {
        for (let i = 0; i < navItems.length; i++) {
            if (navItems[i].id === root.activePage)
                return navItems[i];
        }
        return navItems[0];
    }

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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.closeRequested()

        // Dimmed scrim backdrop (click outside to close)
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, Theme.isSimple ? 0.56 : 0.44)

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeRequested()
            }
        }

        // Centered Settings Dialog
        Rectangle {
            id: dialog
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 800)
            height: Math.min(parent.height - 48, 540)
            radius: Theme.r(22)
            color: Theme.notchBg
            border.width: Theme.islandBorderWidth
            border.color: Theme.islandBorder
            clip: true

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

                        // Dynamic Navigation Links
                        ColumnLayout {
                            Layout.fillWidth: true
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
                                    color: navBtn.isSelected
                                        ? Theme.primary
                                        : (navMouse.containsMouse ? Theme.hoverBg : "transparent")
                                    border.width: (Theme.isSimple && navBtn.isSelected) ? 1 : 0
                                    border.color: Theme.primary

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
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: navBtn.modelData.label
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 12
                                            font.weight: navBtn.isSelected ? Font.Bold : Font.Medium
                                            color: navBtn.isSelected ? Theme.fgPrimary : Theme.fgSurface
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

                    // Scrollable Page Container
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
                                onLoaded: scrollFlick.contentY = 0
                            }
                        }
                    }
                }
            }
        }
    }
}
