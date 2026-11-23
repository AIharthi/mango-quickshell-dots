pragma ComponentBehavior: Bound
import QtQuick
import ".."

QtObject {
    id: style

    readonly property color accent: {
        const ov = (ShellState.fmAccentOverride || "").trim();
        if (ov.length === 7 && ov.charAt(0) === "#")
            return ov;
        return Theme.primary;
    }

    readonly property color onAccent: Theme.fgPrimary

    readonly property color windowBg: {
        const op = ShellState.fmOpacity;
        const preset = ShellState.fmSurfacePreset;
        if (Theme.isSimple || preset === "solid")
            return Theme.withAlpha(Theme.surface, Math.max(0.92, op));
        if (preset === "oled")
            return Theme.withAlpha("#050507", Math.max(0.88, op));
        if (preset === "glass")
            return Theme.isDark
                ? Theme.withAlpha(Theme.surfaceContainerLowest, Math.min(0.86, op * 0.85))
                : Theme.withAlpha(Theme.surface, Math.min(0.90, op * 0.88));
        if (preset === "tinted")
            return Theme.withAlpha(Theme.primaryContainer, Math.min(0.96, op));
        return Theme.withAlpha(Theme.surfaceContainerLowest, op);
    }

    readonly property color sidebarBg: {
        const preset = ShellState.fmSurfacePreset;
        if (Theme.isSimple)
            return Theme.surfaceContainerLow;
        if (preset === "oled")
            return Theme.withAlpha("#09090d", 0.92);
        if (preset === "tinted")
            return Theme.withAlpha(Theme.surfaceContainer, 0.72);
        return Theme.cardBg;
    }

    readonly property color paneBg: {
        if (Theme.isSimple)
            return Theme.surface;
        if (ShellState.fmSurfacePreset === "oled")
            return Theme.withAlpha("#08080c", 0.88);
        return Theme.withAlpha(Theme.surfaceContainer, Math.min(0.85, ShellState.cardOpacity + 0.18));
    }

    readonly property color headerBg: {
        const hs = ShellState.fmHeaderStyle;
        if (Theme.isSimple || hs === "underline")
            return Theme.surfaceContainerLow;
        if (hs === "minimal")
            return "transparent";
        return Theme.cardBg;
    }

    readonly property color altRowBg: Theme.isDark
        ? Qt.rgba(1, 1, 1, 0.028)
        : Qt.rgba(0, 0, 0, 0.025)

    readonly property color borderCol: {
        if (ShellState.highContrast || ShellState.borderStyle === "accent" || ShellState.borderStyle === "glow")
            return style.accent;
        if (Theme.isSimple)
            return Theme.outlineVariant;
        return Theme.cardBorder;
    }

    readonly property int rowHeight: {
        if (ShellState.fmDensity === "compact")
            return 28;
        if (ShellState.fmDensity === "spacious")
            return 42;
        return 34;
    }

    readonly property int iconBoxSize: {
        if (ShellState.fmDensity === "compact")
            return 20;
        if (ShellState.fmDensity === "spacious")
            return 28;
        return 24;
    }

    readonly property int rowRadius: Theme.r(ShellState.fmDensity === "compact" ? 6 : 9)

    readonly property int sidebarWidth: {
        if (!ShellState.fmSidebarVisible)
            return 0;
        if (ShellState.fmSidebarStyle === "icons")
            return 56;
        if (ShellState.fmSidebarStyle === "compact")
            return 168;
        return 206;
    }

    function categoryIcon(category: string, ext: string, isDir: bool): string {
        if (isDir)
            return "󰉋";
        if (category === "image")
            return "󰈟";
        if (category === "video")
            return "󰕧";
        if (category === "audio")
            return "󰎆";
        if (category === "archive")
            return "󰗄";
        if (category === "pdf")
            return "󰈦";
        if (category === "font")
            return "󰛖";
        if (category === "code")
            return "󰅩";
        if (category === "doc")
            return "󰈙";
        if (category === "exec")
            return "󰆍";
        if (ext === "iso" || ext === "img")
            return "󰋊";
        return "󰈔";
    }

    function categoryColor(category: string, isDir: bool, isBroken: bool): color {
        if (isBroken)
            return Theme.error;
        const mode = ShellState.fmIconStyle;
        if (mode === "mono")
            return isDir ? Theme.fgSurface : Theme.fgSurfaceVariant;
        if (mode === "accent")
            return isDir ? style.accent : Theme.withAlpha(style.accent, 0.85);
        if (mode === "vivid") {
            if (isDir) return style.accent;
            if (category === "image") return "#2dd4bf";
            if (category === "video") return "#f472b6";
            if (category === "audio") return "#a78bfa";
            if (category === "archive") return "#fbbf24";
            if (category === "code") return "#38bdf8";
            if (category === "pdf") return "#fb7185";
            if (category === "doc") return "#60a5fa";
            if (category === "exec") return "#4ade80";
            if (category === "font") return "#c084fc";
            return Theme.fgSurfaceVariant;
        }
        // Default semantic "category" synced with active Theme palette
        if (isDir) return style.accent;
        if (category === "image") return Theme.info;
        if (category === "video") return Theme.tertiary;
        if (category === "audio") return Theme.secondary;
        if (category === "archive") return Theme.warning;
        if (category === "code") return Theme.primary;
        if (category === "pdf") return Theme.error;
        if (category === "doc") return Theme.secondary;
        if (category === "exec") return Theme.success;
        if (category === "font") return Theme.tertiary;
        return Theme.fgSurfaceVariant;
    }

    function formatMtime(epochSecs: var): string {
        const secs = Number(epochSecs || 0);
        if (secs <= 0)
            return "";
        const dt = new Date(secs * 1000);
        const now = new Date();
        const sameYear = dt.getFullYear() === now.getFullYear();
        const timePart = ShellState.clock24h ? "HH:mm" : "hh:mm AP";
        return Qt.formatDateTime(dt, sameYear ? ("MMM d  " + timePart) : ("yyyy-MM-dd"));
    }

    function fileUrl(p: string): string {
        if (!p || p.length === 0)
            return "";
        // Qt handles file:///path with URI-encoded # and ?
        const escaped = String(p).replace(/%/g, "%25").replace(/#/g, "%23").replace(/\?/g, "%3F");
        return "file://" + escaped;
    }
}
