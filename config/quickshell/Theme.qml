pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- Theme State (synced via theme-state.json) ---
    property string themeMode: "preset"          // "preset" | "dynamic" | "accent" | "custom"
    property string colorScheme: "dark"          // "dark" | "light"
    property string presetName: "catppuccin-mocha"
    property string accentColor: "#cba6f7"
    property string customTheme: ""
    property string wallpaperPath: ""
    property string lastError: ""
    readonly property bool applyingTheme: applyProcess.running

    // --- Shell & MangoWC Visual Mode (synced via shell-mode.json & mode-prefs.json) ---
    property string shellMode: "default"         // "default" | "blur" | "neon" | "minimal" | "retro" | "oled" | "simple"
    readonly property bool isDefaultMode: shellMode === "default"
    readonly property bool isSimple: shellMode === "simple"
    readonly property bool isBlur: shellMode === "blur"
    readonly property bool isNeon: shellMode === "neon"
    readonly property bool isMinimal: shellMode === "minimal"
    readonly property bool isRetro: shellMode === "retro"
    readonly property bool isOled: shellMode === "oled"
    readonly property bool applyingMode: modeProcess.running

    readonly property var availableModes: [
        { id: "default", label: "Island",   vibe: "Balanced & Soft",     shortDesc: "Floating Dynamic Island, rounded windows & gentle elevation", icon: "󰕮" },
        { id: "blur",    label: "Frosted",  vibe: "visionOS Glass",      shortDesc: "Translucent aero glass panels with multi-pass window blur",    icon: "󰂵" },
        { id: "neon",    label: "Cyber",    vibe: "Neon HUD",            shortDesc: "Obsidian core, glowing accent rim & prismatic top bar",       icon: "󱐋" },
        { id: "minimal", label: "Zen",      vibe: "Dieter Rams Matte",   shortDesc: "Calm matte surfaces, hairline dividers & wide breathing gaps",icon: "󰋑" },
        { id: "retro",   label: "Tactile",  vibe: "Teenage / Brutalist", shortDesc: "Solid tactile blocks, bold structural borders & 4px chamfers",icon: "󰚗" },
        { id: "oled",    label: "Obsidian", vibe: "Pure #000 AMOLED",    shortDesc: "Pitch-black zero-wash panels with razor-thin accent rim",     icon: "󰖔" },
        { id: "simple",  label: "Simple",   vibe: "0px Flat Bar",        shortDesc: "Square corners, edge bar & zero gaps/shadows/motion",         icon: "󰝤" }
    ]

    property bool blurEnabled: false
    property real blurFocusedOpacity: 1.00
    property real blurUnfocusedOpacity: 1.00
    property int blurRadius: 5
    property int blurPasses: 2
    property real blurSaturation: 1.20
    property real blurBrightness: 0.90
    property int defaultRadius: 20
    property int defaultGaps: 8
    property int defaultBorderPx: 0
    property bool wmShadows: true
    property bool wmAnimations: true
    property string animTypeOpen: "zoom"
    property string animTypeClose: "slide"
    property int animDuration: 180
    property int tagAnimDirection: 1
    property bool blurLayer: true
    property bool blurOptimized: true
    property real blurNoise: 0.01
    property real blurContrast: 0.95
    property bool layerShadows: false
    property bool shadowOnlyFloating: false
    property int shadowsSize: 10
    property int shadowsBlur: 14
    property bool layerAnimations: true
    property bool animFadeIn: true
    property bool animFadeOut: true
    property bool dimEnable: false

    readonly property var availablePresets: [
        { id: "catppuccin-mocha", label: "Catppuccin",  swatch: "#cba6f7", secondary: "#89b4fa", bg: "#1e1e2e" },
        { id: "tokyo-night",      label: "Tokyo Night", swatch: "#7aa2f7", secondary: "#bb9af7", bg: "#1a1b26" },
        { id: "gruvbox",          label: "Gruvbox",     swatch: "#fabd2f", secondary: "#83a598", bg: "#282828" },
        { id: "nord",             label: "Nord",        swatch: "#88c0d0", secondary: "#81a1c1", bg: "#2e3440" },
        { id: "rose-pine",        label: "Rose Pine",   swatch: "#ebbcba", secondary: "#c4a7e7", bg: "#1f1d2e" },
        { id: "dracula",          label: "Dracula",     swatch: "#bd93f9", secondary: "#ff79c6", bg: "#282a36" },
        { id: "everforest",       label: "Everforest",  swatch: "#a7c080", secondary: "#83c092", bg: "#2d353b" },
        { id: "kanagawa",         label: "Kanagawa",    swatch: "#7e9cd8", secondary: "#957fb8", bg: "#1f1f28" },
        { id: "solarized",        label: "Solarized",   swatch: "#268bd2", secondary: "#2aa198", bg: "#002b36" },
        { id: "one-dark",         label: "One Dark",    swatch: "#61afef", secondary: "#c678dd", bg: "#282c34" },
        { id: "ayu",              label: "Ayu Mirage",  swatch: "#ffcc66", secondary: "#73d0ff", bg: "#1f2430" },
        { id: "oxocarbon",        label: "Oxocarbon",   swatch: "#3ddbd9", secondary: "#ff7eb6", bg: "#161616" },
        { id: "synthwave",        label: "Synthwave",   swatch: "#ff7edb", secondary: "#36f9f6", bg: "#262335" },
        { id: "oled-black",       label: "OLED Pitch",  swatch: "#82aaff", secondary: "#c792ea", bg: "#050507" },
        { id: "sakura",           label: "Sakura",      swatch: "#f28fad", secondary: "#c9a0dc", bg: "#231b22" },
        { id: "cyberpunk",        label: "Cyberpunk",   swatch: "#00f0ff", secondary: "#fcee09", bg: "#121220" }
    ]

    // --- Typography & Design Tokens ---
    readonly property string fontFamily: ShellState.uiFontFamily.length > 0 ? ShellState.uiFontFamily : "IBM Plex Sans"
    readonly property string monoFont: ShellState.monoFontFamily.length > 0 ? ShellState.monoFontFamily : "IBM Plex Mono"
    readonly property string iconFont: "Symbols Nerd Font"
    readonly property bool reducedMotion: isSimple || ShellState.reducedMotion
    readonly property int animFast: reducedMotion ? 0 : 110
    readonly property int animNormal: reducedMotion ? 0 : 170
    readonly property int animSlow: reducedMotion ? 0 : 230

    // --- Reactive Material You / Preset Color Palette ---
    property bool isDark: true

    property color primary: "#cba6f7"
    property color fgPrimary: "#11111b"
    property color primaryContainer: "#3e2f56"
    property color fgPrimaryContainer: "#f2e5ff"

    property color secondary: "#89b4fa"
    property color fgSecondary: "#11111b"
    property color secondaryContainer: "#293954"
    property color fgSecondaryContainer: "#dce9ff"

    property color tertiary: "#f5c2e7"
    property color fgTertiary: "#11111b"
    property color tertiaryContainer: "#4b3146"
    property color fgTertiaryContainer: "#ffe4f7"

    property color background: "#11111b"
    property color fgBackground: "#cdd6f4"

    property color surface: "#1e1e2e"
    property color surfaceDim: "#181825"
    property color surfaceBright: "#313244"
    property color surfaceContainerLowest: "#11111b"
    property color surfaceContainerLow: "#181825"
    property color surfaceContainer: "#1e1e2e"
    property color surfaceContainerHigh: "#313244"
    property color surfaceContainerHighest: "#45475a"

    property color fgSurface: "#cdd6f4"
    property color fgSurfaceVariant: "#a6adc8"
    property color outline: "#6c7086"
    property color outlineVariant: "#313244"

    property color error: "#f38ba8"
    property color fgError: "#11111b"
    property color success: "#a6e3a1"
    property color warning: "#f9e2af"
    property color info: "#89dceb"
    property color shadow: "#000000"

    // --- Material 3 Expressive Tonal Derivation (DarkShadowShell system) ---
    function m3Mix(a: color, b: color, k: real): color {
        const qa = Qt.color(a);
        const qb = Qt.color(b);
        return Qt.rgba(
            qa.r + (qb.r - qa.r) * k,
            qa.g + (qb.g - qa.g) * k,
            qa.b + (qb.b - qa.b) * k,
            1.0
        );
    }

    function m3Lum(c: color): real {
        const q = Qt.color(c);
        return 0.299 * q.r + 0.587 * q.g + 0.114 * q.b;
    }

    function m3Lift(c: color, target: real): color {
        let k = 0.0;
        while (k < 0.9 && m3Lum(m3Mix(c, "#ffffff", k)) < target)
            k += 0.05;
        return m3Mix(c, "#ffffff", k);
    }

    readonly property bool m3Mono: primary.hslHue < 0 || primary.hslSaturation < 0.1
    readonly property real m3Hue: primary.hslHue < 0 ? 0.55 : primary.hslHue
    readonly property real m3Sat: m3Mono ? 0.0 : Math.max(0.35, Math.min(0.85, primary.hslSaturation))

    readonly property color m3Primary: isDark ? m3Lift(primary, 0.62) : Qt.hsla(m3Hue, m3Sat, 0.36, 1.0)
    readonly property color m3OnPrimary: isDark ? m3Mix(primary, "#000000", 0.82) : "#ffffff"
    readonly property color m3PrimaryContainer: isDark ? m3Mix(m3Primary, "#151718", 0.68) : Qt.hsla(m3Hue, m3Sat * 0.5, 0.86, 1.0)
    readonly property color m3OnPrimaryContainer: isDark ? m3Mix(m3Primary, "#ffffff", 0.55) : Qt.hsla(m3Hue, m3Sat, 0.20, 1.0)
    readonly property color m3SecondaryContainer: isDark ? m3Mix(m3Primary, "#1b1d1e", 0.80) : Qt.hsla(m3Hue, m3Sat * 0.35, 0.90, 1.0)
    readonly property color m3OnSecondaryContainer: isDark ? m3Mix(m3Primary, "#ffffff", 0.70) : Qt.hsla(m3Hue, m3Sat, 0.22, 1.0)

    readonly property color m3SurfaceLowest: isDark ? (m3Mono ? "#0c0d0e" : m3Mix("#0c0d0e", primary, 0.03)) : "#ffffff"
    readonly property color m3Surface: isDark ? (m3Mono ? "#111213" : m3Mix("#111213", primary, 0.035)) : "#f6f6f8"
    readonly property color m3SurfaceLow: isDark ? (m3Mono ? "#17181a" : m3Mix("#17181a", primary, 0.04)) : "#eeeff2"
    readonly property color m3SurfaceC: isDark ? (m3Mono ? "#1f2023" : m3Mix("#1f2023", primary, 0.055)) : "#e6e8ec"
    readonly property color m3SurfaceHigh: isDark ? (m3Mono ? "#292a2e" : m3Mix("#292a2e", primary, 0.065)) : "#dcdfe5"
    readonly property color m3SurfaceHighest: isDark ? (m3Mono ? "#333539" : m3Mix("#333539", primary, 0.075)) : "#d1d5dd"
    readonly property color m3Ink: isDark ? "#ECEDEE" : "#16171a"
    readonly property color m3InkDim: isDark ? "#A9ADB2" : "#5a5e66"
    readonly property color m3Line: isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color m3Track: isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color m3Outline: isDark ? "#8C8F92" : "#72767d"
    readonly property color m3InverseSurface: isDark ? "#E3E2E2" : "#1f2023"
    readonly property color m3InverseInk: isDark ? "#111213" : "#f6f6f8"
    readonly property color m3Error: isDark ? "#FFB4AB" : "#b3261e"
    readonly property color m3ErrorContainer: isDark ? "#93000A" : "#f9dedc"
    readonly property color m3OnErrorContainer: isDark ? "#FFDAD6" : "#410e0b"

    readonly property color m3BarBg: isOled
        ? withAlpha("#000000", 0.82)
        : withAlpha(m3Surface, isSimple ? 1.0 : Math.max(0.68, Math.min(0.86, ShellState.shellOpacity * 0.80)))
    readonly property color m3PanelBg: isOled
        ? withAlpha("#000000", 0.94)
        : withAlpha(m3Surface, isSimple ? 1.0 : Math.max(0.84, Math.min(0.96, ShellState.shellOpacity)))
    readonly property color m3PaneBg: isOled
        ? withAlpha("#08080a", 0.96)
        : withAlpha(m3SurfaceLow, isSimple ? 1.0 : Math.max(0.86, Math.min(0.96, ShellState.shellOpacity)))

    readonly property var m3Emph: [0.2, 0, 0, 1, 1, 1]
    readonly property var m3Decel: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var m3Accel: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property int m3Springy: reducedMotion ? Easing.Linear : Easing.OutBack
    readonly property real m3RowOut: r(22)
    readonly property real m3RowIn: r(6)
    readonly property int m3RowGap: 3

    // Derived Dynamic Island / 7-Mode Visual Style tokens
    readonly property bool showGlassSheen: !isSimple && !isRetro && !isMinimal && (isBlur || ShellState.surfaceStyle === "glass" || ShellState.borderStyle === "glow")
    readonly property bool showNeonAccentBar: isNeon
    readonly property bool showRetroStripe: isRetro
    readonly property bool showOledRim: isOled

    readonly property color notchBg: {
        const sOp = ShellState.shellOpacity;
        if (ShellState.surfaceStyle === "flat")
            return withAlpha(m3SurfaceLowest, Math.max(0.70, sOp));
        if (ShellState.surfaceStyle === "oled")
            return withAlpha("#000000", Math.max(0.70, sOp));
        if (ShellState.surfaceStyle === "tinted")
            return withAlpha(m3PrimaryContainer, Math.max(0.68, Math.min(0.98, sOp * 0.94)));
        if (ShellState.surfaceStyle === "glass")
            return withAlpha(m3Surface, Math.min(0.90, Math.max(0.60, sOp * 0.82)));
        if (isSimple)
            return m3Surface;
        if (isOled)
            return withAlpha("#000000", Math.max(0.72, sOp));
        if (isNeon)
            return isDark
                ? withAlpha(Qt.tint("#07070c", withAlpha(m3PrimaryContainer, 0.16)), Math.max(0.70, sOp))
                : withAlpha(m3Surface, Math.max(0.75, sOp));
        if (isRetro)
            return withAlpha(m3SurfaceLow, Math.max(0.75, sOp));
        if (isMinimal)
            return withAlpha(m3SurfaceLowest, Math.max(0.72, sOp));
        if (isBlur)
            return withAlpha(m3Surface, Math.min(0.90, Math.max(0.60, sOp * 0.82)));
        return m3PanelBg;
    }
    readonly property color islandBg: notchBg
    readonly property color islandBorder: {
        if (ShellState.borderStyle === "none")
            return "transparent";
        if (ShellState.highContrast || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow" || isNeon)
            return m3Primary;
        if (isRetro)
            return isDark ? withAlpha(m3Ink, 0.45) : m3Outline;
        if (isOled)
            return withAlpha(m3Primary, 0.42);
        if (isMinimal)
            return withAlpha(outlineVariant, 0.88);
        if (isSimple)
            return m3Line;
        if (isBlur || ShellState.surfaceStyle === "glass")
            return isDark ? withAlpha(m3Ink, 0.14) : withAlpha(m3Outline, 0.28);
        return m3Line;
    }
    readonly property int islandBorderWidth: {
        if (ShellState.borderStyle === "none" || ShellState.uiBorderWidth <= 0)
            return 0;
        return ShellState.uiBorderWidth;
    }
    readonly property color cardBg: {
        const cOp = ShellState.cardOpacity;
        if (ShellState.surfaceStyle === "oled")
            return withAlpha("#0a0a0f", Math.max(0.35, Math.min(0.99, cOp + 0.36)));
        if (ShellState.surfaceStyle === "tinted")
            return withAlpha(m3SurfaceHigh, Math.max(0.35, Math.min(0.98, cOp + 0.32)));
        if (ShellState.surfaceStyle === "flat")
            return withAlpha(m3SurfaceLow, Math.max(0.45, Math.min(1.0, cOp + 0.44)));
        if (ShellState.surfaceStyle === "glass")
            return withAlpha(m3SurfaceC, Math.max(0.35, Math.min(0.92, cOp + 0.22)));
        if (isSimple)
            return m3SurfaceC;
        if (isOled)
            return withAlpha("#09090e", Math.max(0.45, Math.min(0.99, cOp + 0.42)));
        if (isNeon)
            return isDark
                ? withAlpha(Qt.tint("#0c0d14", withAlpha(m3PrimaryContainer, 0.18)), Math.max(0.40, Math.min(0.98, cOp + 0.38)))
                : withAlpha(m3SurfaceC, Math.max(0.45, Math.min(0.98, cOp + 0.40)));
        if (isRetro)
            return withAlpha(m3SurfaceC, Math.max(0.45, Math.min(1.0, cOp + 0.45)));
        if (isMinimal)
            return withAlpha(m3SurfaceC, Math.max(0.45, Math.min(0.98, cOp + 0.42)));
        if (isBlur)
            return withAlpha(m3SurfaceC, Math.max(0.35, Math.min(0.92, cOp + 0.22)));
        return m3SurfaceC;
    }
    readonly property color subCardBg: {
        const cOp = ShellState.cardOpacity;
        if (ShellState.surfaceStyle === "oled")
            return withAlpha("#12121a", Math.max(0.30, Math.min(0.96, cOp + 0.28)));
        if (ShellState.surfaceStyle === "tinted")
            return withAlpha(m3PrimaryContainer, Math.max(0.25, Math.min(0.90, cOp * 0.75)));
        if (ShellState.surfaceStyle === "flat")
            return withAlpha(m3SurfaceHigh, Math.max(0.40, Math.min(0.98, cOp + 0.38)));
        if (ShellState.surfaceStyle === "glass")
            return withAlpha(m3SurfaceHigh, Math.max(0.28, Math.min(0.88, cOp + 0.15)));
        if (isSimple)
            return m3SurfaceHigh;
        if (isOled)
            return withAlpha("#12121a", Math.max(0.38, Math.min(0.96, cOp + 0.36)));
        if (isNeon)
            return isDark
                ? withAlpha(m3PrimaryContainer, Math.max(0.22, Math.min(0.85, cOp * 0.72)))
                : withAlpha(m3SurfaceHigh, Math.max(0.40, Math.min(0.96, cOp + 0.35)));
        if (isRetro)
            return withAlpha(m3SurfaceHigh, Math.max(0.42, Math.min(1.0, cOp + 0.42)));
        if (isMinimal)
            return withAlpha(m3SurfaceHigh, Math.max(0.35, Math.min(0.92, cOp + 0.24)));
        if (isBlur)
            return withAlpha(m3SurfaceHigh, Math.max(0.28, Math.min(0.88, cOp + 0.15)));
        return m3SurfaceHigh;
    }
    readonly property color cardBorder: {
        if (ShellState.borderStyle === "none")
            return "transparent";
        if (ShellState.highContrast)
            return m3Outline;
        if (ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow")
            return withAlpha(m3Primary, 0.55);
        if (isNeon)
            return withAlpha(m3Primary, 0.48);
        if (isRetro)
            return isDark ? withAlpha(m3Ink, 0.34) : m3Outline;
        if (isOled)
            return withAlpha(outlineVariant, 0.80);
        if (isMinimal)
            return withAlpha(outlineVariant, 0.65);
        if (isBlur)
            return isDark ? withAlpha(m3Ink, 0.10) : withAlpha(m3Outline, 0.22);
        if (isSimple)
            return m3Line;
        return m3Line;
    }
    readonly property int cardBorderWidth: {
        if (ShellState.borderStyle === "none" || ShellState.uiBorderWidth <= 0)
            return 0;
        return ShellState.uiBorderWidth;
    }
    readonly property int subBorderWidth: (ShellState.highContrast || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow" || isRetro || isSimple) ? cardBorderWidth : 0
    readonly property int activeControlBorderWidth: (ShellState.highContrast || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow" || isRetro) ? Math.max(1, cardBorderWidth) : 0
    readonly property color tileActiveBg: isDark ? withAlpha("#ffffff", (isOled || ShellState.surfaceStyle === "oled") ? 0.11 : 0.13) : withAlpha("#ffffff", 0.94)
    readonly property color controlFillHover: isDark ? withAlpha("#ffffff", 0.08) : withAlpha("#000000", 0.06)
    readonly property color rowSelectedBg: isDark ? withAlpha("#ffffff", 0.10) : withAlpha("#000000", 0.07)
    readonly property color hairlineBorder: isDark ? withAlpha(fgSurface, 0.08) : withAlpha(outline, 0.18)
    readonly property color hoverBg: withAlpha(primary, 0.14)
    readonly property color activeBg: withAlpha(primary, 0.22)

    // Smooth color transitions across the entire shell on live palette reload only
    property bool _paletteAnimating: false

    Timer {
        id: paletteAnimTimer
        interval: 180
        repeat: false
        onTriggered: root._paletteAnimating = false
    }

    Behavior on primary { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgPrimary { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on primaryContainer { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgPrimaryContainer { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on secondary { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgSecondary { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on secondaryContainer { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgSecondaryContainer { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on tertiary { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgTertiary { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on background { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgBackground { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surface { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceDim { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceBright { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerLowest { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerLow { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainer { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerHigh { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerHighest { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgSurface { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgSurfaceVariant { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on outline { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on outlineVariant { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on error { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on fgError { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on success { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on warning { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on info { enabled: root._paletteAnimating && !root.reducedMotion; ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

    function withAlpha(col: color, alpha: real): color {
        return Qt.rgba(col.r, col.g, col.b, alpha);
    }

    function contrastInk(bgCol: color): color {
        const lum = 0.2126 * bgCol.r + 0.7152 * bgCol.g + 0.0722 * bgCol.b;
        return lum > 0.42 ? "#11111b" : "#ffffff";
    }

    function r(val: real): real {
        if (ShellState.uiRadiusScale <= 0.01)
            return 0;
        if (root.isSimple)
            return Math.round(val * Math.max(0, ShellState.uiRadiusScale - 1.0));
        if (root.isRetro)
            return val <= 2
                ? Math.round(val * ShellState.uiRadiusScale)
                : Math.max(1, Math.round(val * 0.32 * ShellState.uiRadiusScale));
        if (root.isNeon)
            return Math.round(val * 0.55 * ShellState.uiRadiusScale);
        if (root.isMinimal)
            return Math.round(val * 0.78 * ShellState.uiRadiusScale);
        return Math.round(val * ShellState.uiRadiusScale);
    }

    function fs(px: real): int {
        const fontDelta = (ShellState.uiFontSize > 0 ? (ShellState.uiFontSize - 10) * 0.04 : 0.0);
        const mult = Math.max(0.80, Math.min(1.25, ShellState.uiFontScale + fontDelta));
        return Math.max(7, Math.round(px * mult));
    }

    function applyColorsJson(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const data = JSON.parse(raw);
            if (!root.reducedMotion) {
                root._paletteAnimating = true;
                paletteAnimTimer.restart();
            }
            if (typeof data.isDark === "boolean")
                root.isDark = data.isDark;

            const directKeys = [
                "primary", "primaryContainer", "secondary", "secondaryContainer",
                "tertiary", "tertiaryContainer", "background",
                "surface", "surfaceDim", "surfaceBright",
                "surfaceContainerLowest", "surfaceContainerLow", "surfaceContainer",
                "surfaceContainerHigh", "surfaceContainerHighest",
                "outline", "outlineVariant", "error", "success", "warning", "info", "shadow"
            ];
            for (let i = 0; i < directKeys.length; i++) {
                const k = directKeys[i];
                if (typeof data[k] === "string" && data[k].length > 0)
                    root[k] = data[k];
            }

            const fgMap = {
                "onPrimary": "fgPrimary",
                "onPrimaryContainer": "fgPrimaryContainer",
                "onSecondary": "fgSecondary",
                "onSecondaryContainer": "fgSecondaryContainer",
                "onTertiary": "fgTertiary",
                "onTertiaryContainer": "fgTertiaryContainer",
                "onBackground": "fgBackground",
                "onSurface": "fgSurface",
                "onSurfaceVariant": "fgSurfaceVariant",
                "onError": "fgError"
            };
            for (const jsonKey in fgMap) {
                const targetProp = fgMap[jsonKey];
                if (typeof data[jsonKey] === "string" && data[jsonKey].length > 0)
                    root[targetProp] = data[jsonKey];
            }
        } catch (err) {
            colorsRetryTimer.restart();
        }
    }

    function applyStateJson(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const st = JSON.parse(raw);
            if (typeof st.mode === "string")
                root.themeMode = st.mode;
            if (typeof st.scheme === "string")
                root.colorScheme = st.scheme;
            if (typeof st.preset === "string")
                root.presetName = st.preset;
            if (typeof st.accent === "string")
                root.accentColor = st.accent;
            if (typeof st.customTheme === "string")
                root.customTheme = st.customTheme;
            if (typeof st.wallpaper === "string")
                root.wallpaperPath = st.wallpaper;
        } catch (err) {
            stateRetryTimer.restart();
        }
    }

    function applyModeJson(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const st = JSON.parse(raw);
            if (st.mode === "default" || st.mode === "simple" || st.mode === "blur"
                    || st.mode === "neon" || st.mode === "minimal" || st.mode === "retro" || st.mode === "oled")
                root.shellMode = st.mode;
        } catch (err) {
            modeRetryTimer.restart();
        }
    }

    function applyPrefsJson(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const p = JSON.parse(raw);
            if (typeof p.blurEnabled === "boolean")
                root.blurEnabled = p.blurEnabled;
            if (typeof p.blurFocusedOpacity === "number")
                root.blurFocusedOpacity = p.blurFocusedOpacity;
            if (typeof p.blurUnfocusedOpacity === "number")
                root.blurUnfocusedOpacity = p.blurUnfocusedOpacity;
            if (typeof p.blurRadius === "number")
                root.blurRadius = Math.round(p.blurRadius);
            if (typeof p.blurPasses === "number")
                root.blurPasses = Math.round(p.blurPasses);
            if (typeof p.blurSaturation === "number")
                root.blurSaturation = p.blurSaturation;
            if (typeof p.blurBrightness === "number")
                root.blurBrightness = p.blurBrightness;
            if (typeof p.defaultRadius === "number")
                root.defaultRadius = Math.round(p.defaultRadius);
            if (typeof p.defaultGaps === "number")
                root.defaultGaps = Math.round(p.defaultGaps);
            if (typeof p.defaultBorderPx === "number")
                root.defaultBorderPx = Math.round(p.defaultBorderPx);
            if (typeof p.shadows === "boolean")
                root.wmShadows = p.shadows;
            if (typeof p.animations === "boolean")
                root.wmAnimations = p.animations;
            if (typeof p.animationTypeOpen === "string")
                root.animTypeOpen = p.animationTypeOpen;
            if (typeof p.animationTypeClose === "string")
                root.animTypeClose = p.animationTypeClose;
            if (typeof p.animationDuration === "number")
                root.animDuration = Math.round(p.animationDuration);
            if (typeof p.tagAnimationDirection === "number")
                root.tagAnimDirection = Math.round(p.tagAnimationDirection);
            if (typeof p.blurLayer === "boolean")
                root.blurLayer = p.blurLayer;
            if (typeof p.blurOptimized === "boolean")
                root.blurOptimized = p.blurOptimized;
            if (typeof p.blurNoise === "number")
                root.blurNoise = p.blurNoise;
            if (typeof p.blurContrast === "number")
                root.blurContrast = p.blurContrast;
            if (typeof p.layerShadows === "boolean")
                root.layerShadows = p.layerShadows;
            if (typeof p.shadowOnlyFloating === "boolean")
                root.shadowOnlyFloating = p.shadowOnlyFloating;
            if (typeof p.shadowsSize === "number")
                root.shadowsSize = Math.round(p.shadowsSize);
            if (typeof p.shadowsBlur === "number")
                root.shadowsBlur = Math.round(p.shadowsBlur);
            if (typeof p.layerAnimations === "boolean")
                root.layerAnimations = p.layerAnimations;
            if (typeof p.animFadeIn === "boolean")
                root.animFadeIn = p.animFadeIn;
            if (typeof p.animFadeOut === "boolean")
                root.animFadeOut = p.animFadeOut;
            if (typeof p.dimEnable === "boolean")
                root.dimEnable = p.dimEnable;
        } catch (err) {
            prefsRetryTimer.restart();
        }
    }

    // --- Public Shell & MangoWC Mode Switching API (invokes scripts/apply-mode.sh) ---
    property var _pendingModeCmd: []

    function _runModeScript(args: list<string>): void {
        const cmd = [Quickshell.shellPath("scripts/apply-mode.sh")].concat(args);
        if (modeProcess.running) {
            root._pendingModeCmd = cmd;
            return;
        }
        modeProcess.command = cmd;
        modeProcess.running = true;
    }

    function setShellMode(mode: string): void {
        if (mode !== "default" && mode !== "simple" && mode !== "blur"
                && mode !== "neon" && mode !== "minimal" && mode !== "retro" && mode !== "oled")
            return;
        root.shellMode = mode;
        _runModeScript([mode]);
    }

    function toggleShellMode(mode: string): void {
        if (mode !== "simple" && mode !== "blur" && mode !== "neon"
                && mode !== "minimal" && mode !== "retro" && mode !== "oled")
            return;
        setShellMode(root.shellMode === mode ? "default" : mode);
    }

    function cycleShellMode(): void {
        const order = ["default", "blur", "neon", "minimal", "retro", "oled", "simple"];
        const idx = order.indexOf(root.shellMode);
        const nextMode = order[(idx + 1) % order.length];
        setShellMode(nextMode);
    }

    function updateModePref(key: string, val: var): void {
        if (key === "blurEnabled")
            root.blurEnabled = !!val;
        else if (key === "blurFocusedOpacity")
            root.blurFocusedOpacity = Number(val);
        else if (key === "blurUnfocusedOpacity")
            root.blurUnfocusedOpacity = Number(val);
        else if (key === "blurRadius")
            root.blurRadius = Math.round(Number(val));
        else if (key === "blurPasses")
            root.blurPasses = Math.round(Number(val));
        else if (key === "blurSaturation")
            root.blurSaturation = Number(val);
        else if (key === "blurBrightness")
            root.blurBrightness = Number(val);
        else if (key === "defaultRadius")
            root.defaultRadius = Math.round(Number(val));
        else if (key === "defaultGaps")
            root.defaultGaps = Math.round(Number(val));
        else if (key === "defaultBorderPx")
            root.defaultBorderPx = Math.round(Number(val));
        else if (key === "shadows")
            root.wmShadows = !!val;
        else if (key === "animations")
            root.wmAnimations = !!val;
        else if (key === "animationTypeOpen")
            root.animTypeOpen = String(val);
        else if (key === "animationTypeClose")
            root.animTypeClose = String(val);
        else if (key === "animationDuration")
            root.animDuration = Math.round(Number(val));
        else if (key === "tagAnimationDirection")
            root.tagAnimDirection = Math.round(Number(val));
        else if (key === "blurLayer")
            root.blurLayer = !!val;
        else if (key === "blurOptimized")
            root.blurOptimized = !!val;
        else if (key === "blurNoise")
            root.blurNoise = Number(val);
        else if (key === "blurContrast")
            root.blurContrast = Number(val);
        else if (key === "layerShadows")
            root.layerShadows = !!val;
        else if (key === "shadowOnlyFloating")
            root.shadowOnlyFloating = !!val;
        else if (key === "shadowsSize")
            root.shadowsSize = Math.round(Number(val));
        else if (key === "shadowsBlur")
            root.shadowsBlur = Math.round(Number(val));
        else if (key === "layerAnimations")
            root.layerAnimations = !!val;
        else if (key === "animFadeIn")
            root.animFadeIn = !!val;
        else if (key === "animFadeOut")
            root.animFadeOut = !!val;
        else if (key === "dimEnable")
            root.dimEnable = !!val;
        _runModeScript(["--update-pref", key, String(val)]);
    }

    function resetModePrefs(): void {
        _runModeScript(["--reset-prefs"]);
    }

    // --- Public Theme Switching API (invokes scripts/apply-theme.sh) ---
    property var _pendingArgs: []
    property bool _hasPending: false

    function _runApplyScript(args: list<string>): void {
        const scriptPath = Quickshell.shellPath("scripts/apply-theme.sh");
        const fullCmd = [scriptPath].concat(args);
        if (applyProcess.running) {
            root._pendingArgs = fullCmd;
            root._hasPending = true;
            return;
        }
        root.lastError = "";
        applyProcess.command = fullCmd;
        applyProcess.running = true;
    }

    function applyDynamicWallpaper(wallpaper: string): void {
        root.themeMode = "dynamic";
        root.wallpaperPath = wallpaper;
        _runApplyScript(["--mode", "dynamic", "--scheme", root.colorScheme, "--wallpaper", wallpaper]);
    }

    function applyWallpaperWithCurrentMode(wallpaper: string): void {
        root.wallpaperPath = wallpaper;
        const args = ["--mode", root.themeMode, "--scheme", root.colorScheme, "--preset", root.presetName, "--accent", root.accentColor, "--wallpaper", wallpaper];
        if (root.customTheme.length > 0)
            args.push("--custom", root.customTheme);
        _runApplyScript(args);
    }

    function applyPreset(presetId: string): void {
        root.themeMode = "preset";
        root.presetName = presetId;
        _runApplyScript(["--mode", "preset", "--scheme", root.colorScheme, "--preset", presetId, "--no-wallpaper"]);
    }

    function applyAccentColor(hex: string): void {
        root.themeMode = "accent";
        root.accentColor = hex;
        ShellState.setPref("accentSeedColor", hex);
        _runApplyScript(["--mode", "accent", "--accent", hex, "--scheme", root.colorScheme, "--no-wallpaper"]);
    }

    function applyCustomTheme(slug: string): void {
        root.themeMode = "custom";
        root.customTheme = slug;
        _runApplyScript(["--mode", "custom", "--custom", slug, "--no-wallpaper"]);
    }

    function applyVibe(vibeId: string): void {
        Quickshell.execDetached([Quickshell.shellPath("scripts/manage-themes.sh"), "apply-vibe", vibeId]);
    }

    function randomWallpaper(): void {
        Quickshell.execDetached([Quickshell.shellPath("scripts/manage-themes.sh"), "random-wallpaper"]);
    }

    function setScheme(scheme: string): void {
        if (scheme !== "dark" && scheme !== "light")
            return;
        root.colorScheme = scheme;
        const args = [
            "--mode", root.themeMode, "--scheme", scheme,
            "--preset", root.presetName, "--accent", root.accentColor,
            "--wallpaper", root.wallpaperPath, "--no-wallpaper"
        ];
        if (root.customTheme.length > 0)
            args.push("--custom", root.customTheme);
        _runApplyScript(args);
    }

    function toggleScheme(): void {
        setScheme(root.colorScheme === "dark" ? "light" : "dark");
    }

    function setMode(mode: string): void {
        if (mode !== "dynamic" && mode !== "preset" && mode !== "accent" && mode !== "custom")
            return;
        root.themeMode = mode;
        const args = [
            "--mode", mode, "--scheme", root.colorScheme,
            "--preset", root.presetName, "--accent", root.accentColor,
            "--wallpaper", root.wallpaperPath, "--no-wallpaper"
        ];
        if (root.customTheme.length > 0)
            args.push("--custom", root.customTheme);
        _runApplyScript(args);
    }

    FileView {
        id: colorsFile
        path: Quickshell.shellPath("colors.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.applyColorsJson(text())
    }

    FileView {
        id: stateFile
        path: Quickshell.shellPath("theme-state.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.applyStateJson(text())
    }

    FileView {
        id: modeFile
        path: Quickshell.shellPath("shell-mode.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.applyModeJson(text())
    }

    FileView {
        id: prefsFile
        path: Quickshell.shellPath("mode-prefs.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.applyPrefsJson(text())
    }

    Timer {
        id: colorsRetryTimer
        interval: 60
        repeat: false
        onTriggered: colorsFile.reload()
    }

    Timer {
        id: stateRetryTimer
        interval: 60
        repeat: false
        onTriggered: stateFile.reload()
    }

    Timer {
        id: modeRetryTimer
        interval: 60
        repeat: false
        onTriggered: modeFile.reload()
    }

    Timer {
        id: prefsRetryTimer
        interval: 60
        repeat: false
        onTriggered: prefsFile.reload()
    }

    Process {
        id: modeProcess
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg.length > 0)
                    root.lastError = msg;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.lastError.length === 0)
                root.lastError = "Mode script exited with code " + exitCode;
            if (root._pendingModeCmd.length > 0) {
                const nextCmd = root._pendingModeCmd;
                root._pendingModeCmd = [];
                modeProcess.command = nextCmd;
                modeProcess.running = true;
            }
        }
    }

    Process {
        id: applyProcess
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg.length > 0)
                    root.lastError = msg;
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.lastError.length === 0)
                root.lastError = "Theme script exited with code " + exitCode;
            if (root._hasPending) {
                const nextCmd = root._pendingArgs;
                root._hasPending = false;
                root._pendingArgs = [];
                applyProcess.command = nextCmd;
                applyProcess.running = true;
            }
        }
    }
}
