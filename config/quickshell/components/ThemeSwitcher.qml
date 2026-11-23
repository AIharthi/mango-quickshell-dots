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
    spacing: 10

    // --- Apple Segmented Mode, Shuffle, Studio & Dark/Light Bar ---
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 34
        Layout.minimumHeight: 34
        Layout.maximumHeight: 34
        spacing: 8

        // Dynamic / Presets / Accent Mode Switch
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
                spacing: 2

                Repeater {
                    model: [
                        { id: "dynamic", label: "Dynamic", icon: "󰚰" },
                        { id: "preset",  label: "Presets", icon: "󰏘" },
                        { id: "accent",  label: "Accent",  icon: "󰌁" }
                    ]

                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === modeBtn.modelData.id

                        implicitHeight: 26
                        implicitWidth: modeContent.implicitWidth + 14
                        radius: Theme.r(13)
                        color: modeBtn.selected
                            ? Theme.primary
                            : (modeMouse.containsMouse ? Theme.hoverBg : "transparent")

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

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

        // Shuffle Wallpaper Capsule
        Rectangle {
            implicitHeight: 32
            implicitWidth: rndLbl.implicitWidth + 16
            radius: Theme.r(16)
            color: rndMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            scale: rndMouse.pressed ? 0.95 : 1.0

            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

            Text {
                id: rndLbl
                anchors.centerIn: parent
                text: "󰒝 Shuffle"
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
            implicitHeight: 32
            implicitWidth: stuLbl.implicitWidth + 16
            radius: Theme.r(16)
            color: stuMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            scale: stuMouse.pressed ? 0.95 : 1.0

            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

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
            Layout.maximumWidth: 120
            elide: Text.ElideRight
            text: Theme.applyingTheme ? "Applying..." : Theme.lastError
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.weight: Font.Medium
            color: Theme.applyingTheme ? Theme.primary : Theme.error
        }

        // Dark / Light Appearance Toggle Capsule
        Rectangle {
            implicitHeight: 32
            implicitWidth: schemeRow.implicitWidth + 16
            radius: Theme.r(16)
            color: schemeArea.containsMouse ? Theme.hoverBg : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder
            scale: schemeArea.pressed ? 0.95 : 1.0

            Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

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

    // --- 16 Presets Card (shown cleanly in Presets mode) ---
    Rectangle {
        visible: Theme.themeMode === "preset"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 74
        Layout.minimumHeight: 74
        Layout.maximumHeight: 74
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        Flickable {
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: presetFlow.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Flow {
                id: presetFlow
                width: parent.width
                spacing: 5

                Repeater {
                    model: Theme.availablePresets

                    delegate: Rectangle {
                        id: presetChip
                        required property var modelData
                        readonly property bool isSelected: Theme.themeMode === "preset" && Theme.presetName === presetChip.modelData.id

                        implicitHeight: 26
                        implicitWidth: presetChipRow.implicitWidth + 12
                        radius: Theme.r(13)
                        color: presetChip.isSelected
                            ? Theme.activeBg
                            : (presetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: presetChip.isSelected ? 1 : Theme.cardBorderWidth
                        border.color: presetChip.isSelected ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            id: presetChipRow
                            anchors.centerIn: parent
                            spacing: 5

                            Rectangle {
                                implicitWidth: 9
                                implicitHeight: 9
                                radius: 4.5
                                color: presetChip.modelData.swatch
                            }

                            Text {
                                text: presetChip.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
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
    }

    // --- Quick Apple Color Droplets (shown cleanly in Accent mode) ---
    Rectangle {
        visible: Theme.themeMode === "accent"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 46
        Layout.minimumHeight: 46
        Layout.maximumHeight: 46
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        RowLayout {
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: "SEED"
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: ["#cba6f7", "#89b4fa", "#7aa2f7", "#9ece6a", "#fabd2f", "#fe8019", "#f38ba8", "#ff7eb6", "#00f0ff", "#ebbcba", "#268bd2", "#a7c080"]

                delegate: Rectangle {
                    id: accChip
                    required property string modelData
                    readonly property bool isSelected: Theme.accentColor.toLowerCase() === accChip.modelData.toLowerCase()

                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 13
                    color: accChip.modelData
                    border.width: accChip.isSelected ? 2 : 1
                    border.color: accChip.isSelected ? Theme.fgSurface : Qt.rgba(1, 1, 1, 0.16)
                    scale: accChip.isSelected ? 1.12 : (accMouse.containsMouse ? 1.08 : 1.0)

                    Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        visible: accChip.isSelected
                        text: "󰄬"
                        font.family: Theme.iconFont
                        font.pixelSize: 12
                        color: "#11111b"
                    }

                    MouseArea {
                        id: accMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.applyAccentColor(accChip.modelData)
                    }
                }
            }
        }
    }

    // --- macOS Wallpaper Gallery Card (~/Pictures/Wallpapers) ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(18)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        FolderListModel {
            id: wallpaperFolder
            readonly property string rawDir: (ShellState.wallpaperDir && ShellState.wallpaperDir.length > 0)
                ? ShellState.wallpaperDir
                : "~/Pictures/Wallpapers"
            readonly property string expandedDir: rawDir.startsWith("~/")
                ? (Quickshell.env("HOME") + rawDir.slice(1))
                : (rawDir === "~" ? Quickshell.env("HOME") : rawDir)
            folder: "file://" + expandedDir.replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F")
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.PNG", "*.JPG", "*.JPEG", "*.WEBP"]
            showDirs: false
            sortField: FolderListModel.Name
        }

        GridView {
            id: wallpaperGrid
            anchors.fill: parent
            anchors.margins: 10
            cellWidth: Math.floor(width / 3)
            cellHeight: 124
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
                    radius: Theme.r(14)
                    color: wallDelegate.isCurrent ? Theme.primary : Theme.subCardBg
                    scale: wallArea.containsMouse ? 1.02 : 1.0

                    Behavior on scale {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: wallDelegate.isCurrent ? 2 : 0
                        radius: Theme.r(12)
                        color: Theme.surfaceContainerLowest
                        contentUnderBorder: false
                        contentInsideBorder: true

                        Image {
                            anchors.fill: parent
                            source: wallDelegate.fileUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(260, 150)
                        }

                        // Soft Bottom Gradient Scrim
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 30
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.74) }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9
                                anchors.bottomMargin: 5
                                text: wallDelegate.fileName
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: wallDelegate.isCurrent ? Font.Bold : Font.Medium
                                color: "#ffffff"
                            }
                        }

                        // Floating Circular Checkmark Badge
                        Rectangle {
                            visible: wallDelegate.isCurrent
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 7
                            width: 22
                            height: 22
                            radius: Theme.r(11)
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
        ColumnLayout {
            anchors.centerIn: parent
            visible: wallpaperFolder.count === 0
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰸉"
                font.family: Theme.iconFont
                font.pixelSize: 30
                color: Theme.fgSurfaceVariant
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "No wallpapers found in ~/Pictures/Wallpapers"
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
