pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../settings"

Rectangle {
    id: drawer

    required property FileStyleHelper fileStyle
    signal closeRequested()
    signal customHexSubmitted(string hex)

    radius: Theme.r(16)
    color: Theme.isSimple ? Theme.surfaceContainerLow : Theme.notchBg
    border.width: Math.max(1, Theme.cardBorderWidth)
    border.color: fileStyle.borderCol
    clip: true

    property string hexDraft: ShellState.fmAccentOverride

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Drawer Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "󰏘"
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(15)
                color: drawer.fileStyle.accent
            }

            Text {
                Layout.fillWidth: true
                text: "Customize File Manager"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(13)
                font.weight: Font.Bold
                color: Theme.fgSurface
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: rstLbl.implicitWidth + 14
                radius: Theme.r(8)
                color: rstMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.22) : Theme.subCardBg
                border.width: 1
                border.color: Theme.cardBorder

                Text {
                    id: rstLbl
                    anchors.centerIn: parent
                    text: "󰑐 Reset Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.warning
                }

                MouseArea {
                    id: rstMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ShellState.resetFiles()
                }
            }

            Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: Theme.r(8)
                color: clsMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(12)
                    color: Theme.fgSurfaceVariant
                }

                MouseArea {
                    id: clsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: drawer.closeRequested()
                }
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: drawer.width - 28
                spacing: 12

                // 1. One-Click Style & Workflow Presets
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Quick workflow presets"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgSurfaceVariant
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 6

                        Repeater {
                            model: [
                                { id: "finder",    icon: "󰕮", title: "Finder Columns", desc: "3-pane Miller + preview" },
                                { id: "minimal",   icon: "󰘔", title: "Minimal Zen",    desc: "Compact OLED monochrome" },
                                { id: "gallery",   icon: "󰈟", title: "Media Gallery",  desc: "Large thumbnails + glass" },
                                { id: "commander", icon: "󰝰", title: "Commander",      desc: "Dual-pane split + perms" }
                            ]

                            delegate: Rectangle {
                                id: fmPresetCard
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 46
                                radius: Theme.r(10)
                                color: fpMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                                border.width: 1
                                border.color: fpMouse.containsMouse ? drawer.fileStyle.accent : Theme.cardBorder

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Text {
                                        text: fmPresetCard.modelData.icon
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.fs(16)
                                        color: drawer.fileStyle.accent
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Text {
                                            text: fmPresetCard.modelData.title
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(11)
                                            font.weight: Font.Bold
                                            color: Theme.fgSurface
                                        }
                                        Text {
                                            text: fmPresetCard.modelData.desc
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(9)
                                            color: Theme.fgSurfaceVariant
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: fpMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ShellState.applyFmPreset(fmPresetCard.modelData.id)
                                }
                            }
                        }
                    }
                }

                // 2. Layout & Panes
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: layCol.implicitHeight + 20
                    radius: Theme.r(12)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: layCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            text: "Layout & window"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        // View Mode
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 82; text: "View Mode"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "list",   label: "List" },
                                    { id: "grid",   label: "Grid" },
                                    { id: "miller", label: "Miller" }
                                ]
                                delegate: Rectangle {
                                    id: vmBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmViewMode === vmBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (vmMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: vmBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: vmBtn.sel ? Font.Bold : Font.Normal; color: vmBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: vmMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmViewMode", vmBtn.modelData.id) }
                                }
                            }
                        }

                        // Window Size
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 82; text: "Window Size"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "compact",  label: "S" },
                                    { id: "balanced", label: "M" },
                                    { id: "wide",     label: "L" },
                                    { id: "max",      label: "Max" }
                                ]
                                delegate: Rectangle {
                                    id: wsBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmWindowSize === wsBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (wsMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: wsBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: wsBtn.sel ? Font.Bold : Font.Normal; color: wsBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: wsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmWindowSize", wsBtn.modelData.id) }
                                }
                            }
                        }

                        // Sidebar Style
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 82; text: "Sidebar"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "standard", label: "Full" },
                                    { id: "compact",  label: "Slim" },
                                    { id: "icons",    label: "Icons" }
                                ]
                                delegate: Rectangle {
                                    id: sbBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmSidebarStyle === sbBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (sbMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: sbBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: sbBtn.sel ? Font.Bold : Font.Normal; color: sbBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: sbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmSidebarStyle", sbBtn.modelData.id) }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Dual-Pane Split View (F3)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmDualPane; onToggled: ShellState.setPref("fmDualPane", !ShellState.fmDualPane) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show Left Sidebar"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmSidebarVisible; onToggled: ShellState.setPref("fmSidebarVisible", !ShellState.fmSidebarVisible) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show Inspector / Preview Pane"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmPreviewVisible; onToggled: ShellState.setPref("fmPreviewVisible", !ShellState.fmPreviewVisible) }
                        }
                    }
                }

                // 3. Appearance & Live Skinning
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: appCol.implicitHeight + 20
                    radius: Theme.r(12)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: appCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            text: "Surface, color & typography"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        // Surface Finish
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: [
                                    { id: "inherit", label: "Theme" },
                                    { id: "glass",   label: "Glass" },
                                    { id: "solid",   label: "Solid" },
                                    { id: "oled",    label: "OLED" },
                                    { id: "tinted",  label: "Tint" }
                                ]
                                delegate: Rectangle {
                                    id: sfBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmSurfacePreset === sfBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (sfMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: sfBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: sfBtn.sel ? Font.Bold : Font.Normal; color: sfBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: sfMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmSurfacePreset", sfBtn.modelData.id) }
                                }
                            }
                        }

                        StepControl {
                            label: "Window Opacity"
                            displayValue: Math.round(ShellState.fmOpacity * 100) + "%"
                            onDecremented: ShellState.setPref("fmOpacity", Math.max(0.55, Math.round((ShellState.fmOpacity - 0.05) * 100) / 100))
                            onIncremented: ShellState.setPref("fmOpacity", Math.min(1.0, Math.round((ShellState.fmOpacity + 0.05) * 100) / 100))
                        }

                        // Accent Override Swatches
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Text {
                                text: "Accent Override (empty = follow live Theme)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                color: Theme.fgSurface
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Rectangle {
                                    implicitHeight: 22
                                    implicitWidth: 46
                                    radius: Theme.r(7)
                                    color: ShellState.fmAccentOverride === "" ? Theme.withAlpha(Theme.primary, 0.22) : Theme.subCardBg
                                    border.width: 1
                                    border.color: ShellState.fmAccentOverride === "" ? Theme.primary : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: "Auto"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.Bold; color: Theme.fgSurface }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmAccentOverride", "") }
                                }

                                Repeater {
                                    model: ["#cba6f7", "#89b4fa", "#a6e3a1", "#f9e2af", "#f38ba8", "#94e2d5", "#ff9e64"]
                                    delegate: Rectangle {
                                        id: swDot
                                        required property string modelData
                                        readonly property bool sel: ShellState.fmAccentOverride.toLowerCase() === swDot.modelData
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        radius: Theme.r(11)
                                        color: swDot.modelData
                                        border.width: sel ? 2 : 1
                                        border.color: sel ? Theme.fgSurface : Theme.outlineVariant
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmAccentOverride", swDot.modelData) }
                                    }
                                }
                            }
                        }

                        // Icon Color Style
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 74; text: "Icon Colors"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "category", label: "Theme" },
                                    { id: "vivid",    label: "Vivid" },
                                    { id: "accent",   label: "Accent" },
                                    { id: "mono",     label: "Mono" }
                                ]
                                delegate: Rectangle {
                                    id: icBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmIconStyle === icBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (icMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: icBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: icBtn.sel ? Font.Bold : Font.Normal; color: icBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: icMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmIconStyle", icBtn.modelData.id) }
                                }
                            }
                        }

                        // Header Chrome
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 74; text: "Header Bar"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "pill",      label: "Pill" },
                                    { id: "minimal",   label: "Minimal" },
                                    { id: "underline", label: "Bar" }
                                ]
                                delegate: Rectangle {
                                    id: hdBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmHeaderStyle === hdBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (hdMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: hdBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: hdBtn.sel ? Font.Bold : Font.Normal; color: hdBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: hdMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmHeaderStyle", hdBtn.modelData.id) }
                                }
                            }
                        }

                        // Row Density
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 74; text: "Density"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "compact",  label: "Compact" },
                                    { id: "cozy",     label: "Cozy" },
                                    { id: "spacious", label: "Spacious" }
                                ]
                                delegate: Rectangle {
                                    id: dnBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmDensity === dnBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (dnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: dnBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: dnBtn.sel ? Font.Bold : Font.Normal; color: dnBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: dnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmDensity", dnBtn.modelData.id) }
                                }
                            }
                        }

                        StepControl {
                            label: "Grid Tile Size"
                            displayValue: ShellState.fmGridSize + " px"
                            onDecremented: ShellState.setPref("fmGridSize", Math.max(84, ShellState.fmGridSize - 10))
                            onIncremented: ShellState.setPref("fmGridSize", Math.min(164, ShellState.fmGridSize + 10))
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Alternating Zebra Rows"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmRowAlternating; onToggled: ShellState.setPref("fmRowAlternating", !ShellState.fmRowAlternating) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show Selection Checkboxes"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmShowCheckboxes; onToggled: ShellState.setPref("fmShowCheckboxes", !ShellState.fmShowCheckboxes) }
                        }
                    }
                }

                // 4. Files & Columns
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: colOpts.implicitHeight + 20
                    radius: Theme.r(12)
                    color: Theme.cardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    ColumnLayout {
                        id: colOpts
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Text {
                            text: "Files, columns & startup"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgSurfaceVariant
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show Hidden Files (Ctrl+H)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmShowHidden; onToggled: ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Image Thumbnails in Grid"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmShowThumbnails; onToggled: ShellState.setPref("fmShowThumbnails", !ShellState.fmShowThumbnails) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Folders Always First"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmDirsFirst; onToggled: ShellState.setPref("fmDirsFirst", !ShellState.fmDirsFirst) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show File Sizes Column"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmShowSizes; onToggled: ShellState.setPref("fmShowSizes", !ShellState.fmShowSizes) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show Modified Dates Column"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmShowDates; onToggled: ShellState.setPref("fmShowDates", !ShellState.fmShowDates) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "Show Permissions Column"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            ToggleSwitch { checked: ShellState.fmShowPerms; onToggled: ShellState.setPref("fmShowPerms", !ShellState.fmShowPerms) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { Layout.preferredWidth: 78; text: "Start Folder"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurface }
                            Repeater {
                                model: [
                                    { id: "~",      label: "Home" },
                                    { id: "@last",  label: "Remember Last" }
                                ]
                                delegate: Rectangle {
                                    id: stBtn
                                    required property var modelData
                                    readonly property bool sel: ShellState.fmStartDir === stBtn.modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 24
                                    radius: Theme.r(7)
                                    color: sel ? Theme.withAlpha(drawer.fileStyle.accent, 0.22) : (stMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                                    border.width: 1
                                    border.color: sel ? drawer.fileStyle.accent : Theme.cardBorder
                                    Text { anchors.centerIn: parent; text: stBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: stBtn.sel ? Font.Bold : Font.Normal; color: stBtn.sel ? drawer.fileStyle.accent : Theme.fgSurface }
                                    MouseArea { id: stMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("fmStartDir", stBtn.modelData.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
