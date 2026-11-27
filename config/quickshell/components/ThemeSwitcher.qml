pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import ".."
import "../m3"

ColumnLayout {
    id: root

    property bool active: false
    readonly property bool narrowLayout: root.width < 520
    signal openSettingsRequested(string page)
    spacing: 10

    function formatWallpaperName(fname: string): string {
        const clean = String(fname || "")
            .replace(/\.(png|jpe?g|webp|bmp|avif)$/i, "")
            .replace(/[_-]+/g, " ")
            .replace(/\s+/g, " ")
            .trim();
        return clean.length > 0 ? clean : String(fname || "");
    }

    // --- Responsive Segmented Mode, Shuffle, Studio & Dark/Light Bar ---
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 36
            spacing: 8

            // Dynamic / Presets / Accent Mode Switch
            Rectangle {
                implicitHeight: 36
                implicitWidth: modeRow.implicitWidth + 8
                radius: Theme.r(18)
                color: Theme.m3SurfaceC
                border.width: 1
                border.color: Theme.m3Line

                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 3

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

                            implicitHeight: 28
                            implicitWidth: modeContent.implicitWidth + 14
                            radius: Theme.r(modeBtn.selected ? 11 : 14)
                            color: modeBtn.selected
                                ? Theme.m3Primary
                                : (modeMouse.containsMouse ? Theme.m3SurfaceHigh : "transparent")

                            Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on color { enabled: !Theme.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            RowLayout {
                                id: modeContent
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: modeBtn.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: 11
                                    color: modeBtn.selected ? Theme.m3OnPrimary : Theme.m3InkDim
                                }
                                Text {
                                    text: modeBtn.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    font.weight: modeBtn.selected ? Font.Bold : Font.Medium
                                    color: modeBtn.selected ? Theme.m3OnPrimary : Theme.m3InkDim
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

            // Shuffle Wallpaper Capsule (wide row)
            Rectangle {
                visible: !root.narrowLayout
                implicitHeight: 34
                implicitWidth: rndLbl.implicitWidth + 18
                radius: Theme.r(rndMouse.pressed ? 11 : 17)
                color: rndMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                scale: rndMouse.pressed ? 0.96 : 1.0

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    id: rndLbl
                    anchors.centerIn: parent
                    text: "󰒝 Shuffle"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.m3OnSecondaryContainer
                }

                MouseArea {
                    id: rndMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.randomWallpaper()
                }
            }

            // Studio Button (wide row)
            Rectangle {
                visible: !root.narrowLayout
                implicitHeight: 34
                implicitWidth: stuLbl.implicitWidth + 18
                radius: Theme.r(stuMouse.pressed ? 11 : 17)
                color: stuMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                scale: stuMouse.pressed ? 0.96 : 1.0

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    id: stuLbl
                    anchors.centerIn: parent
                    text: "Studio"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.m3Primary
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

            // Status / Error Indicator (wide row)
            Text {
                visible: !root.narrowLayout && (Theme.applyingTheme || Theme.lastError.length > 0)
                Layout.maximumWidth: 120
                elide: Text.ElideRight
                text: Theme.applyingTheme ? "Applying..." : Theme.lastError
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Medium
                color: Theme.applyingTheme ? Theme.m3Primary : Theme.m3Error
            }

            // Dark / Light Appearance Toggle Capsule
            Rectangle {
                implicitHeight: 34
                implicitWidth: schemeRow.implicitWidth + 18
                radius: Theme.r(schemeArea.pressed ? 11 : 17)
                color: schemeArea.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SecondaryContainer
                scale: schemeArea.pressed ? 0.96 : 1.0

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                RowLayout {
                    id: schemeRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: Theme.colorScheme === "dark" ? "󰖔" : "󰖙"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: Theme.m3OnSecondaryContainer
                    }

                    Text {
                        text: Theme.colorScheme === "dark" ? "Dark" : "Light"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.m3OnSecondaryContainer
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

        // Narrow-width Wrap Row (Shuffle, Studio, Status)
        RowLayout {
            visible: root.narrowLayout
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 32
            spacing: 8

            Rectangle {
                implicitHeight: 32
                implicitWidth: rndLblNarrow.implicitWidth + 18
                radius: Theme.r(rndMouseNarrow.pressed ? 11 : 16)
                color: rndMouseNarrow.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                scale: rndMouseNarrow.pressed ? 0.96 : 1.0

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    id: rndLblNarrow
                    anchors.centerIn: parent
                    text: "󰒝 Shuffle"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.m3OnSecondaryContainer
                }

                MouseArea {
                    id: rndMouseNarrow
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.randomWallpaper()
                }
            }

            Rectangle {
                implicitHeight: 32
                implicitWidth: stuLblNarrow.implicitWidth + 18
                radius: Theme.r(stuMouseNarrow.pressed ? 11 : 16)
                color: stuMouseNarrow.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh
                scale: stuMouseNarrow.pressed ? 0.96 : 1.0

                Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    id: stuLblNarrow
                    anchors.centerIn: parent
                    text: "Studio"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.m3Primary
                }

                MouseArea {
                    id: stuMouseNarrow
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openSettingsRequested("themes")
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: Theme.applyingTheme || Theme.lastError.length > 0
                Layout.maximumWidth: 120
                elide: Text.ElideRight
                text: Theme.applyingTheme ? "Applying..." : Theme.lastError
                font.family: Theme.fontFamily
                font.pixelSize: 9
                font.weight: Font.Medium
                color: Theme.applyingTheme ? Theme.m3Primary : Theme.m3Error
            }
        }
    }

    // --- 16 Presets Card (shown cleanly in Presets mode) ---
    Rectangle {
        visible: Theme.themeMode === "preset"
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: Math.min(126, Math.max(74, presetFlow.implicitHeight + 18))
        Layout.minimumHeight: 72
        radius: Theme.r(24)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        Flickable {
            anchors.fill: parent
            anchors.margins: 10
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

                        implicitHeight: 28
                        implicitWidth: presetChipRow.implicitWidth + 14
                        radius: Theme.r(presetChip.isSelected ? 11 : 14)
                        color: presetChip.isSelected
                            ? Theme.m3Primary
                            : (presetMouse.containsMouse ? Theme.m3SurfaceHighest : Theme.m3SurfaceHigh)
                        Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        RowLayout {
                            id: presetChipRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: 5
                                color: presetChip.modelData.swatch
                                border.width: presetChip.isSelected ? 1 : 0
                                border.color: presetChip.isSelected ? Theme.m3OnPrimary : "transparent"
                            }

                            Text {
                                text: presetChip.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: presetChip.isSelected ? Font.Bold : Font.Medium
                                color: presetChip.isSelected ? Theme.m3OnPrimary : Theme.m3Ink
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
        Layout.preferredHeight: Math.max(52, accOuter.implicitHeight + 20)
        Layout.minimumHeight: 52
        radius: Theme.r(24)
        color: Theme.m3SurfaceC
        border.width: 1
        border.color: Theme.m3Line
        clip: true

        RowLayout {
            id: accOuter
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "Accent"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.m3InkDim
            }

            Flow {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8

                Repeater {
                    model: ["#cba6f7", "#89b4fa", "#7aa2f7", "#9ece6a", "#fabd2f", "#fe8019", "#f38ba8", "#ff7eb6", "#00f0ff", "#ebbcba", "#268bd2", "#a7c080"]

                    delegate: Rectangle {
                        id: accChip
                        required property string modelData
                        readonly property bool isSelected: Theme.accentColor.toLowerCase() === accChip.modelData.toLowerCase()

                        width: 24
                        height: 24
                        radius: accChip.isSelected ? Theme.r(8) : 12
                        color: accChip.modelData
                        border.width: accChip.isSelected ? 2 : 1
                        border.color: accChip.isSelected ? Theme.m3Ink : Theme.m3Line
                        scale: accChip.isSelected ? 1.12 : (accMouse.containsMouse ? 1.08 : 1.0)

                        Behavior on radius { enabled: !Theme.reducedMotion; NumberAnimation { duration: 140 } }
                        Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 100 } }

                        Text {
                            anchors.centerIn: parent
                            visible: accChip.isSelected
                            text: "󰄬"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: Theme.contrastInk(accChip.modelData)
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
    }

    // --- Wallpaper Gallery Card (~/Pictures/Wallpapers) ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(24)
        color: Theme.m3PaneBg
        border.width: 1
        border.color: Theme.m3Line
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
            onStatusChanged: {
                if (status === FolderListModel.Ready && !wallpaperGrid._initialScrollDone) {
                    wallpaperGrid._initialScrollDone = true;
                    Qt.callLater(() => {
                        if (!wallpaperGrid.dragging && !wallpaperGrid.flicking)
                            wallpaperGrid.positionViewAtBeginning();
                    });
                }
            }
        }

        GridView {
            id: wallpaperGrid
            property bool _initialScrollDone: false
            readonly property int gridCols: width >= 300 ? 3 : 2
            anchors.fill: parent
            anchors.margins: 10
            cellWidth: Math.floor(width / gridCols)
            cellHeight: 124
            boundsBehavior: Flickable.StopAtBounds
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
                    radius: Theme.r(20)
                    color: Theme.m3SurfaceC
                    scale: wallArea.containsMouse ? 1.02 : 1.0

                    Behavior on scale {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 0
                        radius: Theme.r(20)
                        color: Theme.m3SurfaceLowest
                        contentUnderBorder: false
                        contentInsideBorder: true
                        border.width: wallDelegate.isCurrent ? 2 : 0
                        border.color: Theme.m3Primary

                        Image {
                            anchors.fill: parent
                            source: wallDelegate.fileUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
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
                                text: root.formatWallpaperName(wallDelegate.fileName)
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
                            anchors.margins: 8
                            width: 24
                            height: 24
                            radius: Theme.r(12)
                            color: Theme.m3Primary

                            Text {
                                anchors.centerIn: parent
                                text: "󰄬"
                                font.family: Theme.iconFont
                                font.pixelSize: 12
                                color: Theme.m3OnPrimary
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
