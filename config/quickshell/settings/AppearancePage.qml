pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    signal openPageRequested(string page)

    property string cursorTheme: "catppuccin-mocha-dark-cursors"
    property int cursorSize: 24
    property int cursorHideTimeout: 0
    property bool cursorHideKeypress: false
    property var availableCursors: ["catppuccin-mocha-dark-cursors", "Adwaita"]
    property var sansFonts: ["IBM Plex Sans", "DejaVu Sans", "Liberation Sans"]
    property var monospaceFonts: ["IBM Plex Mono", "JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono"]
    property var allFonts: []
    property string fontPickerMode: "ui"         // "ui" | "mono" | "all"
    property string fontSearch: ""
    property var gtkInfo: ({
        iconTheme: ShellState.iconTheme,
        availableIconThemes: ["Adwaita"],
        fontHinting: "slight",
        fontAntialiasing: "grayscale",
        fontRgbaOrder: "rgb",
        textScalingFactor: 1.0,
        cursorBlink: true,
        cursorBlinkTime: 1200
    })
    property bool confirmResetAppearance: false
    property string resetStatusMsg: ""

    Timer {
        id: appResetConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmResetAppearance = false
    }

    Timer {
        id: appResetStatusTimer
        interval: 3500
        repeat: false
        onTriggered: root.resetStatusMsg = ""
    }

    Timer {
        id: appReloadTimer
        interval: 600
        repeat: false
        onTriggered: root.loadCursorSettings()
    }

    function loadCursorSettings(): void {
        if (!cursorReadProc.running)
            cursorReadProc.running = true;
        if (ShellState.cachedSansFonts.length > 0 && ShellState.cachedMonospaceFonts.length > 0 && ShellState.cachedAllFonts.length > 0) {
            root.sansFonts = ShellState.cachedSansFonts;
            root.monospaceFonts = ShellState.cachedMonospaceFonts;
            root.allFonts = ShellState.cachedAllFonts;
        } else if (!fontListProc.running) {
            fontListProc.running = true;
        }
        if (!gtkReadProc.running)
            gtkReadProc.running = true;
    }

    function setGtk(key: string, val: var): void {
        if (gtkMutProc.running)
            return;
        gtkMutProc.command = [Quickshell.shellPath("scripts/manage-system.sh"), "gtk-set", key, String(val)];
        gtkMutProc.running = true;
    }

    function setLocal(key: string, val: var): void {
        if (key === "cursor_theme")
            root.cursorTheme = String(val);
        else if (key === "cursor_size")
            root.cursorSize = Number(val);
        else if (key === "cursor_hide_timeout")
            root.cursorHideTimeout = Number(val);
        else if (key === "cursor_hide_on_keypress")
            root.cursorHideKeypress = !!val;

        const outVal = (typeof val === "boolean") ? (val ? "1" : "0") : String(val);
        Quickshell.execDetached([Quickshell.shellPath("scripts/apply-local-setting.sh"), "set", key, outVal]);
    }

    Component.onCompleted: loadCursorSettings()

    Process {
        id: cursorReadProc
        command: [Quickshell.shellPath("scripts/apply-local-setting.sh"), "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (typeof d.cursor_theme === "string")
                        root.cursorTheme = d.cursor_theme;
                    if (typeof d.cursor_size === "number")
                        root.cursorSize = d.cursor_size;
                    if (typeof d.cursor_hide_timeout === "number")
                        root.cursorHideTimeout = d.cursor_hide_timeout;
                    if (typeof d.cursor_hide_on_keypress === "boolean")
                        root.cursorHideKeypress = d.cursor_hide_on_keypress;
                    if (Array.isArray(d.availableCursors) && d.availableCursors.length > 0)
                        root.availableCursors = d.availableCursors;
                } catch (err) {}
            }
        }
    }

    Process {
        id: fontListProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "list-fonts"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (Array.isArray(d.sans) && d.sans.length > 0) {
                        root.sansFonts = d.sans;
                        ShellState.cachedSansFonts = d.sans;
                    }
                    if (Array.isArray(d.monospace) && d.monospace.length > 0) {
                        root.monospaceFonts = d.monospace;
                        ShellState.cachedMonospaceFonts = d.monospace;
                    }
                    if (Array.isArray(d.families) && d.families.length > 0) {
                        root.allFonts = d.families;
                        ShellState.cachedAllFonts = d.families;
                    }
                } catch (err) {}
            }
        }
    }

    Process {
        id: gtkReadProc
        command: [Quickshell.shellPath("scripts/manage-system.sh"), "gtk-get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && d.iconTheme !== undefined)
                        root.gtkInfo = d;
                } catch (err) {}
            }
        }
    }

    Process {
        id: gtkMutProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (d && d.iconTheme !== undefined)
                        root.gtkInfo = d;
                } catch (err) {}
            }
        }
    }

    // --- 0. Safe Recovery Row ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: appResetRow.implicitHeight + 14
        radius: Theme.r(12)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            id: appResetRow
            anchors.fill: parent
            anchors.margins: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.resetStatusMsg.length > 0
                    ? root.resetStatusMsg
                    : "Restore mode, surfaces, theme, fonts, cursor, and blur to defaults."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                font.weight: root.resetStatusMsg.length > 0 ? Font.DemiBold : Font.Normal
                color: root.resetStatusMsg.length > 0 ? Theme.success : Theme.fgSurfaceVariant
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: rstAppLbl.implicitWidth + 16
                radius: Theme.r(8)
                color: root.confirmResetAppearance
                    ? Theme.warning
                    : (rstAppMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: Theme.activeControlBorderWidth
                border.color: root.confirmResetAppearance ? Theme.warning : Theme.cardBorder

                Text {
                    id: rstAppLbl
                    anchors.centerIn: parent
                    text: root.confirmResetAppearance ? "Confirm Reset?" : "󰑐 Reset Appearance"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(10)
                    font.weight: Font.DemiBold
                    color: root.confirmResetAppearance ? Theme.contrastInk(Theme.warning) : Theme.warning
                }

                MouseArea {
                    id: rstAppMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.confirmResetAppearance) {
                            root.confirmResetAppearance = true;
                            appResetConfirmTimer.restart();
                            return;
                        }
                        root.confirmResetAppearance = false;
                        appResetConfirmTimer.stop();
                        ShellState.resetAppearance();
                        appReloadTimer.restart();
                        root.resetStatusMsg = "Restored default Appearance, Theme, Font & Cursor";
                        appResetStatusTimer.restart();
                    }
                }
            }
        }
    }

    // --- 1. Shell & MangoWC Visual Mode ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: modeCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: modeCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Visual Mode"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: schemeLbl.implicitWidth + 18
                    radius: Theme.r(12)
                    color: schemeBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder
                    scale: schemeBtnMouse.pressed ? 0.96 : 1.0

                    Behavior on color {
                        enabled: !Theme.reducedMotion
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.reducedMotion
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                    }

                    Text {
                        id: schemeLbl
                        anchors.centerIn: parent
                        text: Theme.colorScheme === "dark" ? "󰖔  Dark" : "󰖙  Light"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: schemeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.toggleScheme()
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: Theme.availableModes

                    delegate: Rectangle {
                        id: modeCard
                        required property var modelData
                        readonly property string mid: modeCard.modelData.id
                        readonly property bool selected: Theme.shellMode === mid

                        Layout.fillWidth: true
                        Layout.preferredHeight: 68
                        radius: {
                            if (mid === "simple") return 0;
                            if (mid === "retro") return 4;
                            if (mid === "neon") return 8;
                            return Theme.r(12);
                        }
                        color: modeCard.selected
                            ? Theme.tileActiveBg
                            : (modeCardMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: modeCard.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: modeCardMouse.pressed ? 0.97 : 1.0

                        Rectangle {
                            visible: modeCard.selected
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            width: 3
                            radius: 1.5
                            color: Theme.primary
                        }

                        Behavior on color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.reducedMotion
                            NumberAnimation { duration: 95; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            anchors.leftMargin: 12
                            spacing: 10

                            // Miniature Live-Styled Preview Frame
                            Rectangle {
                                implicitWidth: 42
                                implicitHeight: 42
                                radius: {
                                    if (modeCard.mid === "simple") return 0;
                                    if (modeCard.mid === "retro") return 3;
                                    if (modeCard.mid === "neon") return 6;
                                    return 10;
                                }
                                color: {
                                    if (modeCard.mid === "oled") return "#000000";
                                    if (modeCard.mid === "neon") return "#080810";
                                    if (modeCard.mid === "blur") return Theme.withAlpha(Theme.surfaceContainerHigh, 0.48);
                                    if (modeCard.mid === "retro") return Theme.surfaceContainer;
                                    return Theme.surfaceContainerLowest;
                                }
                                border.width: 1
                                border.color: Theme.hairlineBorder
                                clip: true

                                // Mode signature top flourish inside miniature preview
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: modeCard.mid === "retro" ? 3 : 2
                                    visible: modeCard.mid === "neon" || modeCard.mid === "retro" || modeCard.mid === "blur"
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: modeCard.mid === "blur" ? Qt.rgba(1, 1, 1, 0.45) : Theme.primary }
                                        GradientStop { position: 1.0; color: modeCard.mid === "neon" ? Theme.secondary : (modeCard.mid === "blur" ? Qt.rgba(1, 1, 1, 0.12) : Theme.primary) }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modeCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.fs(16)
                                    color: modeCard.selected ? Theme.primary : Theme.fgSurface
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: modeCard.modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(12)
                                        font.weight: Font.Bold
                                        color: Theme.fgSurface
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "· " + modeCard.modelData.vibe
                                        elide: Text.ElideRight
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fs(9)
                                        font.weight: Font.DemiBold
                                        color: Theme.fgSurfaceVariant
                                    }

                                    Rectangle {
                                        visible: modeCard.selected
                                        implicitWidth: 16
                                        implicitHeight: 16
                                        radius: 8
                                        color: Theme.primary

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰄬"
                                            font.family: Theme.iconFont
                                            font.pixelSize: Theme.fs(10)
                                            color: Theme.fgPrimary
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modeCard.modelData.shortDesc
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fs(9)
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: modeCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setShellMode(modeCard.mid)
                        }
                    }
                }
            }
        }
    }

    // --- 2. Shell Surface Finish & Transparency ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: surfCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: surfCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Surfaces & Transparency"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }

            // Surface Material Style
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 112
                    text: "Surface Finish"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: [
                            { id: "default", label: "Default" },
                            { id: "glass",   label: "Frosted Glass" },
                            { id: "oled",    label: "OLED Black" },
                            { id: "flat",    label: "Flat Minimal" },
                            { id: "tinted",  label: "Accent Tinted" }
                        ]

                        delegate: Rectangle {
                            id: surfChip
                            required property var modelData
                            readonly property bool selected: ShellState.surfaceStyle === surfChip.modelData.id

                            implicitHeight: 26
                            implicitWidth: surfChipLbl.implicitWidth + 14
                            radius: Theme.r(8)
                            color: surfChip.selected
                                ? Theme.primary
                                : (surfChipMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: surfChip.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                id: surfChipLbl
                                anchors.centerIn: parent
                                text: surfChip.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: surfChip.selected ? Font.Bold : Font.Medium
                                color: surfChip.selected ? Theme.fgPrimary : Theme.fgSurface
                            }

                            MouseArea {
                                id: surfChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("surfaceStyle", surfChip.modelData.id)
                            }
                        }
                    }
                }
            }

            StepControl {
                label: "Panel & Island Opacity"
                displayValue: Math.round(ShellState.shellOpacity * 100) + "%"
                onDecremented: ShellState.setPref("shellOpacity", Number(Math.max(0.40, ShellState.shellOpacity - 0.04).toFixed(2)))
                onIncremented: ShellState.setPref("shellOpacity", Number(Math.min(1.00, ShellState.shellOpacity + 0.04).toFixed(2)))
            }

            StepControl {
                label: "Card Background Opacity"
                displayValue: Math.round(ShellState.cardOpacity * 100) + "%"
                onDecremented: ShellState.setPref("cardOpacity", Number(Math.max(0.15, ShellState.cardOpacity - 0.05).toFixed(2)))
                onIncremented: ShellState.setPref("cardOpacity", Number(Math.min(1.00, ShellState.cardOpacity + 0.05).toFixed(2)))
            }

            // Corner Roundness Scale
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 112
                    text: "Corner Roundness"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { val: 0.0, label: "Sharp" },
                        { val: 0.5, label: "Subtle" },
                        { val: 1.0, label: "Balanced" },
                        { val: 1.4, label: "Pill" }
                    ]

                    delegate: Rectangle {
                        id: radChip
                        required property var modelData
                        readonly property bool selected: Math.abs(ShellState.uiRadiusScale - radChip.modelData.val) < 0.08

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: radChip.selected
                            ? Theme.primary
                            : (radChipMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: radChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: radChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: radChip.selected ? Font.Bold : Font.Medium
                            color: radChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: radChipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("uiRadiusScale", radChip.modelData.val)
                        }
                    }
                }
            }

            StepControl {
                label: "Corner Roundness Fine Scale"
                displayValue: Math.round(ShellState.uiRadiusScale * 100) + "%"
                onDecremented: ShellState.setPref("uiRadiusScale", Number(Math.max(0.0, ShellState.uiRadiusScale - 0.1).toFixed(2)))
                onIncremented: ShellState.setPref("uiRadiusScale", Number(Math.min(1.6, ShellState.uiRadiusScale + 0.1).toFixed(2)))
            }

            // Border Style
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 112
                    text: "Border Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { id: "none",   label: "None" },
                        { id: "subtle", label: "Subtle" },
                        { id: "accent", label: "Accent" },
                        { id: "glow",   label: "Glow" }
                    ]

                    delegate: Rectangle {
                        id: brdChip
                        required property var modelData
                        readonly property bool selected: ShellState.borderStyle === brdChip.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: brdChip.selected
                            ? Theme.primary
                            : (brdChipMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: brdChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: brdChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: brdChip.selected ? Font.Bold : Font.Medium
                            color: brdChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: brdChipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("borderStyle", brdChip.modelData.id)
                        }
                    }
                }
            }

            StepControl {
                label: "UI Border Width"
                displayValue: ShellState.uiBorderWidth + " px"
                controlEnabled: ShellState.borderStyle !== "none"
                onDecremented: ShellState.setPref("uiBorderWidth", Math.max(0, ShellState.uiBorderWidth - 1))
                onIncremented: ShellState.setPref("uiBorderWidth", Math.min(3, ShellState.uiBorderWidth + 1))
            }

            // Shell UI Text Scale
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 112
                    text: "Shell UI Text Scale"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [0.85, 0.95, 1.0, 1.1, 1.2]

                    delegate: Rectangle {
                        id: fsScaleChip
                        required property real modelData
                        readonly property bool selected: Math.abs(ShellState.uiFontScale - fsScaleChip.modelData) < 0.03

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: fsScaleChip.selected
                            ? Theme.primary
                            : (fsScaleMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: fsScaleChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            anchors.centerIn: parent
                            text: Math.round(fsScaleChip.modelData * 100) + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fsScaleChip.selected ? Font.Bold : Font.Medium
                            color: fsScaleChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: fsScaleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("uiFontScale", fsScaleChip.modelData)
                        }
                    }
                }
            }

            // Quick Links to Island & Sequoia pages
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Bar Shape & Menu Layout"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: appGoIslTxt.implicitWidth + 14
                    radius: Theme.r(7)
                    color: appGoIslMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: appGoIslTxt
                        anchors.centerIn: parent
                        text: "󰀵 Island Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }

                    MouseArea {
                        id: appGoIslMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("island")
                    }
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: appGoSeqTxt.implicitWidth + 14
                    radius: Theme.r(7)
                    color: appGoSeqMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: appGoSeqTxt
                        anchors.centerIn: parent
                        text: "󰘔 Sequoia Settings"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(9)
                        font.weight: Font.DemiBold
                        color: Theme.secondary
                    }

                    MouseArea {
                        id: appGoSeqMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPageRequested("sequoia")
                    }
                }
            }
        }
    }

    // --- 3. Typography & System Font ---
    Rectangle {
        id: fontCard
        Layout.fillWidth: true
        implicitHeight: fontCol.implicitHeight + 24
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        readonly property var displayedFonts: {
            let base = root.sansFonts;
            if (root.fontPickerMode === "mono")
                base = root.monospaceFonts;
            else if (root.fontPickerMode === "all" && root.allFonts.length > 0)
                base = root.allFonts;
            const q = root.fontSearch.trim().toLowerCase();
            if (q.length === 0)
                return base.slice(0, 24);
            const filtered = [];
            for (let i = 0; i < base.length; i++) {
                if (base[i].toLowerCase().indexOf(q) !== -1)
                    filtered.push(base[i]);
                if (filtered.length >= 24)
                    break;
            }
            return filtered;
        }

        ColumnLayout {
            id: fontCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Typography"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.DemiBold
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "UI: " + ShellState.uiFontFamily + "  ·  Mono: " + ShellState.monoFontFamily
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }
                }

                Repeater {
                    model: [
                        { id: "ui",   label: "Interface" },
                        { id: "mono", label: "Monospace" },
                        { id: "all",  label: "All" }
                    ]

                    delegate: Rectangle {
                        id: fpTab
                        required property var modelData
                        readonly property bool sel: root.fontPickerMode === fpTab.modelData.id
                        implicitHeight: 24
                        implicitWidth: fpLbl.implicitWidth + 14
                        radius: Theme.r(7)
                        color: fpTab.sel ? Theme.primary : (fpMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: fpTab.sel ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            id: fpLbl
                            anchors.centerIn: parent
                            text: fpTab.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fpTab.sel ? Font.Bold : Font.Normal
                            color: fpTab.sel ? Theme.fgPrimary : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: fpMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.fontPickerMode = fpTab.modelData.id
                        }
                    }
                }
            }

            // Optional Filter Input when exploring fonts
            Rectangle {
                visible: root.fontPickerMode === "all" || fontCard.displayedFonts.length > 10
                Layout.fillWidth: true
                implicitHeight: 28
                radius: Theme.r(8)
                color: Theme.subCardBg
                border.width: fontFilterInput.activeFocus ? 1 : Theme.subBorderWidth
                border.color: fontFilterInput.activeFocus ? Theme.primary : Theme.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    Text {
                        text: "󰍉"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurfaceVariant
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 16

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Filter font families..."
                            visible: fontFilterInput.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: fontFilterInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.fontSearch
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            color: Theme.fgSurface
                            clip: true
                            onTextEdited: root.fontSearch = text
                        }
                    }
                }
            }

            // Font Family Chips
            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: fontCard.displayedFonts

                    delegate: Rectangle {
                        id: fontPill
                        required property string modelData
                        readonly property bool isMonoPick: root.fontPickerMode === "mono"
                        readonly property bool selected: fontPill.isMonoPick
                            ? (ShellState.monoFontFamily === fontPill.modelData)
                            : (ShellState.uiFontFamily === fontPill.modelData)

                        implicitHeight: 28
                        implicitWidth: fontNameTxt.implicitWidth + 18
                        radius: Theme.r(8)
                        color: fontPill.selected
                            ? Theme.primary
                            : (fontPillMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: fontPill.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: fontPillMouse.pressed ? 0.96 : 1.0

                        Behavior on color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.reducedMotion
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            id: fontNameTxt
                            anchors.centerIn: parent
                            text: fontPill.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(11)
                            font.weight: fontPill.selected ? Font.Bold : Font.Normal
                            color: fontPill.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: fontPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (fontPill.isMonoPick)
                                    ShellState.setMonoFont(fontPill.modelData, ShellState.uiFontSize);
                                else
                                    ShellState.setFont(fontPill.modelData, ShellState.uiFontSize);
                            }
                        }
                    }
                }
            }

            // Lightweight 2-Font Live Preview (UI + Monospace without mmap'ing 24 list fonts)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fontPrevCol.implicitHeight + 14
                radius: Theme.r(10)
                color: Theme.subCardBg
                border.width: Theme.subBorderWidth
                border.color: Theme.cardBorder

                ColumnLayout {
                    id: fontPrevCol
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: ShellState.uiFontFamily + ": Pack my box with five dozen liquor jugs 0123456789"
                        font.family: ShellState.uiFontFamily
                        font.pixelSize: Theme.fs(11)
                        color: Theme.fgSurface
                    }

                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: ShellState.monoFontFamily + ": const aurora = () => [0x1F, true, null];"
                        font.family: ShellState.monoFontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.primary
                    }
                }
            }

            // Font Size + Sample Preview Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Font Size (GTK & Terminal)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    spacing: 5

                    Repeater {
                        model: [9, 10, 11, 12]

                        delegate: Rectangle {
                            id: fSzPill
                            required property int modelData
                            readonly property bool selected: ShellState.uiFontSize === fSzPill.modelData

                            implicitHeight: 24
                            implicitWidth: fSzLbl.implicitWidth + 14
                            radius: Theme.r(7)
                            color: fSzPill.selected
                                ? Theme.primary
                                : (fSzMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: fSzPill.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                id: fSzLbl
                                anchors.centerIn: parent
                                text: fSzPill.modelData + "pt"
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fs(10)
                                font.weight: fSzPill.selected ? Font.Bold : Font.Normal
                                color: fSzPill.selected ? Theme.fgPrimary : Theme.fgSurface
                            }

                            MouseArea {
                                id: fSzMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    ShellState.setFont(ShellState.uiFontFamily, fSzPill.modelData);
                                    ShellState.setMonoFont(ShellState.monoFontFamily, fSzPill.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 4. Cursor Theme, Size & Auto-Hide ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: curCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: curCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Cursor & Pointer"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.availableCursors

                    delegate: Rectangle {
                        id: curThemePill
                        required property string modelData
                        readonly property bool selected: root.cursorTheme === curThemePill.modelData

                        implicitHeight: 28
                        implicitWidth: curThemeRow.implicitWidth + 18
                        radius: Theme.r(9)
                        color: curThemePill.selected
                            ? Theme.primary
                            : (curThemeMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: curThemePill.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: curThemeMouse.pressed ? 0.96 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            id: curThemeRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                visible: curThemePill.selected
                                text: "󰄬"
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.fs(11)
                                color: Theme.fgPrimary
                            }

                            Text {
                                text: curThemePill.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: curThemePill.selected ? Font.Bold : Font.Medium
                                color: curThemePill.selected ? Theme.fgPrimary : Theme.fgSurface
                            }
                        }

                        MouseArea {
                            id: curThemeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLocal("cursor_theme", curThemePill.modelData)
                        }
                    }
                }
            }

            // Cursor Size
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Cursor Size"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [20, 24, 28, 32, 40, 48]

                    delegate: Rectangle {
                        id: curSzBtn
                        required property int modelData
                        readonly property bool selected: root.cursorSize === curSzBtn.modelData

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: curSzBtn.selected
                            ? Theme.primary
                            : (curSzMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: curSzBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: curSzMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: curSzBtn.modelData + "px"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: curSzBtn.selected ? Font.Bold : Font.Normal
                            color: curSzBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: curSzMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLocal("cursor_size", curSzBtn.modelData)
                        }
                    }
                }
            }

            // Auto-Hide Cursor Timeout
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 115
                    text: "Auto-Hide Idle"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { label: "Off", val: 0 },
                        { label: "2s",  val: 2 },
                        { label: "5s",  val: 5 },
                        { label: "10s", val: 10 }
                    ]

                    delegate: Rectangle {
                        id: hideBtn
                        required property var modelData
                        readonly property bool selected: root.cursorHideTimeout === hideBtn.modelData.val

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: hideBtn.selected
                            ? Theme.primary
                            : (hideMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: hideBtn.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: hideMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: hideBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: hideBtn.selected ? Font.Bold : Font.Normal
                            color: hideBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: hideMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setLocal("cursor_hide_timeout", hideBtn.modelData.val)
                        }
                    }
                }
            }

            // Hide Cursor on Keypress
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Hide Cursor While Typing"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: root.cursorHideKeypress
                    onToggled: root.setLocal("cursor_hide_on_keypress", !root.cursorHideKeypress)
                }
            }
        }
    }

    // --- 4. MangoWC Effects & Animations ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: tuneCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: tuneCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 9

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Animations & Window Effects"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: resetLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: resetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.subBorderWidth
                    border.color: Theme.cardBorder
                    scale: resetMouse.pressed ? 0.95 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }

                    Text {
                        id: resetLbl
                        anchors.centerIn: parent
                        text: "Reset Defaults"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        color: Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: resetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.resetModePrefs()
                    }
                }
            }

            // Animations Toggle Row
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Window & Layer Animations"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.wmAnimations
                    onToggled: Theme.updateModePref("animations", !Theme.wmAnimations)
                }
            }

            // Open Animation Type
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                opacity: Theme.wmAnimations ? 1.0 : 0.45

                Text {
                    Layout.preferredWidth: 115
                    text: "Open Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: ["zoom", "slide", "fade", "none"]

                    delegate: Rectangle {
                        id: openChip
                        required property string modelData
                        readonly property bool selected: Theme.animTypeOpen === openChip.modelData

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: openChip.selected
                            ? Theme.primary
                            : (openMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: openChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: openMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: openChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: openChip.selected ? Font.Bold : Font.Normal
                            color: openChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: openMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.updateModePref("animationTypeOpen", openChip.modelData)
                        }
                    }
                }
            }

            // Close Animation Type
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                opacity: Theme.wmAnimations ? 1.0 : 0.45

                Text {
                    Layout.preferredWidth: 115
                    text: "Close Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: ["slide", "zoom", "fade", "none"]

                    delegate: Rectangle {
                        id: closeChip
                        required property string modelData
                        readonly property bool selected: Theme.animTypeClose === closeChip.modelData

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: closeChip.selected
                            ? Theme.primary
                            : (closeChipMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: closeChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: closeChipMouse.pressed ? 0.95 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: closeChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: closeChip.selected ? Font.Bold : Font.Normal
                            color: closeChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: closeChipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.updateModePref("animationTypeClose", closeChip.modelData)
                        }
                    }
                }
            }

            // Tag Slide Direction
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                opacity: Theme.wmAnimations ? 1.0 : 0.45

                Text {
                    Layout.preferredWidth: 115
                    text: "Tag Slide"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: [
                        { label: "Horizontal", val: 1 },
                        { label: "Vertical",   val: 0 }
                    ]

                    delegate: Rectangle {
                        id: dirChip
                        required property var modelData
                        readonly property bool selected: Theme.tagAnimDirection === dirChip.modelData.val

                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Theme.r(8)
                        color: dirChip.selected
                            ? Theme.primary
                            : (dirMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: dirChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary
                        scale: dirMouse.pressed ? 0.96 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: dirChip.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: dirChip.selected ? Font.Bold : Font.Normal
                            color: dirChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: dirMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.updateModePref("tagAnimationDirection", dirChip.modelData.val)
                        }
                    }
                }
            }

            StepControl {
                label: "Animation Speed (Duration)"
                displayValue: Theme.animDuration + " ms"
                controlEnabled: Theme.wmAnimations
                onDecremented: Theme.updateModePref("animationDuration", Math.max(100, Theme.animDuration - 30))
                onIncremented: Theme.updateModePref("animationDuration", Math.min(560, Theme.animDuration + 30))
            }

            // Shadows Toggle Row
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Window Drop Shadows"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.wmShadows
                    onToggled: Theme.updateModePref("shadows", !Theme.wmShadows)
                }
            }

            StepControl {
                label: "Window Corner Radius"
                displayValue: Theme.defaultRadius + " px"
                onDecremented: Theme.updateModePref("defaultRadius", Math.max(0, Theme.defaultRadius - 2))
                onIncremented: Theme.updateModePref("defaultRadius", Math.min(28, Theme.defaultRadius + 2))
            }

            StepControl {
                label: "Window Gaps"
                displayValue: Theme.defaultGaps + " px"
                onDecremented: Theme.updateModePref("defaultGaps", Math.max(0, Theme.defaultGaps - 2))
                onIncremented: Theme.updateModePref("defaultGaps", Math.min(28, Theme.defaultGaps + 2))
            }

            StepControl {
                label: "Window Border Width"
                displayValue: Theme.defaultBorderPx + " px"
                onDecremented: Theme.updateModePref("defaultBorderPx", Math.max(0, Theme.defaultBorderPx - 1))
                onIncremented: Theme.updateModePref("defaultBorderPx", Math.min(4, Theme.defaultBorderPx + 1))
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Window Background Blur (Dual Kawase)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.blurEnabled
                    activeColor: Theme.secondary
                    onToggled: Theme.updateModePref("blurEnabled", !Theme.blurEnabled)
                }
            }

            StepControl {
                label: "Focused Window Opacity"
                displayValue: Theme.blurFocusedOpacity.toFixed(2)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurFocusedOpacity", Number(Math.max(0.50, Theme.blurFocusedOpacity - 0.02).toFixed(2)))
                onIncremented: Theme.updateModePref("blurFocusedOpacity", Number(Math.min(1.00, Theme.blurFocusedOpacity + 0.02).toFixed(2)))
            }

            StepControl {
                label: "Unfocused Window Opacity"
                displayValue: Theme.blurUnfocusedOpacity.toFixed(2)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurUnfocusedOpacity", Number(Math.max(0.50, Theme.blurUnfocusedOpacity - 0.02).toFixed(2)))
                onIncremented: Theme.updateModePref("blurUnfocusedOpacity", Number(Math.min(1.00, Theme.blurUnfocusedOpacity + 0.02).toFixed(2)))
            }

            StepControl {
                label: "Blur Radius"
                displayValue: Theme.blurRadius + " px"
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurRadius", Math.max(2, Theme.blurRadius - 1))
                onIncremented: Theme.updateModePref("blurRadius", Math.min(16, Theme.blurRadius + 1))
            }

            StepControl {
                label: "Blur Passes"
                displayValue: String(Theme.blurPasses)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurPasses", Math.max(1, Theme.blurPasses - 1))
                onIncremented: Theme.updateModePref("blurPasses", Math.min(6, Theme.blurPasses + 1))
            }

            StepControl {
                label: "Blur Saturation"
                displayValue: Theme.blurSaturation.toFixed(2)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurSaturation", Number(Math.max(0.80, Theme.blurSaturation - 0.05).toFixed(2)))
                onIncremented: Theme.updateModePref("blurSaturation", Number(Math.min(1.60, Theme.blurSaturation + 0.05).toFixed(2)))
            }

            StepControl {
                label: "Blur Brightness"
                displayValue: Theme.blurBrightness.toFixed(2)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurBrightness", Number(Math.max(0.65, Theme.blurBrightness - 0.05).toFixed(2)))
                onIncremented: Theme.updateModePref("blurBrightness", Number(Math.min(1.15, Theme.blurBrightness + 0.05).toFixed(2)))
            }

            StepControl {
                label: "Blur Noise"
                displayValue: Theme.blurNoise.toFixed(3)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurNoise", Number(Math.max(0.0, Theme.blurNoise - 0.005).toFixed(3)))
                onIncremented: Theme.updateModePref("blurNoise", Number(Math.min(0.10, Theme.blurNoise + 0.005).toFixed(3)))
            }

            StepControl {
                label: "Blur Contrast"
                displayValue: Theme.blurContrast.toFixed(2)
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurContrast", Number(Math.max(0.70, Theme.blurContrast - 0.05).toFixed(2)))
                onIncremented: Theme.updateModePref("blurContrast", Number(Math.min(1.30, Theme.blurContrast + 0.05).toFixed(2)))
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Blur Layer Surfaces & Optimized Dual Kawase"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.blurLayer
                    onToggled: Theme.updateModePref("blurLayer", !Theme.blurLayer)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Blur Cache Optimization"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.blurOptimized
                    onToggled: Theme.updateModePref("blurOptimized", !Theme.blurOptimized)
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Dim Unfocused Windows"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.dimEnable
                    onToggled: Theme.updateModePref("dimEnable", !Theme.dimEnable)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                opacity: Theme.wmShadows ? 1.0 : 0.45

                Text {
                    Layout.fillWidth: true
                    text: "Layer Drop Shadows & Floating-Only Shadows"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.layerShadows
                    onToggled: Theme.updateModePref("layerShadows", !Theme.layerShadows)
                }

                ToggleSwitch {
                    checked: Theme.shadowOnlyFloating
                    activeColor: Theme.secondary
                    onToggled: Theme.updateModePref("shadowOnlyFloating", !Theme.shadowOnlyFloating)
                }
            }

            StepControl {
                label: "Shadow Spread Size"
                displayValue: Theme.shadowsSize + " px"
                controlEnabled: Theme.wmShadows
                onDecremented: Theme.updateModePref("shadowsSize", Math.max(2, Theme.shadowsSize - 2))
                onIncremented: Theme.updateModePref("shadowsSize", Math.min(40, Theme.shadowsSize + 2))
            }

            StepControl {
                label: "Shadow Softness (Blur)"
                displayValue: Theme.shadowsBlur + " px"
                controlEnabled: Theme.wmShadows
                onDecremented: Theme.updateModePref("shadowsBlur", Math.max(2, Theme.shadowsBlur - 2))
                onIncremented: Theme.updateModePref("shadowsBlur", Math.min(48, Theme.shadowsBlur + 2))
            }

            RowLayout {
                Layout.fillWidth: true
                opacity: Theme.wmAnimations ? 1.0 : 0.45

                Text {
                    Layout.fillWidth: true
                    text: "Layer Animations & Fade In/Out"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: Theme.layerAnimations
                    onToggled: Theme.updateModePref("layerAnimations", !Theme.layerAnimations)
                }

                ToggleSwitch {
                    checked: Theme.animFadeIn && Theme.animFadeOut
                    activeColor: Theme.secondary
                    onToggled: {
                        const next = !(Theme.animFadeIn && Theme.animFadeOut);
                        Theme.updateModePref("animFadeIn", next);
                        Theme.updateModePref("animFadeOut", next);
                    }
                }
            }
        }
    }

    // --- 5. Wallpaper Transitions (awww / swww) ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: wpCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: wpCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: "Wallpaper Transitions"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(12)
                    font.weight: Font.DemiBold
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: reapLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: reapMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        id: reapLbl
                        anchors.centerIn: parent
                        text: "Re-apply Now"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fs(10)
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: reapMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.applyWallpaperWithCurrentMode(Theme.wallpaperPath)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 120
                    text: "Transition Effect"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: ["grow", "wipe", "fade", "wave", "outer", "simple", "none"]

                        delegate: Rectangle {
                            id: trChip
                            required property string modelData
                            readonly property bool selected: ShellState.wallpaperTransition === trChip.modelData

                            implicitHeight: 24
                            implicitWidth: trTxt.implicitWidth + 12
                            radius: Theme.r(7)
                            color: trChip.selected
                                ? Theme.primary
                                : (trMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                            border.width: trChip.selected ? Theme.activeControlBorderWidth : 0
                            border.color: Theme.primary

                            Text {
                                id: trTxt
                                anchors.centerIn: parent
                                text: trChip.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fs(10)
                                font.weight: trChip.selected ? Font.Bold : Font.Medium
                                color: trChip.selected ? Theme.fgPrimary : Theme.fgSurface
                            }

                            MouseArea {
                                id: trMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("wallpaperTransition", trChip.modelData)
                            }
                        }
                    }
                }
            }

            StepControl {
                label: "Wallpaper Transition Speed"
                displayValue: ShellState.wallpaperDuration.toFixed(2) + " s"
                onDecremented: ShellState.setPref("wallpaperDuration", Number(Math.max(0.10, ShellState.wallpaperDuration - 0.15).toFixed(2)))
                onIncremented: ShellState.setPref("wallpaperDuration", Number(Math.min(2.50, ShellState.wallpaperDuration + 0.15).toFixed(2)))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: "Wallpaper Scaling & FPS"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: ["crop", "fit", "no"]

                    delegate: Rectangle {
                        id: rzChip
                        required property string modelData
                        readonly property bool selected: ShellState.wallpaperResize === rzChip.modelData

                        implicitHeight: 24
                        implicitWidth: rzTxt.implicitWidth + 10
                        radius: Theme.r(7)
                        color: rzChip.selected ? Theme.primary : Theme.subCardBg
                        border.width: rzChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            id: rzTxt
                            anchors.centerIn: parent
                            text: rzChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: rzChip.selected ? Font.Bold : Font.Medium
                            color: rzChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("wallpaperResize", rzChip.modelData)
                        }
                    }
                }

                Repeater {
                    model: [30, 60, 120, 144]

                    delegate: Rectangle {
                        id: fpsChip
                        required property int modelData
                        readonly property bool selected: ShellState.wallpaperFps === fpsChip.modelData

                        implicitHeight: 24
                        implicitWidth: fpsTxt.implicitWidth + 10
                        radius: Theme.r(7)
                        color: fpsChip.selected ? Theme.primary : Theme.subCardBg
                        border.width: fpsChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            id: fpsTxt
                            anchors.centerIn: parent
                            text: fpsChip.modelData + "fps"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: fpsChip.selected ? Font.Bold : Font.Medium
                            color: fpsChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("wallpaperFps", fpsChip.modelData)
                        }
                    }
                }
            }
        }
    }

    // --- 6. GTK, Icons & Font Rendering ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: gtkCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: gtkCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Icons & GTK Rendering"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(12)
                font.weight: Font.DemiBold
                color: Theme.fgSurface
            }

            Text {
                text: "Icon Theme (" + String(root.gtkInfo.iconTheme || "Adwaita") + ")"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(11)
                color: Theme.fgSurface
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.gtkInfo.availableIconThemes || ["Adwaita"]

                    delegate: Rectangle {
                        id: icChip
                        required property string modelData
                        readonly property bool selected: root.gtkInfo.iconTheme === icChip.modelData

                        implicitHeight: 26
                        implicitWidth: icTxt.implicitWidth + 14
                        radius: Theme.r(8)
                        color: icChip.selected
                            ? Theme.primary
                            : (icMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                        border.width: icChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            id: icTxt
                            anchors.centerIn: parent
                            text: icChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: icChip.selected ? Font.Bold : Font.Medium
                            color: icChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: icMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setGtk("icon-theme", icChip.modelData)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: "Font Hinting"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: ["none", "slight", "medium", "full"]

                    delegate: Rectangle {
                        id: hntChip
                        required property string modelData
                        readonly property bool selected: root.gtkInfo.fontHinting === hntChip.modelData

                        implicitHeight: 24
                        implicitWidth: hntTxt.implicitWidth + 12
                        radius: Theme.r(7)
                        color: hntChip.selected ? Theme.primary : Theme.subCardBg
                        border.width: hntChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            id: hntTxt
                            anchors.centerIn: parent
                            text: hntChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: hntChip.selected ? Font.Bold : Font.Medium
                            color: hntChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setGtk("font-hinting", hntChip.modelData)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: "Antialiasing & Subpixel"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                Repeater {
                    model: ["none", "grayscale", "rgba"]

                    delegate: Rectangle {
                        id: aaChip
                        required property string modelData
                        readonly property bool selected: root.gtkInfo.fontAntialiasing === aaChip.modelData

                        implicitHeight: 24
                        implicitWidth: aaTxt.implicitWidth + 10
                        radius: Theme.r(7)
                        color: aaChip.selected ? Theme.primary : Theme.subCardBg
                        border.width: aaChip.selected ? Theme.activeControlBorderWidth : 0
                        border.color: Theme.primary

                        Text {
                            id: aaTxt
                            anchors.centerIn: parent
                            text: aaChip.modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(10)
                            font.weight: aaChip.selected ? Font.Bold : Font.Medium
                            color: aaChip.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setGtk("font-antialiasing", aaChip.modelData)
                        }
                    }
                }
            }

            StepControl {
                label: "GTK UI Text Scale Factor"
                displayValue: Number(root.gtkInfo.textScalingFactor || 1.0).toFixed(2) + "x"
                onDecremented: root.setGtk("text-scaling-factor", Math.max(0.80, Number(root.gtkInfo.textScalingFactor || 1.0) - 0.05).toFixed(2))
                onIncremented: root.setGtk("text-scaling-factor", Math.min(1.60, Number(root.gtkInfo.textScalingFactor || 1.0) + 0.05).toFixed(2))
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Text Cursor Blinking (GTK)"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(11)
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: !!root.gtkInfo.cursorBlink
                    onToggled: root.setGtk("cursor-blink", !root.gtkInfo.cursorBlink)
                }
            }

            StepControl {
                label: "Text Cursor Blink Interval"
                displayValue: Number(root.gtkInfo.cursorBlinkTime || 1200) + " ms"
                controlEnabled: !!root.gtkInfo.cursorBlink
                onDecremented: root.setGtk("cursor-blink-time", Math.max(400, Number(root.gtkInfo.cursorBlinkTime || 1200) - 200))
                onIncremented: root.setGtk("cursor-blink-time", Math.min(2400, Number(root.gtkInfo.cursorBlinkTime || 1200) + 200))
            }
        }
    }
}
