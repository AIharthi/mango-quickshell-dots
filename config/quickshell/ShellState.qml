pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- User Preferences (synced via shell-prefs.json) ---
    property bool dnd: false
    property bool dndAllowCritical: true
    property bool notifSoundEnabled: false
    property int notifTimeoutMs: 4500
    property int notifMaxHistory: 40
    property bool clock24h: true
    property bool clockShowSeconds: false
    property string dateFormat: "ddd d MMM"
    property bool keepAwake: false
    property string uiFontFamily: "JetBrains Mono"
    property int uiFontSize: 10
    property string iconTheme: "Adwaita"
    property string matugenType: "scheme-tonal-spot"
    property real matugenContrast: 0.0
    property string wallpaperTransition: "grow"
    property int wallpaperFps: 60
    property real wallpaperDuration: 0.85
    property string wallpaperResize: "crop"
    property bool nightLightEnabled: false
    property int nightLightTemp: 4500
    property string defaultTerminal: "foot"
    property string defaultBrowser: "helium"
    property string defaultEditor: "zedit"
    property string defaultFileManager: "pcmanfm"

    // --- Shell, Island, Bar & Accessibility ---
    property bool islandHoverExpand: true
    property int islandHoverDelayMs: 120
    property int islandCollapseDelayMs: 450
    property bool pillShowMedia: true
    property bool pillSpinArt: true
    property bool pillShowEqualizer: true
    property bool osdEnabled: true
    property int osdTimeoutMs: 1800
    property int simpleBarHeight: 28
    property string simpleBarPosition: "top"
    property bool simpleBarShowLayout: true
    property bool simpleBarShowDate: true
    property bool reducedMotion: false
    property bool highContrast: false
    property bool audioOverAmp: false

    // --- Screenshots ---
    property string screenshotDir: "~/Pictures/Screenshots"
    property bool screenshotCopyClipboard: true
    property bool screenshotNotify: true
    property int screenshotDelay: 0

    // --- Surface, Shape, Island Layout & Advanced Theming ---
    property string surfaceStyle: "default"      // "default" | "glass" | "oled" | "flat" | "tinted"
    property real shellOpacity: 0.92
    property real cardOpacity: 0.50
    property real uiRadiusScale: 1.0
    property string borderStyle: "subtle"        // "none" | "subtle" | "accent" | "glow"
    property int uiBorderWidth: 1
    property real uiFontScale: 1.0
    property string islandStyle: "pill"          // "pill" | "notch" | "bar"
    property int islandTopMargin: 6
    property int pillHeight: 32
    property int matugenSourceIndex: 0
    property string matugenPrefer: "saturation"
    property real matugenLightnessDark: 0.0
    property real matugenLightnessLight: 0.0
    property string wallpaperDir: "~/Pictures/Wallpapers"
    property string accentSeedColor: "#cba6f7"
    property string solidWallpaperColor: "#1e1e2e"
    property string mangoFocusColor: ""
    property string mangoBorderColor: ""
    property bool mangoShadowTint: false
    property real mangoShadowAlpha: 0.80
    property real mangoDimAlpha: 0.27

    // --- Modular Bar Widgets ---
    property bool barShowDate: false
    property bool barShowWindow: false
    property bool barShowWorkspaces: false
    property bool barShowLayout: false
    property bool barShowSystem: false
    property bool barShowVolume: false
    property bool barShowKbLayout: false
    property bool barShowTray: false
    property bool barShowQuickIcons: false
    property bool barShowFiles: true
    property bool barShowBattery: true

    // --- Dynamic File Manager Preferences (Rust Backend) ---
    property string fmViewMode: "list"           // "list" | "grid" | "miller"
    property string fmDensity: "cozy"            // "compact" | "cozy" | "spacious"
    property int fmGridSize: 116
    property string fmIconStyle: "category"      // "category" | "accent" | "mono" | "vivid"
    property string fmSurfacePreset: "inherit"   // "inherit" | "glass" | "solid" | "oled" | "tinted"
    property real fmOpacity: 0.94
    property string fmAccentOverride: ""
    property string fmHeaderStyle: "pill"        // "pill" | "minimal" | "underline"
    property bool fmSidebarVisible: true
    property string fmSidebarStyle: "standard"   // "standard" | "compact" | "icons"
    property bool fmPreviewVisible: true
    property bool fmDualPane: false
    property bool fmShowHidden: false
    property bool fmShowThumbnails: true
    property bool fmShowSizes: true
    property bool fmShowDates: true
    property bool fmShowPerms: false
    property bool fmDirsFirst: true
    property string fmSortBy: "name"             // "name" | "size" | "mtime" | "ext"
    property bool fmSortDesc: false
    property string fmWindowSize: "balanced"     // "compact" | "balanced" | "wide" | "max"
    property bool fmRowAlternating: false
    property bool fmShowCheckboxes: false
    property string fmStartDir: "~"
    property string fmLastDir: "~"

    // --- Live File Operation Status (Session only) ---
    property bool fmOpActive: false
    property string fmOpLabel: ""
    property real fmOpProgress: 0.0
    property string fmOpCurrent: ""

    // --- Picture-in-Picture (PiP) ---
    property bool pipAutoManage: true
    property bool pipSticky: true
    property bool pipAlwaysOnTop: true
    property string pipCorner: "bottom-right"
    property int pipWidthPct: 25
    property int pipMargin: 20

    // --- Session Caches (avoid repeated slow subprocess lookups) ---
    property var cachedMonospaceFonts: []
    property var cachedAllFonts: []
    property string cachedExtractedWpPath: ""
    property var cachedExtractedColors: []

    // --- Session Notification History ---
    property var notificationHistory: []
    property int unreadCount: 0
    property int _nextNotifUid: 1
    property string lastError: ""

    function applyPrefsJson(raw: string): void {
        const text = (raw || "").trim();
        if (text.length === 0) {
            prefsRetryTimer.restart();
            return;
        }
        try {
            const d = JSON.parse(text);
            if (d.dnd !== undefined) root.dnd = !!d.dnd;
            if (d.dndAllowCritical !== undefined) root.dndAllowCritical = !!d.dndAllowCritical;
            if (d.notifSoundEnabled !== undefined) root.notifSoundEnabled = !!d.notifSoundEnabled;
            if (d.notifTimeoutMs !== undefined) root.notifTimeoutMs = Math.max(1500, Math.min(15000, Number(d.notifTimeoutMs)));
            if (d.notifMaxHistory !== undefined) root.notifMaxHistory = Math.max(10, Math.min(200, Number(d.notifMaxHistory)));
            if (d.clock24h !== undefined) root.clock24h = !!d.clock24h;
            if (d.clockShowSeconds !== undefined) root.clockShowSeconds = !!d.clockShowSeconds;
            if (d.dateFormat !== undefined && String(d.dateFormat).length > 0) root.dateFormat = String(d.dateFormat);
            if (d.keepAwake !== undefined) root.keepAwake = !!d.keepAwake;
            if (d.uiFontFamily !== undefined && String(d.uiFontFamily).length > 0) root.uiFontFamily = String(d.uiFontFamily);
            if (d.uiFontSize !== undefined) root.uiFontSize = Math.max(8, Math.min(18, Number(d.uiFontSize)));
            if (d.iconTheme !== undefined && String(d.iconTheme).length > 0) root.iconTheme = String(d.iconTheme);
            if (d.matugenType !== undefined && String(d.matugenType).length > 0) root.matugenType = String(d.matugenType);
            if (d.matugenContrast !== undefined) root.matugenContrast = Math.max(-1.0, Math.min(1.0, Number(d.matugenContrast)));
            if (d.wallpaperTransition !== undefined && String(d.wallpaperTransition).length > 0) root.wallpaperTransition = String(d.wallpaperTransition);
            if (d.wallpaperFps !== undefined) root.wallpaperFps = Math.max(24, Math.min(240, Number(d.wallpaperFps)));
            if (d.wallpaperDuration !== undefined) root.wallpaperDuration = Math.max(0.1, Math.min(3.0, Number(d.wallpaperDuration)));
            if (d.wallpaperResize !== undefined && String(d.wallpaperResize).length > 0) root.wallpaperResize = String(d.wallpaperResize);
            if (d.nightLightEnabled !== undefined) root.nightLightEnabled = !!d.nightLightEnabled;
            if (d.nightLightTemp !== undefined) root.nightLightTemp = Math.max(2500, Math.min(6500, Number(d.nightLightTemp)));
            if (d.defaultTerminal !== undefined && String(d.defaultTerminal).length > 0) root.defaultTerminal = String(d.defaultTerminal);
            if (d.defaultBrowser !== undefined && String(d.defaultBrowser).length > 0) root.defaultBrowser = String(d.defaultBrowser);
            if (d.defaultEditor !== undefined && String(d.defaultEditor).length > 0) root.defaultEditor = String(d.defaultEditor);
            if (d.defaultFileManager !== undefined && String(d.defaultFileManager).length > 0) root.defaultFileManager = String(d.defaultFileManager);
            if (d.islandHoverExpand !== undefined) root.islandHoverExpand = !!d.islandHoverExpand;
            if (d.islandHoverDelayMs !== undefined) root.islandHoverDelayMs = Math.max(50, Math.min(1500, Number(d.islandHoverDelayMs)));
            if (d.islandCollapseDelayMs !== undefined) root.islandCollapseDelayMs = Math.max(200, Math.min(4000, Number(d.islandCollapseDelayMs)));
            if (d.pillShowMedia !== undefined) root.pillShowMedia = !!d.pillShowMedia;
            if (d.pillSpinArt !== undefined) root.pillSpinArt = !!d.pillSpinArt;
            if (d.pillShowEqualizer !== undefined) root.pillShowEqualizer = !!d.pillShowEqualizer;
            if (d.osdEnabled !== undefined) root.osdEnabled = !!d.osdEnabled;
            if (d.osdTimeoutMs !== undefined) root.osdTimeoutMs = Math.max(800, Math.min(6000, Number(d.osdTimeoutMs)));
            if (d.simpleBarHeight !== undefined) root.simpleBarHeight = Math.max(22, Math.min(44, Number(d.simpleBarHeight)));
            if (d.simpleBarPosition !== undefined) root.simpleBarPosition = (String(d.simpleBarPosition) === "bottom" ? "bottom" : "top");
            if (d.simpleBarShowLayout !== undefined) root.simpleBarShowLayout = !!d.simpleBarShowLayout;
            if (d.simpleBarShowDate !== undefined) root.simpleBarShowDate = !!d.simpleBarShowDate;
            if (d.reducedMotion !== undefined) root.reducedMotion = !!d.reducedMotion;
            if (d.highContrast !== undefined) root.highContrast = !!d.highContrast;
            if (d.audioOverAmp !== undefined) root.audioOverAmp = !!d.audioOverAmp;
            if (d.screenshotDir !== undefined && String(d.screenshotDir).length > 0) root.screenshotDir = String(d.screenshotDir);
            if (d.screenshotCopyClipboard !== undefined) root.screenshotCopyClipboard = !!d.screenshotCopyClipboard;
            if (d.screenshotNotify !== undefined) root.screenshotNotify = !!d.screenshotNotify;
            if (d.screenshotDelay !== undefined) root.screenshotDelay = Math.max(0, Math.min(10, Number(d.screenshotDelay)));
            if (d.surfaceStyle !== undefined && String(d.surfaceStyle).length > 0) root.surfaceStyle = String(d.surfaceStyle);
            if (d.shellOpacity !== undefined) root.shellOpacity = Math.max(0.40, Math.min(1.0, Number(d.shellOpacity)));
            if (d.cardOpacity !== undefined) root.cardOpacity = Math.max(0.15, Math.min(1.0, Number(d.cardOpacity)));
            if (d.uiRadiusScale !== undefined) root.uiRadiusScale = Math.max(0.0, Math.min(1.6, Number(d.uiRadiusScale)));
            if (d.borderStyle !== undefined && String(d.borderStyle).length > 0) root.borderStyle = String(d.borderStyle);
            if (d.uiBorderWidth !== undefined) root.uiBorderWidth = Math.max(0, Math.min(3, Number(d.uiBorderWidth)));
            if (d.uiFontScale !== undefined) root.uiFontScale = Math.max(0.85, Math.min(1.25, Number(d.uiFontScale)));
            if (d.islandStyle !== undefined && String(d.islandStyle).length > 0) root.islandStyle = String(d.islandStyle);
            if (d.islandTopMargin !== undefined) root.islandTopMargin = Math.max(0, Math.min(20, Number(d.islandTopMargin)));
            if (d.pillHeight !== undefined) root.pillHeight = Math.max(26, Math.min(40, Number(d.pillHeight)));
            if (d.matugenSourceIndex !== undefined) root.matugenSourceIndex = Math.max(0, Math.min(4, Number(d.matugenSourceIndex)));
            if (d.matugenPrefer !== undefined && String(d.matugenPrefer).length > 0) root.matugenPrefer = String(d.matugenPrefer);
            if (d.matugenLightnessDark !== undefined) root.matugenLightnessDark = Math.max(-0.5, Math.min(0.3, Number(d.matugenLightnessDark)));
            if (d.matugenLightnessLight !== undefined) root.matugenLightnessLight = Math.max(-0.3, Math.min(0.3, Number(d.matugenLightnessLight)));
            if (d.wallpaperDir !== undefined && String(d.wallpaperDir).length > 0) root.wallpaperDir = String(d.wallpaperDir);
            if (d.accentSeedColor !== undefined && String(d.accentSeedColor).length > 0) root.accentSeedColor = String(d.accentSeedColor);
            if (d.solidWallpaperColor !== undefined && String(d.solidWallpaperColor).length > 0) root.solidWallpaperColor = String(d.solidWallpaperColor);
            if (d.mangoFocusColor !== undefined) root.mangoFocusColor = String(d.mangoFocusColor);
            if (d.mangoBorderColor !== undefined) root.mangoBorderColor = String(d.mangoBorderColor);
            if (d.mangoShadowTint !== undefined) root.mangoShadowTint = !!d.mangoShadowTint;
            if (d.mangoShadowAlpha !== undefined) root.mangoShadowAlpha = Math.max(0.0, Math.min(1.0, Number(d.mangoShadowAlpha)));
            if (d.mangoDimAlpha !== undefined) root.mangoDimAlpha = Math.max(0.0, Math.min(0.75, Number(d.mangoDimAlpha)));
            if (d.barShowDate !== undefined) root.barShowDate = !!d.barShowDate;
            if (d.barShowWindow !== undefined) root.barShowWindow = !!d.barShowWindow;
            if (d.barShowWorkspaces !== undefined) root.barShowWorkspaces = !!d.barShowWorkspaces;
            if (d.barShowLayout !== undefined) root.barShowLayout = !!d.barShowLayout;
            if (d.barShowSystem !== undefined) root.barShowSystem = !!d.barShowSystem;
            if (d.barShowVolume !== undefined) root.barShowVolume = !!d.barShowVolume;
            if (d.barShowKbLayout !== undefined) root.barShowKbLayout = !!d.barShowKbLayout;
            if (d.barShowTray !== undefined) root.barShowTray = !!d.barShowTray;
            if (d.barShowQuickIcons !== undefined) root.barShowQuickIcons = !!d.barShowQuickIcons;
            if (d.barShowFiles !== undefined) root.barShowFiles = !!d.barShowFiles;
            if (d.barShowBattery !== undefined) root.barShowBattery = !!d.barShowBattery;
            if (d.fmViewMode !== undefined && String(d.fmViewMode).length > 0) root.fmViewMode = String(d.fmViewMode);
            if (d.fmDensity !== undefined && String(d.fmDensity).length > 0) root.fmDensity = String(d.fmDensity);
            if (d.fmGridSize !== undefined) root.fmGridSize = Math.max(84, Math.min(164, Number(d.fmGridSize)));
            if (d.fmIconStyle !== undefined && String(d.fmIconStyle).length > 0) root.fmIconStyle = String(d.fmIconStyle);
            if (d.fmSurfacePreset !== undefined && String(d.fmSurfacePreset).length > 0) root.fmSurfacePreset = String(d.fmSurfacePreset);
            if (d.fmOpacity !== undefined) root.fmOpacity = Math.max(0.55, Math.min(1.0, Number(d.fmOpacity)));
            if (d.fmAccentOverride !== undefined) root.fmAccentOverride = String(d.fmAccentOverride);
            if (d.fmHeaderStyle !== undefined && String(d.fmHeaderStyle).length > 0) root.fmHeaderStyle = String(d.fmHeaderStyle);
            if (d.fmSidebarVisible !== undefined) root.fmSidebarVisible = !!d.fmSidebarVisible;
            if (d.fmSidebarStyle !== undefined && String(d.fmSidebarStyle).length > 0) root.fmSidebarStyle = String(d.fmSidebarStyle);
            if (d.fmPreviewVisible !== undefined) root.fmPreviewVisible = !!d.fmPreviewVisible;
            if (d.fmDualPane !== undefined) root.fmDualPane = !!d.fmDualPane;
            if (d.fmShowHidden !== undefined) root.fmShowHidden = !!d.fmShowHidden;
            if (d.fmShowThumbnails !== undefined) root.fmShowThumbnails = !!d.fmShowThumbnails;
            if (d.fmShowSizes !== undefined) root.fmShowSizes = !!d.fmShowSizes;
            if (d.fmShowDates !== undefined) root.fmShowDates = !!d.fmShowDates;
            if (d.fmShowPerms !== undefined) root.fmShowPerms = !!d.fmShowPerms;
            if (d.fmDirsFirst !== undefined) root.fmDirsFirst = !!d.fmDirsFirst;
            if (d.fmSortBy !== undefined && String(d.fmSortBy).length > 0) root.fmSortBy = String(d.fmSortBy);
            if (d.fmSortDesc !== undefined) root.fmSortDesc = !!d.fmSortDesc;
            if (d.fmWindowSize !== undefined && String(d.fmWindowSize).length > 0) root.fmWindowSize = String(d.fmWindowSize);
            if (d.fmRowAlternating !== undefined) root.fmRowAlternating = !!d.fmRowAlternating;
            if (d.fmShowCheckboxes !== undefined) root.fmShowCheckboxes = !!d.fmShowCheckboxes;
            if (d.fmStartDir !== undefined && String(d.fmStartDir).length > 0) root.fmStartDir = String(d.fmStartDir);
            if (d.fmLastDir !== undefined && String(d.fmLastDir).length > 0) root.fmLastDir = String(d.fmLastDir);
            if (d.pipAutoManage !== undefined) root.pipAutoManage = !!d.pipAutoManage;
            if (d.pipSticky !== undefined) root.pipSticky = !!d.pipSticky;
            if (d.pipAlwaysOnTop !== undefined) root.pipAlwaysOnTop = !!d.pipAlwaysOnTop;
            if (d.pipCorner !== undefined && String(d.pipCorner).length > 0) root.pipCorner = String(d.pipCorner);
            if (d.pipWidthPct !== undefined) root.pipWidthPct = Math.max(18, Math.min(45, Number(d.pipWidthPct)));
            if (d.pipMargin !== undefined) root.pipMargin = Math.max(6, Math.min(64, Number(d.pipMargin)));
            root.lastError = "";
        } catch (err) {
            prefsRetryTimer.restart();
        }
    }

    function _assignPrefLocal(key: string, value): void {
        if (key === "dnd") root.dnd = !!value;
        else if (key === "dndAllowCritical") root.dndAllowCritical = !!value;
        else if (key === "notifSoundEnabled") root.notifSoundEnabled = !!value;
        else if (key === "notifTimeoutMs") root.notifTimeoutMs = Math.max(1500, Math.min(15000, Number(value)));
        else if (key === "notifMaxHistory") root.notifMaxHistory = Math.max(10, Math.min(200, Number(value)));
        else if (key === "clock24h") root.clock24h = !!value;
        else if (key === "clockShowSeconds") root.clockShowSeconds = !!value;
        else if (key === "dateFormat") root.dateFormat = String(value);
        else if (key === "keepAwake") root.keepAwake = !!value;
        else if (key === "uiFontFamily") root.uiFontFamily = String(value);
        else if (key === "uiFontSize") root.uiFontSize = Math.max(8, Math.min(18, Number(value)));
        else if (key === "iconTheme") root.iconTheme = String(value);
        else if (key === "matugenType") root.matugenType = String(value);
        else if (key === "matugenContrast") root.matugenContrast = Math.max(-1.0, Math.min(1.0, Number(value)));
        else if (key === "wallpaperTransition") root.wallpaperTransition = String(value);
        else if (key === "wallpaperFps") root.wallpaperFps = Math.max(24, Math.min(240, Number(value)));
        else if (key === "wallpaperDuration") root.wallpaperDuration = Math.max(0.1, Math.min(3.0, Number(value)));
        else if (key === "wallpaperResize") root.wallpaperResize = String(value);
        else if (key === "nightLightEnabled") root.nightLightEnabled = !!value;
        else if (key === "nightLightTemp") root.nightLightTemp = Math.max(2500, Math.min(6500, Number(value)));
        else if (key === "defaultTerminal") root.defaultTerminal = String(value);
        else if (key === "defaultBrowser") root.defaultBrowser = String(value);
        else if (key === "defaultEditor") root.defaultEditor = String(value);
        else if (key === "defaultFileManager") root.defaultFileManager = String(value);
        else if (key === "islandHoverExpand") root.islandHoverExpand = !!value;
        else if (key === "islandHoverDelayMs") root.islandHoverDelayMs = Math.max(50, Math.min(1500, Number(value)));
        else if (key === "islandCollapseDelayMs") root.islandCollapseDelayMs = Math.max(200, Math.min(4000, Number(value)));
        else if (key === "pillShowMedia") root.pillShowMedia = !!value;
        else if (key === "pillSpinArt") root.pillSpinArt = !!value;
        else if (key === "pillShowEqualizer") root.pillShowEqualizer = !!value;
        else if (key === "osdEnabled") root.osdEnabled = !!value;
        else if (key === "osdTimeoutMs") root.osdTimeoutMs = Math.max(800, Math.min(6000, Number(value)));
        else if (key === "simpleBarHeight") root.simpleBarHeight = Math.max(22, Math.min(44, Number(value)));
        else if (key === "simpleBarPosition") root.simpleBarPosition = (String(value) === "bottom" ? "bottom" : "top");
        else if (key === "simpleBarShowLayout") root.simpleBarShowLayout = !!value;
        else if (key === "simpleBarShowDate") root.simpleBarShowDate = !!value;
        else if (key === "reducedMotion") root.reducedMotion = !!value;
        else if (key === "highContrast") root.highContrast = !!value;
        else if (key === "audioOverAmp") root.audioOverAmp = !!value;
        else if (key === "screenshotDir") root.screenshotDir = String(value);
        else if (key === "screenshotCopyClipboard") root.screenshotCopyClipboard = !!value;
        else if (key === "screenshotNotify") root.screenshotNotify = !!value;
        else if (key === "screenshotDelay") root.screenshotDelay = Math.max(0, Math.min(10, Number(value)));
        else if (key === "surfaceStyle") root.surfaceStyle = String(value);
        else if (key === "shellOpacity") root.shellOpacity = Math.max(0.40, Math.min(1.0, Number(value)));
        else if (key === "cardOpacity") root.cardOpacity = Math.max(0.15, Math.min(1.0, Number(value)));
        else if (key === "uiRadiusScale") root.uiRadiusScale = Math.max(0.0, Math.min(1.6, Number(value)));
        else if (key === "borderStyle") root.borderStyle = String(value);
        else if (key === "uiBorderWidth") root.uiBorderWidth = Math.max(0, Math.min(3, Number(value)));
        else if (key === "uiFontScale") root.uiFontScale = Math.max(0.85, Math.min(1.25, Number(value)));
        else if (key === "islandStyle") root.islandStyle = String(value);
        else if (key === "islandTopMargin") root.islandTopMargin = Math.max(0, Math.min(20, Number(value)));
        else if (key === "pillHeight") root.pillHeight = Math.max(26, Math.min(40, Number(value)));
        else if (key === "matugenSourceIndex") root.matugenSourceIndex = Math.max(0, Math.min(4, Number(value)));
        else if (key === "matugenPrefer") root.matugenPrefer = String(value);
        else if (key === "matugenLightnessDark") root.matugenLightnessDark = Math.max(-0.5, Math.min(0.3, Number(value)));
        else if (key === "matugenLightnessLight") root.matugenLightnessLight = Math.max(-0.3, Math.min(0.3, Number(value)));
        else if (key === "wallpaperDir") root.wallpaperDir = String(value);
        else if (key === "accentSeedColor") root.accentSeedColor = String(value);
        else if (key === "solidWallpaperColor") root.solidWallpaperColor = String(value);
        else if (key === "mangoFocusColor") root.mangoFocusColor = String(value);
        else if (key === "mangoBorderColor") root.mangoBorderColor = String(value);
        else if (key === "mangoShadowTint") root.mangoShadowTint = !!value;
        else if (key === "mangoShadowAlpha") root.mangoShadowAlpha = Math.max(0.0, Math.min(1.0, Number(value)));
        else if (key === "mangoDimAlpha") root.mangoDimAlpha = Math.max(0.0, Math.min(0.75, Number(value)));
        else if (key === "barShowDate") root.barShowDate = !!value;
        else if (key === "barShowWindow") root.barShowWindow = !!value;
        else if (key === "barShowWorkspaces") root.barShowWorkspaces = !!value;
        else if (key === "barShowLayout") root.barShowLayout = !!value;
        else if (key === "barShowSystem") root.barShowSystem = !!value;
        else if (key === "barShowVolume") root.barShowVolume = !!value;
        else if (key === "barShowKbLayout") root.barShowKbLayout = !!value;
        else if (key === "barShowTray") root.barShowTray = !!value;
        else if (key === "barShowQuickIcons") root.barShowQuickIcons = !!value;
        else if (key === "barShowFiles") root.barShowFiles = !!value;
        else if (key === "barShowBattery") root.barShowBattery = !!value;
        else if (key === "fmViewMode") root.fmViewMode = String(value);
        else if (key === "fmDensity") root.fmDensity = String(value);
        else if (key === "fmGridSize") root.fmGridSize = Math.max(84, Math.min(164, Number(value)));
        else if (key === "fmIconStyle") root.fmIconStyle = String(value);
        else if (key === "fmSurfacePreset") root.fmSurfacePreset = String(value);
        else if (key === "fmOpacity") root.fmOpacity = Math.max(0.55, Math.min(1.0, Number(value)));
        else if (key === "fmAccentOverride") root.fmAccentOverride = String(value);
        else if (key === "fmHeaderStyle") root.fmHeaderStyle = String(value);
        else if (key === "fmSidebarVisible") root.fmSidebarVisible = !!value;
        else if (key === "fmSidebarStyle") root.fmSidebarStyle = String(value);
        else if (key === "fmPreviewVisible") root.fmPreviewVisible = !!value;
        else if (key === "fmDualPane") root.fmDualPane = !!value;
        else if (key === "fmShowHidden") root.fmShowHidden = !!value;
        else if (key === "fmShowThumbnails") root.fmShowThumbnails = !!value;
        else if (key === "fmShowSizes") root.fmShowSizes = !!value;
        else if (key === "fmShowDates") root.fmShowDates = !!value;
        else if (key === "fmShowPerms") root.fmShowPerms = !!value;
        else if (key === "fmDirsFirst") root.fmDirsFirst = !!value;
        else if (key === "fmSortBy") root.fmSortBy = String(value);
        else if (key === "fmSortDesc") root.fmSortDesc = !!value;
        else if (key === "fmWindowSize") root.fmWindowSize = String(value);
        else if (key === "fmRowAlternating") root.fmRowAlternating = !!value;
        else if (key === "fmShowCheckboxes") root.fmShowCheckboxes = !!value;
        else if (key === "fmStartDir") root.fmStartDir = String(value);
        else if (key === "fmLastDir") root.fmLastDir = String(value);
        else if (key === "pipAutoManage") root.pipAutoManage = !!value;
        else if (key === "pipSticky") root.pipSticky = !!value;
        else if (key === "pipAlwaysOnTop") root.pipAlwaysOnTop = !!value;
        else if (key === "pipCorner") root.pipCorner = String(value);
        else if (key === "pipWidthPct") root.pipWidthPct = Math.max(18, Math.min(45, Number(value)));
        else if (key === "pipMargin") root.pipMargin = Math.max(6, Math.min(64, Number(value)));
    }

    function setPref(key: string, value): void {
        _assignPrefLocal(key, value);
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "prefs-set", key, String(value)
        ]);
    }

    function setPrefsBatch(map: var): void {
        if (!map)
            return;
        for (const k in map)
            _assignPrefLocal(k, map[k]);
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "prefs-set-batch", JSON.stringify(map)
        ]);
    }

    function togglePip(): void {
        Quickshell.execDetached([Quickshell.shellPath("scripts/manage-pip.sh"), "toggle"]);
    }

    function cyclePipCorner(): void {
        Quickshell.execDetached([Quickshell.shellPath("scripts/manage-pip.sh"), "cycle-corner"]);
    }

    function snapPip(): void {
        Quickshell.execDetached([Quickshell.shellPath("scripts/manage-pip.sh"), "snap"]);
    }

    function resetPrefs(): void {
        if (!resetProc.running)
            resetProc.running = true;
    }

    function _runResetCmd(subcmd: string): void {
        if (resetActionProc.running)
            return;
        resetActionProc.command = [Quickshell.shellPath("scripts/manage-settings.sh"), subcmd];
        resetActionProc.running = true;
    }

    function resetAppearance(): void {
        _runResetCmd("reset-appearance");
    }

    function resetBar(): void {
        _runResetCmd("reset-bar");
    }

    function resetFiles(): void {
        _runResetCmd("reset-files");
    }

    function applyFmPreset(preset: string): void {
        let map = null;
        if (preset === "finder") {
            map = {
                fmViewMode: "miller",
                fmDensity: "cozy",
                fmIconStyle: "category",
                fmSurfacePreset: "inherit",
                fmHeaderStyle: "pill",
                fmSidebarVisible: true,
                fmSidebarStyle: "standard",
                fmPreviewVisible: true,
                fmDualPane: false,
                fmRowAlternating: false,
                fmShowSizes: true,
                fmShowDates: true,
                fmShowPerms: false,
                fmWindowSize: "wide"
            };
        } else if (preset === "minimal") {
            map = {
                fmViewMode: "list",
                fmDensity: "compact",
                fmIconStyle: "mono",
                fmSurfacePreset: "oled",
                fmOpacity: 0.96,
                fmHeaderStyle: "minimal",
                fmSidebarVisible: false,
                fmPreviewVisible: false,
                fmDualPane: false,
                fmRowAlternating: false,
                fmShowDates: false,
                fmShowPerms: false,
                fmWindowSize: "compact"
            };
        } else if (preset === "gallery") {
            map = {
                fmViewMode: "grid",
                fmDensity: "spacious",
                fmGridSize: 138,
                fmIconStyle: "vivid",
                fmSurfacePreset: "glass",
                fmOpacity: 0.90,
                fmHeaderStyle: "pill",
                fmSidebarVisible: true,
                fmSidebarStyle: "compact",
                fmPreviewVisible: true,
                fmDualPane: false,
                fmShowThumbnails: true,
                fmWindowSize: "wide"
            };
        } else if (preset === "commander") {
            map = {
                fmViewMode: "list",
                fmDensity: "compact",
                fmIconStyle: "accent",
                fmSurfacePreset: "solid",
                fmHeaderStyle: "underline",
                fmSidebarVisible: true,
                fmSidebarStyle: "icons",
                fmPreviewVisible: false,
                fmDualPane: true,
                fmRowAlternating: true,
                fmShowSizes: true,
                fmShowDates: true,
                fmShowPerms: true,
                fmWindowSize: "max"
            };
        }
        if (map)
            setPrefsBatch(map);
    }

    function resetAllSettings(): void {
        _runResetCmd("reset-all");
    }

    function applyBarPreset(preset: string): void {
        let map = null;
        if (preset === "minimal") {
            map = {
                islandStyle: "pill",
                barShowDate: false,
                barShowWindow: false,
                barShowWorkspaces: false,
                barShowLayout: false,
                barShowSystem: false,
                barShowVolume: false,
                barShowKbLayout: false,
                barShowTray: false,
                barShowQuickIcons: false,
                barShowFiles: false,
                pillShowMedia: true
            };
        } else if (preset === "balanced") {
            map = {
                islandStyle: "pill",
                barShowDate: true,
                barShowWindow: true,
                barShowWorkspaces: true,
                barShowLayout: false,
                barShowSystem: false,
                barShowVolume: false,
                barShowKbLayout: false,
                barShowTray: false,
                barShowQuickIcons: false,
                barShowFiles: true,
                pillShowMedia: true
            };
        } else if (preset === "full") {
            map = {
                islandStyle: "bar",
                barShowDate: true,
                barShowWindow: true,
                barShowWorkspaces: true,
                barShowLayout: true,
                barShowSystem: true,
                barShowVolume: DeviceCaps.hasAudio,
                barShowKbLayout: false,
                barShowTray: true,
                barShowQuickIcons: true,
                barShowFiles: true,
                pillShowMedia: true
            };
        }
        if (map)
            setPrefsBatch(map);
    }

    function setFont(family: string, size: int): void {
        const cleanFam = (family || "").trim();
        const clampedSize = Math.max(8, Math.min(18, size));
        if (cleanFam.length === 0)
            return;
        root.uiFontFamily = cleanFam;
        root.uiFontSize = clampedSize;
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "set-font", cleanFam, String(clampedSize)
        ]);
    }

    function setNightLight(enabled: bool, temp: int): void {
        const clampedTemp = Math.max(2500, Math.min(6500, temp));
        root.nightLightEnabled = enabled;
        root.nightLightTemp = clampedTemp;
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "night-light", enabled ? "on" : "off", String(clampedTemp)
        ]);
    }

    function toggleDnd(): void {
        setPref("dnd", !root.dnd);
    }

    function toggleKeepAwake(): void {
        setPref("keepAwake", !root.keepAwake);
    }

    function recordNotification(notif): void {
        if (!notif)
            return;
        const entry = {
            uid: root._nextNotifUid++,
            summary: String(notif.summary || "Notification"),
            body: String(notif.body || ""),
            appName: String(notif.appName || "System"),
            urgency: Number(notif.urgency || 0),
            timeStr: formatTime(new Date())
        };
        const cap = Math.max(10, Math.min(200, root.notifMaxHistory));
        const updated = [entry].concat(root.notificationHistory || []);
        if (updated.length > cap)
            updated.length = cap;
        root.notificationHistory = updated;
        root.unreadCount = root.unreadCount + 1;
    }

    function dismissNotification(uid: int): void {
        root.notificationHistory = (root.notificationHistory || []).filter(item => item.uid !== uid);
    }

    function clearHistory(): void {
        root.notificationHistory = [];
        root.unreadCount = 0;
    }

    function clearUnread(): void {
        root.unreadCount = 0;
    }

    function formatTime(dt): string {
        if (!dt)
            return "";
        const fmt = root.clock24h
            ? (root.clockShowSeconds ? "HH:mm:ss" : "HH:mm")
            : (root.clockShowSeconds ? "hh:mm:ss AP" : "hh:mm AP");
        return Qt.formatDateTime(dt, fmt);
    }

    function formatDate(dt): string {
        if (!dt)
            return "";
        return Qt.formatDateTime(dt, root.dateFormat.length > 0 ? root.dateFormat : "ddd d MMM");
    }

    Component.onCompleted: {
        initProc.running = true;
    }

    Process {
        id: initProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "prefs-get"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyPrefsJson(text)
        }
    }

    Process {
        id: resetProc
        command: [Quickshell.shellPath("scripts/manage-settings.sh"), "prefs-reset"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyPrefsJson(text)
        }
    }

    Process {
        id: resetActionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyPrefsJson(text)
        }
    }

    FileView {
        id: prefsFile
        path: Quickshell.shellPath("shell-prefs.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.applyPrefsJson(text())
    }

    Timer {
        id: prefsRetryTimer
        interval: 80
        repeat: false
        onTriggered: prefsFile.reload()
    }
}
