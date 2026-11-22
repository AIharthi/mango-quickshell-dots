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
    property string wallpaperPath: Quickshell.env("HOME") + "/Pictures/Wallpapers/aurora_evening.jpg"
    property string lastError: ""
    readonly property bool applyingTheme: applyProcess.running

    // --- Shell & MangoWC Visual Mode (synced via shell-mode.json & mode-prefs.json) ---
    property string shellMode: "default"         // "default" | "simple" | "blur"
    readonly property bool isSimple: shellMode === "simple"
    readonly property bool isBlur: shellMode === "blur"
    readonly property bool applyingMode: modeProcess.running

    property real blurFocusedOpacity: 0.86
    property real blurUnfocusedOpacity: 0.76
    property int blurRadius: 8
    property int blurPasses: 4
    property real blurSaturation: 1.25
    property real blurBrightness: 0.90
    property int defaultRadius: 20
    property int defaultGaps: 8
    property int defaultBorderPx: 0
    property bool wmShadows: true
    property bool wmAnimations: true
    property string animTypeOpen: "zoom"
    property string animTypeClose: "slide"
    property int animDuration: 300
    property int tagAnimDirection: 1
    property bool blurLayer: true
    property bool blurOptimized: true
    property real blurNoise: 0.02
    property real blurContrast: 0.95
    property bool layerShadows: false
    property bool shadowOnlyFloating: false
    property int shadowsSize: 14
    property int shadowsBlur: 20
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
    readonly property string fontFamily: ShellState.uiFontFamily.length > 0 ? ShellState.uiFontFamily : "JetBrains Mono"
    readonly property string iconFont: "Symbols Nerd Font"
    readonly property bool reducedMotion: isSimple || ShellState.reducedMotion
    readonly property int animFast: reducedMotion ? 0 : 160
    readonly property int animNormal: reducedMotion ? 0 : 260
    readonly property int animSlow: reducedMotion ? 0 : 380

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

    // Derived Dynamic Island / Simple / Blur / Surface-Style tokens
    readonly property bool showGlassSheen: !isSimple && (isBlur || ShellState.surfaceStyle === "glass" || ShellState.borderStyle === "glow")
    readonly property color notchBg: {
        if (isSimple || ShellState.surfaceStyle === "flat")
            return withAlpha(surfaceContainerLowest, ShellState.shellOpacity);
        if (ShellState.surfaceStyle === "oled")
            return withAlpha("#000000", Math.max(0.88, ShellState.shellOpacity));
        if (ShellState.surfaceStyle === "tinted")
            return withAlpha(primaryContainer, Math.min(0.95, ShellState.shellOpacity * 0.88));
        if (isBlur || ShellState.surfaceStyle === "glass")
            return isDark
                ? withAlpha(surfaceContainerLowest, Math.min(0.86, ShellState.shellOpacity * 0.82))
                : withAlpha(surface, Math.min(0.90, ShellState.shellOpacity * 0.86));
        return isDark
            ? withAlpha(Qt.tint("#060609", withAlpha(surfaceContainerLowest, 0.25)), ShellState.shellOpacity)
            : withAlpha(surface, ShellState.shellOpacity);
    }
    readonly property color islandBg: notchBg
    readonly property color islandBorder: {
        if (ShellState.highContrast || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow")
            return primary;
        if (ShellState.borderStyle === "none")
            return "transparent";
        if (isSimple)
            return outlineVariant;
        if (isBlur || ShellState.surfaceStyle === "glass")
            return isDark ? withAlpha(fgSurface, 0.18) : withAlpha(outline, 0.30);
        return withAlpha(outlineVariant, 0.70);
    }
    readonly property int islandBorderWidth: {
        if (ShellState.highContrast)
            return Math.max(1, ShellState.uiBorderWidth);
        if (ShellState.borderStyle === "none")
            return 0;
        if (isSimple)
            return Math.max(1, ShellState.uiBorderWidth);
        if (isBlur || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow" || ShellState.surfaceStyle !== "default")
            return ShellState.uiBorderWidth;
        return 0;
    }
    readonly property color cardBg: {
        if (isSimple)
            return surfaceContainerLow;
        if (ShellState.surfaceStyle === "oled")
            return withAlpha("#0a0a0f", Math.max(0.75, ShellState.cardOpacity));
        if (ShellState.surfaceStyle === "tinted")
            return withAlpha(surfaceContainerHigh, ShellState.cardOpacity * 0.85);
        return isDark
            ? withAlpha(surfaceContainerHigh, ShellState.cardOpacity)
            : withAlpha(surfaceContainerHigh, Math.min(1.0, ShellState.cardOpacity + 0.22));
    }
    readonly property color subCardBg: {
        if (isSimple)
            return surfaceContainer;
        if (ShellState.surfaceStyle === "oled")
            return withAlpha("#12121a", Math.max(0.70, ShellState.cardOpacity));
        return isDark
            ? withAlpha(surfaceContainerHighest, Math.max(0.20, ShellState.cardOpacity * 0.78))
            : withAlpha(surfaceContainer, Math.min(1.0, ShellState.cardOpacity + 0.35));
    }
    readonly property color cardBorder: {
        if (ShellState.highContrast)
            return outline;
        if (ShellState.borderStyle === "none")
            return "transparent";
        if (ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow")
            return withAlpha(primary, 0.55);
        if (isSimple)
            return outlineVariant;
        return isDark ? withAlpha(fgSurface, 0.12) : withAlpha(outline, 0.22);
    }
    readonly property int cardBorderWidth: {
        if (ShellState.highContrast)
            return Math.max(1, ShellState.uiBorderWidth);
        if (ShellState.borderStyle === "none")
            return 0;
        if (isSimple || isBlur || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow" || ShellState.surfaceStyle !== "default")
            return ShellState.uiBorderWidth;
        return 0;
    }
    readonly property color hoverBg: withAlpha(primary, 0.14)
    readonly property color activeBg: withAlpha(primary, 0.22)

    // Smooth color transitions across the entire shell on live reload
    Behavior on primary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgPrimary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on primaryContainer { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgPrimaryContainer { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on secondary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgSecondary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on secondaryContainer { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgSecondaryContainer { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on tertiary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgTertiary { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on background { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgBackground { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surface { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceDim { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceBright { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerLowest { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerLow { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainer { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerHigh { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on surfaceContainerHighest { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgSurface { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgSurfaceVariant { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on outline { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on outlineVariant { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on error { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on fgError { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on success { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on warning { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
    Behavior on info { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }

    function withAlpha(col: color, alpha: real): color {
        return Qt.rgba(col.r, col.g, col.b, alpha);
    }

    function r(val: real): real {
        return root.isSimple ? 0 : Math.round(val * ShellState.uiRadiusScale);
    }

    function fs(px: real): int {
        return Math.max(8, Math.round(px * ShellState.uiFontScale));
    }

    function applyColorsJson(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const data = JSON.parse(raw);
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
            if (st.mode === "default" || st.mode === "simple" || st.mode === "blur")
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
        if (mode !== "default" && mode !== "simple" && mode !== "blur")
            return;
        root.shellMode = mode;
        _runModeScript([mode]);
    }

    function toggleShellMode(mode: string): void {
        if (mode !== "simple" && mode !== "blur")
            return;
        setShellMode(root.shellMode === mode ? "default" : mode);
    }

    function updateModePref(key: string, val: var): void {
        if (key === "blurFocusedOpacity")
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
