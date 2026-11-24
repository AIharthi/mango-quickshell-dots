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
    property string activeMode: "apps"        // "apps" | "clip" | "snippets" | "calc" | "cmds" | "emoji"
    property int selectedIndex: 0
    property string query: ""
    property var clipboardItems: []
    property bool clipboardLoading: false
    property var snippetItems: []
    property bool snippetsLoading: false
    property string snippetsError: ""
    property bool composerOpen: false
    property bool _composerClipboardMode: false

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
    signal openCaptureHubRequested()

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
        if (trimmed.startsWith(";"))
            return "snippets";
        if (trimmed.toLowerCase().startsWith("cb "))
            return "clip";
        if (root.activeMode === "apps" && isQuickCalcOrConvert(trimmed))
            return "calc";
        return root.activeMode;
    }

    readonly property string cleanQuery: {
        const trimmed = (root.query || "").replace(/^\s+/, "");
        if (trimmed.startsWith("=") || trimmed.startsWith(">") || trimmed.startsWith(":") || trimmed.startsWith(";"))
            return trimmed.slice(1).trim();
        if (trimmed.toLowerCase().startsWith("cb "))
            return trimmed.slice(3).trim();
        return trimmed.trim();
    }

    function isQuickCalcOrConvert(s: string): bool {
        if (!s || s.length === 0 || s.length > 160)
            return false;
        if (/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s))
            return true;
        if (/^rgb\s*\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)$/i.test(s))
            return true;
        if (/^[+-]?(?:\d+(?:\.\d+)?|\.\d+)\s*[a-zA-Z°]+\s+(?:to|in)\s+[a-zA-Z°]+$/i.test(s))
            return true;
        return false;
    }

    function openInMode(modeName: string): void {
        const valid = (modeName === "clip" || modeName === "snippets" || modeName === "calc" || modeName === "cmds" || modeName === "emoji")
            ? modeName
            : "apps";
        root.activeMode = valid;
        root.composerOpen = false;
        searchInput.text = "";
        root.query = "";
        root.selectedIndex = 0;
        if (valid === "clip")
            refreshClipboard();
        else if (valid === "snippets")
            refreshSnippets();
        if (root.active)
            focusTimer.restart();
    }

    onInitialModeChanged: {
        if (root.active)
            openInMode(root.initialMode);
    }

    onEffectiveModeChanged: {
        root.selectedIndex = 0;
        if (root.effectiveMode !== "snippets")
            root.composerOpen = false;
        if (root.effectiveMode === "clip")
            refreshClipboard();
        else if (root.effectiveMode === "snippets")
            refreshSnippets();
    }

    onActiveChanged: {
        if (active) {
            openInMode(root.initialMode || "apps");
        } else {
            root.composerOpen = false;
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

    function refreshSnippets(): void {
        if (snippetsProc.running)
            return;
        root.snippetsLoading = true;
        root.snippetsError = "";
        snippetsProc.command = [Quickshell.shellPath("bin/aurora-backend"), "snippets", "list"];
        snippetsProc.running = true;
    }

    function runSnippetAction(action: string, itemId: int): void {
        if (action === "copy") {
            Quickshell.execDetached([Quickshell.shellPath("bin/aurora-backend"), "snippets", "copy", String(itemId)]);
            root.closeRequested();
            return;
        }
        if (snippetsProc.running)
            return;
        root.snippetsLoading = true;
        root.snippetsError = "";
        snippetsProc.command = [Quickshell.shellPath("bin/aurora-backend"), "snippets", action, String(itemId)];
        snippetsProc.running = true;
    }

    function saveComposerSnippet(): void {
        const title = snipTitleInput.text.trim();
        const tag = snipTagInput.text.trim().length > 0 ? snipTagInput.text.trim() : "general";
        const body = snipBodyInput.text;
        if (title.length === 0) {
            root.snippetsError = "Snippet title is required";
            return;
        }
        if (!root._composerClipboardMode && body.trim().length === 0) {
            root.snippetsError = "Snippet text is required";
            return;
        }
        if (snippetsProc.running)
            return;
        root.snippetsLoading = true;
        root.snippetsError = "";
        if (root._composerClipboardMode) {
            snippetsProc.command = [
                Quickshell.shellPath("bin/aurora-backend"),
                "snippets", "add", title, tag, "--from-clipboard"
            ];
        } else {
            snippetsProc.command = [
                "sh", "-c",
                "printf '%s' \"$4\" | \"$1\" snippets add \"$2\" \"$3\" --stdin",
                "_", Quickshell.shellPath("bin/aurora-backend"), title, tag, body
            ];
        }
        snippetsProc.running = true;
    }

    function openSnippetComposer(fromClipboard: bool): void {
        root._composerClipboardMode = fromClipboard;
        root.snippetsError = "";
        snipTitleInput.text = "";
        snipTagInput.text = "shell";
        snipBodyInput.text = "";
        root.composerOpen = true;
        snipTitleInput.forceActiveFocus();
    }

    Process {
        id: snippetsProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.snippetsLoading = false;
                const raw = (text || "").trim();
                if (raw.length === 0) {
                    root.snippetsError = "Snippets backend returned empty response";
                    return;
                }
                try {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) {
                        root.snippetsError = "";
                        root.snippetItems = parsed;
                        if (root.composerOpen)
                            root.composerOpen = false;
                    } else if (parsed && parsed.ok === false) {
                        root.snippetsError = String(parsed.error || "Snippet command failed");
                    }
                } catch (err) {
                    root.snippetsError = "Unable to parse snippets store";
                }
            }
        }
        onExited: (code) => {
            root.snippetsLoading = false;
            if (code !== 0 && root.snippetsError.length === 0)
                root.snippetsError = "Snippets backend exited with code " + code;
        }
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

    // --- Snippets Model ---
    readonly property var filteredSnippets: {
        if (root.effectiveMode !== "snippets")
            return [];
        const q = root.cleanQuery.toLowerCase();
        const items = root.snippetItems || [];
        if (q.length === 0)
            return items;
        return items.filter(it =>
            String(it.title || "").toLowerCase().indexOf(q) !== -1
            || String(it.tag || "").toLowerCase().indexOf(q) !== -1
            || String(it.body || "").toLowerCase().indexOf(q) !== -1
        );
    }

    // --- Safe Calculator, Unit Converter & Color Inspector (zero eval) ---
    function inspectColorExpr(s: string): var {
        let r = -1;
        let g = -1;
        let b = -1;
        const mShort = /^#([0-9a-fA-F]{3})$/.exec(s);
        const mLong = /^#([0-9a-fA-F]{6})$/.exec(s);
        const mRgb = /^rgb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/i.exec(s);
        if (mShort) {
            const h = mShort[1];
            r = parseInt(h[0] + h[0], 16);
            g = parseInt(h[1] + h[1], 16);
            b = parseInt(h[2] + h[2], 16);
        } else if (mLong) {
            const h = mLong[1];
            r = parseInt(h.slice(0, 2), 16);
            g = parseInt(h.slice(2, 4), 16);
            b = parseInt(h.slice(4, 6), 16);
        } else if (mRgb) {
            r = parseInt(mRgb[1], 10);
            g = parseInt(mRgb[2], 10);
            b = parseInt(mRgb[3], 10);
            if (r > 255 || g > 255 || b > 255)
                return null;
        } else {
            return null;
        }

        const hex2 = n => (n < 16 ? "0" : "") + n.toString(16).toUpperCase();
        const hexStr = "#" + hex2(r) + hex2(g) + hex2(b);
        const rgbStr = "rgb(" + r + ", " + g + ", " + b + ")";

        const rn = r / 255.0;
        const gn = g / 255.0;
        const bn = b / 255.0;
        const maxC = Math.max(rn, gn, bn);
        const minC = Math.min(rn, gn, bn);
        const l = (maxC + minC) / 2.0;
        let h = 0.0;
        let sat = 0.0;
        if (maxC !== minC) {
            const d = maxC - minC;
            sat = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC);
            if (maxC === rn)
                h = (gn - bn) / d + (gn < bn ? 6.0 : 0.0);
            else if (maxC === gn)
                h = (bn - rn) / d + 2.0;
            else
                h = (rn - gn) / d + 4.0;
            h /= 6.0;
        }
        const hslStr = "hsl(" + Math.round(h * 360) + ", " + Math.round(sat * 100) + "%, " + Math.round(l * 100) + "%)";

        return [
            { title: hexStr + " · " + rgbStr, sub: hslStr + " · Enter to copy hex", copyVal: hexStr, icon: "󰏘" },
            { title: rgbStr, sub: "CSS RGB · Enter to copy", copyVal: rgbStr, icon: "󰏘" },
            { title: hslStr, sub: "CSS HSL · Enter to copy", copyVal: hslStr, icon: "󰏘" }
        ];
    }

    function convertUnitsExpr(s: string): var {
        const m = /^([+-]?(?:\d+(?:\.\d+)?|\.\d+))\s*([a-zA-Z°]+)\s+(?:to|in)\s+([a-zA-Z°]+)$/i.exec(s);
        if (!m)
            return null;
        const val = parseFloat(m[1]);
        if (!isFinite(val))
            return null;
        const srcRaw = m[2].replace("°", "").toLowerCase();
        const dstRaw = m[3].replace("°", "").toLowerCase();

        const fmtVal = v => {
            if (Math.abs(v - Math.round(v)) < 1e-9)
                return String(Math.round(v));
            return Number(v.toPrecision(8)).toString();
        };

        const tempNorm = u => (u === "c" || u === "celsius") ? "c" : ((u === "f" || u === "fahrenheit") ? "f" : ((u === "k" || u === "kelvin") ? "k" : ""));
        const tSrc = tempNorm(srcRaw);
        const tDst = tempNorm(dstRaw);
        if (tSrc.length > 0 && tDst.length > 0) {
            let celsius = val;
            if (tSrc === "f") celsius = (val - 32.0) * 5.0 / 9.0;
            else if (tSrc === "k") celsius = val - 273.15;
            let out = celsius;
            if (tDst === "f") out = celsius * 9.0 / 5.0 + 32.0;
            else if (tDst === "k") out = celsius + 273.15;
            const labelMap = { c: "°C", f: "°F", k: "K" };
            const formatted = fmtVal(out);
            return [{
                title: formatted + " " + labelMap[tDst],
                sub: m[1] + " " + labelMap[tSrc] + " converted · Enter to copy",
                copyVal: formatted,
                icon: "󰑭"
            }];
        }

        const groups = [
            { units: { mm: 0.001, cm: 0.01, m: 1.0, km: 1000.0, "in": 0.0254, inch: 0.0254, inches: 0.0254, ft: 0.3048, foot: 0.3048, feet: 0.3048, yd: 0.9144, yard: 0.9144, yards: 0.9144, mi: 1609.344, mile: 1609.344, miles: 1609.344 } },
            { units: { mg: 0.001, g: 1.0, gram: 1.0, grams: 1.0, kg: 1000.0, oz: 28.349523125, lb: 453.59237, lbs: 453.59237 } },
            { units: { b: 1.0, byte: 1.0, bytes: 1.0, kb: 1000.0, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024.0, mib: 1048576.0, gib: 1073741824.0, tib: 1099511627776.0 } },
            { units: { ms: 0.001, s: 1.0, sec: 1.0, secs: 1.0, second: 1.0, seconds: 1.0, min: 60.0, mins: 60.0, minute: 60.0, minutes: 60.0, h: 3600.0, hr: 3600.0, hrs: 3600.0, hour: 3600.0, hours: 3600.0, d: 86400.0, day: 86400.0, days: 86400.0 } }
        ];

        for (let gi = 0; gi < groups.length; gi++) {
            const tbl = groups[gi].units;
            if (tbl[srcRaw] !== undefined && tbl[dstRaw] !== undefined) {
                const out = (val * tbl[srcRaw]) / tbl[dstRaw];
                const formatted = fmtVal(out);
                return [{
                    title: formatted + " " + m[3],
                    sub: m[1] + " " + m[2] + " converted · Enter to copy",
                    copyVal: formatted,
                    icon: "󰑭"
                }];
            }
        }
        return null;
    }

    function parseSafeMath(src: string): var {
        const toks = [];
        let i = 0;
        const n = src.length;
        while (i < n) {
            const ch = src[i];
            if (ch === " " || ch === "\t") {
                i++;
                continue;
            }
            if ((ch >= "0" && ch <= "9") || (ch === "." && i + 1 < n && src[i + 1] >= "0" && src[i + 1] <= "9")) {
                if (ch === "0" && i + 1 < n && (src[i + 1] === "x" || src[i + 1] === "X" || src[i + 1] === "b" || src[i + 1] === "B" || src[i + 1] === "o" || src[i + 1] === "O")) {
                    const baseChar = src[i + 1].toLowerCase();
                    let j = i + 2;
                    while (j < n && /[0-9a-fA-F]/.test(src[j]))
                        j++;
                    const digits = src.slice(i + 2, j);
                    if (digits.length === 0)
                        return NaN;
                    const radix = baseChar === "x" ? 16 : (baseChar === "b" ? 2 : 8);
                    const parsedInt = parseInt(digits, radix);
                    if (isNaN(parsedInt))
                        return NaN;
                    toks.push({ t: "num", v: parsedInt });
                    i = j;
                    continue;
                }
                let j = i;
                while (j < n && ((src[j] >= "0" && src[j] <= "9") || src[j] === "."))
                    j++;
                if (j < n && (src[j] === "e" || src[j] === "E")) {
                    j++;
                    if (j < n && (src[j] === "+" || src[j] === "-"))
                        j++;
                    while (j < n && src[j] >= "0" && src[j] <= "9")
                        j++;
                }
                const numVal = Number(src.slice(i, j));
                if (!isFinite(numVal))
                    return NaN;
                toks.push({ t: "num", v: numVal });
                i = j;
                continue;
            }
            if ((ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch === "_") {
                let j = i + 1;
                while (j < n && (/[a-zA-Z0-9_]/.test(src[j])))
                    j++;
                toks.push({ t: "id", v: src.slice(i, j).toLowerCase() });
                i = j;
                continue;
            }
            if (i + 1 < n) {
                const two = src.slice(i, i + 2);
                if (two === "**" || two === "<<" || two === ">>") {
                    toks.push({ t: "op", v: two });
                    i += 2;
                    continue;
                }
            }
            if (ch === "(" || ch === ")" || ch === ",") {
                toks.push({ t: ch, v: ch });
                i++;
                continue;
            }
            if ("+-*/%^~&|".indexOf(ch) !== -1) {
                toks.push({ t: "op", v: ch });
                i++;
                continue;
            }
            return NaN;
        }
        if (toks.length === 0)
            return NaN;

        let pos = 0;
        const peek = () => pos < toks.length ? toks[pos] : null;
        const consume = () => toks[pos++];

        let parseBitOr = null;
        let parseUnary = null;

        const callFn = (name, args) => {
            if (name === "sqrt" && args.length === 1) return Math.sqrt(args[0]);
            if (name === "cbrt" && args.length === 1) return Math.cbrt(args[0]);
            if (name === "sin" && args.length === 1) return Math.sin(args[0]);
            if (name === "cos" && args.length === 1) return Math.cos(args[0]);
            if (name === "tan" && args.length === 1) return Math.tan(args[0]);
            if (name === "abs" && args.length === 1) return Math.abs(args[0]);
            if (name === "round" && args.length === 1) return Math.round(args[0]);
            if (name === "floor" && args.length === 1) return Math.floor(args[0]);
            if (name === "ceil" && args.length === 1) return Math.ceil(args[0]);
            if ((name === "log" || name === "ln") && args.length === 1) return Math.log(args[0]);
            if (name === "log10" && args.length === 1) return Math.log10(args[0]);
            if (name === "exp" && args.length === 1) return Math.exp(args[0]);
            if (name === "min" && args.length >= 1) return Math.min.apply(null, args);
            if (name === "max" && args.length >= 1) return Math.max.apply(null, args);
            if (name === "pow" && args.length === 2) return Math.pow(args[0], args[1]);
            return NaN;
        };

        const parsePrimary = () => {
            const tk = peek();
            if (!tk)
                return NaN;
            if (tk.t === "num") {
                consume();
                return tk.v;
            }
            if (tk.t === "id") {
                consume();
                if (peek() && peek().t === "(") {
                    consume();
                    const args = [];
                    if (peek() && peek().t !== ")") {
                        while (true) {
                            args.push(parseBitOr());
                            if (peek() && peek().t === ",") {
                                consume();
                                continue;
                            }
                            break;
                        }
                    }
                    if (!peek() || peek().t !== ")")
                        return NaN;
                    consume();
                    return callFn(tk.v, args);
                }
                if (tk.v === "pi") return Math.PI;
                if (tk.v === "e") return Math.E;
                if (tk.v === "tau") return Math.PI * 2.0;
                return NaN;
            }
            if (tk.t === "(") {
                consume();
                const inner = parseBitOr();
                if (!peek() || peek().t !== ")")
                    return NaN;
                consume();
                return inner;
            }
            return NaN;
        };

        const parsePower = () => {
            const base = parsePrimary();
            if (peek() && peek().t === "op" && (peek().v === "^" || peek().v === "**")) {
                consume();
                const exp = parseUnary();
                return Math.pow(base, exp);
            }
            return base;
        };

        parseUnary = () => {
            if (peek() && peek().t === "op" && (peek().v === "+" || peek().v === "-" || peek().v === "~")) {
                const op = consume().v;
                const val = parseUnary();
                if (op === "+") return val;
                if (op === "-") return -val;
                return ~(val | 0);
            }
            return parsePower();
        };

        const parseMul = () => {
            let left = parseUnary();
            while (peek() && peek().t === "op" && (peek().v === "*" || peek().v === "/" || peek().v === "%")) {
                const op = consume().v;
                const right = parseUnary();
                if (op === "*") left *= right;
                else if (op === "/") left = right === 0 ? NaN : left / right;
                else left = right === 0 ? NaN : left % right;
            }
            return left;
        };

        const parseAdd = () => {
            let left = parseMul();
            while (peek() && peek().t === "op" && (peek().v === "+" || peek().v === "-")) {
                const op = consume().v;
                const right = parseMul();
                left = op === "+" ? left + right : left - right;
            }
            return left;
        };

        const parseShift = () => {
            let left = parseAdd();
            while (peek() && peek().t === "op" && (peek().v === "<<" || peek().v === ">>")) {
                const op = consume().v;
                const right = parseAdd();
                left = op === "<<" ? ((left | 0) << (right | 0)) : ((left | 0) >> (right | 0));
            }
            return left;
        };

        const parseBitAnd = () => {
            let left = parseShift();
            while (peek() && peek().t === "op" && peek().v === "&") {
                consume();
                const right = parseShift();
                left = (left | 0) & (right | 0);
            }
            return left;
        };

        parseBitOr = () => {
            let left = parseBitAnd();
            while (peek() && peek().t === "op" && peek().v === "|") {
                consume();
                const right = parseBitAnd();
                left = (left | 0) | (right | 0);
            }
            return left;
        };

        const result = parseBitOr();
        if (pos !== toks.length)
            return NaN;
        return result;
    }

    function evalExpression(rawExpr: string): var {
        const s = (rawExpr || "").trim();
        if (s.length === 0 || s.length > 160)
            return [];

        const colorCards = inspectColorExpr(s);
        if (colorCards !== null)
            return colorCards;

        const unitCards = convertUnitsExpr(s);
        if (unitCards !== null)
            return unitCards;

        const val = parseSafeMath(s);
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
        { id: "captures",    title: "Open Capture Studio",          sub: "Gallery, copy, annotate & record",   icon: "󰹑", kw: "capture studio screenshots recordings gallery" },
        { id: "snippets",    title: "Open Snippets Vault",          sub: "Reusable commands and text templates", icon: "󰅍", kw: "snippets templates vault paste" },
        { id: "distro-stat", title: "Check Distro & Package Status",sub: "Inspect Portage, pacman, or dnf health", icon: "󰏗", kw: "distro packages updates arch fedora gentoo doctor" },
        { id: "color-pick",  title: "Color Picker (Eyedropper)",    sub: "Pick pixel #RRGGBB to clipboard",    icon: "󰈊", kw: "color picker eyedropper hex" },
        { id: "record-area", title: "Toggle Screen Recording",      sub: "Start/stop wf-recorder capture",     icon: "󰑊", kw: "record screen video mp4" },
        { id: "keybinds",    title: "Keybind Cheat Sheet",          sub: "Show all MangoWC & shell shortcuts", icon: "󰌌", kw: "keybinds shortcuts help" },
        { id: "win-switch",  title: "Window Switcher",              sub: "Jump to or close any open window",   icon: "󰖯", kw: "windows switcher focus alt tab" },
        { id: "power-menu",  title: "Power & Session Overlay",      sub: "Lock, suspend, hibernate, reboot",   icon: "󰐥", kw: "power shutdown reboot suspend logout" },
        { id: "game-mode",   title: "Toggle Game Mode",             sub: "Simple bar + DND + Keep Awake",      icon: "󰊴", kw: "game mode performance dnd" },
        { id: "sync-sddm",   title: "Sync SDDM Login Theme",        sub: "Push palette & wallpaper to SDDM",   icon: "󰍹", kw: "sddm login greeter sync theme" },
        { id: "refresh-wx",  title: "Refresh Weather Forecast",     sub: "Fetch latest conditions (wttr.in)",  icon: "󰖐", kw: "weather forecast temp refresh" },
        { id: "files",       title: "Open Dynamic File Manager",    sub: "Launch Rust-backed aurora-fm",        icon: "󰉋", kw: "files manager explorer" },
        { id: "settings",    title: "Open Aurora Settings",         sub: "16-page configuration studio",       icon: "󰒓", kw: "settings preferences config" },
        { id: "doctor",      title: "Run Aurora Doctor Health Check",sub: "Inspect compositor, portals, audio & theme health", icon: "󰋼", kw: "doctor health check diagnostics system" },
        { id: "net-speed",   title: "Toggle Network Speed in Bar",  sub: "Show or hide live ↓/↑ throughput in top bar", icon: "󰇚", kw: "network speed bandwidth bar" },
        { id: "hub-cycle",   title: "Cycle Hub Layout Style",       sub: "Switch Cupertino, Stage, Cockpit, Bento", icon: "󰕰", kw: "hub layout cycle cupertino stage cockpit bento" },
        { id: "bar-cycle",   title: "Cycle Top Bar UI Style",       sub: "Switch Island, Split, Sequoia, Modular", icon: "󰘔", kw: "bar style cycle island split menubar" },
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
        if (root.effectiveMode === "snippets") return root.filteredSnippets.length;
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
        else if (root.effectiveMode === "snippets") snipList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
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
        } else if (cmdId === "captures") {
            root.openCaptureHubRequested();
        } else if (cmdId === "snippets") {
            root.openInMode("snippets");
            return;
        } else if (cmdId === "distro-stat") {
            root.openSettingsRequested("system");
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
        } else if (cmdId === "doctor") {
            root.openSettingsRequested("system");
        } else if (cmdId === "net-speed") {
            ShellState.setPref("barShowNetSpeed", !ShellState.barShowNetSpeed);
        } else if (cmdId === "hub-cycle") {
            ShellState.cycleHubUiStyle();
        } else if (cmdId === "bar-cycle") {
            ShellState.cycleBarUiStyle();
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
        } else if (root.effectiveMode === "snippets" && idx < root.filteredSnippets.length) {
            runSnippetAction("copy", root.filteredSnippets[idx].id);
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

    readonly property bool anyInputFocused: searchInput.activeFocus || snipTitleInput.activeFocus || snipTagInput.activeFocus || snipBodyInput.activeFocus
    onAnyInputFocusedChanged: root.searchFocusChanged(anyInputFocused)

    // --- macOS Spotlight Search / Expression Bar ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 46
        Layout.minimumHeight: 46
        Layout.maximumHeight: 46
        radius: Theme.r(16)
        color: Theme.cardBg
        border.width: searchInput.activeFocus ? 1.5 : Theme.cardBorderWidth
        border.color: searchInput.activeFocus ? Theme.primary : Theme.cardBorder

        Behavior on border.color {
            enabled: !Theme.isSimple
            ColorAnimation { duration: 150 }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 10

            Text {
                text: {
                    if (root.effectiveMode === "clip") return "󰅌";
                    if (root.effectiveMode === "snippets") return "󰅍";
                    if (root.effectiveMode === "calc") return "󰪚";
                    if (root.effectiveMode === "cmds") return "󰘳";
                    if (root.effectiveMode === "emoji") return "󰞅";
                    return "󰍉";
                }
                font.family: Theme.iconFont
                font.pixelSize: 18
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
                        if (root.effectiveMode === "snippets") return "Search snippets by title, tag, or body...";
                        if (root.effectiveMode === "calc") return "Math (1920*1080), units (100f to c, 2 gib to mb), or #hex...";
                        if (root.effectiveMode === "cmds") return "Search desktop commands...";
                        if (root.effectiveMode === "emoji") return "Search emojis & Nerd Font icons...";
                        return "Search apps, > commands, ; snippets, = math, #hex...";
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
                    font.pixelSize: 14
                    clip: true

                    onTextChanged: {
                        root.query = text;
                        root.selectedIndex = 0;
                    }

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

            Rectangle {
                visible: searchInput.text.length > 0
                implicitWidth: 22
                implicitHeight: 22
                radius: Theme.r(11)
                color: clrSearchMouse.containsMouse ? Theme.hoverBg : Theme.subCardBg

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    font.family: Theme.iconFont
                    font.pixelSize: 11
                    color: Theme.fgSurfaceVariant
                }

                MouseArea {
                    id: clrSearchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        searchInput.text = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }

            Rectangle {
                implicitHeight: 22
                implicitWidth: cntBadgeLbl.implicitWidth + 12
                radius: Theme.r(11)
                color: Theme.subCardBg

                Text {
                    id: cntBadgeLbl
                    anchors.centerIn: parent
                    text: root.currentCount + (root.effectiveMode === "apps" ? " apps" : " items")
                    font.family: Theme.monoFont
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Theme.fgSurfaceVariant
                }
            }
        }
    }

    // --- Apple Segmented Mode Bar + Contextual Hints ---
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 30
        Layout.minimumHeight: 30
        Layout.maximumHeight: 30
        spacing: 8

        Rectangle {
            implicitHeight: 30
            implicitWidth: modePillRow.implicitWidth + 6
            radius: Theme.r(15)
            color: Theme.cardBg
            border.width: Theme.subBorderWidth
            border.color: Theme.cardBorder

            RowLayout {
                id: modePillRow
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: [
                        { id: "apps",     label: "Apps",      icon: "󰀻" },
                        { id: "clip",     label: "Clipboard", icon: "󰅌" },
                        { id: "snippets", label: "Snippets",  icon: "󰅍" },
                        { id: "calc",     label: "Calc",      icon: "󰪚" },
                        { id: "cmds",     label: "Commands",  icon: "󰘳" },
                        { id: "emoji",    label: "Emoji",     icon: "󰞅" }
                    ]

                    delegate: Rectangle {
                        id: modeBtn
                        required property var modelData
                        readonly property bool selected: root.effectiveMode === modeBtn.modelData.id

                        implicitHeight: 24
                        implicitWidth: modeContent.implicitWidth + 12
                        radius: Theme.r(12)
                        color: modeBtn.selected
                            ? Theme.primary
                            : (modeMouse.containsMouse ? Theme.hoverBg : "transparent")

                        Behavior on color {
                            enabled: !Theme.isSimple
                            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

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
            border.width: Theme.subBorderWidth
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

        // Snippet Composer Quick Actions
        RowLayout {
            visible: root.effectiveMode === "snippets"
            spacing: 6

            Rectangle {
                implicitHeight: 26
                implicitWidth: newSnipLbl.implicitWidth + 14
                radius: Theme.r(8)
                color: (root.composerOpen && !root._composerClipboardMode)
                    ? Theme.primary
                    : (newSnipMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)

                Text {
                    id: newSnipLbl
                    anchors.centerIn: parent
                    text: "+ New"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: (root.composerOpen && !root._composerClipboardMode) ? Theme.fgPrimary : Theme.fgSurface
                }

                MouseArea {
                    id: newSnipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.composerOpen && !root._composerClipboardMode) {
                            root.composerOpen = false;
                            searchInput.forceActiveFocus();
                        } else {
                            root.openSnippetComposer(false);
                        }
                    }
                }
            }

            Rectangle {
                implicitHeight: 26
                implicitWidth: clipSnipLbl.implicitWidth + 14
                radius: Theme.r(8)
                color: (root.composerOpen && root._composerClipboardMode)
                    ? Theme.primary
                    : (clipSnipMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg)

                Text {
                    id: clipSnipLbl
                    anchors.centerIn: parent
                    text: "+ Clipboard"
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: (root.composerOpen && root._composerClipboardMode) ? Theme.fgPrimary : Theme.fgSurfaceVariant
                }

                MouseArea {
                    id: clipSnipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.composerOpen && root._composerClipboardMode) {
                            root.composerOpen = false;
                            searchInput.forceActiveFocus();
                        } else {
                            root.openSnippetComposer(true);
                        }
                    }
                }
            }
        }

        // Subtle Keycap Shortcuts Hint
        RowLayout {
            visible: !(root.effectiveMode === "clip" && root.clipboardItems.length > 0) && root.effectiveMode !== "snippets"
            spacing: 8

            Repeater {
                model: [
                    { k: "↑↓", l: "Select" },
                    { k: "Enter", l: "Open" },
                    { k: "Esc", l: "Close" }
                ]
                delegate: RowLayout {
                    id: khItem
                    required property var modelData
                    spacing: 3

                    Rectangle {
                        implicitHeight: 18
                        implicitWidth: khTxt.implicitWidth + 8
                        radius: Theme.r(5)
                        color: Theme.subCardBg
                        border.width: Theme.subBorderWidth
                        border.color: Theme.cardBorder

                        Text {
                            id: khTxt
                            anchors.centerIn: parent
                            text: khItem.modelData.k
                            font.family: Theme.monoFont
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            color: Theme.fgSurface
                        }
                    }

                    Text {
                        text: khItem.modelData.l
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: Theme.fgSurfaceVariant
                    }
                }
            }
        }
    }

    // --- Results Container ---
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.r(18)
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
                height: 48
                radius: Theme.r(13)
                color: appRow.isSelected
                    ? Theme.rowSelectedBg
                    : (rowMouse.containsMouse ? Theme.controlFillHover : "transparent")
                border.width: appRow.isSelected ? Theme.activeControlBorderWidth : 0
                border.color: Theme.primary

                Rectangle {
                    visible: appRow.isSelected
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    width: 3
                    radius: 1.5
                    color: Theme.primary
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: Theme.r(9)
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
                            font.pixelSize: 16
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
                            visible: {
                                const sub = String(appRow.modelData.genericName || appRow.modelData.comment || "").trim();
                                const nm = String(appRow.modelData.name || "").trim();
                                return sub.length > 0 && sub.toLowerCase() !== nm.toLowerCase();
                            }
                            text: appRow.modelData.genericName || appRow.modelData.comment || ""
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    Rectangle {
                        visible: appRow.isSelected
                        implicitHeight: 22
                        implicitWidth: openHintLbl.implicitWidth + 14
                        radius: Theme.r(11)
                        color: Theme.withAlpha(Theme.primary, 0.22)

                        Text {
                            id: openHintLbl
                            anchors.centerIn: parent
                            text: "Open"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
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
                height: 48
                radius: Theme.r(13)
                color: clipRow.isSelected
                    ? Theme.rowSelectedBg
                    : (clipMouse.containsMouse ? Theme.controlFillHover : "transparent")
                border.width: clipRow.isSelected ? Theme.activeControlBorderWidth : 0
                border.color: Theme.primary

                Rectangle {
                    visible: clipRow.isSelected
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    width: 3
                    radius: 1.5
                    color: Theme.primary
                }

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
                    anchors.rightMargin: 10
                    spacing: 10

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Theme.r(13)
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
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Theme.r(13)
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
                height: 58
                radius: Theme.r(14)
                color: calcRow.isSelected
                    ? Theme.rowSelectedBg
                    : (calcMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: calcRow.isSelected ? Theme.activeControlBorderWidth : Theme.subBorderWidth
                border.color: calcRow.isSelected ? Theme.primary : Theme.cardBorder

                Rectangle {
                    visible: calcRow.isSelected
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 11
                    anchors.bottomMargin: 11
                    width: 3
                    radius: 1.5
                    color: Theme.primary
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Theme.r(18)
                        color: Theme.withAlpha(Theme.primary, 0.16)

                        Text {
                            anchors.centerIn: parent
                            text: calcRow.modelData.icon
                            font.family: Theme.iconFont
                            font.pixelSize: 17
                            color: Theme.primary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: calcRow.modelData.title
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 18
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

                    Rectangle {
                        implicitHeight: 24
                        implicitWidth: copyHintLbl.implicitWidth + 14
                        radius: Theme.r(12)
                        color: Theme.withAlpha(Theme.primary, 0.22)

                        Text {
                            id: copyHintLbl
                            anchors.centerIn: parent
                            text: "Copy"
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
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
                height: 46
                radius: Theme.r(13)
                color: cmdRow.isSelected
                    ? Theme.rowSelectedBg
                    : (cmdMouse.containsMouse ? Theme.controlFillHover : "transparent")
                border.width: cmdRow.isSelected ? Theme.activeControlBorderWidth : 0
                border.color: Theme.primary

                Rectangle {
                    visible: cmdRow.isSelected
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 9
                    anchors.bottomMargin: 9
                    width: 3
                    radius: 1.5
                    color: Theme.primary
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        implicitWidth: 30
                        implicitHeight: 30
                        radius: Theme.r(15)
                        color: cmdRow.isSelected ? Theme.withAlpha(Theme.primary, 0.22) : Theme.subCardBg

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

                    Rectangle {
                        visible: cmdRow.isSelected
                        implicitHeight: 22
                        implicitWidth: runHintLbl.implicitWidth + 14
                        radius: Theme.r(11)
                        color: Theme.withAlpha(Theme.primary, 0.22)

                        Text {
                            id: runHintLbl
                            anchors.centerIn: parent
                            text: "Run"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
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
            cellWidth: Math.max(58, Math.floor((width) / 9))
            cellHeight: 56
            clip: true
            model: root.filteredEmojis

            delegate: Rectangle {
                id: emojiCell
                required property var modelData
                required property int index
                readonly property bool isSelected: emojiCell.index === root.selectedIndex

                width: emojiGrid.cellWidth - 4
                height: emojiGrid.cellHeight - 4
                radius: Theme.r(12)
                color: emojiCell.isSelected
                    ? Theme.tileActiveBg
                    : (emojiMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                border.width: emojiCell.isSelected ? Theme.activeControlBorderWidth : 0
                border.color: Theme.primary
                scale: emojiMouse.containsMouse ? 1.06 : 1.0

                Behavior on scale { enabled: !Theme.reducedMotion; NumberAnimation { duration: 90 } }

                Text {
                    anchors.centerIn: parent
                    text: emojiCell.modelData.g
                    font.family: Theme.iconFont
                    font.pixelSize: 21
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

        // 6. Snippets Vault List + Inline Composer
        ColumnLayout {
            visible: root.effectiveMode === "snippets"
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Rectangle {
                visible: root.composerOpen
                Layout.fillWidth: true
                implicitHeight: compCol.implicitHeight + 16
                radius: Theme.r(12)
                color: Theme.subCardBg

                ColumnLayout {
                    id: compCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 30
                            radius: Theme.r(8)
                            color: Theme.cardBg
                            border.width: snipTitleInput.activeFocus ? 1 : 0
                            border.color: Theme.primary

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                visible: snipTitleInput.text.length === 0
                                text: "Snippet title"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgSurfaceVariant
                            }

                            TextInput {
                                id: snipTitleInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fgSurface
                                selectionColor: Theme.primary
                                selectedTextColor: Theme.fgPrimary
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                clip: true
                                Keys.onTabPressed: snipTagInput.forceActiveFocus()
                                Keys.onEscapePressed: {
                                    root.composerOpen = false;
                                    searchInput.forceActiveFocus();
                                }
                                Keys.onReturnPressed: {
                                    if (root._composerClipboardMode)
                                        root.saveComposerSnippet();
                                    else
                                        snipBodyInput.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 110
                            implicitHeight: 30
                            radius: Theme.r(8)
                            color: Theme.cardBg
                            border.width: snipTagInput.activeFocus ? 1 : 0
                            border.color: Theme.primary

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                visible: snipTagInput.text.length === 0
                                text: "Tag (shell)"
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.fgSurfaceVariant
                            }

                            TextInput {
                                id: snipTagInput
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.fgSurface
                                selectionColor: Theme.primary
                                selectedTextColor: Theme.fgPrimary
                                font.family: Theme.monoFont
                                font.pixelSize: 10
                                clip: true
                                Keys.onTabPressed: {
                                    if (root._composerClipboardMode)
                                        snipTitleInput.forceActiveFocus();
                                    else
                                        snipBodyInput.forceActiveFocus();
                                }
                                Keys.onEscapePressed: {
                                    root.composerOpen = false;
                                    searchInput.forceActiveFocus();
                                }
                                Keys.onReturnPressed: {
                                    if (root._composerClipboardMode)
                                        root.saveComposerSnippet();
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: !root._composerClipboardMode
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: Theme.r(8)
                        color: Theme.cardBg
                        border.width: snipBodyInput.activeFocus ? 1 : 0
                        border.color: Theme.primary

                        Text {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.margins: 8
                            visible: snipBodyInput.text.length === 0
                            text: "Enter reusable command, path, or template text..."
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            color: Theme.fgSurfaceVariant
                        }

                        TextEdit {
                            id: snipBodyInput
                            anchors.fill: parent
                            anchors.margins: 8
                            color: Theme.fgSurface
                            selectionColor: Theme.primary
                            selectedTextColor: Theme.fgPrimary
                            font.family: Theme.monoFont
                            font.pixelSize: 11
                            wrapMode: TextEdit.Wrap
                            clip: true
                            Keys.onEscapePressed: {
                                root.composerOpen = false;
                                searchInput.forceActiveFocus();
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: root.snippetsError.length > 0
                                ? root.snippetsError
                                : (root._composerClipboardMode ? "Reads current clipboard text safely into vault" : "Saved with 0600 permissions")
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: root.snippetsError.length > 0 ? Theme.error : Theme.fgSurfaceVariant
                        }

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: cnlSnipTxt.implicitWidth + 14
                            radius: Theme.r(7)
                            color: cnlSnipMouse.containsMouse ? Theme.controlFillHover : Theme.cardBg

                            Text {
                                id: cnlSnipTxt
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: cnlSnipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.composerOpen = false;
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }

                        Rectangle {
                            implicitHeight: 24
                            implicitWidth: svSnipTxt.implicitWidth + 16
                            radius: Theme.r(7)
                            color: Theme.primary

                            Text {
                                id: svSnipTxt
                                anchors.centerIn: parent
                                text: "Save snippet"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: Theme.fgPrimary
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.saveComposerSnippet()
                            }
                        }
                    }
                }
            }

            ListView {
                id: snipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.snippetsLoading && root.snippetsError.length === 0 && root.filteredSnippets.length > 0
                spacing: 4
                clip: true
                model: root.filteredSnippets

                delegate: Rectangle {
                    id: snipRow
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: snipRow.index === root.selectedIndex

                    width: snipList.width
                    height: 52
                    radius: Theme.r(12)
                    color: snipRow.isSelected
                        ? Theme.rowSelectedBg
                        : (snipMouse.containsMouse ? Theme.controlFillHover : Theme.subCardBg)
                    border.width: snipRow.isSelected ? 1 : 0
                    border.color: Theme.primary

                    MouseArea {
                        id: snipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selectedIndex = snipRow.index
                        onClicked: root.runSnippetAction("copy", snipRow.modelData.id)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(13)
                            color: snipRow.modelData.pinned
                                ? Theme.withAlpha(Theme.primary, 0.22)
                                : (snipPinMouse.containsMouse ? Theme.hoverBg : Theme.cardBg)

                            Text {
                                anchors.centerIn: parent
                                text: "󰐃"
                                font.family: Theme.iconFont
                                font.pixelSize: 11
                                color: snipRow.modelData.pinned ? Theme.primary : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: snipPinMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runSnippetAction("pin", snipRow.modelData.id)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: String(snipRow.modelData.title || "")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    font.weight: snipRow.isSelected ? Font.Bold : Font.DemiBold
                                    color: snipRow.isSelected ? Theme.primary : Theme.fgSurface
                                }

                                Rectangle {
                                    implicitHeight: 17
                                    implicitWidth: tagBadgeLbl.implicitWidth + 10
                                    radius: Theme.r(5)
                                    color: Theme.cardBg

                                    Text {
                                        id: tagBadgeLbl
                                        anchors.centerIn: parent
                                        text: String(snipRow.modelData.tag || "general")
                                        font.family: Theme.monoFont
                                        font.pixelSize: 9
                                        color: Theme.secondary
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: String(snipRow.modelData.preview || "")
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.monoFont
                                font.pixelSize: 10
                                color: Theme.fgSurfaceVariant
                            }
                        }

                        Rectangle {
                            implicitWidth: 26
                            implicitHeight: 26
                            radius: Theme.r(13)
                            color: snipDelMouse.containsMouse ? Theme.withAlpha(Theme.error, 0.22) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰆴"
                                font.family: Theme.iconFont
                                font.pixelSize: 12
                                color: snipDelMouse.containsMouse ? Theme.error : Theme.fgSurfaceVariant
                            }

                            MouseArea {
                                id: snipDelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runSnippetAction("delete", snipRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // Empty / Loading / Error State Text
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.effectiveMode === "snippets"
                ? (!root.composerOpen && (root.snippetsLoading || root.snippetsError.length > 0 || root.filteredSnippets.length === 0))
                : (root.currentCount === 0)
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.effectiveMode === "clip") return "󰅌";
                    if (root.effectiveMode === "snippets") return root.snippetsError.length > 0 ? "󰀦" : "󰅍";
                    if (root.effectiveMode === "calc") return "󰪚";
                    if (root.effectiveMode === "cmds") return "󰘳";
                    if (root.effectiveMode === "emoji") return "󰞅";
                    return "󰍉";
                }
                font.family: Theme.iconFont
                font.pixelSize: 28
                color: (root.effectiveMode === "snippets" && root.snippetsError.length > 0) ? Theme.error : Theme.fgSurfaceVariant
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.effectiveMode === "clip")
                        return root.clipboardLoading ? "Loading clipboard..." : "Clipboard history is empty";
                    if (root.effectiveMode === "snippets") {
                        if (root.snippetsLoading) return "Loading snippets...";
                        if (root.snippetsError.length > 0) return root.snippetsError;
                        return root.cleanQuery.length > 0
                            ? "No matching snippets"
                            : "No saved snippets yet. Click + New or + Clipboard above.";
                    }
                    if (root.effectiveMode === "calc")
                        return "Enter an arithmetic, hex (0xff), or Math expression";
                    if (root.effectiveMode === "cmds")
                        return "No matching commands";
                    if (root.effectiveMode === "emoji")
                        return "No matching emojis or glyphs";
                    return "No matching applications";
                }
                font.family: Theme.fontFamily
                font.pixelSize: 11
                color: Theme.fgSurfaceVariant
            }
        }
    }
}
