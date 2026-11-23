pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".."

ColumnLayout {
    id: root

    property bool active: false
    property string initialMode: "apps"
    property string activeMode: "apps"        // "apps" | "clip" | "calc" | "cmds" | "emoji"
    property int selectedIndex: 0
    property string query: ""
    property var clipboardItems: []
    property bool clipboardLoading: false

    property var hiddenConfig: ({
        hiddenIds: [
            "foot-server", "footclient",
            "assistant", "designer", "linguist", "qdbusviewer",
            "libfm-pref-apps", "pcmanfm-desktop-pref", "lxshortcut",
            "cups", "rofi", "rofi-theme-selector",
            "gtk3-demo", "gtk4-demo", "gtk3-widget-factory", "gtk4-widget-factory",
            "gtk3-icon-browser", "gtk4-icon-browser",
            "org.gtk.Demo4", "org.gtk.IconBrowser4", "org.gtk.WidgetFactory4",
            "xdg-desktop-portal-gtk",
            "avahi-discover", "bssh", "bvnc", "qv4l2", "qvidcap"
        ],
        hiddenNamePrefixes: ["qt ", "gtk"]
    })

    signal searchFocusChanged(bool focused)
    signal closeRequested()
    signal openSettingsRequested(string page)
    signal openFilesRequested(string path)
    signal openKeybindsRequested()

    spacing: 8

    readonly property string effectiveMode: {
        const raw = root.query || "";
        const trimmed = raw.replace(/^\s+/, "");
        if (trimmed.startsWith("="))
            return "calc";
        if (trimmed.startsWith(">"))
            return "cmds";
        if (trimmed.startsWith(":"))
            return "emoji";
        if (trimmed.toLowerCase().startsWith("cb "))
            return "clip";
        return root.activeMode;
    }

    readonly property string cleanQuery: {
        const trimmed = (root.query || "").replace(/^\s+/, "");
        if (trimmed.startsWith("=") || trimmed.startsWith(">") || trimmed.startsWith(":"))
            return trimmed.slice(1).trim();
        if (trimmed.toLowerCase().startsWith("cb "))
            return trimmed.slice(3).trim();
        return trimmed.trim();
    }

    function openInMode(modeName: string): void {
        const valid = (modeName === "clip" || modeName === "calc" || modeName === "cmds" || modeName === "emoji")
            ? modeName
            : "apps";
        root.activeMode = valid;
        searchInput.text = "";
        root.query = "";
        root.selectedIndex = 0;
        if (valid === "clip")
            refreshClipboard();
        if (root.active)
            focusTimer.restart();
    }

    onInitialModeChanged: {
        if (root.active)
            openInMode(root.initialMode);
    }

    onEffectiveModeChanged: {
        root.selectedIndex = 0;
        if (root.effectiveMode === "clip")
            refreshClipboard();
    }

    onActiveChanged: {
        if (active) {
            openInMode(root.initialMode || "apps");
        } else {
            searchInput.focus = false;
        }
    }

    Component.onCompleted: {
        if (active)
            openInMode(root.initialMode || "apps");
    }

    Timer {
        id: focusTimer
        interval: 30
        repeat: false
        onTriggered: {
            if (root.active)
                searchInput.forceActiveFocus();
        }
    }

    function copyPlainText(txt: string): void {
        if (!txt || txt.length === 0)
            return;
        Quickshell.clipboardText = txt;
        if (DeviceCaps.hasClipboard) {
            Quickshell.execDetached([
                "sh", "-c", "printf '%s' \"$1\" | wl-copy -n --type text/plain", "_", txt
            ]);
        }
    }

    function refreshClipboard(): void {
        if (clipProc.running)
            return;
        root.clipboardLoading = true;
        clipProc.command = [Quickshell.shellPath("scripts/manage-clipboard.sh"), "list"];
        clipProc.running = true;
    }

    function runClipboardAction(action: string, itemId: int): void {
        if (action === "copy") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/manage-clipboard.sh"), "copy", String(itemId)]);
            root.closeRequested();
            return;
        }
        if (clipProc.running)
            return;
        if (action === "clear") {
            clipProc.command = [Quickshell.shellPath("scripts/manage-clipboard.sh"), "clear"];
        } else {
            clipProc.command = [Quickshell.shellPath("scripts/manage-clipboard.sh"), action, String(itemId)];
        }
        clipProc.running = true;
    }

    Process {
        id: clipProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.clipboardLoading = false;
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.clipboardItems = [];
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    root.clipboardItems = Array.isArray(parsed) ? parsed : [];
                } catch (err) {
                    root.clipboardItems = [];
                }
            }
        }
        onExited: root.clipboardLoading = false
    }

    FileView {
        id: hiddenAppsFile
        path: Quickshell.shellPath("hidden-apps.json")
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: root.parseHiddenConfig(text())
    }

    Timer {
        id: hiddenConfigRetryTimer
        interval: 60
        repeat: false
        onTriggered: hiddenAppsFile.reload()
    }

    function parseHiddenConfig(raw: string): void {
        if (!raw || raw.trim().length === 0)
            return;
        try {
            const parsed = JSON.parse(raw);
            const ids = Array.isArray(parsed.hiddenIds) ? parsed.hiddenIds : root.hiddenConfig.hiddenIds;
            const prefixes = Array.isArray(parsed.hiddenNamePrefixes) ? parsed.hiddenNamePrefixes : root.hiddenConfig.hiddenNamePrefixes;
            root.hiddenConfig = { hiddenIds: ids, hiddenNamePrefixes: prefixes };
        } catch (err) {
            hiddenConfigRetryTimer.restart();
        }
    }

    function isAppHidden(app: var): bool {
        if (!app || app.noDisplay)
            return true;

        const idLower = (app.id || "").replace(/\.desktop$/i, "").toLowerCase();
        const nameLower = (app.name || "").trim().toLowerCase();
        const cfg = root.hiddenConfig;

        if (cfg && Array.isArray(cfg.hiddenIds)) {
            for (let i = 0; i < cfg.hiddenIds.length; i++) {
                const hid = String(cfg.hiddenIds[i] || "").replace(/\.desktop$/i, "").toLowerCase();
                if (hid.length > 0 && idLower === hid)
                    return true;
            }
        }

        if (cfg && Array.isArray(cfg.hiddenNamePrefixes)) {
            for (let i = 0; i < cfg.hiddenNamePrefixes.length; i++) {
                const prefix = String(cfg.hiddenNamePrefixes[i] || "").toLowerCase();
                if (prefix.length > 0 && (nameLower.startsWith(prefix) || idLower.startsWith(prefix)))
                    return true;
            }
        }

        const cats = app.categories;
        if (cats && cats.length > 0) {
            let hasQt = false;
            let hasQtTool = false;
            for (let k = 0; k < cats.length; k++) {
                const c = cats[k];
                if (c === "X-LXDE-Settings")
                    return true;
                if (c === "Qt")
                    hasQt = true;
                else if (c === "Documentation" || c === "Debugger" || c === "GUIDesigner" || c === "Translation")
                    hasQtTool = true;
            }
            if (hasQt && hasQtTool)
                return true;
        }

        return false;
    }

    function fuzzyScore(hay: string, needle: string): int {
        if (!needle || needle.length === 0)
            return 1;
        if (!hay || hay.length === 0)
            return 0;

        if (hay === needle)
            return 1000;
        if (hay.startsWith(needle))
            return 800 - hay.length;

        const idx = hay.indexOf(needle);
        if (idx !== -1)
            return 500 - idx;

        let qi = 0;
        let gaps = 0;
        for (let hi = 0; hi < hay.length && qi < needle.length; hi++) {
            if (hay[hi] === needle[qi])
                qi++;
            else if (qi > 0)
                gaps++;
        }
        return (qi === needle.length) ? Math.max(10, 250 - gaps) : 0;
    }

    // --- Apps Model ---
    readonly property var visibleApps: {
        const all = DesktopEntries.applications.values;
        if (!all)
            return [];
        const items = [];
        for (let i = 0; i < all.length; i++) {
            const app = all[i];
            if (root.isAppHidden(app))
                continue;
            const kwText = app.keywords ? app.keywords.join(" ") : "";
            items.push({
                entry: app,
                nameL: (app.name || "").toLowerCase(),
                genericL: (app.genericName || "").toLowerCase(),
                commentL: (app.comment || "").toLowerCase(),
                kwL: kwText.toLowerCase()
            });
        }
        items.sort((a, b) => a.nameL.localeCompare(b.nameL));
        return items;
    }

    readonly property var filteredApps: {
        if (root.effectiveMode !== "apps")
            return [];
        const list = root.visibleApps;
        const q = root.cleanQuery.toLowerCase();
        if (q.length === 0) {
            const plain = [];
            for (let k = 0; k < Math.min(60, list.length); k++)
                plain.push(list[k].entry);
            return plain;
        }

        const scored = [];
        for (let i = 0; i < list.length; i++) {
            const item = list[i];
            const nameScore = fuzzyScore(item.nameL, q) * 3;
            const genericScore = fuzzyScore(item.genericL, q) * 2;
            const commentScore = fuzzyScore(item.commentL, q);
            const kwScore = fuzzyScore(item.kwL, q);
            const best = Math.max(nameScore, genericScore, commentScore, kwScore);
            if (best > 0)
                scored.push({ entry: item.entry, score: best });
        }

        scored.sort((a, b) => {
            if (b.score !== a.score)
                return b.score - a.score;
            return (a.entry.name || "").localeCompare(b.entry.name || "");
        });

        const out = [];
        for (let j = 0; j < Math.min(60, scored.length); j++)
            out.push(scored[j].entry);
        return out;
    }

    // --- Clipboard Model ---
    readonly property var filteredClipboard: {
        if (root.effectiveMode !== "clip")
            return [];
        const q = root.cleanQuery.toLowerCase();
        const items = root.clipboardItems || [];
        if (q.length === 0)
            return items;
        return items.filter(it => String(it.text || "").toLowerCase().indexOf(q) !== -1);
    }

    // --- Safe Calculator Evaluation ---
    function evalExpression(rawExpr: string): var {
        const s = (rawExpr || "").trim();
        if (s.length === 0 || s.length > 160)
            return [];
        try {
            let expr = s.replace(/\^/g, "**");
            expr = expr.replace(/\bpi\b/gi, "Math.PI");
            expr = expr.replace(/\be\b/gi, "Math.E");
            expr = expr.replace(/\b(sqrt|cbrt|sin|cos|tan|abs|round|floor|ceil|log|log10|exp|min|max|pow)\b/gi, (_, fn) => "Math." + fn.toLowerCase());
            const stripped = expr.replace(/Math\.(?:PI|E|sqrt|cbrt|sin|cos|tan|abs|round|floor|ceil|log10|log|exp|min|max|pow)/g, "");
            if (!/^[0-9a-fA-FxXbBoO+\-*/%().,\s&|~<>]*$/.test(stripped))
                return [];
            const fn = new Function("\"use strict\"; return (" + expr + ");");
            const val = fn();
            if (typeof val !== "number" || !isFinite(val) || isNaN(val))
                return [];
            const rounded = Math.abs(val - Math.round(val)) < 1e-12
                ? String(Math.round(val))
                : Number(val.toPrecision(12)).toString();
            const cards = [{
                title: rounded,
                sub: "Result · Enter to copy",
                copyVal: rounded,
                icon: "󰪚"
            }];
            if (Math.abs(val - Math.round(val)) < 1e-9 && Math.abs(val) <= 0x7FFFFFFF) {
                const iv = Math.round(val);
                const hexStr = (iv < 0 ? "-0x" + Math.abs(iv).toString(16) : "0x" + iv.toString(16)).toUpperCase().replace("0X", "0x");
                cards.push({
                    title: hexStr,
                    sub: "Hexadecimal",
                    copyVal: hexStr,
                    icon: "󰅪"
                });
                const binStr = "0b" + (iv >>> 0).toString(2);
                cards.push({
                    title: binStr,
                    sub: "Binary (32-bit)",
                    copyVal: binStr,
                    icon: "󰌋"
                });
            }
            return cards;
        } catch (err) {
            return [];
        }
    }

    readonly property var calcResults: {
        if (root.effectiveMode !== "calc")
            return [];
        return evalExpression(root.cleanQuery);
    }

    // --- Quick Shell Commands Model ---
    readonly property var allCommands: [
        { id: "lock",        title: "Lock Screen",                  sub: "Lock current Wayland session",       icon: "󰌾", kw: "lock screen security" },
        { id: "dark-light",  title: "Toggle Dark / Light Scheme",   sub: "Switch Material theme polarity",     icon: "󰔎", kw: "theme dark light polarity" },
        { id: "rand-wp",     title: "Random Wallpaper & Theme",     sub: "Pick random wallpaper and re-theme", icon: "󰸉", kw: "wallpaper random matugen" },
        { id: "mode-cycle",  title: "Cycle Visual Mode",            sub: "Step through all 7 visual styles", icon: "󰚗", kw: "mode cycle switch visual style" },
        { id: "mode-default",title: "Visual Mode: Island (Default)",sub: "Balanced Dynamic Island & shadows", icon: "󰕮", kw: "mode default island" },
        { id: "mode-blur",   title: "Visual Mode: Frosted Glass",   sub: "visionOS frosted aero glass + blur", icon: "󰂵", kw: "mode blur glass frosted" },
        { id: "mode-neon",   title: "Visual Mode: Cyber Neon",      sub: "Obsidian HUD + glowing neon rim",    icon: "󱐋", kw: "mode cyber neon hud" },
        { id: "mode-minimal",title: "Visual Mode: Zen Matte",       sub: "Calm matte surfaces & wide gaps",    icon: "󰋑", kw: "mode minimal zen matte" },
        { id: "mode-retro",  title: "Visual Mode: Tactile Brutalist",sub: "Bold borders & 4px hardware chamfer",icon: "󰚗", kw: "mode retro tactile brutalist" },
        { id: "mode-oled",   title: "Visual Mode: Obsidian OLED",   sub: "True #000 pitch black + thin rim",   icon: "󰖔", kw: "mode oled pitch obsidian" },
        { id: "mode-simple", title: "Visual Mode: Simple Bar",      sub: "Crisp 28px square top bar",          icon: "󰘔", kw: "mode simple bar square" },
        { id: "vibe-aurora", title: "Vibe: Aurora Glass",           sub: "Blur + Catppuccin Mocha glass",      icon: "󰏘", kw: "vibe aurora glass" },
        { id: "vibe-oled",   title: "Vibe: OLED Stealth",           sub: "Pitch black notch layout",           icon: "󰽥", kw: "vibe oled stealth dark" },
        { id: "vibe-neon",   title: "Vibe: Neon Cyber",             sub: "Glowing cyberpunk blur theme",       icon: "󱐋", kw: "vibe neon cyberpunk" },
        { id: "dnd",         title: "Toggle Do Not Disturb",        sub: "Silence desktop banners & sounds",   icon: "󰂛", kw: "dnd notifications silence" },
        { id: "awake",       title: "Toggle Keep Awake",            sub: "Inhibit screen idle & auto-lock",    icon: "󰅶", kw: "caffeine awake idle inhibit" },
        { id: "shot-area",   title: "Screenshot: Area Selection",   sub: "Select region with slurp",           icon: "󰹑", kw: "screenshot capture area" },
        { id: "shot-win",    title: "Screenshot: Focused Window",   sub: "Capture active window geometry",     icon: "󰖯", kw: "screenshot window capture" },
        { id: "shot-full",   title: "Screenshot: Fullscreen",       sub: "Capture entire display",             icon: "󰍹", kw: "screenshot full screen" },
        { id: "color-pick",  title: "Color Picker (Eyedropper)",    sub: "Pick pixel #RRGGBB to clipboard",    icon: "󰈊", kw: "color picker eyedropper hex" },
        { id: "record-area", title: "Toggle Screen Recording",      sub: "Start/stop wf-recorder capture",     icon: "󰑊", kw: "record screen video mp4" },
        { id: "keybinds",    title: "Keybind Cheat Sheet",          sub: "Show all MangoWC & shell shortcuts", icon: "󰌌", kw: "keybinds shortcuts help" },
        { id: "win-switch",  title: "Window Switcher",              sub: "Jump to or close any open window",   icon: "󰖯", kw: "windows switcher focus alt tab" },
        { id: "power-menu",  title: "Power & Session Overlay",      sub: "Lock, suspend, hibernate, reboot",   icon: "󰐥", kw: "power shutdown reboot suspend logout" },
        { id: "game-mode",   title: "Toggle Game Mode",             sub: "Simple bar + DND + Keep Awake",      icon: "󰊴", kw: "game mode performance dnd" },
        { id: "sync-sddm",   title: "Sync SDDM Login Theme",        sub: "Push palette & wallpaper to SDDM",   icon: "󰍹", kw: "sddm login greeter sync theme" },
        { id: "refresh-wx",  title: "Refresh Weather Forecast",     sub: "Fetch latest conditions (wttr.in)",  icon: "󰖐", kw: "weather forecast temp refresh" },
        { id: "files",       title: "Open Dynamic File Manager",    sub: "Launch Rust-backed mango-fm",        icon: "󰉋", kw: "files manager explorer" },
        { id: "settings",    title: "Open Desktop Settings",        sub: "16-page configuration studio",       icon: "󰒓", kw: "settings preferences config" },
        { id: "reload-wm",   title: "Reload MangoWC Config",        sub: "mmsg dispatch reload_config",        icon: "󰑐", kw: "reload mango config wm" }
    ]

    readonly property var filteredCommands: {
        if (root.effectiveMode !== "cmds")
            return [];
        const q = root.cleanQuery.toLowerCase();
        if (q.length === 0)
            return root.allCommands;
        const scored = [];
        for (let i = 0; i < root.allCommands.length; i++) {
            const c = root.allCommands[i];
            const hay = (c.title + " " + c.sub + " " + c.kw).toLowerCase();
            const s = fuzzyScore(hay, q);
            if (s > 0)
                scored.push({ cmd: c, score: s });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.map(x => x.cmd);
    }

    // --- Emoji & Nerd Font Glyph Model ---
    readonly property var allEmojis: [
        { g: "🚀", n: "rocket launch ship deploy" },
        { g: "🔥", n: "fire flame hot lit" },
        { g: "✨", n: "sparkles magic shine stars" },
        { g: "🎉", n: "party tada celebrate" },
        { g: "❤️", n: "heart love red" },
        { g: "👍", n: "thumbs up approve ok yes" },
        { g: "👎", n: "thumbs down dislike no" },
        { g: "👀", n: "eyes look watch see" },
        { g: "🤔", n: "thinking hmm ponder" },
        { g: "😄", n: "smile happy grin" },
        { g: "😂", n: "laugh joy tears funny" },
        { g: "🥳", n: "party celebrate hat" },
        { g: "😎", n: "cool sunglasses" },
        { g: "😭", n: "cry sad sob" },
        { g: "🙏", n: "please thanks pray" },
        { g: "💯", n: "100 percent perfect" },
        { g: "✅", n: "check done pass green" },
        { g: "❌", n: "cross fail error x" },
        { g: "⚠️", n: "warning alert caution" },
        { g: "💡", n: "idea bulb tip light" },
        { g: "📌", n: "pin pushpin note" },
        { g: "📝", n: "memo note edit write" },
        { g: "🔒", n: "lock secure password" },
        { g: "🔑", n: "key auth access" },
        { g: "🛠️", n: "tools wrench hammer build" },
        { g: "⚙️", n: "gear settings config" },
        { g: "💻", n: "laptop computer dev code" },
        { g: "🐧", n: "linux penguin tux" },
        { g: "🦀", n: "rust crab ferris" },
        { g: "🐍", n: "python snake" },
        { g: "📁", n: "folder directory files" },
        { g: "📦", n: "package box archive" },
        { g: "🎨", n: "palette art theme color" },
        { g: "🎵", n: "music note audio song" },
        { g: "📷", n: "camera photo screenshot" },
        { g: "🎥", n: "video record movie" },
        { g: "📅", n: "calendar date schedule" },
        { g: "⏰", n: "alarm clock timer" },
        { g: "⚡", n: "lightning bolt fast power" },
        { g: "🌙", n: "moon night dark" },
        { g: "☀️", n: "sun light day" },
        { g: "🌊", n: "wave ocean water" },
        { g: "☕", n: "coffee tea awake" },
        { g: "🍕", n: "pizza food" },
        { g: "🎯", n: "target bullseye goal" },
        { g: "🧠", n: "brain smart ai think" },
        { g: "󰀻", n: "nerd apps grid launcher" },
        { g: "󰌾", n: "nerd lock padlock" },
        { g: "󰒓", n: "nerd settings gear" },
        { g: "󰉋", n: "nerd folder files" },
        { g: "󰏘", n: "nerd palette theme" },
        { g: "󰂚", n: "nerd bell notification" },
        { g: "󰍛", n: "nerd cpu chip" },
        { g: "󰘚", n: "nerd ram memory" },
        { g: "󰖩", n: "nerd wifi network" },
        { g: "󰂯", n: "nerd bluetooth" },
        { g: "󰎈", n: "nerd music note" },
        { g: "󰹑", n: "nerd screenshot camera" },
        { g: "󰑊", n: "nerd record circle" },
        { g: "󰅌", n: "nerd clipboard paste" },
        { g: "󰌌", n: "nerd keyboard shortcut" },
        { g: "󰐥", n: "nerd power shutdown" }
    ]

    readonly property var filteredEmojis: {
        if (root.effectiveMode !== "emoji")
            return [];
        const q = root.cleanQuery.toLowerCase();
        if (q.length === 0)
            return root.allEmojis;
        return root.allEmojis.filter(e => e.n.indexOf(q) !== -1 || e.g === q);
    }

    readonly property int currentCount: {
        if (root.effectiveMode === "apps") return root.filteredApps.length;
        if (root.effectiveMode === "clip") return root.filteredClipboard.length;
        if (root.effectiveMode === "calc") return root.calcResults.length;
        if (root.effectiveMode === "cmds") return root.filteredCommands.length;
        return root.filteredEmojis.length;
    }

    onCurrentCountChanged: {
        if (root.selectedIndex >= root.currentCount)
            root.selectedIndex = Math.max(0, root.currentCount - 1);
    }

    function moveSelection(delta: int): void {
        const count = root.currentCount;
        if (count === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + count) % count;
        if (root.effectiveMode === "apps") appList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else if (root.effectiveMode === "clip") clipList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else if (root.effectiveMode === "cmds") cmdsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        else if (root.effectiveMode === "emoji") emojiGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
    }

    function launchEntry(entry: var): void {
        if (!entry)
            return;
        if (entry.runInTerminal && entry.command && entry.command.length > 0) {
            Quickshell.execDetached([Quickshell.shellPath("scripts/launch-app.sh"), "terminal-exec"].concat(entry.command));
        } else {
            entry.execute();
        }
        root.closeRequested();
    }

    function runQuickCommand(cmdId: string): void {
        root.closeRequested();
        if (cmdId === "lock") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/lock.sh")]);
        } else if (cmdId === "dark-light") {
            Theme.toggleScheme();
        } else if (cmdId === "rand-wp") {
            Theme.randomWallpaper();
        } else if (cmdId === "mode-cycle") {
            Theme.cycleShellMode();
        } else if (cmdId === "mode-default") {
            Theme.setShellMode("default");
        } else if (cmdId === "mode-blur") {
            Theme.setShellMode("blur");
        } else if (cmdId === "mode-neon") {
            Theme.setShellMode("neon");
        } else if (cmdId === "mode-minimal") {
            Theme.setShellMode("minimal");
        } else if (cmdId === "mode-retro") {
            Theme.setShellMode("retro");
        } else if (cmdId === "mode-oled") {
            Theme.setShellMode("oled");
        } else if (cmdId === "mode-simple") {
            Theme.setShellMode("simple");
        } else if (cmdId === "vibe-aurora") {
            Theme.applyVibe("aurora-glass");
        } else if (cmdId === "vibe-oled") {
            Theme.applyVibe("oled-stealth");
        } else if (cmdId === "vibe-neon") {
            Theme.applyVibe("neon-cyber");
        } else if (cmdId === "dnd") {
            ShellState.toggleDnd();
        } else if (cmdId === "awake") {
            ShellState.toggleKeepAwake();
        } else if (cmdId === "shot-area") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--area"]);
        } else if (cmdId === "shot-win") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--window"]);
        } else if (cmdId === "shot-full") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--full"]);
        } else if (cmdId === "color-pick") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/screenshot.sh"), "--color"]);
        } else if (cmdId === "record-area") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/record-screen.sh"), "toggle", "--area"]);
        } else if (cmdId === "keybinds") {
            root.openKeybindsRequested();
        } else if (cmdId === "win-switch") {
            Quickshell.execDetached(["qs", "ipc", "call", "island", "toggleWindowSwitcher"]);
        } else if (cmdId === "power-menu") {
            Quickshell.execDetached(["qs", "ipc", "call", "island", "togglePowerOverlay"]);
        } else if (cmdId === "game-mode") {
            ShellState.toggleGameMode();
        } else if (cmdId === "sync-sddm") {
            Quickshell.execDetached([Quickshell.shellPath("scripts/sync-sddm-theme.sh")]);
        } else if (cmdId === "refresh-wx") {
            ShellState.refreshWeather(true);
        } else if (cmdId === "files") {
            root.openFilesRequested("");
        } else if (cmdId === "settings") {
            root.openSettingsRequested("appearance");
        } else if (cmdId === "reload-wm") {
            Quickshell.execDetached(["mmsg", "dispatch", "reload_config"]);
        }
    }

    function activateSelected(): void {
        const idx = root.selectedIndex;
        if (root.effectiveMode === "apps" && idx < root.filteredApps.length) {
            launchEntry(root.filteredApps[idx]);
        } else if (root.effectiveMode === "clip" && idx < root.filteredClipboard.length) {
            runClipboardAction("copy", root.filteredClipboard[idx].id);
        } else if (root.effectiveMode === "calc" && idx < root.calcResults.length) {
            copyPlainText(root.calcResults[idx].copyVal);
            root.closeRequested();
        } else if (root.effectiveMode === "cmds" && idx < root.filteredCommands.length) {
            runQuickCommand(root.filteredCommands[idx].id);
        } else if (root.effectiveMode === "emoji" && idx < root.filteredEmojis.length) {
            copyPlainText(root.filteredEmojis[idx].g);
            root.closeRequested();
        }
    }

    // --- Mode Selector Pills ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            implicitHeight: 28
            implicitWidth: modePillRow.implicitWidth + 6
            radius: Theme.r(14)
            color: Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: modePillRow
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: [
                        { id: "apps",  label: "Apps",      icon: "󰀻" },
                        { id: "clip",  label: "Clipboard", icon: "󰅌" },
                        { id: "calc",  label: "Calc",      icon: "󰪚" },
                        { id: "cmds",  label: "Commands",  icon: "󰘳" },
                        { id: "emoji", label: "Emoji",     icon: "󰞅" }
                    ]

                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        readonly property bool selected: root.effectiveMode === modeBtn.modelData.id

                        implicitHeight: 22
                        implicitWidth: modeContent.implicitWidth + 12
                        radius: Theme.r(11)
                        color: modeBtn.selected
                            ? Theme.primary
                            : (modeMouse.containsMouse ? Theme.hoverBg : "transparent")

                        RowLayout {
                            id: modeContent
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: modeBtn.modelData.icon
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: modeBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }

                            Text {
                                text: modeBtn.modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: modeBtn.selected ? Font.Bold : Font.Medium
                                color: modeBtn.selected ? Theme.fgPrimary : Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.openInMode(modeBtn.modelData.id);
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Clear unpinned clipboard entries button
        Rectangle {
            visible: root.effectiveMode === "clip" && root.clipboardItems.length > 0
            implicitHeight: 26
            implicitWidth: clrClipLbl.implicitWidth + 14
            radius: Theme.r(13)
            color: clrClipMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : Theme.cardBg
            border.width: Theme.cardBorderWidth
            border.color: clrClipMouse.containsMouse ? Theme.error : Theme.cardBorder

            Text {
                id: clrClipLbl
                anchors.centerIn: parent
                text: "Clear Unpinned"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                color: clrClipMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
            }

            MouseArea {
                id: clrClipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runClipboardAction("clear", 0)
            }
        }
    }

    // --- Search / Expression Input Bar ---
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Theme.r(14)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: {
                    if (root.effectiveMode === "clip") return "󰅌";
                    if (root.effectiveMode === "calc") return "󰪚";
                    if (root.effectiveMode === "cmds") return "󰘳";
                    if (root.effectiveMode === "emoji") return "󰞅";
                    return "󰍉";
                }
                font.family: Theme.iconFont
                font.pixelSize: 16
                color: searchInput.activeFocus ? Theme.primary : Theme.fgSurfaceVariant
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0
                    text: {
                        if (root.effectiveMode === "clip") return "Search clipboard history...";
                        if (root.effectiveMode === "calc") return "Type math expression (e.g. 1920*1080, 0xff + 16, sqrt(144))...";
                        if (root.effectiveMode === "cmds") return "Search desktop commands...";
                        if (root.effectiveMode === "emoji") return "Search emojis & Nerd Font icons...";
                        return "Search apps...  (prefixes: = calc · > cmd · : emoji · cb clip)";
                    }
                    elide: Text.ElideRight
                    width: parent.width
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: Theme.fgSurfaceVariant
                }

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fgSurface
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.fgPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    clip: true

                    onTextChanged: {
                        root.query = text;
                        root.selectedIndex = 0;
                    }
                    onActiveFocusChanged: root.searchFocusChanged(activeFocus)

                    Keys.onUpPressed: root.moveSelection(-1)
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onTabPressed: root.moveSelection(1)
                    Keys.onBacktabPressed: root.moveSelection(-1)
                    Keys.onReturnPressed: root.activateSelected()
                    Keys.onEnterPressed: root.activateSelected()
                    Keys.onEscapePressed: {
                        if (text.length > 0)
                            text = "";
                        else
                            root.closeRequested();
                    }
                }
            }

            Text {
                text: root.currentCount + (root.effectiveMode === "apps" ? " apps" : " items")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.fgSurfaceVariant
            }
        }
    }

    // --- Results Container ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: Theme.cardBorderWidth
        border.color: Theme.cardBorder
        clip: true

        // 1. Applications List
        ListView {
            id: appList
            visible: root.effectiveMode === "apps"
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            clip: true
            model: root.filteredApps

            delegate: Rectangle {
                id: appRow
                required property var modelData
                required property int index

                readonly property bool isSelected: appRow.index === root.selectedIndex

                width: appList.width
                height: 44
                radius: Theme.r(12)
                color: appRow.isSelected
                    ? Theme.activeBg
                    : (rowMouse.containsMouse ? Theme.hoverBg : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: appIcon.visible ? "transparent" : Theme.surfaceContainerHigh

                        IconImage {
                            id: appIcon
                            anchors.fill: parent
                            asynchronous: true
                            readonly property string resolvedIcon: Quickshell.iconPath(appRow.modelData.icon, true)
                            source: resolvedIcon
                            visible: resolvedIcon.length > 0 && status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !appIcon.visible
                            text: "󰣆"
                            font.family: Theme.iconFont
                            font.pixelSize: 15
                            color: appRow.isSelected ? Theme.primary : Theme.fgSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: appRow.modelData.name || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: appRow.isSelected ? Font.Bold : Font.DemiBold
                            color: appRow.isSelected ? Theme.primary : Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: appRow.modelData.genericName || appRow.modelData.comment || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        visible: appRow.isSelected
                        text: "↵"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = appRow.index
                    onClicked: root.launchEntry(appRow.modelData)
                }
            }
        }

        // 2. Clipboard History List
        ListView {
            id: clipList
            visible: root.effectiveMode === "clip"
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            clip: true
            model: root.filteredClipboard

            delegate: Rectangle {
                id: clipRow
                required property var modelData
                required property int index

                readonly property bool isSelected: clipRow.index === root.selectedIndex

                width: clipList.width
                height: 44
                radius: Theme.r(12)
                color: clipRow.isSelected
                    ? Theme.activeBg
                    : (clipMouse.containsMouse ? Theme.hoverBg : "transparent")

                MouseArea {
                    id: clipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = clipRow.index
                    onClicked: root.runClipboardAction("copy", clipRow.modelData.id)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    spacing: 8

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: Theme.r(8)
                        color: clipRow.modelData.pinned
                            ? Theme.withAlpha(Theme.primary, 0.22)
                            : (pinMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)

                        Text {
                            anchors.centerIn: parent
                            text: "󰐃"
                            font.family: Theme.iconFont
                            font.pixelSize: 11
                            color: clipRow.modelData.pinned ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: pinMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runClipboardAction("pin", clipRow.modelData.id)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: clipRow.modelData.preview || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            font.weight: clipRow.isSelected ? Font.Bold : Font.Medium
                            color: clipRow.isSelected ? Theme.primary : Theme.fgSurface
                        }

                        Text {
                            text: (clipRow.modelData.pinned ? "Pinned · " : "") + (clipRow.modelData.time || "")
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: Theme.r(8)
                        color: delMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "󰆴"
                            font.family: Theme.iconFont
                            font.pixelSize: 12
                            color: delMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                        }

                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runClipboardAction("delete", clipRow.modelData.id)
                        }
                    }
                }
            }
        }

        // 3. Calculator Results
        ListView {
            id: calcList
            visible: root.effectiveMode === "calc"
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6
            clip: true
            model: root.calcResults

            delegate: Rectangle {
                id: calcRow
                required property var modelData
                required property int index

                readonly property bool isSelected: calcRow.index === root.selectedIndex

                width: calcList.width
                height: 54
                radius: Theme.r(12)
                color: calcRow.isSelected
                    ? Theme.activeBg
                    : (calcMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Text {
                        text: calcRow.modelData.icon
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: Theme.primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: calcRow.modelData.title
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }

                        Text {
                            text: calcRow.modelData.sub
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        text: "Copy ↵"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: calcMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = calcRow.index
                    onClicked: {
                        root.copyPlainText(calcRow.modelData.copyVal);
                        root.closeRequested();
                    }
                }
            }
        }

        // 4. Quick Desktop Commands
        ListView {
            id: cmdsList
            visible: root.effectiveMode === "cmds"
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4
            clip: true
            model: root.filteredCommands

            delegate: Rectangle {
                id: cmdRow
                required property var modelData
                required property int index

                readonly property bool isSelected: cmdRow.index === root.selectedIndex

                width: cmdsList.width
                height: 44
                radius: Theme.r(12)
                color: cmdRow.isSelected
                    ? Theme.activeBg
                    : (cmdMouse.containsMouse ? Theme.hoverBg : "transparent")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: Theme.r(8)
                        color: Theme.subCardBg

                        Text {
                            anchors.centerIn: parent
                            text: cmdRow.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                            color: cmdRow.isSelected ? Theme.primary : Theme.secondary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: cmdRow.modelData.title
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            font.weight: cmdRow.isSelected ? Font.Bold : Font.DemiBold
                            color: cmdRow.isSelected ? Theme.primary : Theme.fgSurface
                        }

                        Text {
                            Layout.fillWidth: true
                            text: cmdRow.modelData.sub
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Text {
                        visible: cmdRow.isSelected
                        text: "↵"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: cmdMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = cmdRow.index
                    onClicked: root.runQuickCommand(cmdRow.modelData.id)
                }
            }
        }

        // 5. Emoji & Nerd Font Picker
        GridView {
            id: emojiGrid
            visible: root.effectiveMode === "emoji"
            anchors.fill: parent
            anchors.margins: 10
            cellWidth: Math.max(54, Math.floor((width) / 8))
            cellHeight: 54
            clip: true
            model: root.filteredEmojis

            delegate: Rectangle {
                id: emojiCell
                required property var modelData
                required property int index
                readonly property bool isSelected: emojiCell.index === root.selectedIndex

                width: emojiGrid.cellWidth - 4
                height: emojiGrid.cellHeight - 4
                radius: Theme.r(10)
                color: emojiCell.isSelected
                    ? Theme.activeBg
                    : (emojiMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg)
                border.width: emojiCell.isSelected ? 1 : 0
                border.color: Theme.primary

                Text {
                    anchors.centerIn: parent
                    text: emojiCell.modelData.g
                    font.family: Theme.iconFont
                    font.pixelSize: 20
                    color: Theme.fgSurface
                }

                MouseArea {
                    id: emojiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.selectedIndex = emojiCell.index
                    onClicked: {
                        root.copyPlainText(emojiCell.modelData.g);
                        root.closeRequested();
                    }
                }
            }
        }

        // Empty State Text
        Text {
            anchors.centerIn: parent
            visible: root.currentCount === 0
            text: {
                if (root.effectiveMode === "clip")
                    return root.clipboardLoading ? "Loading clipboard..." : "Clipboard history is empty";
                if (root.effectiveMode === "calc")
                    return "Enter an arithmetic, hex (0xff), or Math expression";
                if (root.effectiveMode === "cmds")
                    return "No matching commands";
                if (root.effectiveMode === "emoji")
                    return "No matching emojis or glyphs";
                return "No matching applications";
            }
            font.family: Theme.fontFamily
            font.pixelSize: 12
            color: Theme.fgSurfaceVariant
        }
    }
}
