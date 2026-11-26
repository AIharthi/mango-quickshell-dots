pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    signal openPageRequested(string page)

    property bool confirmResetSplit: false

    readonly property var podShapes: [
        { id: "pill",    label: "Floating Pill",  desc: "Full stadium capsule corners" },
        { id: "rounded", label: "Rounded Sequoia", desc: "Soft macOS squircle framing" },
        { id: "compact", label: "Compact Sharp",  desc: "Tight 8px radius telemetry pods" }
    ]

    readonly property var menuGlyphs: [
        { id: "aurora",  label: "Aurora",  glyph: "󰀻" },
        { id: "apple",   label: "Apple",   glyph: "󰀵" },
        { id: "cachyos", label: "CachyOS", glyph: "󰣇" },
        { id: "arch",    label: "Arch",    glyph: "󰣇" },
        { id: "fedora",  label: "Fedora",  glyph: "󰣛" },
        { id: "gentoo",  label: "Gentoo",  glyph: "󰣨" },
        { id: "minimal", label: "Minimal", glyph: "󰘔" }
    ]

    readonly property var splitPresets: [
        { id: "minimal",  label: "Minimal Pods",  desc: "Clean spaces, clock & audio", icon: "󰘔" },
        { id: "balanced", label: "Balanced",      desc: "Spaces, weather, media & tray", icon: "󰕰" },
        { id: "creator",  label: "Creator / Dev", desc: "CPU/RAM, net speed & all tools", icon: "󰍛" }
    ]

    readonly property var leftModules: [
        { key: "splitShowLauncherIcon", label: "Leading Pod Glyph",        sub: "Clickable icon on the far left that opens the Spaces & Quick Hub popover" },
        { key: "splitShowWorkspaces",   label: "Interactive Workspaces",   sub: "Active/occupied tag chips with wheel-scroll workspace switching" },
        { key: "splitShowLayout",       label: "Tiling Layout Badge",      sub: "Click to cycle MangoWC layout directly from the left pod" },
        { key: "splitShowAppTitle",     label: "Focused App & Title",      sub: "Show active application name and window title in the left pod" }
    ]

    readonly property var centerModules: [
        { key: "splitShowDate",    label: "Date Next to Clock",         sub: "Show formatted weekday/date beside the centered clock" },
        { key: "splitShowMedia",   label: "Media Vinyl & Track Info",   sub: "Circular spinning cover art, title & equalizer (middle-click pauses)" },
        { key: "splitShowWeather", label: "Inline Weather Chip",        sub: "Show temperature and icon when Weather Integration is enabled" }
    ]

    readonly property var rightModules: [
        { key: "splitShowSystem",   label: "CPU & RAM Percentages",      sub: "Compact processor and memory load counters inside the right pod" },
        { key: "splitShowNetSpeed", label: "Live Network Throughput",    sub: "Real-time download and upload rates in the right pod" },
        { key: "splitShowVolume",   label: "Volume Pill (Scroll & RMB)", sub: "Click to mute, scroll +/-5%, right-click to cycle output sink" },
        { key: "splitShowKbLayout", label: "Keyboard Layout Badge",      sub: "Display current XKB layout (US / AR) inside the right pod" },
        { key: "splitShowTray",     label: "System Tray Icons",          sub: "Embed StatusNotifier tray icons inside the right pod" },
        { key: "splitShowStore",    label: "App Store Button",           sub: "One-click Aurora Store launch icon in the right pod" },
        { key: "splitShowFiles",    label: "Dynamic Files Button",       sub: "One-click aurora-fm shortcut in the right pod" }
    ]

    Timer {
        id: resetConfirmTimer
        interval: 4000
        onTriggered: root.confirmResetSplit = false
    }

    // ==================== HEADER + ACTIVATION BANNER ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hdrCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: hdrCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 36; implicitHeight: 36; radius: Theme.r(10)
                    color: Theme.withAlpha(Theme.primary, 0.16)
                    border.width: 1; border.color: Theme.withAlpha(Theme.primary, 0.35)
                    Text { anchors.centerIn: parent; text: "󰕰"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(18); color: Theme.primary }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Split Islands & Per-Pod Hubs"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.weight: Font.Bold; color: Theme.fgSurface }
                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Three stationary Sequoia glass pods with dedicated popovers: Left Spaces & Quick Hub, Center Media & Focus Timer, and Right Control Center & Notifications."; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
                }

                Rectangle {
                    implicitWidth: spRstTxt.implicitWidth + 20
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: root.confirmResetSplit ? Theme.warning : (spRstMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: 1
                    border.color: root.confirmResetSplit ? Theme.warning : Theme.cardBorder

                    Text { id: spRstTxt; anchors.centerIn: parent; text: root.confirmResetSplit ? "Confirm Reset?" : "󰑐 Reset Split"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: root.confirmResetSplit ? Theme.contrastInk(Theme.warning) : Theme.warning }

                    MouseArea {
                        id: spRstMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmResetSplit) {
                                root.confirmResetSplit = true;
                                resetConfirmTimer.restart();
                                return;
                            }
                            root.confirmResetSplit = false;
                            resetConfirmTimer.stop();
                            ShellState.resetSplit();
                        }
                    }
                }
            }

            // Live Mini 3-Pod Preview Strip
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                radius: Theme.r(12)
                color: Theme.surfaceContainerLowest
                border.width: Theme.subBorderWidth
                border.color: Theme.cardBorder

                readonly property int prevRad: ShellState.splitPodStyle === "compact" ? Theme.r(7) : (ShellState.splitPodStyle === "rounded" ? Theme.r(11) : Theme.r(15))

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: prevL.implicitWidth + 16
                        radius: parent.parent.prevRad
                        color: ShellState.splitBarTranslucent ? Theme.cardBg : Theme.surfaceContainerHigh
                        border.width: 1; border.color: Theme.cardBorder

                        RowLayout {
                            id: prevL
                            anchors.centerIn: parent
                            spacing: 6
                            Text { visible: ShellState.splitShowLauncherIcon; text: ShellState.menuGlyphFor(ShellState.splitMenuIcon); font.family: Theme.iconFont; font.pixelSize: 11; color: Theme.primary }
                            Text { visible: ShellState.splitShowWorkspaces; text: "1 2 3"; font.family: Theme.monoFont; font.pixelSize: 9; font.weight: Font.Bold; color: Theme.fgSurface }
                            Text { visible: ShellState.splitShowLayout; text: "tile"; font.family: Theme.monoFont; font.pixelSize: 8; color: Theme.fgSurfaceVariant }
                            Text { visible: ShellState.splitShowAppTitle; text: "Terminal"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        height: 28
                        width: prevC.implicitWidth + 18
                        radius: parent.parent.prevRad
                        color: ShellState.splitBarTranslucent ? Theme.cardBg : Theme.surfaceContainerHigh
                        border.width: 1; border.color: Theme.withAlpha(Theme.primary, 0.4)

                        RowLayout {
                            id: prevC
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: "12:00"; font.family: Theme.monoFont; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.fgSurface }
                            Text { visible: ShellState.splitShowDate; text: "Thu"; font.family: Theme.fontFamily; font.pixelSize: 9; color: Theme.fgSurfaceVariant }
                            Rectangle { visible: ShellState.splitShowMedia; implicitWidth: 12; implicitHeight: 12; radius: 6; color: Theme.primary }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 28
                        width: prevR.implicitWidth + 16
                        radius: parent.parent.prevRad
                        color: ShellState.splitBarTranslucent ? Theme.cardBg : Theme.surfaceContainerHigh
                        border.width: 1; border.color: Theme.cardBorder

                        RowLayout {
                            id: prevR
                            anchors.centerIn: parent
                            spacing: 5
                            Text { visible: ShellState.splitShowSystem; text: "CPU"; font.family: Theme.monoFont; font.pixelSize: 8; color: Theme.fgSurfaceVariant }
                            Text { visible: ShellState.splitShowVolume; text: "󰕾"; font.family: Theme.iconFont; font.pixelSize: 10; color: Theme.fgSurfaceVariant }
                            Text { visible: ShellState.splitShowStore; text: "󰏖"; font.family: Theme.iconFont; font.pixelSize: 10; color: Theme.primary }
                            Text { text: "󰕰 󰂚"; font.family: Theme.iconFont; font.pixelSize: 10; color: Theme.fgSurface }
                        }
                    }
                }
            }

            // Activation notice when Split Islands is not the active bar mode
            Rectangle {
                visible: Theme.isSimple || ShellState.barUiStyle !== "split"
                Layout.fillWidth: true
                implicitHeight: actRow.implicitHeight + 16
                radius: Theme.r(12)
                color: Theme.withAlpha(Theme.tertiary, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(Theme.tertiary, 0.35)

                RowLayout {
                    id: actRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Text { text: "󰋼"; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: Theme.tertiary }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Theme.isSimple
                            ? "Simple Edge Bar mode is currently active. Activate Split Islands to switch to Modern mode with the 3-pod bar & Sequoia hubs."
                            : "Split Islands is not currently selected as the active top bar. Activate it to display the 3 stationary pods and per-pod popovers."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurface
                    }

                    Rectangle {
                        implicitWidth: actSplitTxt.implicitWidth + 18
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: actSplitMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                        Text { id: actSplitTxt; anchors.centerIn: parent; text: "Activate Split Islands"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgPrimary }

                        MouseArea {
                            id: actSplitMouse
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Theme.isSimple)
                                    ShellState.setPrefsBatch({ shellMode: "default", barUiStyle: "split" });
                                else
                                    ShellState.setBarUiStyle("split");
                            }
                        }
                    }
                }
            }
        }
    }

    // ==================== 1. POD GEOMETRY, FRAMING & LEADING ICON ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: geoCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: geoCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text { Layout.fillWidth: true; text: "Pod Geometry & Framing"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }

                Rectangle {
                    implicitWidth: jSeqTxt.implicitWidth + 14
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: jSeqMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1; border.color: Theme.cardBorder
                    Text { id: jSeqTxt; anchors.centerIn: parent; text: "󰘔 Sequoia Bar"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.secondary }
                    MouseArea { id: jSeqMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPageRequested("sequoia") }
                }

                Rectangle {
                    implicitWidth: jIslTxt.implicitWidth + 14
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: jIslMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1; border.color: Theme.cardBorder
                    Text { id: jIslTxt; anchors.centerIn: parent; text: "󰀵 Dynamic Island"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: Theme.primary }
                    MouseArea { id: jIslMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPageRequested("island") }
                }
            }

            StepControl {
                label: "Pod Height"
                displayValue: ShellState.splitBarHeight + " px"
                accentColor: Theme.primary
                onDecremented: ShellState.setPref("splitBarHeight", Math.max(26, ShellState.splitBarHeight - 1))
                onIncremented: ShellState.setPref("splitBarHeight", Math.min(40, ShellState.splitBarHeight + 1))
            }

            StepControl {
                label: "Top Floating Margin"
                displayValue: ShellState.splitTopMargin + " px"
                accentColor: Theme.secondary
                onDecremented: ShellState.setPref("splitTopMargin", Math.max(2, ShellState.splitTopMargin - 1))
                onIncremented: ShellState.setPref("splitTopMargin", Math.min(18, ShellState.splitTopMargin + 1))
            }

            StepControl {
                label: "Side Screen Inset"
                displayValue: ShellState.splitSideMargin + " px"
                accentColor: Theme.tertiary
                onDecremented: ShellState.setPref("splitSideMargin", Math.max(4, ShellState.splitSideMargin - 2))
                onIncremented: ShellState.setPref("splitSideMargin", Math.min(28, ShellState.splitSideMargin + 2))
            }

            // Pod Shape Selector
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.fillWidth: true; text: "Pod Corner Shape"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }

                Repeater {
                    model: root.podShapes
                    delegate: Rectangle {
                        id: shapeChip
                        required property var modelData
                        readonly property bool selected: ShellState.splitPodStyle === modelData.id
                        implicitWidth: scTxt.implicitWidth + 18
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: shapeChip.selected ? Theme.primary : (scMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: 1; border.color: shapeChip.selected ? Theme.primary : Theme.cardBorder
                        Text { id: scTxt; anchors.centerIn: parent; text: shapeChip.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: shapeChip.selected ? Font.Bold : Font.Normal; color: shapeChip.selected ? Theme.fgPrimary : Theme.fgSurface }
                        MouseArea { id: scMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("splitPodStyle", shapeChip.modelData.id) }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.fillWidth: true; text: "Translucent Sequoia Pod Glass"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch {
                    checked: ShellState.splitBarTranslucent
                    onToggled: ShellState.setPref("splitBarTranslucent", !ShellState.splitBarTranslucent)
                }
            }

            Text { text: "Left Pod System Glyph"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: root.menuGlyphs

                    delegate: Rectangle {
                        id: gChip
                        required property var modelData
                        readonly property bool selected: ShellState.splitMenuIcon === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: gCol.implicitHeight + 12
                        radius: Theme.r(10)
                        color: gChip.selected ? Theme.withAlpha(Theme.primary, 0.18) : (gMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: gChip.selected ? 2 : Theme.subBorderWidth
                        border.color: gChip.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: gCol; anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: gChip.modelData.glyph; font.family: Theme.iconFont; font.pixelSize: Theme.fs(15); color: gChip.selected ? Theme.primary : Theme.fgSurface }
                            Text { Layout.alignment: Qt.AlignHCenter; text: gChip.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); font.weight: gChip.selected ? Font.Bold : Font.Normal; color: gChip.selected ? Theme.primary : Theme.fgSurfaceVariant }
                        }

                        MouseArea { id: gMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setPref("splitMenuIcon", gChip.modelData.id) }
                    }
                }
            }
        }
    }

    // ==================== 2. CONTROL CENTER POPOVER LAYOUT & PRESETS ====================
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: ccCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: ccCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text { text: "Right Pod Control Center Popover Layout"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ShellState.availableSequoiaHubStyles

                    delegate: Rectangle {
                        id: ccCard
                        required property var modelData
                        readonly property bool selected: ShellState.splitHubStyle === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: ccCardCol.implicitHeight + 16
                        radius: Theme.r(12)
                        color: ccCard.selected ? Theme.withAlpha(Theme.primary, 0.16) : (ccMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: ccCard.selected ? 2 : Theme.subBorderWidth
                        border.color: ccCard.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: ccCardCol; anchors.fill: parent; anchors.margins: 8; spacing: 3
                            RowLayout {
                                Layout.fillWidth: true; spacing: 5
                                Text { text: ccCard.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(14); color: ccCard.selected ? Theme.primary : Theme.fgSurfaceVariant }
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: ccCard.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                            }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: ccCard.modelData.vibe; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); font.weight: Font.DemiBold; color: ccCard.selected ? Theme.primary : Theme.fgSurfaceVariant }
                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: ccCard.modelData.desc; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                        }

                        MouseArea { id: ccMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.setSplitHubStyle(ccCard.modelData.id) }
                    }
                }
            }

            Text { text: "Quick Split Islands Presets"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.splitPresets

                    delegate: Rectangle {
                        id: prBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: prRow.implicitHeight + 14
                        radius: Theme.r(10)
                        color: prMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: prMouse.containsMouse ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            id: prRow; anchors.centerIn: parent; spacing: 6
                            Text { text: prBtn.modelData.icon; font.family: Theme.iconFont; font.pixelSize: Theme.fs(13); color: Theme.primary }
                            ColumnLayout {
                                spacing: 0
                                Text { text: prBtn.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.Bold; color: Theme.fgSurface }
                                Text { text: prBtn.modelData.desc; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                            }
                        }

                        MouseArea { id: prMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ShellState.applySplitPreset(prBtn.modelData.id) }
                    }
                }
            }
        }
    }

    // ==================== 3. PER-POD MODULE TOGGLES ====================
    Repeater {
        model: [
            { title: "Left Pod Modules (Spaces & Quick Hub)", rows: root.leftModules,   hasBatteryRow: false },
            { title: "Center Pod Modules (Clock, Media & Focus)", rows: root.centerModules, hasBatteryRow: false },
            { title: "Right Pod Modules (Telemetry & Control Center)", rows: root.rightModules, hasBatteryRow: true }
        ]

        delegate: Rectangle {
            id: podModCard
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: podModCol.implicitHeight + 24
            radius: Theme.r(16)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            ColumnLayout {
                id: podModCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text { text: podModCard.modelData.title; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); font.weight: Font.Bold; color: Theme.fgSurfaceVariant }

                Repeater {
                    model: podModCard.modelData.rows

                    delegate: RowLayout {
                        id: modRow
                        required property var modelData
                        readonly property bool isOn: Boolean(ShellState[modelData.key])
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: modRow.modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.DemiBold; color: Theme.fgSurface }
                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modRow.modelData.sub; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                        }

                        ToggleSwitch {
                            checked: modRow.isOn
                            onToggled: ShellState.setPref(modRow.modelData.key, !modRow.isOn)
                        }
                    }
                }

                RowLayout {
                    visible: podModCard.modelData.hasBatteryRow && DeviceCaps.hasBattery
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: "Battery Percentage & Status"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.weight: Font.DemiBold; color: Theme.fgSurface }
                        Text { text: "Show battery readout inside the right pod"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(9); color: Theme.fgSurfaceVariant }
                    }

                    ToggleSwitch {
                        checked: ShellState.splitShowBattery
                        onToggled: ShellState.setPref("splitShowBattery", !ShellState.splitShowBattery)
                    }
                }
            }
        }
    }
}
