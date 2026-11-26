pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

ColumnLayout {
    id: root
    spacing: 12

    signal openPageRequested(string page)

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
                    text: root.barStatusMsg.length > 0 ? root.barStatusMsg : "Restore bar widgets, island, and shell defaults."
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    font.weight: root.barStatusMsg.length > 0 ? Font.DemiBold : Font.Normal
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
                    : (rstBarMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: Theme.activeControlBorderWidth
                border.color: root.confirmResetBar ? Theme.warning : Theme.cardBorder

                Text {
                    id: rstBarLbl
                    anchors.centerIn: parent
                    text: root.confirmResetBar ? "Confirm Reset?" : "󰑐 Reset Bar & Shell"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.Bold
                    color: root.confirmResetBar ? Theme.contrastInk(Theme.warning) : Theme.warning
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

    // --- 0. Active Top Bar Architecture ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: archCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: archCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Active Top Bar Architecture"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: jIslLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: jIslMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: jIslLbl
                        anchors.centerIn: parent
                        text: "󰀵 Island Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: jIslMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("island")
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: jSplLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: jSplMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: jSplLbl
                        anchors.centerIn: parent
                        text: "󰕰 Split Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.tertiary
                    }

                    MouseArea {
                        id: jSplMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("split")
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: jSeqLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: jSeqMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: jSeqLbl
                        anchors.centerIn: parent
                        text: "󰘔 Sequoia Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.DemiBold
                        color: Theme.secondary
                    }

                    MouseArea {
                        id: jSeqMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("sequoia")
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Dynamic Island and Sequoia Bar now have their own dedicated settings pages, hubs, and popovers. Switch your active top bar mode here, then customize its modules on its dedicated page."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10)
                color: Theme.fgSurfaceVariant
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ShellState.availableBarStyles

                    delegate: Rectangle {
                        id: archCard
                        required property var modelData
                        readonly property bool selected: !Theme.isSimple && ShellState.barUiStyle === archCard.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: archCardCol.implicitHeight + 16
                        radius: Theme.r(12)
                        color: archCard.selected
                            ? Theme.withAlpha(Theme.primary, 0.16)
                            : (archMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: archCard.selected ? 2 : Theme.subBorderWidth
                        border.color: archCard.selected ? Theme.primary : Theme.cardBorder

                        ColumnLayout {
                            id: archCardCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: archCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(14)
                                    color: archCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    text: archCard.modelData.label
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(11)
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: "· " + archCard.modelData.vibe
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: archCard.modelData.desc
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(9)
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: archMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Theme.isSimple)
                                    ShellState.setPrefsBatch({ shellMode: "default", barUiStyle: archCard.modelData.id });
                                else
                                    ShellState.setBarUiStyle(archCard.modelData.id);
                            }
                        }
                    }
                }
            }

            // Simple Edge Bar Quick Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: simplePickRow.implicitHeight + 14
                radius: Theme.r(11)
                color: Theme.isSimple
                    ? Theme.withAlpha(Theme.tertiary, 0.16)
                    : (simplePickMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: Theme.isSimple ? 2 : Theme.subBorderWidth
                border.color: Theme.isSimple ? Theme.tertiary : Theme.cardBorder

                RowLayout {
                    id: simplePickRow
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 8

                    Text {
                        text: "󰕮"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(15)
                        color: Theme.isSimple ? Theme.tertiary : Theme.fgSurfaceVariant
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: "Simple Edge Bar (Minimal Flat Mode)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "Classic full-width edge bar configured below without floating morphing surfaces"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(9)
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        text: Theme.isSimple ? "Active" : "Enable"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.isSimple ? Theme.tertiary : Theme.fgSurfaceVariant
                    }
                }

                MouseArea {
                    id: simplePickMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Theme.setShellMode(Theme.isSimple ? "default" : "simple")
                }
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
                text: "Simple Mode Edge Bar"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
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
                    font.pixelSize: Theme.fs(11)
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
                                ? Theme.primary
                                : (posMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: posPill.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                id: posTxt
                                anchors.centerIn: parent
                                text: posPill.modelData === "top" ? "Top" : "Bottom"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: posPill.selected ? Font.Bold : Font.Medium
                                color: posPill.selected ? Theme.fgPrimary : Theme.fgSurface
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
                    font.pixelSize: Theme.fs(11)
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
                    font.pixelSize: Theme.fs(11)
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
                text: "Screenshots & Recording"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.preferredWidth: 112
                    text: "Screenshots Folder"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: dirInput.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: dirInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: dirInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: ShellState.screenshotDir
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(10)
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
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: saveDirLbl
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.preferredWidth: 112
                    text: "Recordings Folder"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: recDirInput.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: recDirInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: recDirInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: ShellState.recordingDir
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurface
                        clip: true
                        onAccepted: {
                            if (text.trim().length > 0)
                                ShellState.setPref("recordingDir", text.trim());
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: saveRecDirLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: saveRecDirMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: saveRecDirLbl
                        anchors.centerIn: parent
                        text: "Save"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: saveRecDirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (recDirInput.text.trim().length > 0)
                                ShellState.setPref("recordingDir", recDirInput.text.trim());
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
                    font.pixelSize: Theme.fs(11)
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
                    font.pixelSize: Theme.fs(11)
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
                text: "Accessibility & Motion"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
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
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Disables spinning art, equalizer animation, and UI motion across Quickshell & GTK"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
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
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    Text {
                        text: "Forces crisp high-visibility borders across panels, cards, and GTK a11y schema"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
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
                    text: "File Manager"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: openFmLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: openFmMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary
                    border.width: Theme.activeControlBorderWidth
                    border.color: Theme.primary

                    Text {
                        id: openFmLbl
                        anchors.centerIn: parent
                        text: "󰉋 Open Files"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
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
                    border.width: Theme.activeControlBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: rstFmLbl
                        anchors.centerIn: parent
                        text: "Reset Style"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
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
                    font.pixelSize: Theme.fs(11)
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
                        color: sel ? Theme.primary : (fmVmMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmVmBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmVmBtn.sel ? Font.Bold : Font.Medium
                            color: fmVmBtn.sel ? Theme.fgPrimary : Theme.fgSurface
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
                Text { Layout.fillWidth: true; text: "Dual-Pane Split by Default (F3)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.fmDualPane; onToggled: ShellState.setPref("fmDualPane", !ShellState.fmDualPane) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Show Live Inspector / Preview Pane"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.fmPreviewVisible; onToggled: ShellState.setPref("fmPreviewVisible", !ShellState.fmPreviewVisible) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { Layout.fillWidth: true; text: "Show Hidden Dotfiles by Default (Ctrl+H)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                ToggleSwitch { checked: ShellState.fmShowHidden; onToggled: ShellState.setPref("fmShowHidden", !ShellState.fmShowHidden) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "FM Vibe Presets"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "finder",    label: "Finder" },
                        { id: "minimal",   label: "Minimal" },
                        { id: "gallery",   label: "Gallery" },
                        { id: "commander", label: "Commander" }
                    ]
                    delegate: Rectangle {
                        id: fmPreBtn
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: fmPreMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                        border.width: Theme.activeControlBorderWidth
                        border.color: Theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: fmPreBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: Font.Bold
                            color: fmPreMouse.containsMouse ? Theme.primary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmPreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ShellState.applyFmPreset(fmPreBtn.modelData.id);
                                root.barStatusMsg = "Applied File Manager preset: " + fmPreBtn.modelData.label;
                                barStatusTimer.restart();
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Sort Order"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "name",  label: "Name" },
                        { id: "size",  label: "Size" },
                        { id: "mtime", label: "Modified" },
                        { id: "ext",   label: "Extension" }
                    ]
                    delegate: Rectangle {
                        id: fmSortBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmSortBy === fmSortBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmSortMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmSortBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmSortBtn.sel ? Font.Bold : Font.Medium
                            color: fmSortBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmSortMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmSortBy", fmSortBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Row Density"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "compact",  label: "Compact" },
                        { id: "cozy",     label: "Cozy" },
                        { id: "spacious", label: "Spacious" }
                    ]
                    delegate: Rectangle {
                        id: fmDensBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmDensity === fmDensBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmDensMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmDensBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmDensBtn.sel ? Font.Bold : Font.Medium
                            color: fmDensBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmDensMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmDensity", fmDensBtn.modelData.id)
                        }
                    }
                }
            }

            StepControl {
                label: "Grid Tile Size"
                displayValue: ShellState.fmGridSize + " px"
                onDecremented: ShellState.setPref("fmGridSize", Math.max(84, ShellState.fmGridSize - 12))
                onIncremented: ShellState.setPref("fmGridSize", Math.min(172, ShellState.fmGridSize + 12))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Icon Badge Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "category", label: "Category" },
                        { id: "accent",   label: "Accent" },
                        { id: "mono",     label: "Mono" },
                        { id: "vivid",    label: "Vivid" }
                    ]
                    delegate: Rectangle {
                        id: fmIcoBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmIconStyle === fmIcoBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmIcoMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmIcoBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmIcoBtn.sel ? Font.Bold : Font.Medium
                            color: fmIcoBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmIcoMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmIconStyle", fmIcoBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Window Surface"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "inherit", label: "Inherit" },
                        { id: "glass",   label: "Glass" },
                        { id: "oled",    label: "OLED" },
                        { id: "tinted",  label: "Tinted" },
                        { id: "solid",   label: "Solid" }
                    ]
                    delegate: Rectangle {
                        id: fmSurfBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmSurfacePreset === fmSurfBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmSurfMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmSurfBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmSurfBtn.sel ? Font.Bold : Font.Medium
                            color: fmSurfBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmSurfMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmSurfacePreset", fmSurfBtn.modelData.id)
                        }
                    }
                }
            }

            StepControl {
                label: "File Manager Window Opacity"
                displayValue: Math.round(ShellState.fmOpacity * 100) + "%"
                onDecremented: ShellState.setPref("fmOpacity", Number(Math.max(0.60, ShellState.fmOpacity - 0.04).toFixed(2)))
                onIncremented: ShellState.setPref("fmOpacity", Number(Math.min(1.00, ShellState.fmOpacity + 0.04).toFixed(2)))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Toolbar Header"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "pill",      label: "Pill Header" },
                        { id: "minimal",   label: "Minimal" },
                        { id: "underline", label: "Underline" }
                    ]
                    delegate: Rectangle {
                        id: fmHdrBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmHeaderStyle === fmHdrBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmHdrMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmHdrBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmHdrBtn.sel ? Font.Bold : Font.Medium
                            color: fmHdrBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmHdrMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmHeaderStyle", fmHdrBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Sidebar Nav"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "standard", label: "Standard" },
                        { id: "compact",  label: "Compact" },
                        { id: "icons",    label: "Icons Only" }
                    ]
                    delegate: Rectangle {
                        id: fmSbBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmSidebarStyle === fmSbBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmSbMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmSbBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmSbBtn.sel ? Font.Bold : Font.Medium
                            color: fmSbBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmSbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmSidebarStyle", fmSbBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 110
                    text: "Dialog Size"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "compact",  label: "Compact" },
                        { id: "balanced", label: "Balanced" },
                        { id: "wide",     label: "Wide" },
                        { id: "max",      label: "Max" }
                    ]
                    delegate: Rectangle {
                        id: fmSzBtn
                        required property var modelData
                        readonly property bool sel: ShellState.fmWindowSize === fmSzBtn.modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: Theme.r(7)
                        color: sel ? Theme.primary : (fmSzMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: fmSzBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fmSzBtn.sel ? Font.Bold : Font.Medium
                            color: fmSzBtn.sel ? Theme.fgPrimary : Theme.fgSurface
                        }
                        MouseArea {
                            id: fmSzMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("fmWindowSize", fmSzBtn.modelData.id)
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 8

                Repeater {
                    model: [
                        { key: "fmDirsFirst",      label: "Folders First",         val: ShellState.fmDirsFirst },
                        { key: "fmSortDesc",       label: "Reverse Sort Order",    val: ShellState.fmSortDesc },
                        { key: "fmSidebarVisible", label: "Show Places Sidebar",   val: ShellState.fmSidebarVisible },
                        { key: "fmShowThumbnails", label: "Image Thumbnails",      val: ShellState.fmShowThumbnails },
                        { key: "fmRowAlternating", label: "Alternating List Rows", val: ShellState.fmRowAlternating },
                        { key: "fmShowSizes",      label: "Show File Sizes",       val: ShellState.fmShowSizes },
                        { key: "fmShowDates",      label: "Show Modified Dates",   val: ShellState.fmShowDates },
                        { key: "fmShowPerms",      label: "Show POSIX Perms",      val: ShellState.fmShowPerms }
                    ]
                    delegate: RowLayout {
                        id: fmFlagRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: fmFlagRow.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurface
                        }
                        ToggleSwitch {
                            checked: fmFlagRow.modelData.val
                            onToggled: ShellState.setPref(fmFlagRow.modelData.key, !fmFlagRow.modelData.val)
                        }
                    }
                }
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
                text: "Weather & Wallpaper Slideshow"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text { text: "Enable Opt-In Weather Widget (wttr.in)"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                    Text { text: "Caches conditions locally every 30 minutes when enabled"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
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

                Text { Layout.fillWidth: true; text: "Show Compact Weather Pill in Top Bar"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
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
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: locInput.activeFocus ? 1 : Theme.subBorderWidth
                    border.color: locInput.activeFocus ? Theme.primary : Theme.cardBorder

                    TextInput {
                        id: locInput
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        text: ShellState.weatherLocation
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurface
                        clip: true

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: locInput.text.length === 0
                            text: "Auto-detect by IP (or enter city)"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
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
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: "°" + ShellState.weatherUnits
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
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
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: saveLocLbl
                        anchors.centerIn: parent
                        text: "Apply"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
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
                    Text { text: "Automatic Wallpaper Slideshow"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); color: Theme.fgSurface }
                    Text { text: "Automatically rotates wallpaper & re-themes via Matugen"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(10); color: Theme.fgSurfaceVariant }
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
