pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property bool confirmResetBar: false
    property string barStatusMsg: ""

    Timer {
        id: barConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmResetBar = false
    }

    Timer {
        id: barStatusTimer
        interval: 3500
        repeat: false
        onTriggered: root.barStatusMsg = ""
    }

    // --- Quick Recovery Row ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: resetBarRow.implicitHeight + 16
        radius: Theme.r(12)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            id: resetBarRow
            anchors.fill: parent
            anchors.margins: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: root.barStatusMsg.length > 0 ? root.barStatusMsg : "Reset Bar Widgets, Dynamic Island & Simple Bar to defaults"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: root.barStatusMsg.length > 0 ? Font.Bold : Font.Normal
                    color: root.barStatusMsg.length > 0 ? Theme.success : Theme.fgSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: rstBarLbl.implicitWidth + 16
                radius: Theme.r(8)
                color: root.confirmResetBar
                    ? Theme.warning
                    : (rstBarMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.20) : Theme.subCardBg)
                border.width: 1
                border.color: root.confirmResetBar ? Theme.warning : Theme.cardBorder

                Text {
                    id: rstBarLbl
                    anchors.centerIn: parent
                    text: root.confirmResetBar ? "Confirm Reset?" : "󰑐 Reset Bar & Shell"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: root.confirmResetBar ? Theme.fgPrimary : Theme.warning
                }

                MouseArea {
                    id: rstBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.confirmResetBar) {
                            root.confirmResetBar = true;
                            barConfirmTimer.restart();
                            return;
                        }
                        root.confirmResetBar = false;
                        barConfirmTimer.stop();
                        ShellState.resetBar();
                        root.barStatusMsg = "Bar & Shell settings restored to defaults";
                        barStatusTimer.restart();
                    }
                }
            }
        }
    }

    // --- 0. Bar Widgets & Modules (Dynamic Island + Simple Bar) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: widgetsCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: widgetsCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "BAR WIDGETS & MODULES (ISLAND & BAR)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Add date, window title, tags, stats & more"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: Theme.fgSurfaceVariant
                }
            }

            // 1-Click Bar Presets
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 106
                    text: "Bar Presets"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "minimal",  label: "Minimal Pill" },
                        { id: "balanced", label: "Balanced Island" },
                        { id: "full",     label: "Full Desktop Bar" }
                    ]

                    delegate: Rectangle {
                        id: bpBtn
                        required property var modelData
                        readonly property bool active: (
                            (bpBtn.modelData.id === "minimal"
                                && ShellState.islandStyle === "pill"
                                && !ShellState.barShowDate && !ShellState.barShowWindow && !ShellState.barShowWorkspaces && !ShellState.barShowSystem)
                            || (bpBtn.modelData.id === "balanced"
                                && ShellState.islandStyle === "pill"
                                && ShellState.barShowDate && ShellState.barShowWindow && ShellState.barShowWorkspaces && !ShellState.barShowSystem)
                            || (bpBtn.modelData.id === "full"
                                && ShellState.islandStyle === "bar"
                                && ShellState.barShowDate && ShellState.barShowWindow && ShellState.barShowWorkspaces && ShellState.barShowSystem)
                        )

                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: bpBtn.active
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (bpMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: bpBtn.active ? 1 : Theme.cardBorderWidth
                        border.color: bpBtn.active ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: bpBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: bpBtn.active ? Font.Bold : Font.Medium
                            color: bpBtn.active ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            id: bpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ShellState.applyBarPreset(bpBtn.modelData.id);
                                root.barStatusMsg = "Applied preset: " + bpBtn.modelData.label;
                                barStatusTimer.restart();
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Date Next to Clock (Island Pill / Bar)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowDate; onToggled: ShellState.setPref("barShowDate", !ShellState.barShowDate) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Active Window Title"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowWindow; onToggled: ShellState.setPref("barShowWindow", !ShellState.barShowWindow) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Workspaces / Tags Strip (Island Pill / Bar)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowWorkspaces; onToggled: ShellState.setPref("barShowWorkspaces", !ShellState.barShowWorkspaces) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Window Layout Badge ([T]) (Island Pill / Bar)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowLayout; onToggled: ShellState.setPref("barShowLayout", !ShellState.barShowLayout) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Now-Playing Media Strip"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.pillShowMedia; onToggled: ShellState.setPref("pillShowMedia", !ShellState.pillShowMedia) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "CPU & RAM Usage"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowSystem; onToggled: ShellState.setPref("barShowSystem", !ShellState.barShowSystem) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: DeviceCaps.hasAudio
                Text { Layout.fillWidth: true; text: "Volume Indicator (Click Mute / Scroll ±5%)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowVolume; onToggled: ShellState.setPref("barShowVolume", !ShellState.barShowVolume) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Keyboard Layout Indicator (US / AR)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowKbLayout; onToggled: ShellState.setPref("barShowKbLayout", !ShellState.barShowKbLayout) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "System Tray Icons (Island Pill / Bar)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowTray; onToggled: ShellState.setPref("barShowTray", !ShellState.barShowTray) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "App Launcher & Settings Shortcut Icons"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowQuickIcons; onToggled: ShellState.setPref("barShowQuickIcons", !ShellState.barShowQuickIcons) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Files Manager Shortcut Icon (Island / Simple Bar)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowFiles; onToggled: ShellState.setPref("barShowFiles", !ShellState.barShowFiles) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: DeviceCaps.hasBattery
                Text { Layout.fillWidth: true; text: "Battery Percentage"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.barShowBattery; onToggled: ShellState.setPref("barShowBattery", !ShellState.barShowBattery) }
            }
        }
    }

    // --- 1. Dynamic Island & Pill Behavior ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: islCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: islCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "DYNAMIC ISLAND & COMPACT PILL"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Expand Hub on Pointer Hover"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "When disabled, click the pill or press Super + D to expand"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.islandHoverExpand
                    onToggled: ShellState.setPref("islandHoverExpand", !ShellState.islandHoverExpand)
                }
            }

            StepControl {
                label: "Hover Expand Delay"
                displayValue: ShellState.islandHoverDelayMs + " ms"
                controlEnabled: ShellState.islandHoverExpand
                onDecremented: ShellState.setPref("islandHoverDelayMs", Math.max(50, ShellState.islandHoverDelayMs - 50))
                onIncremented: ShellState.setPref("islandHoverDelayMs", Math.min(1500, ShellState.islandHoverDelayMs + 50))
            }

            StepControl {
                label: "Auto-Collapse Leave Delay"
                displayValue: ShellState.islandCollapseDelayMs + " ms"
                onDecremented: ShellState.setPref("islandCollapseDelayMs", Math.max(200, ShellState.islandCollapseDelayMs - 100))
                onIncremented: ShellState.setPref("islandCollapseDelayMs", Math.min(4000, ShellState.islandCollapseDelayMs + 100))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: ShellState.pillShowMedia ? 1.0 : 0.45

                Text {
                    Layout.fillWidth: true
                    text: "Rotate Album Cover Art While Playing"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.pillSpinArt
                    onToggled: ShellState.setPref("pillSpinArt", !ShellState.pillSpinArt)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: ShellState.pillShowMedia ? 1.0 : 0.45

                Text {
                    Layout.fillWidth: true
                    text: "Show Animated Mini Equalizer Bars"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.pillShowEqualizer
                    onToggled: ShellState.setPref("pillShowEqualizer", !ShellState.pillShowEqualizer)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "On-Screen Volume & Brightness OSD Popups"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.osdEnabled
                    onToggled: ShellState.setPref("osdEnabled", !ShellState.osdEnabled)
                }
            }

            StepControl {
                label: "OSD Popup Duration"
                displayValue: (ShellState.osdTimeoutMs / 1000.0).toFixed(1) + " s"
                controlEnabled: ShellState.osdEnabled
                onDecremented: ShellState.setPref("osdTimeoutMs", Math.max(800, ShellState.osdTimeoutMs - 200))
                onIncremented: ShellState.setPref("osdTimeoutMs", Math.min(6000, ShellState.osdTimeoutMs + 200))
            }
        }
    }

    // --- 2. Simple Square Bar ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: barCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: barCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "SIMPLE MODE TOP/BOTTOM BAR"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            StepControl {
                label: "Bar Thickness"
                displayValue: ShellState.simpleBarHeight + " px"
                onDecremented: ShellState.setPref("simpleBarHeight", Math.max(22, ShellState.simpleBarHeight - 2))
                onIncremented: ShellState.setPref("simpleBarHeight", Math.min(44, ShellState.simpleBarHeight + 2))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Screen Edge Position"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                RowLayout {
                    spacing: 6

                    Repeater {
                        model: ["top", "bottom"]

                        delegate: Rectangle {
                            id: posPill
                            required property string modelData
                            readonly property bool selected: ShellState.simpleBarPosition === posPill.modelData

                            implicitHeight: 24
                            implicitWidth: posTxt.implicitWidth + 16
                            radius: Theme.r(7)
                            color: posPill.selected
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (posMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: posPill.selected ? 1 : Theme.cardBorderWidth
                            border.color: posPill.selected ? Theme.primary : Theme.cardBorder

                            Text {
                                id: posTxt
                                anchors.centerIn: parent
                                text: posPill.modelData === "top" ? "Top" : "Bottom"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: posPill.selected ? Font.Bold : Font.Medium
                                color: posPill.selected ? Theme.primary : Theme.fgSurface
                            }

                            MouseArea {
                                id: posMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("simpleBarPosition", posPill.modelData)
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Show Layout Badge ([T]) Beside Workspaces"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.simpleBarShowLayout
                    onToggled: ShellState.setPref("simpleBarShowLayout", !ShellState.simpleBarShowLayout)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Show Date Next to Bar Clock"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.simpleBarShowDate
                    onToggled: ShellState.setPref("simpleBarShowDate", !ShellState.simpleBarShowDate)
                }
            }
        }
    }

    // --- 3. Screenshot Capture Pipeline ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: shotCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: shotCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "SCREENSHOTS (GRIM + SLURP)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Save Directory"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: dirInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: dirInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: dirInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: ShellState.screenshotDir
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurface
                        clip: true
                        onAccepted: {
                            if (text.trim().length > 0)
                                ShellState.setPref("screenshotDir", text.trim());
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: saveDirLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: saveDirMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: saveDirLbl
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: saveDirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (dirInput.text.trim().length > 0)
                                ShellState.setPref("screenshotDir", dirInput.text.trim());
                        }
                    }
                }
            }

            StepControl {
                label: "Capture Countdown Delay"
                displayValue: ShellState.screenshotDelay + " s"
                onDecremented: ShellState.setPref("screenshotDelay", Math.max(0, ShellState.screenshotDelay - 1))
                onIncremented: ShellState.setPref("screenshotDelay", Math.min(10, ShellState.screenshotDelay + 1))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Copy Captured Image to Clipboard (wl-copy)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.screenshotCopyClipboard
                    onToggled: ShellState.setPref("screenshotCopyClipboard", !ShellState.screenshotCopyClipboard)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Send Dynamic Island Notification After Capture"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.screenshotNotify
                    onToggled: ShellState.setPref("screenshotNotify", !ShellState.screenshotNotify)
                }
            }
        }
    }

    // --- 4. Accessibility & Motion ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: a11yCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: a11yCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "ACCESSIBILITY & MOTION"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Reduce Motion (Shell + GTK)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Disables spinning art, equalizer animation, and UI motion across Quickshell & GTK"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.reducedMotion
                    onToggled: ShellState.setPref("reducedMotion", !ShellState.reducedMotion)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "High-Contrast Card & Island Outlines"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Forces crisp high-visibility borders across panels, cards, and GTK a11y schema"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }
                }

                ToggleSwitch {
                    checked: ShellState.highContrast
                    onToggled: ShellState.setPref("highContrast", !ShellState.highContrast)
                }
            }
        }
    }

    // --- 5. Dynamic File Manager (Rust Backend) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: fmCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: fmCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "DYNAMIC FILE MANAGER (RUST BACKEND)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: openFmLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: openFmMouse.containsMouse ? Theme.primary : Theme.withAlpha(Theme.primary, 0.20)
                    border.width: 1
                    border.color: Theme.primary

                    Text {
                        id: openFmLbl
                        anchors.centerIn: parent
                        text: "󰉋 Open Files"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: openFmMouse.containsMouse ? Theme.fgPrimary : Theme.primary
                    }
                    MouseArea {
                        id: openFmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleFiles"])
                    }
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: rstFmLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: rstFmMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.22) : Theme.subCardBg
                    border.width: 1
                    border.color: Theme.cardBorder

                    Text {
                        id: rstFmLbl
                        anchors.centerIn: parent
                        text: "Reset Style"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.warning
                    }
                    MouseArea {
                        id: rstFmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.resetFiles();
                            root.barStatusMsg = "File Manager appearance reset to defaults";
                            barStatusTimer.restart();
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Default View Mode"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "list",   label: "List" },
                        { id: "grid",   label: "Grid" },
                        { id: "miller", label: "Miller Columns" }
                    ]
                    delegate: Rectangle {
                        id: fmVmBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmViewMode === fmVmBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: sel ? Theme.withAlpha(Theme.primary, 0.22) : (fmVmMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: 1
                        border.color: sel ? Theme.primary : Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: fmVmBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: fmVmBtn.sel ? Font.Bold : Font.Medium
                            color: fmVmBtn.sel ? Theme.primary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmVmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmViewMode", fmVmBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Dual-Pane Split by Default (F3)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.fmDualPane; onToggled: ShellState.setPref("fmDualPane", !ShellState.fmDualPane) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Show Live Inspector / Preview Pane"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.fmPreviewVisible; onToggled: ShellState.setPref("fmPreviewVisible", !ShellState.fmPreviewVisible) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Show Hidden Dotfiles by Default (Ctrl+H)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.fmShowHidden; onToggled: ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden) }
            }
        }
    }

    // --- 6. Weather Widget & Wallpaper Slideshow ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: extrasCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: extrasCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "WEATHER WIDGET & WALLPAPER SLIDESHOW"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text { text: "Enable Opt-In Weather Widget (wttr.in)"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                    Text { text: "Caches conditions locally every 30 minutes when enabled"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurfaceVariant }
                }

                ToggleSwitch {
                    checked: ShellState.weatherEnabled
                    onToggled: ShellState.setPref("weatherEnabled", !ShellState.weatherEnabled)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                opacity: ShellState.weatherEnabled ? 1.0 : 0.45

                Text { Layout.fillWidth: true; text: "Show Compact Weather Pill in Top Bar"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                ToggleSwitch {
                    checked: ShellState.barShowWeather
                    onToggled: ShellState.setPref("barShowWeather", !ShellState.barShowWeather)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: ShellState.weatherEnabled ? 1.0 : 0.45

                Text {
                    text: "City / Location"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: locInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: locInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: locInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: ShellState.weatherLocation
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurface
                        clip: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: locInput.text.length === 0
                            text: "Auto-detect by IP (or enter city)"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        onAccepted: {
                            ShellState.setPref("weatherLocation", text.trim());
                            ShellState.refreshWeather(true);
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: 34
                    radius: Theme.r(8)
                    color: unitMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: "°" + ShellState.weatherUnits
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: unitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.setPref("weatherUnits", ShellState.weatherUnits === "C" ? "F" : "C");
                            ShellState.refreshWeather(true);
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: saveLocLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: saveLocMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: saveLocLbl
                        anchors.centerIn: parent
                        text: "Apply"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: saveLocMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ShellState.setPref("weatherLocation", locInput.text.trim());
                            ShellState.refreshWeather(true);
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.outlineVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Automatic Wallpaper Slideshow"; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.fgSurface }
                    Text { text: "Automatically rotates wallpaper & re-themes via Matugen"; font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.fgSurfaceVariant }
                }

                ToggleSwitch {
                    checked: ShellState.wallpaperSlideshowEnabled
                    onToggled: ShellState.setPref("wallpaperSlideshowEnabled", !ShellState.wallpaperSlideshowEnabled)
                }
            }

            StepControl {
                label: "Slideshow Rotation Interval"
                displayValue: ShellState.wallpaperSlideshowMinutes + " min"
                controlEnabled: ShellState.wallpaperSlideshowEnabled
                onDecremented: ShellState.setPref("wallpaperSlideshowMinutes", Math.max(1, ShellState.wallpaperSlideshowMinutes - 5))
                onIncremented: ShellState.setPref("wallpaperSlideshowMinutes", Math.min(240, ShellState.wallpaperSlideshowMinutes + 5))
            }
        }
    }
}
