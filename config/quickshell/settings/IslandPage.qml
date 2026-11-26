pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    signal openPageRequested(string page)

    property bool confirmResetIsland: false

    readonly property var islandShapes: [
        { id: "pill",  label: "Floating Pill", desc: "Rounded capsule suspended from screen top", icon: "󰀵" },
        { id: "notch", label: "Mac Notch",     desc: "Flush screen notch hugging the top bezel", icon: "󰘔" },
        { id: "bar",   label: "Flat Strip",    desc: "Wide rounded pill across the top edge",    icon: "󰕮" }
    ]

    readonly property var islandFamilies: [
        { id: "apple",   label: "Dynamic Island", vibe: "Calmed Capsule",    icon: "󰀵", desc: "Compact adaptive pill with live media art and clean telemetry" },
        { id: "classic", label: "Modular Pill",   vibe: "Custom Widget Row", icon: "󰕮", desc: "Modular widget strip calibrated by your selected module toggles" }
    ]

    readonly property var barPresets: [
        { id: "minimal",  label: "Minimal",  desc: "Clock, date & tray",        icon: "󰘔" },
        { id: "balanced", label: "Balanced", desc: "Tags, volume & battery",    icon: "󰕮" },
        { id: "full",     label: "Full",     desc: "All widgets enabled",       icon: "󰕰" }
    ]

    readonly property var islandWidgets: [
        { key: "barShowDate",       label: "Date Next to Clock",               sub: "Display abbreviated weekday and date in the pill" },
        { key: "barShowWindow",     label: "Active Window Title",              sub: "Show focused application title inside the bar" },
        { key: "barShowWorkspaces", label: "Workspaces & Tags Strip",          sub: "Interactive tag indicators for active workspaces" },
        { key: "barShowLayout",     label: "Window Layout Badge",              sub: "Show tiling/scroller layout code beside tags" },
        { key: "barShowSystem",     label: "CPU & RAM Load Readout",           sub: "Live processor and memory telemetry badges" },
        { key: "barShowNetSpeed",   label: "Live Network Speed",               sub: "Download and upload throughput counters" },
        { key: "barShowVolume",     label: "Volume Control Badge",             sub: "Click to mute or scroll to adjust volume by 5%" },
        { key: "barShowKbLayout",   label: "Keyboard Layout Badge",            sub: "Show active keymap (US / AR) in the pill" },
        { key: "barShowTray",       label: "System Tray Icons",                sub: "Embed StatusNotifier tray icons in the right slot" },
        { key: "barShowQuickIcons", label: "Quick Capture Buttons",            sub: "Instant screenshot and screen record triggers" },
        { key: "barShowFiles",      label: "Quick Files Hub Tab",              sub: "Expose the Files drawer tab inside the expanded hub" }
    ]

    Timer {
        id: resetConfirmTimer
        interval: 4000
        onTriggered: root.confirmResetIsland = false
    }

    // Header + Reset Dynamic Island
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: headerCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: headerCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: Theme.r(10)
                    color: Theme.withAlpha(Theme.primary, 0.16)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.primary, 0.35)

                    Text {
                        anchors.centerIn: parent
                        text: "󰀵"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(18)
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Dynamic Island & Hub"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Configure the morphing capsule, floating pods, expanded hub dashboard, and live pill modules."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitWidth: islandResetTxt.implicitWidth + 20
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: root.confirmResetIsland
                        ? Theme.warning
                        : (islandResetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: 1
                    border.color: root.confirmResetIsland ? Theme.warning : Theme.cardBorder

                    Text {
                        id: islandResetTxt
                        anchors.centerIn: parent
                        text: root.confirmResetIsland ? "Confirm Reset?" : "󰑐 Reset Island"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.confirmResetIsland ? Theme.contrastInk(Theme.warning) : Theme.warning
                    }

                    MouseArea {
                        id: islandResetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmResetIsland) {
                                root.confirmResetIsland = true;
                                resetConfirmTimer.restart();
                                return;
                            }
                            root.confirmResetIsland = false;
                            resetConfirmTimer.stop();
                            ShellState.resetIsland();
                        }
                    }
                }
            }

            // Activation notice when Sequoia Menu Bar, Split Islands, or Simple Mode is active
            Rectangle {
                visible: Theme.isSimple || ShellState.barUiStyle === "menubar" || ShellState.barUiStyle === "split"
                Layout.fillWidth: true
                implicitHeight: inactiveRow.implicitHeight + 16
                radius: Theme.r(12)
                color: Theme.withAlpha(Theme.tertiary, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(Theme.tertiary, 0.35)

                RowLayout {
                    id: inactiveRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Text {
                        text: "󰋼"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(15)
                        color: Theme.tertiary
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Theme.isSimple
                            ? "Simple Edge Bar mode is currently active. Switch to Modern mode to show the Dynamic Island on screen."
                            : (ShellState.barUiStyle === "split"
                                ? "Split Islands is currently active and uses its own 3 stationary pods & per-pod hubs."
                                : "Sequoia Top Menu Bar is currently active and uses its own dedicated bar & Control Center Hub.")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurface
                    }

                    Rectangle {
                        implicitWidth: actBtnTxt.implicitWidth + 18
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: actBtnMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                        Text {
                            id: actBtnTxt
                            anchors.centerIn: parent
                            text: "Activate Dynamic Island"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgPrimary
                        }

                        MouseArea {
                            id: actBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const updates = {};
                                if (Theme.isSimple)
                                    updates["shellMode"] = "default";
                                if (ShellState.barUiStyle === "menubar" || ShellState.barUiStyle === "split")
                                    updates["barUiStyle"] = "apple";
                                ShellState.setPrefsBatch(updates);
                            }
                        }
                    }
                }
            }
        }
    }

    // 1. Island Capsule Family & Geometry
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: shapeCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: shapeCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Capsule Style & Geometry"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitWidth: goSplTxt.implicitWidth + 16
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: goSplMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder

                    Text {
                        id: goSplTxt
                        anchors.centerIn: parent
                        text: "󰕰 Configure Split Islands"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.DemiBold
                        color: Theme.secondary
                    }

                    MouseArea {
                        id: goSplMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("split")
                    }
                }

                Rectangle {
                    implicitWidth: goSeqTxt.implicitWidth + 16
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: goSeqMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder

                    Text {
                        id: goSeqTxt
                        anchors.centerIn: parent
                        text: "󰘔 Configure Sequoia Bar"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: goSeqMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("sequoia")
                    }
                }
            }

            // Capsule style selector (apple / classic)
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: root.islandFamilies

                    delegate: Rectangle {
                        id: famCard
                        required property var modelData
                        readonly property bool selected: !Theme.isSimple && ShellState.barUiStyle === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: famCol.implicitHeight + 16
                        radius: Theme.r(12)
                        color: famCard.selected
                            ? Theme.withAlpha(Theme.primary, 0.16)
                            : (famMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: famCard.selected ? 2 : Theme.subBorderWidth
                        border.color: famCard.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: famCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: famCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(15)
                                    color: famCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: famCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: famCard.modelData.vibe
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.DemiBold
                                color: famCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: famCard.modelData.desc
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: famMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Theme.isSimple)
                                    ShellState.setPrefsBatch({ shellMode: "default", barUiStyle: famCard.modelData.id });
                                else
                                    ShellState.setBarUiStyle(famCard.modelData.id);
                            }
                        }
                    }
                }
            }

            // Island Shape (pill / notch / bar)
            Text {
                text: "Container Shape"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.islandShapes

                    delegate: Rectangle {
                        id: shapeCard
                        required property var modelData
                        readonly property bool selected: ShellState.islandStyle === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: shapeCardCol.implicitHeight + 14
                        radius: Theme.r(10)
                        color: shapeCard.selected
                            ? Theme.withAlpha(Theme.secondary, 0.16)
                            : (shapeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: shapeCard.selected ? 2 : Theme.subBorderWidth
                        border.color: shapeCard.selected ? Theme.secondary : Theme.cardBorder

                        ColumnLayout {
                            id: shapeCardCol
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    text: shapeCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(13)
                                    color: shapeCard.selected ? Theme.secondary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: shapeCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: shapeCard.modelData.desc
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: shapeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("islandStyle", shapeCard.modelData.id)
                        }
                    }
                }
            }

            StepControl {
                label: "Compact Pill Height"
                displayValue: ShellState.pillHeight + " px"
                accentColor: Theme.secondary
                onDecremented: ShellState.setPref("pillHeight", Math.max(24, ShellState.pillHeight - 2))
                onIncremented: ShellState.setPref("pillHeight", Math.min(46, ShellState.pillHeight + 2))
            }

            StepControl {
                label: "Top Screen Margin"
                displayValue: ShellState.islandTopMargin + " px"
                accentColor: Theme.secondary
                controlEnabled: ShellState.islandStyle !== "notch"
                onDecremented: ShellState.setPref("islandTopMargin", Math.max(0, ShellState.islandTopMargin - 2))
                onIncremented: ShellState.setPref("islandTopMargin", Math.min(24, ShellState.islandTopMargin + 2))
            }
        }
    }

    // 2. Expanded Island Hub Layout & Presets
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hubCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: hubCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Expanded Dashboard Hub"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ShellState.availableHubStyles

                    delegate: Rectangle {
                        id: hubCard
                        required property var modelData
                        readonly property bool selected: ShellState.hubUiStyle === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: hubCardCol.implicitHeight + 16
                        radius: Theme.r(12)
                        color: hubCard.selected
                            ? Theme.withAlpha(Theme.primary, 0.16)
                            : (hubMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: hubCard.selected ? 2 : Theme.subBorderWidth
                        border.color: hubCard.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: hubCardCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: hubCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(15)
                                    color: hubCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    text: hubCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: "· " + hubCard.modelData.vibe
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: hubCard.modelData.desc
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: hubMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setHubUiStyle(hubCard.modelData.id)
                        }
                    }
                }
            }

            Text {
                text: "Quick Island Module Presets"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.barPresets

                    delegate: Rectangle {
                        id: presetBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: presetRow.implicitHeight + 14
                        radius: Theme.r(10)
                        color: presetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: presetMouse.containsMouse ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            id: presetRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: presetBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(13)
                                color: Theme.primary
                            }

                            ColumnLayout {
                                spacing: 0

                                Text {
                                    text: presetBtn.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }

                                Text {
                                    text: presetBtn.modelData.desc
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.applyBarPreset(presetBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // 3. Morphing, Media & OSD Behavior
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: morphCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: morphCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Morphing, Media & OSD Behavior"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.fillWidth: true; text: "Expand Overview Hub on Pointer Hover"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.islandHoverExpand; onToggled: ShellState.setPref("islandHoverExpand", !ShellState.islandHoverExpand) }
            }

            StepControl {
                label: "Hover Expand Delay"
                displayValue: ShellState.islandHoverDelayMs + " ms"
                controlEnabled: ShellState.islandHoverExpand
                onDecremented: ShellState.setPref("islandHoverDelayMs", Math.max(0, ShellState.islandHoverDelayMs - 30))
                onIncremented: ShellState.setPref("islandHoverDelayMs", Math.min(600, ShellState.islandHoverDelayMs + 30))
            }

            StepControl {
                label: "Collapse Grace Delay"
                displayValue: ShellState.islandCollapseDelayMs + " ms"
                onDecremented: ShellState.setPref("islandCollapseDelayMs", Math.max(150, ShellState.islandCollapseDelayMs - 50))
                onIncremented: ShellState.setPref("islandCollapseDelayMs", Math.min(1200, ShellState.islandCollapseDelayMs + 50))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.fillWidth: true; text: "Now-Playing Media Strip in Pill"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.pillShowMedia; onToggled: ShellState.setPref("pillShowMedia", !ShellState.pillShowMedia) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: ShellState.pillShowMedia ? 1.0 : 0.45
                Text { Layout.fillWidth: true; text: "Spin Album Art When Playing"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch {
                    checked: ShellState.pillSpinArt
                    onToggled: if (ShellState.pillShowMedia) ShellState.setPref("pillSpinArt", !ShellState.pillSpinArt)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: ShellState.pillShowMedia ? 1.0 : 0.45
                Text { Layout.fillWidth: true; text: "Animated Equalizer Bars in Pill"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch {
                    checked: ShellState.pillShowEqualizer
                    onToggled: if (ShellState.pillShowMedia) ShellState.setPref("pillShowEqualizer", !ShellState.pillShowEqualizer)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { Layout.fillWidth: true; text: "Show Volume & Brightness OSD Morphs"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.osdEnabled; onToggled: ShellState.setPref("osdEnabled", !ShellState.osdEnabled) }
            }

            StepControl {
                label: "OSD Auto-Hide Timeout"
                displayValue: (ShellState.osdTimeoutMs / 1000).toFixed(1) + " s"
                controlEnabled: ShellState.osdEnabled
                onDecremented: ShellState.setPref("osdTimeoutMs", Math.max(800, ShellState.osdTimeoutMs - 200))
                onIncremented: ShellState.setPref("osdTimeoutMs", Math.min(4000, ShellState.osdTimeoutMs + 200))
            }
        }
    }

    // 4. Pill & Modular Bar Widgets
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: modCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: modCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Pill & Bar Modules"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.islandWidgets

                delegate: RowLayout {
                    id: wRow
                    required property var modelData
                    readonly property bool isOn: Boolean(ShellState[modelData.key])
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: wRow.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: wRow.modelData.sub
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    ToggleSwitch {
                        checked: wRow.isOn
                        onToggled: ShellState.setPref(wRow.modelData.key, !wRow.isOn)
                    }
                }
            }

            RowLayout {
                visible: DeviceCaps.hasBattery
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Battery Indicator"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Display charge percentage and AC charging badge in the pill"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.barShowBattery
                    onToggled: ShellState.setPref("barShowBattery", !ShellState.barShowBattery)
                }
            }
        }
    }
}
