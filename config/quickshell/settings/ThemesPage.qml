pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ColumnLayout {
    id: root
    spacing: 12

    property string statusMsg: ""
    property bool statusError: false
    property string seedHex: ShellState.accentSeedColor.length > 0 ? ShellState.accentSeedColor : Theme.accentColor
    property int seedR: 203
    property int seedG: 166
    property int seedB: 247

    property string wallpaperDirInput: ShellState.wallpaperDir
    property var wallpapersList: []
    property var extractedColors: []
    property var customThemes: []
    property string saveThemeName: ""
    property string importThemePath: ""

    property string mangoFocusInput: ShellState.mangoFocusColor
    property string mangoBorderInput: ShellState.mangoBorderColor

    property string slotPrimary: "#cba6f7"
    property string slotSecondary: "#89b4fa"
    property string slotTertiary: "#f5c2e7"
    property string slotBackground: "#11111b"
    property string slotSurface: "#1e1e2e"
    property string slotOnSurface: "#cdd6f4"
    property string slotOutline: "#6c7086"
    property string slotError: "#f38ba8"
    property string slotSuccess: "#a6e3a1"
    property string slotWarning: "#f9e2af"

    property string _pendingActionMsg: ""
    property string _lastActionCmd: ""
    property string _lastActionStderr: ""
    property bool confirmResetTheme: false

    Timer {
        id: themeResetConfirmTimer
        interval: 4000
        repeat: false
        onTriggered: root.confirmResetTheme = false
    }

    readonly property var vibeModels: [
        { id: "aurora-glass",   title: "Aurora Glass",   desc: "Frosted blur · Catppuccin · pill",   c1: "#1e1e2e", c2: "#cba6f7", c3: "#89b4fa" },
        { id: "minimal-square", title: "Minimal Square", desc: "Simple 0px flat bar · Nord",         c1: "#2e3440", c2: "#88c0d0", c3: "#81a1c1" },
        { id: "oled-stealth",   title: "OLED Stealth",   desc: "True #000 black · top notch",        c1: "#050507", c2: "#82aaff", c3: "#c792ea" },
        { id: "neon-cyber",     title: "Neon Cyber",     desc: "Tinted blur · glow · neon shadows",  c1: "#121220", c2: "#00f0ff", c3: "#fcee09" },
        { id: "cozy-paper",     title: "Cozy Paper",     desc: "Warm light · Rose Pine Dawn",        c1: "#fffaf3", c2: "#d7827e", c3: "#907aa9" },
        { id: "full-dock-bar",  title: "Full Dock Bar",  desc: "Full-width bar · Tokyo Night glass", c1: "#1a1b26", c2: "#7aa2f7", c3: "#bb9af7" },
        { id: "warm-gruvbox",   title: "Warm Gruvbox",   desc: "Retro earthy palette · soft radius", c1: "#282828", c2: "#fabd2f", c3: "#83a598" },
        { id: "dracula-notch",  title: "Dracula Notch",  desc: "Frosted notch · Dracula · glow",     c1: "#282a36", c2: "#bd93f9", c3: "#ff79c6" }
    ]

    readonly property var seedSwatches: [
        "#cba6f7", "#89b4fa", "#f38ba8", "#a6e3a1",
        "#fabd2f", "#fe8019", "#00f0ff", "#ff79c6",
        "#ebbcba", "#3ddbd9", "#ff5555", "#7aa2f7",
        "#9ece6a", "#e0af68", "#b48ead", "#f28fad"
    ]

    readonly property var solidWallpapers: [
        "#000000", "#11111b", "#1e1e2e", "#1a1b26", "#282828",
        "#2e3440", "#002b36", "#eff1f5", "#faf4ed", "#fbf1c7"
    ]

    readonly property var matugenSchemes: [
        "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
        "scheme-fidelity", "scheme-content", "scheme-neutral",
        "scheme-monochrome", "scheme-rainbow", "scheme-fruit-salad", "scheme-smart"
    ]

    readonly property var slotDescriptors: [
        { key: "primary",    label: "Primary" },
        { key: "secondary",  label: "Secondary" },
        { key: "tertiary",   label: "Tertiary" },
        { key: "background", label: "Background" },
        { key: "surface",    label: "Surface" },
        { key: "onSurface",  label: "Text" },
        { key: "outline",    label: "Outline" },
        { key: "error",      label: "Error" },
        { key: "success",    label: "Success" },
        { key: "warning",    label: "Warning" }
    ]

    function isValidHex(val: string): bool {
        return /^#[0-9a-fA-F]{6}$/.test((val || "").trim());
    }

    function normalizeHex(val: string, fallback: string): string {
        const clean = (val || "").trim();
        const prefixed = clean.startsWith("#") ? clean : ("#" + clean);
        return /^#[0-9a-fA-F]{6}$/.test(prefixed) ? prefixed.toLowerCase() : fallback;
    }

    function colorToHex(col: color): string {
        const toByte = x => Math.max(0, Math.min(255, Math.round(x * 255)));
        const toHex2 = n => (n < 16 ? "0" : "") + n.toString(16);
        return "#" + toHex2(toByte(col.r)) + toHex2(toByte(col.g)) + toHex2(toByte(col.b));
    }

    function syncSeedRgbFromHex(hexStr: string): void {
        if (!isValidHex(hexStr))
            return;
        const clean = hexStr.trim().slice(1);
        root.seedR = parseInt(clean.slice(0, 2), 16);
        root.seedG = parseInt(clean.slice(2, 4), 16);
        root.seedB = parseInt(clean.slice(4, 6), 16);
    }

    function updateSeedFromRgb(rVal: int, gVal: int, bVal: int): void {
        const clamp = v => Math.max(0, Math.min(255, Math.round(v)));
        const r = clamp(rVal);
        const g = clamp(gVal);
        const b = clamp(bVal);
        const toHex2 = n => (n < 16 ? "0" : "") + n.toString(16);
        root.seedR = r;
        root.seedG = g;
        root.seedB = b;
        root.seedHex = "#" + toHex2(r) + toHex2(g) + toHex2(b);
    }

    function getSlotValue(key: string): string {
        if (key === "primary") return root.slotPrimary;
        if (key === "secondary") return root.slotSecondary;
        if (key === "tertiary") return root.slotTertiary;
        if (key === "background") return root.slotBackground;
        if (key === "surface") return root.slotSurface;
        if (key === "onSurface") return root.slotOnSurface;
        if (key === "outline") return root.slotOutline;
        if (key === "error") return root.slotError;
        if (key === "success") return root.slotSuccess;
        if (key === "warning") return root.slotWarning;
        return "#cba6f7";
    }

    function setSlotValue(key: string, val: string): void {
        if (key === "primary") root.slotPrimary = val;
        else if (key === "secondary") root.slotSecondary = val;
        else if (key === "tertiary") root.slotTertiary = val;
        else if (key === "background") root.slotBackground = val;
        else if (key === "surface") root.slotSurface = val;
        else if (key === "onSurface") root.slotOnSurface = val;
        else if (key === "outline") root.slotOutline = val;
        else if (key === "error") root.slotError = val;
        else if (key === "success") root.slotSuccess = val;
        else if (key === "warning") root.slotWarning = val;
    }

    function syncSlotsFromTheme(): void {
        root.slotPrimary = colorToHex(Theme.primary);
        root.slotSecondary = colorToHex(Theme.secondary);
        root.slotTertiary = colorToHex(Theme.tertiary);
        root.slotBackground = colorToHex(Theme.background);
        root.slotSurface = colorToHex(Theme.surface);
        root.slotOnSurface = colorToHex(Theme.fgSurface);
        root.slotOutline = colorToHex(Theme.outline);
        root.slotError = colorToHex(Theme.error);
        root.slotSuccess = colorToHex(Theme.success);
        root.slotWarning = colorToHex(Theme.warning);
    }

    function showStatus(msg: string, isError: bool): void {
        root.statusMsg = msg;
        root.statusError = isError;
        statusTimer.restart();
    }

    function loadWallpapers(): void {
        if (!wallpapersProc.running)
            wallpapersProc.running = true;
    }

    function loadWallpaperColors(): void {
        if (Theme.wallpaperPath.length === 0)
            return;
        wpColorsProc.command = [Quickshell.shellPath("scripts/manage-themes.sh"), "wallpaper-colors", Theme.wallpaperPath];
        wpColorsProc.running = true;
    }

    function loadCustomThemes(): void {
        if (!customListProc.running)
            customListProc.running = true;
    }

    function runAction(args: list<string>, okMessage: string): void {
        if (actionProc.running)
            return;
        root._pendingActionMsg = okMessage;
        root._lastActionCmd = args.length > 0 ? args[0] : "";
        root._lastActionStderr = "";
        actionProc.command = [Quickshell.shellPath("scripts/manage-themes.sh")].concat(args);
        actionProc.running = true;
    }

    function applyPaletteSlots(): void {
        const payload = {
            isDark: Theme.isDark,
            primary: normalizeHex(root.slotPrimary, colorToHex(Theme.primary)),
            secondary: normalizeHex(root.slotSecondary, colorToHex(Theme.secondary)),
            tertiary: normalizeHex(root.slotTertiary, colorToHex(Theme.tertiary)),
            background: normalizeHex(root.slotBackground, colorToHex(Theme.background)),
            surface: normalizeHex(root.slotSurface, colorToHex(Theme.surface)),
            onSurface: normalizeHex(root.slotOnSurface, colorToHex(Theme.fgSurface)),
            outline: normalizeHex(root.slotOutline, colorToHex(Theme.outline)),
            error: normalizeHex(root.slotError, colorToHex(Theme.error)),
            success: normalizeHex(root.slotSuccess, colorToHex(Theme.success)),
            warning: normalizeHex(root.slotWarning, colorToHex(Theme.warning))
        };
        runAction(["tweak-colors", JSON.stringify(payload)], "Applied live custom palette");
    }

    Component.onCompleted: {
        syncSeedRgbFromHex(root.seedHex);
        syncSlotsFromTheme();
        loadWallpapers();
        loadWallpaperColors();
        loadCustomThemes();
    }

    Connections {
        target: Theme
        function onWallpaperPathChanged() {
            root.loadWallpaperColors();
        }
        function onPrimaryChanged() {
            root.syncSlotsFromTheme();
        }
        function onSurfaceChanged() {
            root.syncSlotsFromTheme();
        }
        function onIsDarkChanged() {
            root.syncSlotsFromTheme();
        }
    }

    Connections {
        target: ShellState
        function onWallpaperDirChanged() {
            root.wallpaperDirInput = ShellState.wallpaperDir;
        }
        function onMangoFocusColorChanged() {
            root.mangoFocusInput = ShellState.mangoFocusColor;
        }
        function onMangoBorderColorChanged() {
            root.mangoBorderInput = ShellState.mangoBorderColor;
        }
    }

    Timer {
        id: statusTimer
        interval: 3500
        repeat: false
        onTriggered: root.statusMsg = ""
    }

    Process {
        id: wallpapersProc
        command: [Quickshell.shellPath("scripts/manage-themes.sh"), "wallpapers-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (Array.isArray(d.wallpapers))
                        root.wallpapersList = d.wallpapers;
                } catch (err) {}
            }
        }
    }

    Process {
        id: wpColorsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (Array.isArray(d.colors))
                        root.extractedColors = d.colors;
                } catch (err) {}
            }
        }
    }

    Process {
        id: customListProc
        command: [Quickshell.shellPath("scripts/manage-themes.sh"), "custom-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse((text || "").trim());
                    if (Array.isArray(d.themes))
                        root.customThemes = d.themes;
                } catch (err) {}
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    if (Array.isArray(d.themes))
                        root.customThemes = d.themes;
                    if (typeof d.path === "string" && d.path.length > 0) {
                        root.showStatus("Exported theme to " + d.path, false);
                        return;
                    }
                    if (typeof d.imported === "string" && d.imported.length > 0) {
                        root.importThemePath = "";
                        root.showStatus("Imported theme: " + d.imported, false);
                        return;
                    }
                    if (typeof d.saved === "string" && d.saved.length > 0) {
                        root.saveThemeName = "";
                        root.showStatus("Saved custom theme: " + d.saved, false);
                        return;
                    }
                    if (typeof d.solid === "string" && d.solid.length > 0) {
                        root.showStatus("Applied solid wallpaper " + d.solid, false);
                        return;
                    }
                    if (root._pendingActionMsg.length > 0)
                        root.showStatus(root._pendingActionMsg, false);
                } catch (err) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: root._lastActionStderr = (text || "").trim()
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.showStatus(root._lastActionStderr.length > 0 ? root._lastActionStderr : ("Theme action failed (" + exitCode + ")"), true);
            } else if (root._lastActionCmd === "apply-mango-overrides" && root._pendingActionMsg.length > 0) {
                root.showStatus(root._pendingActionMsg, false);
            }
        }
    }

    // --- Status Banner ---
    Rectangle {
        Layout.fillWidth: true
        visible: root.statusMsg.length > 0
        implicitHeight: statusLbl.implicitHeight + 14
        radius: Theme.r(10)
        color: root.statusError ? Theme.withAlpha(Theme.error, 0.16) : Theme.withAlpha(Theme.primary, 0.16)
        border.width: 1
        border.color: root.statusError ? Theme.withAlpha(Theme.error, 0.45) : Theme.withAlpha(Theme.primary, 0.45)

        Text {
            id: statusLbl
            anchors.centerIn: parent
            width: parent.width - 20
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            text: root.statusMsg
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Medium
            color: root.statusError ? Theme.error : Theme.primary
        }
    }

    // --- 1. One-Click Aesthetic Vibes ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: vibeCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: vibeCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "ONE-CLICK AESTHETIC VIBES"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Applies palette + surface + shape"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: Theme.fgSurfaceVariant
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: root.vibeModels

                    delegate: Rectangle {
                        id: vibeCard
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 56
                        radius: Theme.r(11)
                        color: vibeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                        border.width: Theme.cardBorderWidth
                        border.color: vibeMouse.containsMouse ? Theme.primary : Theme.cardBorder
                        scale: vibeMouse.pressed ? 0.97 : 1.0

                        Behavior on color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            enabled: !Theme.reducedMotion
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 9

                            // Mini tri-color preview badge
                            Rectangle {
                                implicitWidth: 34
                                implicitHeight: 34
                                radius: Theme.r(9)
                                color: vibeCard.modelData.c1
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.outline, 0.45)

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 3

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: Theme.r(4)
                                        color: vibeCard.modelData.c2
                                    }

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: Theme.r(4)
                                        color: vibeCard.modelData.c3
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: vibeCard.modelData.title
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Theme.fgSurface
                                }

                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: vibeCard.modelData.desc
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: Theme.fgSurfaceVariant
                                }
                            }
                        }

                        MouseArea {
                            id: vibeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Theme.applyVibe(vibeCard.modelData.id);
                                root.showStatus("Applied vibe: " + vibeCard.modelData.title, false);
                            }
                        }
                    }
                }
            }
        }
    }

    // --- 2. Color Engine & Dark/Light Scheme ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: engineCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: engineCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "COLOR ENGINE & SCHEME"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: rstThmLbl.implicitWidth + 14
                    radius: Theme.r(12)
                    color: root.confirmResetTheme
                        ? Theme.warning
                        : (rstThmMouse.containsMouse ? Theme.withAlpha(Theme.warning, 0.20) : Theme.subCardBg)
                    border.width: 1
                    border.color: root.confirmResetTheme ? Theme.warning : Theme.cardBorder

                    Text {
                        id: rstThmLbl
                        anchors.centerIn: parent
                        text: root.confirmResetTheme ? "Confirm?" : "󰑐 Reset Theme & Colors"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: root.confirmResetTheme ? Theme.fgPrimary : Theme.warning
                    }

                    MouseArea {
                        id: rstThmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.confirmResetTheme) {
                                root.confirmResetTheme = true;
                                themeResetConfirmTimer.restart();
                                return;
                            }
                            root.confirmResetTheme = false;
                            themeResetConfirmTimer.stop();
                            ShellState.resetAppearance();
                            root.showStatus("Restored default Catppuccin Mocha dark theme & appearance", false);
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: schemeRow.implicitWidth + 16
                    radius: Theme.r(12)
                    color: schemeMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder
                    scale: schemeMouse.pressed ? 0.96 : 1.0

                    Behavior on color {
                        enabled: !Theme.reducedMotion
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        id: schemeRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: Theme.colorScheme === "dark" ? "󰖔" : "󰖙"
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: Theme.primary
                        }

                        Text {
                            text: Theme.colorScheme === "dark" ? "Dark Scheme" : "Light Scheme"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
                    }

                    MouseArea {
                        id: schemeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Theme.toggleScheme()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { id: "dynamic", label: "Dynamic (Matugen)" },
                        { id: "preset",  label: "Presets (16)" },
                        { id: "accent",  label: "Seed Accent" },
                        { id: "custom",  label: "Custom Palette" }
                    ]

                    delegate: Rectangle {
                        id: engBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === engBtn.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.r(10)
                        color: engBtn.selected
                            ? Theme.primary
                            : (engMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: Theme.cardBorderWidth
                        border.color: engBtn.selected ? Theme.primary : Theme.cardBorder
                        scale: engMouse.pressed ? 0.97 : 1.0

                        Behavior on color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: engBtn.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: engBtn.selected ? Font.Bold : Font.Medium
                            color: engBtn.selected ? Theme.fgPrimary : Theme.fgSurface
                        }

                        MouseArea {
                            id: engMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.setMode(engBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // --- 3. 16 Curated Theme Presets ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: presetsCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: presetsCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "16 CURATED THEME PRESETS"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Theme.themeMode === "preset" ? ("Active: " + Theme.presetName) : "Supports Dark & Light"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: Theme.fgSurfaceVariant
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 4
                columnSpacing: 6
                rowSpacing: 6

                Repeater {
                    model: Theme.availablePresets

                    delegate: Rectangle {
                        id: preBtn
                        required property var modelData
                        readonly property bool selected: Theme.themeMode === "preset" && Theme.presetName === preBtn.modelData.id

                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Theme.r(9)
                        color: preBtn.selected
                            ? Theme.activeBg
                            : (preMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: preBtn.selected ? 1 : Theme.cardBorderWidth
                        border.color: preBtn.selected ? Theme.primary : Theme.cardBorder
                        scale: preMouse.pressed ? 0.96 : 1.0

                        Behavior on color {
                            enabled: !Theme.reducedMotion
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Rectangle {
                                implicitWidth: 18
                                implicitHeight: 14
                                radius: Theme.r(4)
                                color: preBtn.modelData.bg
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.outline, 0.35)

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Rectangle {
                                        width: 5
                                        height: 5
                                        radius: Theme.r(2)
                                        color: preBtn.modelData.swatch
                                    }

                                    Rectangle {
                                        width: 5
                                        height: 5
                                        radius: Theme.r(2)
                                        color: preBtn.modelData.secondary
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: preBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: preBtn.selected ? Font.Bold : Font.Medium
                                color: preBtn.selected ? Theme.primary : Theme.fgSurface
                            }
                        }

                        MouseArea {
                            id: preMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.applyPreset(preBtn.modelData.id)
                        }
                    }
                }
            }
        }
    }

    // --- 4. Seed Accent Color Generator ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: seedCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: seedCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "SEED ACCENT COLOR GENERATOR (MATUGEN HEX)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: Theme.themeMode === "accent" ? ("Seed: " + Theme.accentColor) : "Pick or mix RGB"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    color: Theme.fgSurfaceVariant
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 7

                Repeater {
                    model: root.seedSwatches

                    delegate: Rectangle {
                        id: swCircle
                        required property string modelData
                        readonly property bool selected: root.seedHex.toLowerCase() === swCircle.modelData.toLowerCase()

                        implicitWidth: 24
                        implicitHeight: 24
                        radius: Theme.r(12)
                        color: swCircle.modelData
                        border.width: swCircle.selected ? 2 : 1
                        border.color: swCircle.selected ? Theme.fgSurface : Theme.withAlpha(Theme.outline, 0.35)
                        scale: swCircleMouse.pressed ? 0.90 : 1.0

                        Behavior on scale {
                            enabled: !Theme.reducedMotion
                            NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                        }

                        MouseArea {
                            id: swCircleMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.seedHex = swCircle.modelData;
                                root.syncSeedRgbFromHex(swCircle.modelData);
                                Theme.applyAccentColor(swCircle.modelData);
                                root.showStatus("Generated Material You theme from " + swCircle.modelData, false);
                            }
                        }
                    }
                }
            }

            // Hex input + Generate + Solid Wallpaper buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Theme.r(8)
                    color: root.isValidHex(root.seedHex) ? root.seedHex : Theme.primary
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.5)
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: seedInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: seedInput.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        TextInput {
                            id: seedInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.seedHex
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.fgSurface
                            selectByMouse: true
                            onTextEdited: {
                                root.seedHex = text;
                                root.syncSeedRgbFromHex(text);
                            }
                            Keys.onReturnPressed: {
                                const h = root.normalizeHex(root.seedHex, "#cba6f7");
                                root.seedHex = h;
                                root.syncSeedRgbFromHex(h);
                                Theme.applyAccentColor(h);
                            }
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: genLbl.implicitWidth + 18
                    radius: Theme.r(8)
                    color: genMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        id: genLbl
                        anchors.centerIn: parent
                        text: "Generate Theme"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: genMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const h = root.normalizeHex(root.seedHex, "#cba6f7");
                            root.seedHex = h;
                            root.syncSeedRgbFromHex(h);
                            Theme.applyAccentColor(h);
                            root.showStatus("Generated Material You theme from " + h, false);
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: solidUseLbl.implicitWidth + 16
                    radius: Theme.r(8)
                    color: solidUseMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: solidUseLbl
                        anchors.centerIn: parent
                        text: "Solid Wallpaper"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: solidUseMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const h = root.normalizeHex(root.seedHex, "#1e1e2e");
                            root.runAction(["solid-wallpaper", h], "Applied solid wallpaper " + h);
                        }
                    }
                }
            }

            // RGB fine sliders (StepControls)
            StepControl {
                label: "Red Channel"
                displayValue: String(root.seedR)
                accentColor: Theme.error
                onDecremented: root.updateSeedFromRgb(root.seedR - 16, root.seedG, root.seedB)
                onIncremented: root.updateSeedFromRgb(root.seedR + 16, root.seedG, root.seedB)
            }

            StepControl {
                label: "Green Channel"
                displayValue: String(root.seedG)
                accentColor: Theme.success
                onDecremented: root.updateSeedFromRgb(root.seedR, root.seedG - 16, root.seedB)
                onIncremented: root.updateSeedFromRgb(root.seedR, root.seedG + 16, root.seedB)
            }

            StepControl {
                label: "Blue Channel"
                displayValue: String(root.seedB)
                accentColor: Theme.secondary
                onDecremented: root.updateSeedFromRgb(root.seedR, root.seedG, root.seedB - 16)
                onIncremented: root.updateSeedFromRgb(root.seedR, root.seedG, root.seedB + 16)
            }
        }
    }

    // --- 5. Wallpaper Studio & Matugen Tuning ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: wpStudioCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: wpStudioCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: "WALLPAPER STUDIO & MATUGEN EXTRACTION"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: rndLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: rndMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: rndLbl
                        anchors.centerIn: parent
                        text: "󰒝 Random"
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
                        onClicked: {
                            Theme.randomWallpaper();
                            root.showStatus("Picking random wallpaper...", false);
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: reExtLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: reExtMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        id: reExtLbl
                        anchors.centerIn: parent
                        text: "Re-extract"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: reExtMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Theme.applyDynamicWallpaper(Theme.wallpaperPath);
                            root.showStatus("Re-extracting Material You palette from wallpaper...", false);
                        }
                    }
                }
            }

            // Wallpaper Folder Config
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: wpDirInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: wpDirInput.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "~/Pictures/Wallpapers"
                            visible: wpDirInput.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: wpDirInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.wallpaperDirInput
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            clip: true
                            selectByMouse: true
                            onTextEdited: root.wallpaperDirInput = text
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: setDirLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: setDirMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: setDirLbl
                        anchors.centerIn: parent
                        text: "Load Folder"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: setDirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const dir = root.wallpaperDirInput.trim() || "~/Pictures/Wallpapers";
                            ShellState.setPref("wallpaperDir", dir);
                            wallpapersProc.command = [Quickshell.shellPath("scripts/manage-themes.sh"), "wallpapers-list", dir];
                            wallpapersProc.running = true;
                            root.showStatus("Loaded wallpapers from " + dir, false);
                        }
                    }
                }
            }

            // Quick Solid Color Wallpapers
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Solid Backdrop"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 5

                    Repeater {
                        model: root.solidWallpapers

                        delegate: Rectangle {
                            id: solidSwatch
                            required property string modelData

                            width: 18
                            height: 18
                            radius: Theme.r(5)
                            color: solidSwatch.modelData
                            border.width: ShellState.solidWallpaperColor.toLowerCase() === solidSwatch.modelData.toLowerCase() ? 2 : 1
                            border.color: ShellState.solidWallpaperColor.toLowerCase() === solidSwatch.modelData.toLowerCase()
                                ? Theme.primary
                                : Theme.withAlpha(Theme.outline, 0.4)

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["solid-wallpaper", solidSwatch.modelData], "Applied solid wallpaper " + solidSwatch.modelData)
                            }
                        }
                    }
                }
            }

            // Thumbnail Gallery
            Text {
                visible: root.wallpapersList.length === 0
                text: "No .png / .jpg / .webp images found in wallpaper folder."
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }

            Flickable {
                Layout.fillWidth: true
                visible: root.wallpapersList.length > 0
                implicitHeight: Math.min(200, Math.max(84, wpGrid.implicitHeight))
                clip: true
                contentWidth: width
                contentHeight: wpGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: wpGrid
                    width: parent.width
                    columns: 3
                    columnSpacing: 8
                    rowSpacing: 8

                    Repeater {
                        model: root.wallpapersList

                        delegate: Rectangle {
                            id: wpTile
                            required property var modelData
                            readonly property bool selected: Theme.wallpaperPath === wpTile.modelData.path

                            Layout.fillWidth: true
                            implicitHeight: 74
                            radius: Theme.r(10)
                            color: Theme.subCardBg
                            clip: true
                            border.width: wpTile.selected ? 2 : 1
                            border.color: wpTile.selected ? Theme.primary : Theme.cardBorder

                            Image {
                                anchors.fill: parent
                                source: "file://" + wpTile.modelData.path
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 240
                                sourceSize.height: 135
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 20
                                color: Qt.rgba(0, 0, 0, 0.62)

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: wpTile.modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    font.weight: wpTile.selected ? Font.Bold : Font.Normal
                                    color: wpTile.selected ? Theme.primary : "#ffffff"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Theme.applyWallpaperWithCurrentMode(wpTile.modelData.path)
                            }
                        }
                    }
                }
            }

            // Dominant Extracted Source Swatches
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.extractedColors.length > 0

                Text {
                    text: "Dominant Wallpaper Colors (click index)"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 6

                    Repeater {
                        model: root.extractedColors

                        delegate: Rectangle {
                            id: extCircle
                            required property string modelData
                            required property int index
                            readonly property bool selected: ShellState.matugenSourceIndex === extCircle.index

                            width: 22
                            height: 22
                            radius: Theme.r(11)
                            color: root.isValidHex(extCircle.modelData) ? extCircle.modelData : Theme.primary
                            border.width: extCircle.selected ? 2 : 1
                            border.color: extCircle.selected ? Theme.fgSurface : Theme.withAlpha(Theme.outline, 0.45)

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    ShellState.setPref("matugenSourceIndex", extCircle.index);
                                    Theme.applyDynamicWallpaper(Theme.wallpaperPath);
                                    root.showStatus("Using dominant color #" + extCircle.index + " (" + extCircle.modelData + ")", false);
                                }
                            }
                        }
                    }
                }
            }

            // Matugen 10 Scheme Types
            Text {
                text: "Matugen Scheme Algorithm"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }

            Flow {
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: root.matugenSchemes

                    delegate: Rectangle {
                        id: schemeChip
                        required property string modelData
                        readonly property bool selected: ShellState.matugenType === schemeChip.modelData

                        implicitHeight: 24
                        implicitWidth: schemeChipTxt.implicitWidth + 12
                        radius: Theme.r(7)
                        color: schemeChip.selected
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (schemeChipMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                        border.width: schemeChip.selected ? 1 : Theme.cardBorderWidth
                        border.color: schemeChip.selected ? Theme.primary : Theme.cardBorder

                        Text {
                            id: schemeChipTxt
                            anchors.centerIn: parent
                            text: schemeChip.modelData.replace("scheme-", "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: schemeChip.selected ? Font.Bold : Font.Medium
                            color: schemeChip.selected ? Theme.primary : Theme.fgSurface
                        }

                        MouseArea {
                            id: schemeChipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setPref("matugenType", schemeChip.modelData)
                        }
                    }
                }
            }

            // Color Preference (--prefer)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 108
                    text: "Color Preference"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: ["saturation", "darkness", "lightness", "less-saturation", "value"]

                        delegate: Rectangle {
                            id: prefChip
                            required property string modelData
                            readonly property bool selected: ShellState.matugenPrefer === prefChip.modelData

                            implicitHeight: 24
                            implicitWidth: prefChipTxt.implicitWidth + 12
                            radius: Theme.r(7)
                            color: prefChip.selected
                                ? Theme.withAlpha(Theme.secondary, 0.22)
                                : (prefChipMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                            border.width: prefChip.selected ? 1 : Theme.cardBorderWidth
                            border.color: prefChip.selected ? Theme.secondary : Theme.cardBorder

                            Text {
                                id: prefChipTxt
                                anchors.centerIn: parent
                                text: prefChip.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: prefChip.selected ? Font.Bold : Font.Medium
                                color: prefChip.selected ? Theme.secondary : Theme.fgSurface
                            }

                            MouseArea {
                                id: prefChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ShellState.setPref("matugenPrefer", prefChip.modelData)
                            }
                        }
                    }
                }
            }

            StepControl {
                label: "Matugen Palette Contrast"
                displayValue: ShellState.matugenContrast.toFixed(1)
                onDecremented: ShellState.setPref("matugenContrast", Number(Math.max(-1.0, ShellState.matugenContrast - 0.2).toFixed(1)))
                onIncremented: ShellState.setPref("matugenContrast", Number(Math.min(1.0, ShellState.matugenContrast + 0.2).toFixed(1)))
            }

            StepControl {
                label: "Dark Surface Lightness"
                displayValue: ShellState.matugenLightnessDark.toFixed(2)
                onDecremented: ShellState.setPref("matugenLightnessDark", Number(Math.max(-0.50, ShellState.matugenLightnessDark - 0.05).toFixed(2)))
                onIncremented: ShellState.setPref("matugenLightnessDark", Number(Math.min(0.30, ShellState.matugenLightnessDark + 0.05).toFixed(2)))
            }

            StepControl {
                label: "Light Surface Lightness"
                displayValue: ShellState.matugenLightnessLight.toFixed(2)
                onDecremented: ShellState.setPref("matugenLightnessLight", Number(Math.max(-0.30, ShellState.matugenLightnessLight - 0.05).toFixed(2)))
                onIncremented: ShellState.setPref("matugenLightnessLight", Number(Math.min(0.30, ShellState.matugenLightnessLight + 0.05).toFixed(2)))
            }
        }
    }

    // --- 6. Live Palette Slot Editor & Saved Custom Themes ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: slotCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: slotCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: "LIVE PALETTE SLOT EDITOR & CUSTOM THEMES"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: syncSlotsLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: syncSlotsMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: syncSlotsLbl
                        anchors.centerIn: parent
                        text: "Sync Active"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: syncSlotsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.syncSlotsFromTheme();
                            root.showStatus("Loaded active theme colors into slots", false);
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: applySlotsLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: applySlotsMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        id: applySlotsLbl
                        anchors.centerIn: parent
                        text: "Apply Palette"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: applySlotsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyPaletteSlots()
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 6

                Repeater {
                    model: root.slotDescriptors

                    delegate: Rectangle {
                        id: slotRow
                        required property var modelData
                        readonly property string val: root.getSlotValue(slotRow.modelData.key)

                        Layout.fillWidth: true
                        implicitHeight: 32
                        radius: Theme.r(8)
                        color: Theme.subCardBg
                        border.width: slotField.activeFocus ? 1 : Theme.cardBorderWidth
                        border.color: slotField.activeFocus ? Theme.primary : Theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 7

                            Rectangle {
                                implicitWidth: 16
                                implicitHeight: 16
                                radius: Theme.r(4)
                                color: root.isValidHex(slotRow.val) ? slotRow.val : Theme.primary
                                border.width: 1
                                border.color: Theme.withAlpha(Theme.outline, 0.45)
                            }

                            Text {
                                Layout.preferredWidth: 74
                                text: slotRow.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: 18

                                TextInput {
                                    id: slotField
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: slotRow.val
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: Theme.fgSurface
                                    selectByMouse: true
                                    onTextEdited: root.setSlotValue(slotRow.modelData.key, text)
                                    Keys.onReturnPressed: root.applyPaletteSlots()
                                }
                            }
                        }
                    }
                }
            }

            // Save Current Theme As...
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: saveNameInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: saveNameInput.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Save active palette as custom theme name..."
                            visible: saveNameInput.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: saveNameInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.saveThemeName
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            clip: true
                            selectByMouse: true
                            onTextEdited: root.saveThemeName = text
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: saveThemeLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: saveThemeMouse.containsMouse ? Qt.lighter(Theme.secondary, 1.08) : Theme.secondary

                    Text {
                        id: saveThemeLbl
                        anchors.centerIn: parent
                        text: "Save Theme"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgSecondary
                    }

                    MouseArea {
                        id: saveThemeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const nm = root.saveThemeName.trim();
                            if (nm.length === 0) {
                                root.showStatus("Enter a name before saving custom theme", true);
                                return;
                            }
                            root.runAction(["custom-save", nm], "Saved custom theme: " + nm);
                        }
                    }
                }
            }

            // Saved Custom Themes List
            Repeater {
                model: root.customThemes

                delegate: Rectangle {
                    id: custItem
                    required property var modelData
                    readonly property bool selected: Theme.themeMode === "custom" && Theme.customTheme === custItem.modelData.slug

                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Theme.r(9)
                    color: custItem.selected ? Theme.activeBg : Theme.subCardBg
                    border.width: custItem.selected ? 1 : Theme.cardBorderWidth
                    border.color: custItem.selected ? Theme.primary : Theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 7

                        Rectangle {
                            implicitWidth: 20
                            implicitHeight: 16
                            radius: Theme.r(4)
                            color: root.isValidHex(custItem.modelData.surface) ? custItem.modelData.surface : Theme.surface
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.outline, 0.4)

                            Row {
                                anchors.centerIn: parent
                                spacing: 2
                                Rectangle { width: 5; height: 5; radius: Theme.r(2); color: root.isValidHex(custItem.modelData.primary) ? custItem.modelData.primary : Theme.primary }
                                Rectangle { width: 5; height: 5; radius: Theme.r(2); color: root.isValidHex(custItem.modelData.secondary) ? custItem.modelData.secondary : Theme.secondary }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: custItem.modelData.name + " (" + (custItem.modelData.isDark ? "Dark" : "Light") + ")"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: custItem.selected ? Font.Bold : Font.Medium
                            color: custItem.selected ? Theme.primary : Theme.fgSurface
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: cApLbl.implicitWidth + 12
                            radius: Theme.r(6)
                            color: cApMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                            Text {
                                id: cApLbl
                                anchors.centerIn: parent
                                text: "Apply"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                color: Theme.fgPrimary
                            }

                            MouseArea {
                                id: cApMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Theme.applyCustomTheme(custItem.modelData.slug);
                                    root.showStatus("Applied custom theme: " + custItem.modelData.name, false);
                                }
                            }
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: cExLbl.implicitWidth + 12
                            radius: Theme.r(6)
                            color: cExMouse.containsMouse ? Theme.hoverBg : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                id: cExLbl
                                anchors.centerIn: parent
                                text: "Export"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Theme.fgSurface
                            }

                            MouseArea {
                                id: cExMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["custom-export", custItem.modelData.slug], "")
                            }
                        }

                        Rectangle {
                            implicitHeight: 22
                            implicitWidth: cDelLbl.implicitWidth + 12
                            radius: Theme.r(6)
                            color: cDelMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
                            border.width: Theme.cardBorderWidth
                            border.color: Theme.cardBorder

                            Text {
                                id: cDelLbl
                                anchors.centerIn: parent
                                text: "Delete"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: Theme.error
                            }

                            MouseArea {
                                id: cDelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["custom-delete", custItem.modelData.slug], "Deleted theme: " + custItem.modelData.name)
                            }
                        }
                    }
                }
            }

            // Import Theme JSON
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Theme.r(8)
                    color: Theme.subCardBg
                    border.width: importInput.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: importInput.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Import theme JSON file (e.g. ~/mango-theme-name.json)..."
                            visible: importInput.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: importInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.importThemePath
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            clip: true
                            selectByMouse: true
                            onTextEdited: root.importThemePath = text
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 28
                    implicitWidth: impLbl.implicitWidth + 14
                    radius: Theme.r(8)
                    color: impMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: impLbl
                        anchors.centerIn: parent
                        text: "Import JSON"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: impMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const fp = root.importThemePath.trim();
                            if (fp.length === 0) {
                                root.showStatus("Enter a theme JSON file path to import", true);
                                return;
                            }
                            root.runAction(["custom-import", fp], "");
                        }
                    }
                }
            }
        }
    }

    // --- 7. MangoWC Window Border, Shadow & Dim Colors ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: mangoCol.implicitHeight + 24
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        ColumnLayout {
            id: mangoCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "MANGOWC WINDOW BORDERS, SHADOWS & DIM TINT"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: applyWmLbl.implicitWidth + 14
                    radius: Theme.r(7)
                    color: applyWmMouse.containsMouse ? Qt.lighter(Theme.primary, 1.08) : Theme.primary

                    Text {
                        id: applyWmLbl
                        anchors.centerIn: parent
                        text: "Apply WM Colors"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.fgPrimary
                    }

                    MouseArea {
                        id: applyWmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAction(["apply-mango-overrides", "--reload"], "Updated MangoWC border & shadow colors")
                    }
                }
            }

            // Focus Border Color Override
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 126
                    text: "Focused Border Hex"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: Theme.r(5)
                    color: root.isValidHex(root.mangoFocusInput) ? root.mangoFocusInput : Theme.primary
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.5)
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: Theme.subCardBg
                    border.width: focusHexField.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: focusHexField.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Theme default (or #RRGGBB)"
                            visible: focusHexField.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: focusHexField
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.mangoFocusInput
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            clip: true
                            selectByMouse: true
                            onTextEdited: root.mangoFocusInput = text
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: fSetLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: fSetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: fSetLbl
                        anchors.centerIn: parent
                        text: "Set"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.primary
                    }

                    MouseArea {
                        id: fSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const raw = root.mangoFocusInput.trim();
                            if (raw.length === 0) {
                                ShellState.setPref("mangoFocusColor", "");
                            } else {
                                const h = root.normalizeHex(raw, "");
                                if (h.length === 0) {
                                    root.showStatus("Invalid hex color (use #RRGGBB)", true);
                                    return;
                                }
                                root.mangoFocusInput = h;
                                ShellState.setPref("mangoFocusColor", h);
                            }
                            root.runAction(["apply-mango-overrides", "--reload"], "Updated MangoWC focus border color");
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: fClrLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: fClrMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: fClrLbl
                        anchors.centerIn: parent
                        text: "Reset"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: fClrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.mangoFocusInput = "";
                            ShellState.setPref("mangoFocusColor", "");
                            root.runAction(["apply-mango-overrides", "--reload"], "Restored default focus border color");
                        }
                    }
                }
            }

            // Unfocused Border Color Override
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.preferredWidth: 126
                    text: "Unfocused Border"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                Rectangle {
                    implicitWidth: 20
                    implicitHeight: 20
                    radius: Theme.r(5)
                    color: root.isValidHex(root.mangoBorderInput) ? root.mangoBorderInput : Theme.outlineVariant
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outline, 0.5)
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: Theme.r(7)
                    color: Theme.subCardBg
                    border.width: borderHexField.activeFocus ? 1 : Theme.cardBorderWidth
                    border.color: borderHexField.activeFocus ? Theme.primary : Theme.cardBorder

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Theme default (or #RRGGBB)"
                            visible: borderHexField.text.length === 0
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }

                        TextInput {
                            id: borderHexField
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.mangoBorderInput
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurface
                            clip: true
                            selectByMouse: true
                            onTextEdited: root.mangoBorderInput = text
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: bSetLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: bSetMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: bSetLbl
                        anchors.centerIn: parent
                        text: "Set"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.primary
                    }

                    MouseArea {
                        id: bSetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const raw = root.mangoBorderInput.trim();
                            if (raw.length === 0) {
                                ShellState.setPref("mangoBorderColor", "");
                            } else {
                                const h = root.normalizeHex(raw, "");
                                if (h.length === 0) {
                                    root.showStatus("Invalid hex color (use #RRGGBB)", true);
                                    return;
                                }
                                root.mangoBorderInput = h;
                                ShellState.setPref("mangoBorderColor", h);
                            }
                            root.runAction(["apply-mango-overrides", "--reload"], "Updated MangoWC unfocused border color");
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: bClrLbl.implicitWidth + 12
                    radius: Theme.r(7)
                    color: bClrMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg
                    border.width: Theme.cardBorderWidth
                    border.color: Theme.cardBorder

                    Text {
                        id: bClrLbl
                        anchors.centerIn: parent
                        text: "Reset"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.fgSurfaceVariant
                    }

                    MouseArea {
                        id: bClrMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.mangoBorderInput = "";
                            ShellState.setPref("mangoBorderColor", "");
                            root.runAction(["apply-mango-overrides", "--reload"], "Restored default unfocused border color");
                        }
                    }
                }
            }

            // Accent-tinted shadows toggle
            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: "Colored Accent Window Shadows"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    color: Theme.fgSurface
                }

                ToggleSwitch {
                    checked: ShellState.mangoShadowTint
                    onToggled: {
                        ShellState.setPref("mangoShadowTint", !ShellState.mangoShadowTint);
                        root.runAction(["apply-mango-overrides", "--reload"], "Toggled accent-colored shadows");
                    }
                }
            }

            StepControl {
                label: "Shadow Opacity"
                displayValue: Math.round(ShellState.mangoShadowAlpha * 100) + "%"
                onDecremented: {
                    ShellState.setPref("mangoShadowAlpha", Number(Math.max(0.0, ShellState.mangoShadowAlpha - 0.05).toFixed(2)));
                    root.runAction(["apply-mango-overrides", "--reload"], "");
                }
                onIncremented: {
                    ShellState.setPref("mangoShadowAlpha", Number(Math.min(1.0, ShellState.mangoShadowAlpha + 0.05).toFixed(2)));
                    root.runAction(["apply-mango-overrides", "--reload"], "");
                }
            }

            StepControl {
                label: "Unfocused Window Dim Strength"
                displayValue: Math.round(ShellState.mangoDimAlpha * 100) + "%"
                onDecremented: {
                    ShellState.setPref("mangoDimAlpha", Number(Math.max(0.0, ShellState.mangoDimAlpha - 0.05).toFixed(2)));
                    root.runAction(["apply-mango-overrides", "--reload"], "");
                }
                onIncremented: {
                    ShellState.setPref("mangoDimAlpha", Number(Math.min(0.75, ShellState.mangoDimAlpha + 0.05).toFixed(2)));
                    root.runAction(["apply-mango-overrides", "--reload"], "");
                }
            }
        }
    }
}
