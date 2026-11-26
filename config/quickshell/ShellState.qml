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
    property string uiFontFamily: "IBM Plex Sans"
    property string monoFontFamily: "IBM Plex Mono"
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

    // --- Screenshots & Recording ---
    property string screenshotDir: "~/Pictures/Screenshots"
    property bool screenshotCopyClipboard: true
    property bool screenshotNotify: true
    property int screenshotDelay: 0
    property string recordingDir: "~/Videos/Recordings"

    // --- Idle Power, Weather, Slideshow & Scratchpad ---
    property bool idleLockEnabled: true
    property int idleLockSeconds: 300
    property bool idleSuspendEnabled: false
    property int idleSuspendSeconds: 900
    property string scratchpadText: ""
    property bool weatherEnabled: false
    property string weatherLocation: ""
    property string weatherUnits: "C"
    property bool barShowWeather: false
    property bool wallpaperSlideshowEnabled: false
    property int wallpaperSlideshowMinutes: 15

    // --- Session Focus Timer, Stopwatch, Weather, Game Mode & Screen Recording ---
    property bool timerActive: false
    property int timerDurationSec: 1500
    property int timerRemainingSec: 1500
    property bool stopwatchActive: false
    property int stopwatchElapsedSec: 0
    property var stopwatchLaps: []
    property bool weatherAvailable: false
    property string weatherTemp: ""
    property string weatherFeelsLike: ""
    property string weatherCondition: ""
    property string weatherHumidity: ""
    property string weatherWind: ""
    property string weatherCity: ""
    property string weatherIcon: "󰖐"
    property string weatherUpdated: ""
    property bool gameModeActive: false
    property string _preGameShellMode: "default"
    property bool _preGameDnd: false
    property bool _preGameKeepAwake: false
    property string _observedShellMode: "default"
    property bool recordingActive: false
    property int recordingElapsedSec: 0
    property int _recordingStartedAt: 0

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
    property string hubUiStyle: "cupertino"      // "cupertino" | "stage" | "cockpit" | "bento"
    property string barUiStyle: "apple"          // "apple" | "split" | "menubar" | "classic"

    // --- Sequoia Menu Bar & Dedicated Control Center ---
    property int sequoiaBarHeight: 28
    property bool sequoiaBarFloating: false
    property bool sequoiaBarTranslucent: true
    property string sequoiaHubStyle: "controlcenter" // "controlcenter" | "compact" | "media"
    property string sequoiaMenuIcon: "aurora"        // "aurora" | "apple" | "cachyos" | "arch" | "fedora" | "gentoo" | "minimal"
    property bool sequoiaShowAppTitle: true
    property bool sequoiaShowWorkspaces: true
    property bool sequoiaShowLayout: false
    property bool sequoiaShowMedia: true
    property bool sequoiaShowSystem: false
    property bool sequoiaShowNetSpeed: false
    property bool sequoiaShowVolume: true
    property bool sequoiaShowBattery: true
    property bool sequoiaShowTray: true
    property bool sequoiaShowStore: true
    property bool sequoiaShowSpotlightIcon: true
    property bool sequoiaShowDate: true

    // --- Split Islands (3 Stationary Sequoia Pods & Anchored Hubs) ---
    property int splitBarHeight: 32
    property int splitTopMargin: 6
    property int splitSideMargin: 10
    property string splitPodStyle: "pill"            // "pill" | "rounded" | "compact"
    property bool splitBarTranslucent: true
    property string splitHubStyle: "controlcenter"   // "controlcenter" | "compact" | "media"
    property string splitMenuIcon: "aurora"          // "aurora" | "apple" | "cachyos" | "arch" | "fedora" | "gentoo" | "minimal"
    property bool splitShowLauncherIcon: true
    property bool splitShowWorkspaces: true
    property bool splitShowLayout: true
    property bool splitShowAppTitle: true
    property bool splitShowDate: true
    property bool splitShowMedia: true
    property bool splitShowWeather: true
    property bool splitShowSystem: false
    property bool splitShowNetSpeed: false
    property bool splitShowVolume: true
    property bool splitShowKbLayout: true
    property bool splitShowBattery: true
    property bool splitShowTray: true
    property bool splitShowStore: true
    property bool splitShowFiles: true

    readonly property var availableHubStyles: [
        { id: "cupertino", label: "Cupertino", vibe: "macOS Control Center", desc: "Borderless connectivity platter, sliders, compact spaces & activity rings", icon: "󰕰" },
        { id: "stage",     label: "Stage",     vibe: "Media Showcase & Controls", desc: "Artwork showcase card paired with live toggles, spaces & metric deck", icon: "󰓇" },
        { id: "cockpit",   label: "Cockpit",   vibe: "Telemetry & Command Deck", desc: "Top media & workspace ribbon over dual sparkline monitor & controls", icon: "󰍛" },
        { id: "bento",     label: "Bento",     vibe: "Balanced 2x2 Grid", desc: "Snug four-card grid for Media, System Monitor, Workspaces & Controls", icon: "󰕮" }
    ]

    readonly property var availableSequoiaHubStyles: [
        { id: "controlcenter", label: "Control Center", vibe: "macOS Sequoia", desc: "2x2 connectivity platter, display & sound sliders, Now Playing, and spaces", icon: "󰕰" },
        { id: "compact",       label: "Compact Stack",  vibe: "Minimal Popover", desc: "Streamlined quick toggles, audio slider, and active workspaces", icon: "󰘔" },
        { id: "media",         label: "Studio Platter", vibe: "Audio & Media", desc: "Expanded album artwork, output routing, sliders, and telemetry rings", icon: "󰓇" }
    ]

    readonly property var availableBarStyles: [
        { id: "apple",   label: "Dynamic Island", vibe: "iOS / macOS Capsule", desc: "Calm monochrome capsule with clock, cover art & active indicators", icon: "󰀵" },
        { id: "split",   label: "Split Islands",  vibe: "3 Stationary Glass Pods", desc: "Left Spaces, Center Media/Clock & Right Control Center pods with per-pod hubs", icon: "󰕰" },
        { id: "menubar", label: "Sequoia Bar",    vibe: "macOS Top Menu Bar", desc: "Dedicated menu bar with right-side Control Center & Spotlight", icon: "󰘔" },
        { id: "classic", label: "Modular Pill",   vibe: "Custom Widget Bar", desc: "Customizable modular pill, top notch, or full-width desktop bar", icon: "󰕮" }
    ]
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
    property bool barShowNetSpeed: false
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
    property var cachedSansFonts: []
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
            if (d.monoFontFamily !== undefined && String(d.monoFontFamily).length > 0) root.monoFontFamily = String(d.monoFontFamily);
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
            if (d.recordingDir !== undefined && String(d.recordingDir).length > 0) root.recordingDir = String(d.recordingDir);
            if (d.idleLockEnabled !== undefined) root.idleLockEnabled = !!d.idleLockEnabled;
            if (d.idleLockSeconds !== undefined) root.idleLockSeconds = Math.max(30, Math.min(3600, Number(d.idleLockSeconds)));
            if (d.idleSuspendEnabled !== undefined) root.idleSuspendEnabled = !!d.idleSuspendEnabled;
            if (d.idleSuspendSeconds !== undefined) root.idleSuspendSeconds = Math.max(60, Math.min(7200, Number(d.idleSuspendSeconds)));
            if (d.scratchpadText !== undefined) root.scratchpadText = String(d.scratchpadText);
            if (d.weatherEnabled !== undefined) {
                const prevW = root.weatherEnabled;
                root.weatherEnabled = !!d.weatherEnabled;
                if (root.weatherEnabled && !prevW)
                    refreshWeather(false);
            }
            if (d.weatherLocation !== undefined) root.weatherLocation = String(d.weatherLocation);
            if (d.weatherUnits !== undefined) root.weatherUnits = (String(d.weatherUnits).toUpperCase() === "F" ? "F" : "C");
            if (d.barShowWeather !== undefined) root.barShowWeather = !!d.barShowWeather;
            if (d.wallpaperSlideshowEnabled !== undefined) root.wallpaperSlideshowEnabled = !!d.wallpaperSlideshowEnabled;
            if (d.wallpaperSlideshowMinutes !== undefined) root.wallpaperSlideshowMinutes = Math.max(1, Math.min(1440, Number(d.wallpaperSlideshowMinutes)));
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
            if (d.hubUiStyle !== undefined) {
                const hs = String(d.hubUiStyle).toLowerCase();
                if (hs === "cupertino" || hs === "stage" || hs === "cockpit" || hs === "bento")
                    root.hubUiStyle = hs;
            }
            if (d.barUiStyle !== undefined) {
                const bs = String(d.barUiStyle).toLowerCase();
                if (bs === "apple" || bs === "split" || bs === "menubar" || bs === "classic")
                    root.barUiStyle = bs;
            }
            if (d.sequoiaBarHeight !== undefined) root.sequoiaBarHeight = Math.max(24, Math.min(36, Number(d.sequoiaBarHeight)));
            if (d.sequoiaBarFloating !== undefined) root.sequoiaBarFloating = !!d.sequoiaBarFloating;
            if (d.sequoiaBarTranslucent !== undefined) root.sequoiaBarTranslucent = !!d.sequoiaBarTranslucent;
            if (d.sequoiaHubStyle !== undefined) {
                const shs = String(d.sequoiaHubStyle).toLowerCase();
                if (shs === "controlcenter" || shs === "compact" || shs === "media")
                    root.sequoiaHubStyle = shs;
            }
            if (d.sequoiaMenuIcon !== undefined) {
                const smi = String(d.sequoiaMenuIcon).toLowerCase();
                if (smi === "aurora" || smi === "apple" || smi === "cachyos" || smi === "arch" || smi === "fedora" || smi === "gentoo" || smi === "minimal")
                    root.sequoiaMenuIcon = smi;
            }
            if (d.sequoiaShowAppTitle !== undefined) root.sequoiaShowAppTitle = !!d.sequoiaShowAppTitle;
            if (d.sequoiaShowWorkspaces !== undefined) root.sequoiaShowWorkspaces = !!d.sequoiaShowWorkspaces;
            if (d.sequoiaShowLayout !== undefined) root.sequoiaShowLayout = !!d.sequoiaShowLayout;
            if (d.sequoiaShowMedia !== undefined) root.sequoiaShowMedia = !!d.sequoiaShowMedia;
            if (d.sequoiaShowSystem !== undefined) root.sequoiaShowSystem = !!d.sequoiaShowSystem;
            if (d.sequoiaShowNetSpeed !== undefined) root.sequoiaShowNetSpeed = !!d.sequoiaShowNetSpeed;
            if (d.sequoiaShowVolume !== undefined) root.sequoiaShowVolume = !!d.sequoiaShowVolume;
            if (d.sequoiaShowBattery !== undefined) root.sequoiaShowBattery = !!d.sequoiaShowBattery;
            if (d.sequoiaShowTray !== undefined) root.sequoiaShowTray = !!d.sequoiaShowTray;
            if (d.sequoiaShowStore !== undefined) root.sequoiaShowStore = !!d.sequoiaShowStore;
            if (d.sequoiaShowSpotlightIcon !== undefined) root.sequoiaShowSpotlightIcon = !!d.sequoiaShowSpotlightIcon;
            if (d.sequoiaShowDate !== undefined) root.sequoiaShowDate = !!d.sequoiaShowDate;
            if (d.splitBarHeight !== undefined) root.splitBarHeight = Math.max(26, Math.min(40, Number(d.splitBarHeight)));
            if (d.splitTopMargin !== undefined) root.splitTopMargin = Math.max(2, Math.min(18, Number(d.splitTopMargin)));
            if (d.splitSideMargin !== undefined) root.splitSideMargin = Math.max(4, Math.min(28, Number(d.splitSideMargin)));
            if (d.splitPodStyle !== undefined) {
                const sps = String(d.splitPodStyle).toLowerCase();
                if (sps === "pill" || sps === "rounded" || sps === "compact")
                    root.splitPodStyle = sps;
            }
            if (d.splitBarTranslucent !== undefined) root.splitBarTranslucent = !!d.splitBarTranslucent;
            if (d.splitHubStyle !== undefined) {
                const sphs = String(d.splitHubStyle).toLowerCase();
                if (sphs === "controlcenter" || sphs === "compact" || sphs === "media")
                    root.splitHubStyle = sphs;
            }
            if (d.splitMenuIcon !== undefined) {
                const spmi = String(d.splitMenuIcon).toLowerCase();
                if (spmi === "aurora" || spmi === "apple" || spmi === "cachyos" || spmi === "arch" || spmi === "fedora" || spmi === "gentoo" || spmi === "minimal")
                    root.splitMenuIcon = spmi;
            }
            if (d.splitShowLauncherIcon !== undefined) root.splitShowLauncherIcon = !!d.splitShowLauncherIcon;
            if (d.splitShowWorkspaces !== undefined) root.splitShowWorkspaces = !!d.splitShowWorkspaces;
            if (d.splitShowLayout !== undefined) root.splitShowLayout = !!d.splitShowLayout;
            if (d.splitShowAppTitle !== undefined) root.splitShowAppTitle = !!d.splitShowAppTitle;
            if (d.splitShowDate !== undefined) root.splitShowDate = !!d.splitShowDate;
            if (d.splitShowMedia !== undefined) root.splitShowMedia = !!d.splitShowMedia;
            if (d.splitShowWeather !== undefined) root.splitShowWeather = !!d.splitShowWeather;
            if (d.splitShowSystem !== undefined) root.splitShowSystem = !!d.splitShowSystem;
            if (d.splitShowNetSpeed !== undefined) root.splitShowNetSpeed = !!d.splitShowNetSpeed;
            if (d.splitShowVolume !== undefined) root.splitShowVolume = !!d.splitShowVolume;
            if (d.splitShowKbLayout !== undefined) root.splitShowKbLayout = !!d.splitShowKbLayout;
            if (d.splitShowBattery !== undefined) root.splitShowBattery = !!d.splitShowBattery;
            if (d.splitShowTray !== undefined) root.splitShowTray = !!d.splitShowTray;
            if (d.splitShowStore !== undefined) root.splitShowStore = !!d.splitShowStore;
            if (d.splitShowFiles !== undefined) root.splitShowFiles = !!d.splitShowFiles;
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
            if (d.barShowNetSpeed !== undefined) root.barShowNetSpeed = !!d.barShowNetSpeed;
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
        else if (key === "monoFontFamily") root.monoFontFamily = String(value);
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
        else if (key === "recordingDir") root.recordingDir = String(value);
        else if (key === "idleLockEnabled") root.idleLockEnabled = !!value;
        else if (key === "idleLockSeconds") root.idleLockSeconds = Math.max(30, Math.min(3600, Number(value)));
        else if (key === "idleSuspendEnabled") root.idleSuspendEnabled = !!value;
        else if (key === "idleSuspendSeconds") root.idleSuspendSeconds = Math.max(60, Math.min(7200, Number(value)));
        else if (key === "scratchpadText") root.scratchpadText = String(value);
        else if (key === "weatherEnabled") {
            root.weatherEnabled = !!value;
            if (root.weatherEnabled)
                refreshWeather(false);
        }
        else if (key === "weatherLocation") root.weatherLocation = String(value);
        else if (key === "weatherUnits") root.weatherUnits = (String(value).toUpperCase() === "F" ? "F" : "C");
        else if (key === "barShowWeather") root.barShowWeather = !!value;
        else if (key === "wallpaperSlideshowEnabled") root.wallpaperSlideshowEnabled = !!value;
        else if (key === "wallpaperSlideshowMinutes") root.wallpaperSlideshowMinutes = Math.max(1, Math.min(1440, Number(value)));
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
        else if (key === "hubUiStyle") {
            const hs = String(value).toLowerCase();
            if (hs === "cupertino" || hs === "stage" || hs === "cockpit" || hs === "bento")
                root.hubUiStyle = hs;
        }
        else if (key === "barUiStyle") {
            const bs = String(value).toLowerCase();
            if (bs === "apple" || bs === "split" || bs === "menubar" || bs === "classic")
                root.barUiStyle = bs;
        }
        else if (key === "sequoiaBarHeight") root.sequoiaBarHeight = Math.max(24, Math.min(36, Number(value)));
        else if (key === "sequoiaBarFloating") root.sequoiaBarFloating = !!value;
        else if (key === "sequoiaBarTranslucent") root.sequoiaBarTranslucent = !!value;
        else if (key === "sequoiaHubStyle") {
            const shs = String(value).toLowerCase();
            if (shs === "controlcenter" || shs === "compact" || shs === "media")
                root.sequoiaHubStyle = shs;
        }
        else if (key === "sequoiaMenuIcon") {
            const smi = String(value).toLowerCase();
            if (smi === "aurora" || smi === "apple" || smi === "cachyos" || smi === "arch" || smi === "fedora" || smi === "gentoo" || smi === "minimal")
                root.sequoiaMenuIcon = smi;
        }
        else if (key === "sequoiaShowAppTitle") root.sequoiaShowAppTitle = !!value;
        else if (key === "sequoiaShowWorkspaces") root.sequoiaShowWorkspaces = !!value;
        else if (key === "sequoiaShowLayout") root.sequoiaShowLayout = !!value;
        else if (key === "sequoiaShowMedia") root.sequoiaShowMedia = !!value;
        else if (key === "sequoiaShowSystem") root.sequoiaShowSystem = !!value;
        else if (key === "sequoiaShowNetSpeed") root.sequoiaShowNetSpeed = !!value;
        else if (key === "sequoiaShowVolume") root.sequoiaShowVolume = !!value;
        else if (key === "sequoiaShowBattery") root.sequoiaShowBattery = !!value;
        else if (key === "sequoiaShowTray") root.sequoiaShowTray = !!value;
        else if (key === "sequoiaShowStore") root.sequoiaShowStore = !!value;
        else if (key === "sequoiaShowSpotlightIcon") root.sequoiaShowSpotlightIcon = !!value;
        else if (key === "sequoiaShowDate") root.sequoiaShowDate = !!value;
        else if (key === "splitBarHeight") root.splitBarHeight = Math.max(26, Math.min(40, Number(value)));
        else if (key === "splitTopMargin") root.splitTopMargin = Math.max(2, Math.min(18, Number(value)));
        else if (key === "splitSideMargin") root.splitSideMargin = Math.max(4, Math.min(28, Number(value)));
        else if (key === "splitPodStyle") {
            const sps = String(value).toLowerCase();
            if (sps === "pill" || sps === "rounded" || sps === "compact")
                root.splitPodStyle = sps;
        }
        else if (key === "splitBarTranslucent") root.splitBarTranslucent = !!value;
        else if (key === "splitHubStyle") {
            const sphs = String(value).toLowerCase();
            if (sphs === "controlcenter" || sphs === "compact" || sphs === "media")
                root.splitHubStyle = sphs;
        }
        else if (key === "splitMenuIcon") {
            const spmi = String(value).toLowerCase();
            if (spmi === "aurora" || spmi === "apple" || spmi === "cachyos" || spmi === "arch" || spmi === "fedora" || spmi === "gentoo" || spmi === "minimal")
                root.splitMenuIcon = spmi;
        }
        else if (key === "splitShowLauncherIcon") root.splitShowLauncherIcon = !!value;
        else if (key === "splitShowWorkspaces") root.splitShowWorkspaces = !!value;
        else if (key === "splitShowLayout") root.splitShowLayout = !!value;
        else if (key === "splitShowAppTitle") root.splitShowAppTitle = !!value;
        else if (key === "splitShowDate") root.splitShowDate = !!value;
        else if (key === "splitShowMedia") root.splitShowMedia = !!value;
        else if (key === "splitShowWeather") root.splitShowWeather = !!value;
        else if (key === "splitShowSystem") root.splitShowSystem = !!value;
        else if (key === "splitShowNetSpeed") root.splitShowNetSpeed = !!value;
        else if (key === "splitShowVolume") root.splitShowVolume = !!value;
        else if (key === "splitShowKbLayout") root.splitShowKbLayout = !!value;
        else if (key === "splitShowBattery") root.splitShowBattery = !!value;
        else if (key === "splitShowTray") root.splitShowTray = !!value;
        else if (key === "splitShowStore") root.splitShowStore = !!value;
        else if (key === "splitShowFiles") root.splitShowFiles = !!value;
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
        else if (key === "barShowNetSpeed") root.barShowNetSpeed = !!value;
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

    function resetIsland(): void {
        _runResetCmd("reset-island");
    }

    function resetSequoia(): void {
        _runResetCmd("reset-sequoia");
    }

    function resetSplit(): void {
        _runResetCmd("reset-split");
    }

    function menuGlyphFor(iconId: string): string {
        if (iconId === "apple") return "󰀵";
        if (iconId === "cachyos") return "󰣇";
        if (iconId === "arch") return "󰣇";
        if (iconId === "fedora") return "󰣛";
        if (iconId === "gentoo") return "󰣨";
        if (iconId === "minimal") return "󰘔";
        return "󰀻";
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

    function setHubUiStyle(style: string): void {
        if (style !== "cupertino" && style !== "stage" && style !== "cockpit" && style !== "bento")
            return;
        root.hubUiStyle = style;
        setPref("hubUiStyle", style);
    }

    function cycleHubUiStyle(): void {
        const order = ["cupertino", "stage", "cockpit", "bento"];
        const idx = order.indexOf(root.hubUiStyle);
        setHubUiStyle(order[(idx + 1) % order.length]);
    }

    function setBarUiStyle(style: string): void {
        if (style !== "apple" && style !== "split" && style !== "menubar" && style !== "classic")
            return;
        root.barUiStyle = style;
        setPref("barUiStyle", style);
    }

    function cycleBarUiStyle(): void {
        const order = ["apple", "split", "menubar", "classic"];
        const idx = order.indexOf(root.barUiStyle);
        setBarUiStyle(order[(idx + 1) % order.length]);
    }

    function setSequoiaHubStyle(style: string): void {
        if (style !== "controlcenter" && style !== "compact" && style !== "media")
            return;
        root.sequoiaHubStyle = style;
        setPref("sequoiaHubStyle", style);
    }

    function cycleSequoiaHubStyle(): void {
        const order = ["controlcenter", "compact", "media"];
        const idx = order.indexOf(root.sequoiaHubStyle);
        setSequoiaHubStyle(order[(idx + 1) % order.length]);
    }

    function setSplitHubStyle(style: string): void {
        if (style !== "controlcenter" && style !== "compact" && style !== "media")
            return;
        root.splitHubStyle = style;
        setPref("splitHubStyle", style);
    }

    function cycleSplitHubStyle(): void {
        const order = ["controlcenter", "compact", "media"];
        const idx = order.indexOf(root.splitHubStyle);
        setSplitHubStyle(order[(idx + 1) % order.length]);
    }

    function applySplitPreset(preset: string): void {
        let map = null;
        if (preset === "minimal") {
            map = {
                barUiStyle: "split",
                splitBarHeight: 30,
                splitTopMargin: 6,
                splitPodStyle: "pill",
                splitBarTranslucent: true,
                splitShowLauncherIcon: true,
                splitShowWorkspaces: true,
                splitShowLayout: false,
                splitShowAppTitle: false,
                splitShowDate: false,
                splitShowMedia: true,
                splitShowWeather: false,
                splitShowSystem: false,
                splitShowNetSpeed: false,
                splitShowVolume: true,
                splitShowKbLayout: false,
                splitShowBattery: true,
                splitShowTray: false,
                splitShowStore: false,
                splitShowFiles: false
            };
        } else if (preset === "balanced") {
            map = {
                barUiStyle: "split",
                splitBarHeight: 32,
                splitTopMargin: 6,
                splitPodStyle: "pill",
                splitBarTranslucent: true,
                splitShowLauncherIcon: true,
                splitShowWorkspaces: true,
                splitShowLayout: true,
                splitShowAppTitle: true,
                splitShowDate: true,
                splitShowMedia: true,
                splitShowWeather: true,
                splitShowSystem: false,
                splitShowNetSpeed: false,
                splitShowVolume: true,
                splitShowKbLayout: true,
                splitShowBattery: true,
                splitShowTray: true,
                splitShowStore: true,
                splitShowFiles: true
            };
        } else if (preset === "creator") {
            map = {
                barUiStyle: "split",
                splitBarHeight: 32,
                splitTopMargin: 6,
                splitPodStyle: "rounded",
                splitBarTranslucent: true,
                splitShowLauncherIcon: true,
                splitShowWorkspaces: true,
                splitShowLayout: true,
                splitShowAppTitle: true,
                splitShowDate: true,
                splitShowMedia: true,
                splitShowWeather: true,
                splitShowSystem: true,
                splitShowNetSpeed: true,
                splitShowVolume: true,
                splitShowKbLayout: true,
                splitShowBattery: true,
                splitShowTray: true,
                splitShowStore: true,
                splitShowFiles: true
            };
        }
        if (map)
            setPrefsBatch(map);
    }

    function applySequoiaPreset(preset: string): void {
        let map = null;
        if (preset === "macos") {
            map = {
                barUiStyle: "menubar",
                sequoiaBarHeight: 28,
                sequoiaBarFloating: false,
                sequoiaBarTranslucent: true,
                sequoiaShowAppTitle: true,
                sequoiaShowWorkspaces: true,
                sequoiaShowLayout: false,
                sequoiaShowMedia: true,
                sequoiaShowSystem: false,
                sequoiaShowNetSpeed: false,
                sequoiaShowVolume: true,
                sequoiaShowBattery: true,
                sequoiaShowTray: true,
                sequoiaShowStore: true,
                sequoiaShowSpotlightIcon: true,
                sequoiaShowDate: true
            };
        } else if (preset === "minimal") {
            map = {
                barUiStyle: "menubar",
                sequoiaBarHeight: 26,
                sequoiaBarFloating: false,
                sequoiaBarTranslucent: true,
                sequoiaShowAppTitle: true,
                sequoiaShowWorkspaces: false,
                sequoiaShowLayout: false,
                sequoiaShowMedia: false,
                sequoiaShowSystem: false,
                sequoiaShowNetSpeed: false,
                sequoiaShowVolume: true,
                sequoiaShowBattery: true,
                sequoiaShowTray: false,
                sequoiaShowStore: false,
                sequoiaShowSpotlightIcon: true,
                sequoiaShowDate: true
            };
        } else if (preset === "developer") {
            map = {
                barUiStyle: "menubar",
                sequoiaBarHeight: 28,
                sequoiaBarFloating: false,
                sequoiaBarTranslucent: true,
                sequoiaShowAppTitle: true,
                sequoiaShowWorkspaces: true,
                sequoiaShowLayout: true,
                sequoiaShowMedia: true,
                sequoiaShowSystem: true,
                sequoiaShowNetSpeed: true,
                sequoiaShowVolume: true,
                sequoiaShowBattery: true,
                sequoiaShowTray: true,
                sequoiaShowStore: true,
                sequoiaShowSpotlightIcon: true,
                sequoiaShowDate: true
            };
        }
        if (map)
            setPrefsBatch(map);
    }

    function applyBarPreset(preset: string): void {
        const nextBarStyle = (root.barUiStyle === "split" || root.barUiStyle === "menubar")
            ? "apple"
            : root.barUiStyle;
        let map = null;
        if (preset === "minimal") {
            map = {
                barUiStyle: nextBarStyle,
                islandStyle: "pill",
                barShowDate: false,
                barShowWindow: false,
                barShowWorkspaces: false,
                barShowLayout: false,
                barShowSystem: false,
                barShowNetSpeed: false,
                barShowVolume: false,
                barShowKbLayout: false,
                barShowTray: false,
                barShowQuickIcons: false,
                barShowFiles: false,
                pillShowMedia: true
            };
        } else if (preset === "balanced") {
            map = {
                barUiStyle: nextBarStyle,
                islandStyle: "pill",
                barShowDate: true,
                barShowWindow: true,
                barShowWorkspaces: true,
                barShowLayout: false,
                barShowSystem: false,
                barShowNetSpeed: false,
                barShowVolume: false,
                barShowKbLayout: false,
                barShowTray: false,
                barShowQuickIcons: false,
                barShowFiles: true,
                pillShowMedia: true
            };
        } else if (preset === "full") {
            map = {
                barUiStyle: "classic",
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

    function setMonoFont(family: string, size: int): void {
        const cleanFam = (family || "").trim();
        const clampedSize = Math.max(8, Math.min(18, size));
        if (cleanFam.length === 0)
            return;
        root.monoFontFamily = cleanFam;
        root.uiFontSize = clampedSize;
        Quickshell.execDetached([
            Quickshell.shellPath("scripts/manage-settings.sh"),
            "set-mono-font", cleanFam, String(clampedSize)
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

    function markAllNotificationsRead(): void {
        clearUnread();
    }

    function clearNotifications(): void {
        clearHistory();
    }

    function removeNotification(uid: int): void {
        dismissNotification(uid);
    }

    function formatTimer(sec: int): string {
        const s = Math.max(0, Math.round(sec));
        const hrs = Math.floor(s / 3600);
        const mins = Math.floor((s % 3600) / 60);
        const rem = s % 60;
        const mm = (mins < 10 && hrs > 0 ? "0" : (mins < 10 ? "0" : "")) + mins;
        const ss = (rem < 10 ? "0" : "") + rem;
        return hrs > 0 ? (hrs + ":" + mm + ":" + ss) : (mm + ":" + ss);
    }

    function startTimer(): void {
        if (root.timerRemainingSec <= 0)
            root.timerRemainingSec = root.timerDurationSec;
        root.timerActive = true;
    }

    function pauseTimer(): void {
        root.timerActive = false;
    }

    function toggleTimer(): void {
        if (root.timerActive)
            pauseTimer();
        else
            startTimer();
    }

    function resetTimer(seconds: int): void {
        const clamped = Math.max(60, Math.min(7200, seconds));
        root.timerActive = false;
        root.timerDurationSec = clamped;
        root.timerRemainingSec = clamped;
    }

    function syncRecordingState(): void {
        if (!recStatusProc.running)
            recStatusProc.running = true;
    }

    function toggleStopwatch(): void {
        root.stopwatchActive = !root.stopwatchActive;
    }

    function resetStopwatch(): void {
        root.stopwatchActive = false;
        root.stopwatchElapsedSec = 0;
        root.stopwatchLaps = [];
    }

    function addStopwatchLap(): void {
        const lapStr = formatTimer(root.stopwatchElapsedSec);
        const list = (root.stopwatchLaps || []).slice(0, 7);
        root.stopwatchLaps = [lapStr].concat(list);
    }

    function refreshWeather(force: bool): void {
        if (!root.weatherEnabled) {
            root.weatherAvailable = false;
            return;
        }
        if (weatherProc.running)
            return;
        weatherProc.command = force
            ? [Quickshell.shellPath("scripts/fetch-weather.sh"), "--force"]
            : [Quickshell.shellPath("scripts/fetch-weather.sh")];
        weatherProc.running = true;
    }

    function toggleGameMode(): void {
        if (!root.gameModeActive) {
            root._preGameShellMode = root._observedShellMode || "default";
            root._preGameDnd = root.dnd;
            root._preGameKeepAwake = root.keepAwake;
            root.gameModeActive = true;
            setPrefsBatch({ dnd: true, keepAwake: true });
            Quickshell.execDetached([Quickshell.shellPath("scripts/apply-mode.sh"), "simple"]);
            Quickshell.execDetached([
                "sh", "-c",
                "command -v notify-send >/dev/null 2>&1 && notify-send -a 'Game Mode' 'Game Mode Enabled' 'Simple bar active, DND & Keep Awake enabled.' -t 2500"
            ]);
        } else {
            root.gameModeActive = false;
            setPrefsBatch({ dnd: root._preGameDnd, keepAwake: root._preGameKeepAwake });
            Quickshell.execDetached([Quickshell.shellPath("scripts/apply-mode.sh"), root._preGameShellMode || "default"]);
            Quickshell.execDetached([
                "sh", "-c",
                "command -v notify-send >/dev/null 2>&1 && notify-send -a 'Game Mode' 'Game Mode Disabled' 'Restored previous visual mode and preferences.' -t 2500"
            ]);
        }
    }

    Timer {
        id: stopwatchTickTimer
        interval: 1000
        repeat: true
        running: root.stopwatchActive
        onTriggered: root.stopwatchElapsedSec += 1
    }

    Timer {
        id: weatherPollTimer
        interval: 1800000
        repeat: true
        running: root.weatherEnabled
        triggeredOnStart: true
        onTriggered: root.refreshWeather(false)
    }

    Timer {
        id: slideshowTimer
        interval: Math.max(1, root.wallpaperSlideshowMinutes) * 60000
        repeat: true
        running: root.wallpaperSlideshowEnabled && !root.gameModeActive
        onTriggered: Quickshell.execDetached([Quickshell.shellPath("scripts/manage-themes.sh"), "random-wallpaper"])
    }

    Process {
        id: weatherProc
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0)
                    return;
                try {
                    const d = JSON.parse(raw);
                    root.weatherAvailable = !!d.available;
                    if (root.weatherAvailable) {
                        root.weatherTemp = String(d.temp || "");
                        root.weatherFeelsLike = String(d.feelsLike || "");
                        root.weatherCondition = String(d.condition || "");
                        root.weatherHumidity = String(d.humidity || "");
                        root.weatherWind = String(d.wind || "");
                        root.weatherCity = String(d.location || "");
                        root.weatherIcon = String(d.icon || "󰖐");
                        root.weatherUpdated = String(d.updated || "");
                    }
                } catch (err) {}
            }
        }
    }

    FileView {
        id: observedModeFile
        path: Quickshell.shellPath("shell-mode.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d && d.mode)
                    root._observedShellMode = String(d.mode);
            } catch (err) {}
        }
    }

    Timer {
        id: focusCountdownTimer
        interval: 1000
        repeat: true
        running: root.timerActive
        onTriggered: {
            if (root.timerRemainingSec > 1) {
                root.timerRemainingSec -= 1;
            } else {
                root.timerActive = false;
                root.timerRemainingSec = root.timerDurationSec;
                Quickshell.execDetached([
                    "sh", "-c",
                    "command -v notify-send >/dev/null 2>&1 && notify-send -a 'Focus Timer' 'Focus Session Complete' 'Time is up. Take a short break.' -t 6000"
                ]);
            }
        }
    }

    Timer {
        id: recordingElapsedTimer
        interval: 1000
        repeat: true
        running: root.recordingActive
        onTriggered: {
            if (root._recordingStartedAt > 0) {
                const nowSec = Math.floor(Date.now() / 1000);
                root.recordingElapsedSec = Math.max(0, nowSec - root._recordingStartedAt);
            } else {
                root.recordingElapsedSec += 1;
            }
        }
    }

    Process {
        id: recStatusProc
        command: [Quickshell.shellPath("scripts/record-screen.sh"), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.recordingActive = false;
                    root.recordingElapsedSec = 0;
                    root._recordingStartedAt = 0;
                    return;
                }
                try {
                    const d = JSON.parse(raw);
                    root.recordingActive = !!d.active;
                    const startedAt = Number(d.startedAt || 0);
                    root._recordingStartedAt = startedAt;
                    if (root.recordingActive && startedAt > 0) {
                        const nowSec = Math.floor(Date.now() / 1000);
                        root.recordingElapsedSec = Math.max(0, nowSec - startedAt);
                    } else if (!root.recordingActive) {
                        root.recordingElapsedSec = 0;
                    }
                } catch (err) {
                    root.recordingActive = false;
                }
            }
        }
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
        syncRecordingState();
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
