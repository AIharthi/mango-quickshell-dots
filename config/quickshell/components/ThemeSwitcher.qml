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
    signal openSettingsRequested(string page)
    spacing: 8

    // --- Mode, Dark/Light, Random & Studio Controls Bar ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        // Dynamic / Presets / Accent Mode Switch
        Rectangle {
            implicitHeight: 30
            implicitWidth: modeRow.implicitWidth + 6
            radius: Theme.r(15)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: modeRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: [
                        { id: "dynamic", label: "Matugen", icon: "󰚰" },
                        { id: "preset",  label: "Presets", icon: "󰏘" },
                        { id: "accent",  label: "Seed",    icon: "󰌁" }
                    ]

                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === modeBtn.modelData.id

                        implicitHeight: 24
                        implicitWidth: modeContent.implicitWidth + 12
                        radius: Theme.r(12)
                        color: modeBtn.selected
                            ? Theme.primary
                            : (modeMouse.containsMouse ? Theme.hoverBg : "transparent")

                        RowLayout {
                            id: modeContent
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: modeBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: modeBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }
                            Text {
                                text: modeBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
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

        // Random Wallpaper Button
        Rectangle {
            implicitHeight: 30
            implicitWidth: rndLbl.implicitWidth + 14
            radius: Theme.r(15)
            color: rndMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            Text {
                id: rndLbl
                anchors.centerIn: parent
                text: "󰒝 Random"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.secondary
            }

            MouseArea {
                id: rndMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Theme.randomWallpaper()
            }
        }

        // Studio Button
        Rectangle {
            implicitHeight: 30
            implicitWidth: stuLbl.implicitWidth + 14
            radius: Theme.r(15)
            color: stuMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            Text {
                id: stuLbl
                anchors.centerIn: parent
                text: "Studio →"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.primary
            }

            MouseArea {
                id: stuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSettingsRequested("themes")
            }
        }

        Item { Layout.fillWidth: true }

        // Status / Error Indicator
        Text {
            visible: Theme.applyingTheme || Theme.lastError.length > 0
            Layout.maximumWidth: 110
            elide: Text.ElideRight
            text: Theme.applyingTheme ? "Applying..." : Theme.lastError
            font.family: Theme.fontFamily
            font.pixelSize: 9
            color: Theme.applyingTheme ? Theme.primary : Theme.error
        }

        // Dark / Light Scheme Toggle
        Rectangle {
            implicitHeight: 30
            implicitWidth: schemeRow.implicitWidth + 16
            radius: Theme.r(15)
            color: schemeArea.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: schemeRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: Theme.colorScheme === "dark" ? "󰖔" : "󰖙"
                    font.family: Theme.iconFont
                    font.pixelSize: 13
                    color: Theme.primary
                }

                Text {
                    text: Theme.colorScheme === "dark" ? "Dark" : "Light"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
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

    // --- 16 Presets Compact Wrap Row (Scrollable 2-row height) OR Quick Accent Swatches ---
    Flickable {
        visible: Theme.themeMode !== "accent"
        Layout.fillWidth: true
        implicitHeight: 62
        contentWidth: width
        contentHeight: presetFlow.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Flow {
            id: presetFlow
            width: parent.width
            spacing: 6

            Repeater {
                model: Theme.availablePresets

                delegate: Rectangle {
                    id: presetChip
                    required property var modelData
                    readonly property bool isSelected: Theme.themeMode === "preset" && Theme.presetName === presetChip.modelData.id

                    implicitHeight: 27
                    implicitWidth: presetChipRow.implicitWidth + 14
                    radius: Theme.r(9)
                    color: presetChip.isSelected
                        ? Theme.activeBg
                        : (presetMouse.containsMouse ? Theme.hoverBg : Theme.cardBg)
                    border.width: presetChip.isSelected ? 1 : Theme.cardBorderWidth
                    border.color: presetChip.isSelected ? Theme.primary : Theme.cardBorder

                    RowLayout {
                        id: presetChipRow
                        anchors.centerIn: parent
                        spacing: 5

                        Rectangle {
                            implicitWidth: 10
                            implicitHeight: 10
                            radius: Theme.r(5)
                            color: presetChip.modelData.swatch
                        }

                        Text {
                            text: presetChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
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
    }

    // Quick Seed Accent Color Swatches (shown in Seed mode)
    Flow {
        visible: Theme.themeMode === "accent"
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: ["#cba6f7", "#89b4fa", "#7aa2f7", "#9ece6a", "#fabd2f", "#fe8019", "#f38ba8", "#ff7eb6", "#00f0ff", "#ebbcba", "#268bd2", "#a7c080"]

            delegate: Rectangle {
                id: accChip
                required property string modelData
                readonly property bool isSelected: Theme.accentColor.toLowerCase() === accChip.modelData.toLowerCase()
                implicitHeight: 26
                implicitWidth: 40
                radius: Theme.r(8)
                color: accChip.modelData
                border.width: accChip.isSelected ? 2 : 0
                border.color: Theme.fgSurface

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.applyAccentColor(accChip.modelData)
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
