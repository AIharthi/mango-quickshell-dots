pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import ".."

ColumnLayout {
    id: root

    property bool active: false
    spacing: 10

    // --- Mode, Dark/Light & Preset Controls Bar ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        // Dynamic (Matugen) vs Preset Mode Switch
        Rectangle {
            implicitHeight: 32
            implicitWidth: modeRow.implicitWidth + 6
            radius: Theme.r(16)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: modeRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: [
                        { id: "dynamic", label: "Dynamic (Matugen)", icon: "󰚰" },
                        { id: "preset",  label: "Presets",           icon: "󰏘" }
                    ]

                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === modeBtn.modelData.id

                        implicitHeight: 26
                        implicitWidth: modeContent.implicitWidth + 16
                        radius: Theme.r(13)
                        color: modeBtn.selected
                            ? Theme.primary
                            : (modeMouse.containsMouse ? Theme.hoverBg : "transparent")

                        RowLayout {
                            id: modeContent
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: modeBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 12
                                color: modeBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }
                            Text {
                                text: modeBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                font.weight: modeBtn.selected ? Font.Bold : Font.Medium
                                color: modeBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setMode(modeBtn.modelData.id)
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Status / Error Indicator
        Text {
            visible: Theme.applyingTheme || Theme.lastError.length > 0
            Layout.maximumWidth: 210
            elide: Text.ElideRight
            text: Theme.applyingTheme ? "Applying palette..." : Theme.lastError
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.applyingTheme ? Theme.primary : Theme.error
        }

        // Dark / Light Scheme Toggle
        Rectangle {
            implicitHeight: 32
            implicitWidth: schemeRow.implicitWidth + 20
            radius: Theme.r(16)
            color: schemeArea.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: schemeRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: Theme.colorScheme === "dark" ? "󰖔" : "󰖙"
                    font.family: Theme.iconFont
                    font.pixelSize: 14
                    color: Theme.primary
                }

                Text {
                    text: Theme.colorScheme === "dark" ? "Dark" : "Light"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: schemeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.toggleScheme()
            }
        }
    }

    // --- 4 Preset Theme Chips ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: Theme.availablePresets

            delegate: Rectangle {
                id: presetChip
                required property var modelData
                readonly property bool isSelected: Theme.themeMode === "preset" && Theme.presetName === presetChip.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: 34
                radius: Theme.r(12)
                color: presetChip.isSelected
                    ? Theme.activeBg
                    : (presetMouse.containsMouse ? Theme.hoverBg : Theme.cardBg)
                border.width: Theme.cardBorderWidth
                border.color: presetChip.isSelected ? Theme.primary : Theme.cardBorder

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 7

                    Rectangle {
                        implicitWidth: 12
                        implicitHeight: 12
                        radius: Theme.r(6)
                        color: presetChip.modelData.swatch
                        border.width: 0
                    }

                    Text {
                        text: presetChip.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: presetChip.isSelected ? Font.Bold : Font.Medium
                        color: presetChip.isSelected ? Theme.primary : Theme.fgSurface
                    }
                }

                MouseArea {
                    id: presetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.applyPreset(presetChip.modelData.id)
                }
            }
        }
    }

    // --- Wallpaper Thumbnail Grid (~/Pictures/Wallpapers) ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        FolderListModel {
            id: wallpaperFolder
            folder: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
            showDirs: false
            sortField: FolderListModel.Name
        }

        GridView {
            id: wallpaperGrid
            anchors.fill: parent
            anchors.margins: 10
            cellWidth: Math.floor(width / 3)
            cellHeight: 118
            clip: true
            model: wallpaperFolder

            delegate: Item {
                id: wallDelegate
                required property string filePath
                required property url fileUrl
                required property string fileName

                readonly property bool isCurrent: Theme.wallpaperPath === wallDelegate.filePath

                width: wallpaperGrid.cellWidth
                height: wallpaperGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: Theme.r(12)
                    color: wallDelegate.isCurrent ? Theme.primary : Theme.subCardBg
                    border.width: 0

                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: wallDelegate.isCurrent ? 2 : 0
                        radius: Theme.r(10)
                        color: Theme.surfaceContainerLowest

                        Image {
                            anchors.fill: parent
                            source: wallDelegate.fileUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize: Qt.size(240, 140)
                        }

                        // Filename Scrim Overlay
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 24
                            color: Qt.rgba(0, 0, 0, 0.58)

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                text: wallDelegate.fileName
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: wallDelegate.isCurrent ? Font.Bold : Font.Normal
                                color: "#ffffff"
                            }
                        }

                        // Active Badge
                        Rectangle {
                            visible: wallDelegate.isCurrent
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 20
                            height: 20
                            radius: Theme.r(10)
                            color: Theme.primary

                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                font.family: Theme.iconFont
                                font.pixelSize: 12
                                color: Theme.fgPrimary
                            }
                        }
                    }

                    MouseArea {
                        id: wallArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Theme.themeMode === "dynamic")
                                Theme.applyDynamicWallpaper(wallDelegate.filePath);
                            else
                                Theme.applyWallpaperWithCurrentMode(wallDelegate.filePath);
                        }
                    }
                }
            }
        }

        // Empty State Hint
        Text {
            anchors.centerIn: parent
            visible: wallpaperFolder.count === 0
            text: "No wallpapers found in ~/Pictures/Wallpapers"
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fgSurfaceVariant
        }
    }
}
