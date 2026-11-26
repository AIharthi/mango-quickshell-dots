pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    signal openPageRequested(string page)

    property bool confirmResetSequoia: false

    readonly property var menuGlyphs: [
        { id: "aurora",  label: "Aurora",  glyph: "󰀻" },
        { id: "apple",   label: "Apple",   glyph: "󰀵" },
        { id: "cachyos", label: "CachyOS", glyph: "󰣇" },
        { id: "arch",    label: "Arch",    glyph: "󰣇" },
        { id: "fedora",  label: "Fedora",  glyph: "󰣛" },
        { id: "gentoo",  label: "Gentoo",  glyph: "󰣨" },
        { id: "minimal", label: "Minimal", glyph: "󰘔" }
    ]

    readonly property var sequoiaPresets: [
        { id: "macos",     label: "macOS Clean", desc: "Balanced Apple menu bar", icon: "󰀵" },
        { id: "minimal",   label: "Minimal",     desc: "Ultra quiet status bar",  icon: "󰘔" },
        { id: "developer", label: "Developer",   desc: "Tags, CPU, RAM & net",    icon: "󰍛" }
    ]

    readonly property var sequoiaModules: [
        { key: "sequoiaShowAppTitle",      label: "Active Application & Title",   sub: "Bold current app name paired with focused window title on the left" },
        { key: "sequoiaShowWorkspaces",    label: "Compact Workspace Badges",     sub: "Show active and occupied MangoWC tags in the left strip" },
        { key: "sequoiaShowLayout",        label: "Tiling Layout Indicator",      sub: "Display current workspace layout badge beside spaces" },
        { key: "sequoiaShowMedia",         label: "Now-Playing Menu Item",        sub: "Inline track status with click-to-toggle playback in the right tray" },
        { key: "sequoiaShowSystem",        label: "CPU & RAM Load Readout",       sub: "Compact processor and memory utilization readout in the menu bar" },
        { key: "sequoiaShowNetSpeed",      label: "Live Network Speed Readout",   sub: "Real-time download and upload throughput counters" },
        { key: "sequoiaShowVolume",        label: "Volume & Audio Status Icon",   sub: "Scroll to adjust output volume or middle-click to mute" },
        { key: "sequoiaShowTray",          label: "Menu Bar Status Tray",         sub: "Show SystemTray icons inline in the right menu strip" },
        { key: "sequoiaShowStore",         label: "App Store Shortcut Icon",      sub: "One-click button to launch Aurora App Store for Arch & Fedora" },
        { key: "sequoiaShowSpotlightIcon", label: "Spotlight Search Icon",        sub: "Search button opening centered macOS Spotlight launcher overlay" },
        { key: "sequoiaShowDate",          label: "Date Next to Menu Bar Clock",  sub: "Show short date before the clock in the top-right corner" }
    ]

    Timer {
        id: resetConfirmTimer
        interval: 4000
        onTriggered: root.confirmResetSequoia = false
    }

    // Header + Reset Sequoia Bar
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
                        text: "󰘔"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(18)
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Sequoia Bar & Control Center"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(13)
                        font.weight: Font.Bold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Dedicated full-width menu bar with stationary top-right Control Center popover, Notification Center, and centered Spotlight search."
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Rectangle {
                    implicitWidth: seqResetTxt.implicitWidth + 20
                    implicitHeight: 30
                    radius: Theme.r(9)
                    color: root.confirmResetSequoia
                        ? Theme.warning
                        : (seqResetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                    border.width: 1
                    border.color: root.confirmResetSequoia ? Theme.warning : Theme.cardBorder

                    Text {
                        id: seqResetTxt
                        anchors.centerIn: parent
                        text: root.confirmResetSequoia ? "Confirm Reset?" : "󰑐 Reset Sequoia"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: root.confirmResetSequoia ? Theme.contrastInk(Theme.warning) : Theme.warning
                    }

                    MouseArea {
                        id: seqResetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmResetSequoia) {
                                root.confirmResetSequoia = true;
                                resetConfirmTimer.restart();
                                return;
                            }
                            root.confirmResetSequoia = false;
                            resetConfirmTimer.stop();
                            ShellState.resetSequoia();
                        }
                    }
                }
            }

            // Activation notice when Sequoia is not the active bar mode
            Rectangle {
                visible: Theme.isSimple || ShellState.barUiStyle !== "menubar"
                Layout.fillWidth: true
                implicitHeight: activateRow.implicitHeight + 16
                radius: Theme.r(12)
                color: Theme.withAlpha(Theme.tertiary, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(Theme.tertiary, 0.35)

                RowLayout {
                    id: activateRow
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
                            ? "Simple Edge Bar mode is currently active. Activate Sequoia Bar to switch into Modern mode with the macOS top menu bar."
                            : (ShellState.barUiStyle === "split"
                                ? "Split Islands is currently active with its 3 floating glass pods and per-pod hubs. Activate Sequoia Bar to use the unified macOS top menu bar."
                                : "Dynamic Island is currently active. Activate Sequoia Bar to display the stationary full-width top menu bar and Control Center popover.")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurface
                    }

                    Rectangle {
                        implicitWidth: actSeqTxt.implicitWidth + 18
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: actSeqMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                        Text {
                            id: actSeqTxt
                            anchors.centerIn: parent
                            text: "Activate Sequoia Bar"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: Theme.fgPrimary
                        }

                        MouseArea {
                            id: actSeqMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Theme.isSimple)
                                    ShellState.setPrefsBatch({ shellMode: "default", barUiStyle: "menubar" });
                                else
                                    ShellState.setBarUiStyle("menubar");
                            }
                        }
                    }
                }
            }
        }
    }

    // 1. Sequoia Top Bar Geometry & Leading Glyph
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

                Text {
                    Layout.fillWidth: true
                    text: "Menu Bar Geometry & Surface"
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
                    implicitWidth: goIslTxt.implicitWidth + 16
                    implicitHeight: 24
                    radius: Theme.r(7)
                    color: goIslMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder

                    Text {
                        id: goIslTxt
                        anchors.centerIn: parent
                        text: "󰀵 Configure Dynamic Island"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: goIslMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("island")
                    }
                }
            }

            StepControl {
                label: "Menu Bar Height"
                displayValue: ShellState.sequoiaBarHeight + " px"
                accentColor: Theme.primary
                onDecremented: ShellState.setPref("sequoiaBarHeight", Math.max(24, ShellState.sequoiaBarHeight - 1))
                onIncremented: ShellState.setPref("sequoiaBarHeight", Math.min(36, ShellState.sequoiaBarHeight + 1))
            }

            // Flush vs Floating Bar Framing
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Bar Framing"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { val: false, label: "Flush Edge" },
                        { val: true,  label: "Floating Pill" }
                    ]

                    delegate: Rectangle {
                        id: frameBtn
                        required property var modelData
                        readonly property bool selected: ShellState.sequoiaBarFloating === modelData.val
                        implicitWidth: frameTxt.implicitWidth + 20
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: frameBtn.selected
                            ? Theme.primary
                            : (frameMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: 1
                        border.color: frameBtn.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            id: frameTxt
                            anchors.centerIn: parent
                            text: frameBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: frameBtn.selected ? Font.Bold : Font.Normal
                            color: frameBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: frameMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("sequoiaBarFloating", frameBtn.modelData.val)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: "Translucent Menu Bar Glass"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }
                ToggleSwitch {
                    checked: ShellState.sequoiaBarTranslucent
                    onToggled: ShellState.setPref("sequoiaBarTranslucent", !ShellState.sequoiaBarTranslucent)
                }
            }

            Text {
                text: "Leading System Menu Icon"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: root.menuGlyphs

                    delegate: Rectangle {
                        id: glyphChip
                        required property var modelData
                        readonly property bool selected: ShellState.sequoiaMenuIcon === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: glyphCol.implicitHeight + 12
                        radius: Theme.r(10)
                        color: glyphChip.selected
                            ? Theme.withAlpha(Theme.primary, 0.18)
                            : (glyphMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: glyphChip.selected ? 2 : Theme.subBorderWidth
                        border.color: glyphChip.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: glyphCol
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: glyphChip.modelData.glyph
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(15)
                                color: glyphChip.selected ? Theme.primary : Theme.fgSurface
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: glyphChip.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: glyphChip.selected ? Font.Bold : Font.Normal
                                color: glyphChip.selected ? Theme.primary : Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: glyphMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("sequoiaMenuIcon", glyphChip.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // 2. Sequoia Control Center Style & Presets
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

            Text {
                text: "Control Center Popover Layout"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

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
                        readonly property bool selected: ShellState.sequoiaHubStyle === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: ccCardCol.implicitHeight + 16
                        radius: Theme.r(12)
                        color: ccCard.selected
                            ? Theme.withAlpha(Theme.primary, 0.16)
                            : (ccMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: ccCard.selected ? 2 : Theme.subBorderWidth
                        border.color: ccCard.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: ccCardCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    text: ccCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(14)
                                    color: ccCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: ccCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: ccCard.modelData.vibe
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                font.weight: Font.DemiBold
                                color: ccCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: ccCard.modelData.desc
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: ccMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setSequoiaHubStyle(ccCard.modelData.id)
                        }
                    }
                }
            }

            Text {
                text: "Quick Sequoia Presets"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.sequoiaPresets

                    delegate: Rectangle {
                        id: seqPresetBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: seqPresetRow.implicitHeight + 14
                        radius: Theme.r(10)
                        color: seqPresetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: seqPresetMouse.containsMouse ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            id: seqPresetRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: seqPresetBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(13)
                                color: Theme.primary
                            }

                            ColumnLayout {
                                spacing: 0

                                Text {
                                    text: seqPresetBtn.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }

                                Text {
                                    text: seqPresetBtn.modelData.desc
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: seqPresetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.applySequoiaPreset(seqPresetBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // 3. Menu Bar Modules
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
                text: "Menu Bar Modules"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            Repeater {
                model: root.sequoiaModules

                delegate: RowLayout {
                    id: seqModRow
                    required property var modelData
                    readonly property bool isOn: Boolean(ShellState[modelData.key])
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: seqModRow.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.DemiBold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: seqModRow.modelData.sub
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    ToggleSwitch {
                        checked: seqModRow.isOn
                        onToggled: ShellState.setPref(seqModRow.modelData.key, !seqModRow.isOn)
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
                        text: "Battery Percentage & Status"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(11)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Show charge readout beside Control Center in the right strip"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.sequoiaShowBattery
                    onToggled: ShellState.setPref("sequoiaShowBattery", !ShellState.sequoiaShowBattery)
                }
            }
        }
    }
}
