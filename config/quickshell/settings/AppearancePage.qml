pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property string cursorTheme: "catppuccin-mocha-dark-cursors"
    property int cursorSize: 24
    property int cursorHideTimeout: 0
    property bool cursorHideKeypress: false
    property var availableCursors: ["catppuccin-mocha-dark-cursors", "Adwaita"]

    function loadCursorSettings(): void {
        if (!cursorReadProc.running)
            cursorReadProc.running = true;
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

            Text {
                text: "VISUAL MODE (QUICKSHELL + MANGOWC)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { id: "default", title: "Default", desc: "Dynamic Island & rounded windows", icon: "󰕮" },
                        { id: "simple",  title: "Simple",  desc: "0px square, flat bar, zero gaps",  icon: "󰝤" },
                        { id: "blur",    title: "Blur",    desc: "Frosted glass & blurry windows",   icon: "󰂵" }
                    ]

                    delegate: Rectangle {
                        id: modeCard
                        required property var modelData
                        readonly property bool selected: Theme.shellMode === modeCard.modelData.id

                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        radius: Theme.r(12)
                        color: modeCard.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (modeCardMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: modeCard.selected ? 1 : Theme.cardBorderWidth
                        border.color: modeCard.selected ? Theme.primary : Theme.cardBorder
                        scale: modeCardMouse.pressed ? 0.97 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: modeCard.modelData.icon
                                    font.family: Theme.iconFont
                                    font.pixelSize: 15
                                    color: modeCard.selected ? Theme.primary : Theme.fgSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modeCard.modelData.title
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: modeCard.selected ? Theme.primary : Theme.fgSurface
                                }

                                Text {
                                    visible: modeCard.selected
                                    text: "󰄬"
                                    font.family: Theme.iconFont
                                    font.pixelSize: 13
                                    color: Theme.primary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modeCard.modelData.desc
                                wrapMode: Text.WordWrap
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: modeCardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setShellMode(modeCard.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // --- 2. Palette & Color Scheme ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: themeCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: themeCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "THEME & PALETTE"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: schemeLbl.implicitWidth + 18
                    radius: Theme.r(12)
                    color: schemeBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    scale: schemeBtnMouse.pressed ? 0.96 : 1.0

                    Behavior on color {
                        enabled: !Theme.isSimple
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        enabled: !Theme.isSimple
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                    }

                    Text {
                        id: schemeLbl
                        anchors.centerIn: parent
                        text: (Theme.colorScheme === "dark" ? "󰖔  Dark" : "󰖙  Light")
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        { id: "dynamic", label: "Dynamic (Matugen)" },
                        { id: "preset",  label: "Preset Palette" }
                    ]

                    delegate: Rectangle {
                        id: palModeBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === palModeBtn.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(10)
                        color: palModeBtn.selected
                            ? Theme.primary
                            : (palModeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: Theme.cardBorderWidth
                        border.color: palModeBtn.selected ? Theme.primary : Theme.cardBorder
                        scale: palModeMouse.pressed ? 0.97 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: palModeBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: palModeBtn.selected ? Font.Bold : Font.Medium
                            color: palModeBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: palModeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setMode(palModeBtn.modelData.id)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: Theme.availablePresets

                    delegate: Rectangle {
                        id: presetBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === "preset" && Theme.presetName === presetBtn.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(10)
                        color: presetBtn.selected
                            ? Theme.activeBg
                            : (presetBtnMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: presetBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: presetBtn.selected ? Theme.primary : Theme.cardBorder
                        scale: presetBtnMouse.pressed ? 0.97 : 1.0

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.isSimple
                            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: Theme.r(5)
                                color: presetBtn.modelData.swatch
                            }

                            Text {
                                text: presetBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: presetBtn.selected ? Font.Bold : Font.Medium
                                color: presetBtn.selected ? Theme.primary : Theme.fgSurface
                            }
                        }

                        MouseArea {
                            id: presetBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.applyPreset(presetBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // --- 3. Cursor Theme, Size & Auto-Hide ---
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
                text: "CURSOR & POINTER THEME (MANGOWC + GTK)"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                color: Theme.fgSurfaceVariant
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
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (curThemeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: curThemePill.selected ? 1 : Theme.cardBorderWidth
                        border.color: curThemePill.selected ? Theme.primary : Theme.cardBorder
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
                                font.pixelSize: 11
                                color: Theme.primary
                            }

                            Text {
                                text: curThemePill.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: curThemePill.selected ? Font.Bold : Font.Medium
                                color: curThemePill.selected ? Theme.primary : Theme.fgSurface
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
                    font.pixelSize: 11
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
                            ? Theme.withAlpha(Theme.secondary, 0.22)
                            : (curSzMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: curSzBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: curSzBtn.selected ? Theme.secondary : Theme.cardBorder
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
                            font.pixelSize: 10
                            font.weight: curSzBtn.selected ? Font.Bold : Font.Normal
                            color: curSzBtn.selected ? Theme.secondary : Theme.fgSurface
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
                    font.pixelSize: 11
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
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (hideMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: hideBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: hideBtn.selected ? Theme.primary : Theme.cardBorder
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
                            font.pixelSize: 10
                            font.weight: hideBtn.selected ? Font.Bold : Font.Normal
                            color: hideBtn.selected ? Theme.primary : Theme.fgSurface
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
                    font.pixelSize: 11
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
                    text: "MANGOWC ANIMATIONS & EFFECTS"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 22
                    implicitWidth: resetLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: resetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
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
                        font.pixelSize: 10
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

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 28
                visible: Theme.isSimple
                radius: Theme.r(8)
                color: Theme.withAlpha(Theme.warning, 0.14)
                border.width: 1
                border.color: Theme.withAlpha(Theme.warning, 0.4)

                Text {
                    anchors.centerIn: parent
                    text: "Simple Mode enforces 0px radius, zero gaps, and no blur/animations."
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.warning
                }
            }

            // Animations Toggle Row
            RowLayout {
                Layout.fillWidth: true
                opacity: Theme.isSimple ? 0.5 : 1.0

                Text {
                    Layout.fillWidth: true
                    text: "Window & Layer Animations"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
                opacity: (!Theme.isSimple && Theme.wmAnimations) ? 1.0 : 0.45

                Text {
                    Layout.preferredWidth: 115
                    text: "Open Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (openMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: openChip.selected ? 1 : Theme.cardBorderWidth
                        border.color: openChip.selected ? Theme.primary : Theme.cardBorder
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
                            font.pixelSize: 10
                            font.weight: openChip.selected ? Font.Bold : Font.Normal
                            color: openChip.selected ? Theme.primary : Theme.fgSurface
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
                opacity: (!Theme.isSimple && Theme.wmAnimations) ? 1.0 : 0.45

                Text {
                    Layout.preferredWidth: 115
                    text: "Close Style"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (closeChipMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: closeChip.selected ? 1 : Theme.cardBorderWidth
                        border.color: closeChip.selected ? Theme.primary : Theme.cardBorder
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
                            font.pixelSize: 10
                            font.weight: closeChip.selected ? Font.Bold : Font.Normal
                            color: closeChip.selected ? Theme.primary : Theme.fgSurface
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
                opacity: (!Theme.isSimple && Theme.wmAnimations) ? 1.0 : 0.45

                Text {
                    Layout.preferredWidth: 115
                    text: "Tag Slide"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
                            ? Theme.withAlpha(Theme.secondary, 0.22)
                            : (dirMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: dirChip.selected ? 1 : Theme.cardBorderWidth
                        border.color: dirChip.selected ? Theme.secondary : Theme.cardBorder
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
                            font.pixelSize: 10
                            font.weight: dirChip.selected ? Font.Bold : Font.Normal
                            color: dirChip.selected ? Theme.secondary : Theme.fgSurface
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
                controlEnabled: !Theme.isSimple && Theme.wmAnimations
                onDecremented: Theme.updateModePref("animationDuration", Math.max(120, Theme.animDuration - 40))
                onIncremented: Theme.updateModePref("animationDuration", Math.min(560, Theme.animDuration + 40))
            }

            // Shadows Toggle Row
            RowLayout {
                Layout.fillWidth: true
                opacity: Theme.isSimple ? 0.5 : 1.0

                Text {
                    Layout.fillWidth: true
                    text: "Window Drop Shadows"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
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
                controlEnabled: !Theme.isSimple
                onDecremented: Theme.updateModePref("defaultRadius", Math.max(0, Theme.defaultRadius - 2))
                onIncremented: Theme.updateModePref("defaultRadius", Math.min(28, Theme.defaultRadius + 2))
            }

            StepControl {
                label: "Window Gaps"
                displayValue: Theme.defaultGaps + " px"
                controlEnabled: !Theme.isSimple
                onDecremented: Theme.updateModePref("defaultGaps", Math.max(0, Theme.defaultGaps - 2))
                onIncremented: Theme.updateModePref("defaultGaps", Math.min(24, Theme.defaultGaps + 2))
            }

            StepControl {
                label: "Window Border Width"
                displayValue: Theme.defaultBorderPx + " px"
                controlEnabled: !Theme.isSimple
                onDecremented: Theme.updateModePref("defaultBorderPx", Math.max(0, Theme.defaultBorderPx - 1))
                onIncremented: Theme.updateModePref("defaultBorderPx", Math.min(4, Theme.defaultBorderPx + 1))
            }

            StepControl {
                label: "Blur Focused Opacity"
                displayValue: Theme.blurFocusedOpacity.toFixed(2)
                controlEnabled: !Theme.isSimple
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurFocusedOpacity", Number(Math.max(0.60, Theme.blurFocusedOpacity - 0.02).toFixed(2)))
                onIncremented: Theme.updateModePref("blurFocusedOpacity", Number(Math.min(1.00, Theme.blurFocusedOpacity + 0.02).toFixed(2)))
            }

            StepControl {
                label: "Blur Unfocused Opacity"
                displayValue: Theme.blurUnfocusedOpacity.toFixed(2)
                controlEnabled: !Theme.isSimple
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurUnfocusedOpacity", Number(Math.max(0.50, Theme.blurUnfocusedOpacity - 0.02).toFixed(2)))
                onIncremented: Theme.updateModePref("blurUnfocusedOpacity", Number(Math.min(0.98, Theme.blurUnfocusedOpacity + 0.02).toFixed(2)))
            }

            StepControl {
                label: "Blur Radius"
                displayValue: Theme.blurRadius + " px"
                controlEnabled: !Theme.isSimple
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurRadius", Math.max(2, Theme.blurRadius - 1))
                onIncremented: Theme.updateModePref("blurRadius", Math.min(16, Theme.blurRadius + 1))
            }

            StepControl {
                label: "Blur Passes"
                displayValue: String(Theme.blurPasses)
                controlEnabled: !Theme.isSimple
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurPasses", Math.max(1, Theme.blurPasses - 1))
                onIncremented: Theme.updateModePref("blurPasses", Math.min(6, Theme.blurPasses + 1))
            }

            StepControl {
                label: "Blur Saturation"
                displayValue: Theme.blurSaturation.toFixed(2)
                controlEnabled: !Theme.isSimple
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurSaturation", Number(Math.max(0.80, Theme.blurSaturation - 0.05).toFixed(2)))
                onIncremented: Theme.updateModePref("blurSaturation", Number(Math.min(1.60, Theme.blurSaturation + 0.05).toFixed(2)))
            }

            StepControl {
                label: "Blur Brightness"
                displayValue: Theme.blurBrightness.toFixed(2)
                controlEnabled: !Theme.isSimple
                accentColor: Theme.secondary
                onDecremented: Theme.updateModePref("blurBrightness", Number(Math.max(0.65, Theme.blurBrightness - 0.05).toFixed(2)))
                onIncremented: Theme.updateModePref("blurBrightness", Number(Math.min(1.15, Theme.blurBrightness + 0.05).toFixed(2)))
            }
        }
    }
}
