#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
shift || true

case "$CMD" in
    list-presets|render-preset|apply-mango-overrides|tweak-colors|custom-list|custom-save|custom-apply|custom-delete|custom-export|custom-import|wallpaper-colors|wallpapers-list|solid-wallpaper|random-wallpaper|apply-vibe)
        ;;
    *)
        echo "Usage: manage-themes.sh <list-presets|render-preset|apply-mango-overrides|tweak-colors|custom-list|custom-save|custom-apply|custom-delete|custom-export|custom-import|wallpaper-colors|wallpapers-list|solid-wallpaper|random-wallpaper|apply-vibe> [args...]" >&2
        exit 1
        ;;
esac

exec python3 - "$CMD" "$@" <<'PY'
import glob
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

cmd = sys.argv[1]
args = sys.argv[2:]

CONFIG_DIR = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
QS_DIR = os.path.join(CONFIG_DIR, "quickshell")
MANGO_DIR = os.path.join(CONFIG_DIR, "mango")
GTK3_DIR = os.path.join(CONFIG_DIR, "gtk-3.0")
GTK4_DIR = os.path.join(CONFIG_DIR, "gtk-4.0")
FOOT_DIR = os.path.join(CONFIG_DIR, "foot")
KITTY_DIR = os.path.join(CONFIG_DIR, "kitty")
CUSTOM_DIR = os.path.join(QS_DIR, "custom-themes")

COLORS_JSON = os.path.join(QS_DIR, "colors.json")
STATE_JSON = os.path.join(QS_DIR, "theme-state.json")
PREFS_JSON = os.path.join(QS_DIR, "shell-prefs.json")
MANGO_THEME = os.path.join(MANGO_DIR, "theme.conf")
APPLY_THEME_SH = os.path.join(QS_DIR, "scripts", "apply-theme.sh")
APPLY_MODE_SH = os.path.join(QS_DIR, "scripts", "apply-mode.sh")


def atomic_write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp_", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def norm_hex(val, fallback="#cba6f7"):
    s = str(val or "").strip().lstrip("#")
    if re.match(r"^[0-9a-fA-F]{6}$", s):
        return "#" + s.lower()
    if re.match(r"^[0-9a-fA-F]{3}$", s):
        return "#" + "".join(c * 2 for c in s.lower())
    return fallback


def hex_to_rgb(h):
    s = norm_hex(h).lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_hex(rgb):
    r, g, b = [max(0, min(255, int(round(c)))) for c in rgb]
    return f"#{r:02x}{g:02x}{b:02x}"


def mix(c1, c2, t):
    r1, g1, b1 = hex_to_rgb(c1)
    r2, g2, b2 = hex_to_rgb(c2)
    return rgb_to_hex((r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t))


def rel_lum(h):
    def chan(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = hex_to_rgb(h)
    return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b)


def contrast_fg(bg_hex, dark_fg="#11111b", light_fg="#ffffff"):
    return dark_fg if rel_lum(bg_hex) > 0.34 else light_fg


def contrast_ratio(c1, c2):
    l1, l2 = rel_lum(c1), rel_lum(c2)
    if l1 < l2:
        l1, l2 = l2, l1
    return (l1 + 0.05) / (l2 + 0.05)


def ensure_contrast(fg_hex, bg_hex, min_ratio, prefer_dark_bg=True):
    fg = norm_hex(fg_hex)
    bgs = [norm_hex(b) for b in bg_hex] if isinstance(bg_hex, (list, tuple)) else [norm_hex(bg_hex)]
    if all(contrast_ratio(fg, b) >= min_ratio for b in bgs):
        return fg
    target = "#ffffff" if prefer_dark_bg else "#000000"
    for step in range(1, 101):
        cand = mix(fg, target, step / 100.0)
        if all(contrast_ratio(cand, b) >= min_ratio for b in bgs):
            return cand
    alt = "#000000" if prefer_dark_bg else "#ffffff"
    for step in range(1, 101):
        cand = mix(fg, alt, step / 100.0)
        if all(contrast_ratio(cand, b) >= min_ratio for b in bgs):
            return cand
    return fg


def best_ink_on(bg_hex, preferred_fg, dark_ink="#11111b", light_ink="#ffffff", min_ratio=4.6):
    cand = norm_hex(preferred_fg)
    if contrast_ratio(cand, bg_hex) >= min_ratio:
        return cand
    d_cr = contrast_ratio(dark_ink, bg_hex)
    l_cr = contrast_ratio(light_ink, bg_hex)
    best = dark_ink if d_cr >= l_cr else light_ink
    if contrast_ratio(best, bg_hex) >= min_ratio:
        return best
    return ensure_contrast(best, bg_hex, min_ratio, prefer_dark_bg=(l_cr >= d_cr))


def load_json_dict(path):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


PRESETS = {
    "catppuccin-mocha": {
        "label": "Catppuccin",
        "dark": {
            "primary": "#cba6f7", "secondary": "#89b4fa", "tertiary": "#f5c2e7",
            "background": "#11111b", "surface": "#1e1e2e", "surfaceLow": "#181825", "surfaceHigh": "#313244", "surfaceHighest": "#45475a",
            "onSurface": "#cdd6f4", "onSurfaceVariant": "#a6adc8", "outline": "#6c7086", "outlineVariant": "#313244",
            "error": "#f38ba8", "success": "#a6e3a1", "warning": "#f9e2af", "info": "#89dceb",
        },
        "light": {
            "primary": "#8839ef", "secondary": "#1e66f5", "tertiary": "#ea76cb",
            "background": "#eff1f5", "surface": "#eff1f5", "surfaceLow": "#e6e9ef", "surfaceHigh": "#ccd0da", "surfaceHighest": "#bcc0cc",
            "onSurface": "#4c4f69", "onSurfaceVariant": "#6c6f85", "outline": "#8c8fa1", "outlineVariant": "#ccd0da",
            "error": "#d20f39", "success": "#40a02b", "warning": "#df8e1d", "info": "#04a5e5",
        },
    },
    "tokyo-night": {
        "label": "Tokyo Night",
        "dark": {
            "primary": "#7aa2f7", "secondary": "#bb9af7", "tertiary": "#7dcfff",
            "background": "#16161e", "surface": "#1a1b26", "surfaceLow": "#16161e", "surfaceHigh": "#292e42", "surfaceHighest": "#3b4261",
            "onSurface": "#c0caf5", "onSurfaceVariant": "#9aa5ce", "outline": "#565f89", "outlineVariant": "#292e42",
            "error": "#f7768e", "success": "#9ece6a", "warning": "#e0af68", "info": "#7dcfff",
        },
        "light": {
            "primary": "#2e7de9", "secondary": "#9854f1", "tertiary": "#007197",
            "background": "#e1e2e7", "surface": "#e1e2e7", "surfaceLow": "#d5d6db", "surfaceHigh": "#c4c8da", "surfaceHighest": "#b4b8cc",
            "onSurface": "#3760bf", "onSurfaceVariant": "#6172b0", "outline": "#848cb5", "outlineVariant": "#c4c8da",
            "error": "#f52a65", "success": "#587539", "warning": "#8c6c3e", "info": "#007197",
        },
    },
    "gruvbox": {
        "label": "Gruvbox",
        "dark": {
            "primary": "#fabd2f", "secondary": "#83a598", "tertiary": "#fe8019",
            "background": "#1d2021", "surface": "#282828", "surfaceLow": "#1d2021", "surfaceHigh": "#3c3836", "surfaceHighest": "#504945",
            "onSurface": "#ebdbb2", "onSurfaceVariant": "#bdae93", "outline": "#665c54", "outlineVariant": "#3c3836",
            "error": "#fb4934", "success": "#b8bb26", "warning": "#fabd2f", "info": "#8ec07c",
        },
        "light": {
            "primary": "#b57614", "secondary": "#076678", "tertiary": "#af3a03",
            "background": "#fbf1c7", "surface": "#fbf1c7", "surfaceLow": "#f2e5bc", "surfaceHigh": "#ebdbb2", "surfaceHighest": "#d5c4a1",
            "onSurface": "#3c3836", "onSurfaceVariant": "#665c54", "outline": "#928374", "outlineVariant": "#d5c4a1",
            "error": "#9d0006", "success": "#79740e", "warning": "#b57614", "info": "#427b58",
        },
    },
    "nord": {
        "label": "Nord",
        "dark": {
            "primary": "#88c0d0", "secondary": "#81a1c1", "tertiary": "#b48ead",
            "background": "#242933", "surface": "#2e3440", "surfaceLow": "#242933", "surfaceHigh": "#3b4252", "surfaceHighest": "#434c5e",
            "onSurface": "#eceff4", "onSurfaceVariant": "#d8dee9", "outline": "#4c566a", "outlineVariant": "#3b4252",
            "error": "#bf616a", "success": "#a3be8c", "warning": "#ebcb8b", "info": "#8fbcbb",
        },
        "light": {
            "primary": "#5e81ac", "secondary": "#4c566a", "tertiary": "#b48ead",
            "background": "#eceff4", "surface": "#eceff4", "surfaceLow": "#e5e9f0", "surfaceHigh": "#d8dee9", "surfaceHighest": "#c8d0e0",
            "onSurface": "#2e3440", "onSurfaceVariant": "#4c566a", "outline": "#7b88a1", "outlineVariant": "#d8dee9",
            "error": "#bf616a", "success": "#73935c", "warning": "#b88936", "info": "#4f8f9b",
        },
    },
    "rose-pine": {
        "label": "Rose Pine",
        "dark": {
            "primary": "#ebbcba", "secondary": "#c4a7e7", "tertiary": "#9ccfd8",
            "background": "#191724", "surface": "#1f1d2e", "surfaceLow": "#191724", "surfaceHigh": "#26233a", "surfaceHighest": "#403d52",
            "onSurface": "#e0def4", "onSurfaceVariant": "#908caa", "outline": "#6e6a86", "outlineVariant": "#26233a",
            "error": "#eb6f92", "success": "#9ccfd8", "warning": "#f6c177", "info": "#31748f",
        },
        "light": {
            "primary": "#d7827e", "secondary": "#907aa9", "tertiary": "#286983",
            "background": "#faf4ed", "surface": "#fffaf3", "surfaceLow": "#f2e9e1", "surfaceHigh": "#dfdad9", "surfaceHighest": "#cecacd",
            "onSurface": "#575279", "onSurfaceVariant": "#797593", "outline": "#9893a5", "outlineVariant": "#dfdad9",
            "error": "#b4637a", "success": "#56949f", "warning": "#ea9d34", "info": "#286983",
        },
    },
    "dracula": {
        "label": "Dracula",
        "dark": {
            "primary": "#bd93f9", "secondary": "#ff79c6", "tertiary": "#8be9fd",
            "background": "#21222c", "surface": "#282a36", "surfaceLow": "#21222c", "surfaceHigh": "#383a59", "surfaceHighest": "#44475a",
            "onSurface": "#f8f8f2", "onSurfaceVariant": "#bfbfbf", "outline": "#6272a4", "outlineVariant": "#44475a",
            "error": "#ff5555", "success": "#50fa7b", "warning": "#f1fa8c", "info": "#8be9fd",
        },
        "light": {
            "primary": "#644ac9", "secondary": "#a3144d", "tertiary": "#036a96",
            "background": "#fffbeb", "surface": "#fffbeb", "surfaceLow": "#f4efda", "surfaceHigh": "#e5dfc8", "surfaceHighest": "#cfcaa9",
            "onSurface": "#1f1f1f", "onSurfaceVariant": "#5c5a4f", "outline": "#8b8770", "outlineVariant": "#e5dfc8",
            "error": "#cb3a2a", "success": "#14710a", "warning": "#846e15", "info": "#036a96",
        },
    },
    "everforest": {
        "label": "Everforest",
        "dark": {
            "primary": "#a7c080", "secondary": "#83c092", "tertiary": "#e69875",
            "background": "#272e33", "surface": "#2d353b", "surfaceLow": "#232a2e", "surfaceHigh": "#3d484d", "surfaceHighest": "#4f585e",
            "onSurface": "#d3c6aa", "onSurfaceVariant": "#9da9a0", "outline": "#7a8478", "outlineVariant": "#3d484d",
            "error": "#e67e80", "success": "#a7c080", "warning": "#dbbc7f", "info": "#7fbbb3",
        },
        "light": {
            "primary": "#8da101", "secondary": "#35a77c", "tertiary": "#f57d26",
            "background": "#fdf6e3", "surface": "#fffbef", "surfaceLow": "#f4f0d9", "surfaceHigh": "#e6e2cc", "surfaceHighest": "#d8d3ba",
            "onSurface": "#5c6a72", "onSurfaceVariant": "#829181", "outline": "#939f91", "outlineVariant": "#e6e2cc",
            "error": "#f85552", "success": "#8da101", "warning": "#dfa000", "info": "#3a94c5",
        },
    },
    "kanagawa": {
        "label": "Kanagawa",
        "dark": {
            "primary": "#7e9cd8", "secondary": "#957fb8", "tertiary": "#d27e99",
            "background": "#16161d", "surface": "#1f1f28", "surfaceLow": "#181820", "surfaceHigh": "#2a2a37", "surfaceHighest": "#363646",
            "onSurface": "#dcd7ba", "onSurfaceVariant": "#c8c093", "outline": "#727169", "outlineVariant": "#363646",
            "error": "#e82424", "success": "#98bb6c", "warning": "#e6c384", "info": "#7fb4ca",
        },
        "light": {
            "primary": "#4d699b", "secondary": "#766b90", "tertiary": "#b35b79",
            "background": "#f2ecbc", "surface": "#f2ecbc", "surfaceLow": "#e7dba0", "surfaceHigh": "#d5cea3", "surfaceHighest": "#c9cba3",
            "onSurface": "#545464", "onSurfaceVariant": "#716e61", "outline": "#8a8980", "outlineVariant": "#d5cea3",
            "error": "#c84053", "success": "#6f894e", "warning": "#77713f", "info": "#4e8ca2",
        },
    },
    "solarized": {
        "label": "Solarized",
        "dark": {
            "primary": "#268bd2", "secondary": "#2aa198", "tertiary": "#6c71c4",
            "background": "#00212b", "surface": "#002b36", "surfaceLow": "#00212b", "surfaceHigh": "#073642", "surfaceHighest": "#0e4654",
            "onSurface": "#eee8d5", "onSurfaceVariant": "#93a1a1", "outline": "#657b83", "outlineVariant": "#073642",
            "error": "#dc322f", "success": "#859900", "warning": "#b58900", "info": "#2aa198",
        },
        "light": {
            "primary": "#268bd2", "secondary": "#2aa198", "tertiary": "#6c71c4",
            "background": "#fdf6e3", "surface": "#fdf6e3", "surfaceLow": "#eee8d5", "surfaceHigh": "#e1dac6", "surfaceHighest": "#d1cbb7",
            "onSurface": "#586e75", "onSurfaceVariant": "#657b83", "outline": "#93a1a1", "outlineVariant": "#e1dac6",
            "error": "#dc322f", "success": "#859900", "warning": "#b58900", "info": "#2aa198",
        },
    },
    "one-dark": {
        "label": "One Dark",
        "dark": {
            "primary": "#61afef", "secondary": "#c678dd", "tertiary": "#56b6c2",
            "background": "#1e222a", "surface": "#282c34", "surfaceLow": "#21252b", "surfaceHigh": "#323842", "surfaceHighest": "#3e4451",
            "onSurface": "#abb2bf", "onSurfaceVariant": "#828997", "outline": "#5c6370", "outlineVariant": "#323842",
            "error": "#e06c75", "success": "#98c379", "warning": "#e5c07b", "info": "#56b6c2",
        },
        "light": {
            "primary": "#4078f2", "secondary": "#a626a4", "tertiary": "#0184bc",
            "background": "#fafafa", "surface": "#fafafa", "surfaceLow": "#f0f0f1", "surfaceHigh": "#e5e5e6", "surfaceHighest": "#d4d4d8",
            "onSurface": "#383a42", "onSurfaceVariant": "#696c77", "outline": "#a0a1a7", "outlineVariant": "#e5e5e6",
            "error": "#e45649", "success": "#50a14f", "warning": "#c18401", "info": "#0184bc",
        },
    },
    "ayu": {
        "label": "Ayu Mirage",
        "dark": {
            "primary": "#ffcc66", "secondary": "#73d0ff", "tertiary": "#f28779",
            "background": "#171b24", "surface": "#1f2430", "surfaceLow": "#171b24", "surfaceHigh": "#2a303f", "surfaceHighest": "#373f52",
            "onSurface": "#cbccc6", "onSurfaceVariant": "#8a9199", "outline": "#5c6773", "outlineVariant": "#2a303f",
            "error": "#f28779", "success": "#bae67e", "warning": "#ffd173", "info": "#73d0ff",
        },
        "light": {
            "primary": "#f2ae49", "secondary": "#399ee6", "tertiary": "#fa8d3e",
            "background": "#fcfcfc", "surface": "#fcfcfc", "surfaceLow": "#f3f4f5", "surfaceHigh": "#e7e8eb", "surfaceHighest": "#d8dadc",
            "onSurface": "#575f66", "onSurfaceVariant": "#8a9199", "outline": "#abb0b6", "outlineVariant": "#e7e8eb",
            "error": "#f07171", "success": "#86b300", "warning": "#f2ae49", "info": "#399ee6",
        },
    },
    "oxocarbon": {
        "label": "Oxocarbon",
        "dark": {
            "primary": "#3ddbd9", "secondary": "#ff7eb6", "tertiary": "#78a9ff",
            "background": "#111111", "surface": "#161616", "surfaceLow": "#161616", "surfaceHigh": "#262626", "surfaceHighest": "#393939",
            "onSurface": "#f2f4f8", "onSurfaceVariant": "#dde1e6", "outline": "#6f6f6f", "outlineVariant": "#262626",
            "error": "#ee5396", "success": "#42be65", "warning": "#ffab91", "info": "#33b1ff",
        },
        "light": {
            "primary": "#0f62fe", "secondary": "#ee5396", "tertiary": "#007d79",
            "background": "#ffffff", "surface": "#ffffff", "surfaceLow": "#f4f4f4", "surfaceHigh": "#e0e0e0", "surfaceHighest": "#c6c6c6",
            "onSurface": "#161616", "onSurfaceVariant": "#525252", "outline": "#8d8d8d", "outlineVariant": "#e0e0e0",
            "error": "#da1e28", "success": "#24a148", "warning": "#ff832b", "info": "#0043ce",
        },
    },
    "synthwave": {
        "label": "Synthwave",
        "dark": {
            "primary": "#ff7edb", "secondary": "#36f9f6", "tertiary": "#fede5d",
            "background": "#1a1626", "surface": "#262335", "surfaceLow": "#1a1626", "surfaceHigh": "#34294f", "surfaceHighest": "#463869",
            "onSurface": "#ffffff", "onSurfaceVariant": "#d4c3e8", "outline": "#848bbd", "outlineVariant": "#34294f",
            "error": "#fe4450", "success": "#72f1b8", "warning": "#fede5d", "info": "#36f9f6",
        },
        "light": {
            "primary": "#c71585", "secondary": "#008b8b", "tertiary": "#d97706",
            "background": "#faf5ff", "surface": "#ffffff", "surfaceLow": "#f3e8ff", "surfaceHigh": "#e9d5ff", "surfaceHighest": "#d8b4fe",
            "onSurface": "#2e1065", "onSurfaceVariant": "#6b21a8", "outline": "#9333ea", "outlineVariant": "#e9d5ff",
            "error": "#dc2626", "success": "#059669", "warning": "#d97706", "info": "#0284c7",
        },
    },
    "oled-black": {
        "label": "OLED Pitch",
        "dark": {
            "primary": "#82aaff", "secondary": "#c792ea", "tertiary": "#89ddff",
            "background": "#000000", "surface": "#050507", "surfaceLow": "#000000", "surfaceHigh": "#101218", "surfaceHighest": "#1b1e28",
            "onSurface": "#f0f4ff", "onSurfaceVariant": "#94a3b8", "outline": "#475569", "outlineVariant": "#1b1e28",
            "error": "#ff5370", "success": "#c3e88d", "warning": "#ffcb6b", "info": "#89ddff",
        },
        "light": {
            "primary": "#111111", "secondary": "#3b82f6", "tertiary": "#8b5cf6",
            "background": "#ffffff", "surface": "#ffffff", "surfaceLow": "#f8fafc", "surfaceHigh": "#e2e8f0", "surfaceHighest": "#cbd5e1",
            "onSurface": "#0f172a", "onSurfaceVariant": "#475569", "outline": "#94a3b8", "outlineVariant": "#e2e8f0",
            "error": "#ef4444", "success": "#16a34a", "warning": "#d97706", "info": "#0284c7",
        },
    },
    "sakura": {
        "label": "Sakura",
        "dark": {
            "primary": "#f28fad", "secondary": "#c9a0dc", "tertiary": "#f8bd96",
            "background": "#181318", "surface": "#231b22", "surfaceLow": "#1b151a", "surfaceHigh": "#322731", "surfaceHighest": "#433442",
            "onSurface": "#f5e0dc", "onSurfaceVariant": "#caa8b4", "outline": "#7d606b", "outlineVariant": "#322731",
            "error": "#f38ba8", "success": "#98c379", "warning": "#f9e2af", "info": "#89dceb",
        },
        "light": {
            "primary": "#d64571", "secondary": "#8b5cf6", "tertiary": "#e07a5f",
            "background": "#fff5f8", "surface": "#ffffff", "surfaceLow": "#fde8ef", "surfaceHigh": "#fad4e0", "surfaceHighest": "#f3b8cb",
            "onSurface": "#3d222c", "onSurfaceVariant": "#6e4b58", "outline": "#a17c89", "outlineVariant": "#fad4e0",
            "error": "#dc2626", "success": "#2f855a", "warning": "#d97706", "info": "#0284c7",
        },
    },
    "cyberpunk": {
        "label": "Cyberpunk",
        "dark": {
            "primary": "#00f0ff", "secondary": "#fcee09", "tertiary": "#ff2a6d",
            "background": "#0a0a12", "surface": "#121220", "surfaceLow": "#0d0d17", "surfaceHigh": "#1d1d33", "surfaceHighest": "#2b2b4a",
            "onSurface": "#eef2ff", "onSurfaceVariant": "#9ca3c7", "outline": "#585b87", "outlineVariant": "#262642",
            "error": "#ff003c", "success": "#05ffa1", "warning": "#fcee09", "info": "#00f0ff",
        },
        "light": {
            "primary": "#0077ff", "secondary": "#d90429", "tertiary": "#eab308",
            "background": "#f4f4f8", "surface": "#ffffff", "surfaceLow": "#eaeaf2", "surfaceHigh": "#dcdce8", "surfaceHighest": "#c6c6d8",
            "onSurface": "#141422", "onSurfaceVariant": "#4a4a68", "outline": "#7b7b99", "outlineVariant": "#dcdce8",
            "error": "#d90429", "success": "#059669", "warning": "#ca8a04", "info": "#0284c7",
        },
    },
}


def complete_palette(base, is_dark):
    p = norm_hex(base.get("primary"), "#cba6f7")
    s = norm_hex(base.get("secondary"), "#89b4fa")
    t = norm_hex(base.get("tertiary"), "#f5c2e7")
    bg = norm_hex(base.get("background"), "#11111b" if is_dark else "#eff1f5")
    surf = norm_hex(base.get("surface"), "#1e1e2e" if is_dark else "#eff1f5")
    on_surf = norm_hex(base.get("onSurface"), "#cdd6f4" if is_dark else "#333344")
    on_surf_var = norm_hex(base.get("onSurfaceVariant"), mix(on_surf, surf, 0.35))
    outline = norm_hex(base.get("outline"), mix(on_surf, surf, 0.58))
    outline_var = norm_hex(base.get("outlineVariant"), mix(on_surf, surf, 0.78))

    surf_low = norm_hex(base.get("surfaceLow"), mix(surf, bg, 0.45) if is_dark else mix(surf, "#d5d8e0", 0.35))
    surf_high = norm_hex(base.get("surfaceHigh"), mix(surf, on_surf, 0.12))
    surf_highest = norm_hex(base.get("surfaceHighest"), mix(surf, on_surf, 0.22))

    err = norm_hex(base.get("error"), "#f38ba8" if is_dark else "#d20f39")
    suc = norm_hex(base.get("success"), "#a6e3a1" if is_dark else "#40a02b")
    wrn = norm_hex(base.get("warning"), "#f9e2af" if is_dark else "#df8e1d")
    inf = norm_hex(base.get("info"), "#89dceb" if is_dark else "#04a5e5")

    # Enforce WCAG AA readability across both Dark and Light surface tiers
    surf_pair = [surf, surf_low]
    surf_trio = [surf, surf_low, surf_high]
    on_surf = ensure_contrast(on_surf, surf_trio, 7.0 if is_dark else 6.0, prefer_dark_bg=is_dark)
    on_surf_var = ensure_contrast(on_surf_var, surf_trio, 4.6, prefer_dark_bg=is_dark)
    p = ensure_contrast(p, surf_pair, 4.6, prefer_dark_bg=is_dark)
    s = ensure_contrast(s, surf_pair, 4.5, prefer_dark_bg=is_dark)
    err = ensure_contrast(err, surf_pair, 4.6, prefer_dark_bg=is_dark)
    suc = ensure_contrast(suc, surf_pair, 4.5, prefer_dark_bg=is_dark)
    wrn = ensure_contrast(wrn, surf_pair, 4.5, prefer_dark_bg=is_dark)
    inf = ensure_contrast(inf, surf_pair, 4.5, prefer_dark_bg=is_dark)

    p_cont = norm_hex(base.get("primaryContainer"), mix(p, surf, 0.68 if is_dark else 0.76))
    s_cont = norm_hex(base.get("secondaryContainer"), mix(s, surf, 0.68 if is_dark else 0.76))
    t_cont = norm_hex(base.get("tertiaryContainer"), mix(t, surf, 0.68 if is_dark else 0.76))

    on_p = best_ink_on(p, base.get("onPrimary") or contrast_fg(p, "#11111b", "#ffffff"))
    on_s = best_ink_on(s, base.get("onSecondary") or contrast_fg(s, "#11111b", "#ffffff"))
    on_t = best_ink_on(t, base.get("onTertiary") or contrast_fg(t, "#11111b", "#ffffff"))
    on_err = best_ink_on(err, base.get("onError") or contrast_fg(err, "#11111b", "#ffffff"))
    on_p_cont = best_ink_on(p_cont, base.get("onPrimaryContainer") or contrast_fg(p_cont, "#11111b", "#ffffff"))
    on_s_cont = best_ink_on(s_cont, base.get("onSecondaryContainer") or contrast_fg(s_cont, "#11111b", "#ffffff"))
    on_t_cont = best_ink_on(t_cont, base.get("onTertiaryContainer") or contrast_fg(t_cont, "#11111b", "#ffffff"))

    c = {
        "isDark": bool(is_dark),
        "primary": p,
        "onPrimary": on_p,
        "primaryContainer": p_cont,
        "onPrimaryContainer": on_p_cont,
        "secondary": s,
        "onSecondary": on_s,
        "secondaryContainer": s_cont,
        "onSecondaryContainer": on_s_cont,
        "tertiary": t,
        "onTertiary": on_t,
        "tertiaryContainer": t_cont,
        "onTertiaryContainer": on_t_cont,
        "background": bg,
        "onBackground": ensure_contrast(base.get("onBackground") or on_surf, bg, 7.0 if is_dark else 6.0, prefer_dark_bg=is_dark),
        "surface": surf,
        "surfaceDim": norm_hex(base.get("surfaceDim"), bg),
        "surfaceBright": norm_hex(base.get("surfaceBright"), surf_high),
        "surfaceContainerLowest": norm_hex(base.get("surfaceContainerLowest"), bg),
        "surfaceContainerLow": surf_low,
        "surfaceContainer": norm_hex(base.get("surfaceContainer"), surf),
        "surfaceContainerHigh": surf_high,
        "surfaceContainerHighest": surf_highest,
        "onSurface": on_surf,
        "onSurfaceVariant": on_surf_var,
        "outline": outline,
        "outlineVariant": outline_var,
        "error": err,
        "onError": on_err,
        "success": suc,
        "warning": wrn,
        "info": inf,
        "shadow": "#000000",
    }

    c["ansi"] = base.get("ansi") if isinstance(base.get("ansi"), list) and len(base["ansi"]) == 16 else [
        surf_high if is_dark else outline,
        err, suc, wrn, s, t, inf, on_surf_var,
        outline,
        mix(err, "#ffffff", 0.20 if is_dark else 0.0),
        mix(suc, "#ffffff", 0.20 if is_dark else 0.0),
        mix(wrn, "#ffffff", 0.20 if is_dark else 0.0),
        p,
        mix(t, "#ffffff", 0.20 if is_dark else 0.0),
        mix(inf, "#ffffff", 0.20 if is_dark else 0.0),
        on_surf,
    ]
    return c


def write_palette_outputs(c, tag_label="custom"):
    scheme_str = "dark" if c["isDark"] else "light"
    json_obj = {k: v for k, v in c.items() if k != "ansi"}
    atomic_write(COLORS_JSON, json.dumps(json_obj, indent=2) + "\n")

    gtk_common = f"""/* Auto-generated by manage-themes.sh ({tag_label} / {scheme_str}) */
@define-color accent_color {c['primary']};
@define-color accent_bg_color {c['primary']};
@define-color accent_fg_color {c['onPrimary']};
@define-color destructive_color {c['error']};
@define-color destructive_bg_color {c['error']};
@define-color destructive_fg_color {c['onError']};
@define-color success_color {c['success']};
@define-color success_bg_color {c['success']};
@define-color success_fg_color {c['onPrimary']};
@define-color warning_color {c['warning']};
@define-color warning_bg_color {c['warning']};
@define-color warning_fg_color {c['onPrimary']};
@define-color error_color {c['error']};
@define-color error_bg_color {c['error']};
@define-color error_fg_color {c['onError']};
@define-color window_bg_color {c['surface']};
@define-color window_fg_color {c['onSurface']};
@define-color view_bg_color {c['surfaceContainerLow']};
@define-color view_fg_color {c['onSurface']};
@define-color headerbar_bg_color {c['surfaceContainer']};
@define-color headerbar_fg_color {c['onSurface']};
@define-color headerbar_border_color {c['outlineVariant']};
@define-color headerbar_backdrop_color {c['surfaceContainerLowest']};
@define-color card_bg_color {c['surfaceContainerHigh']};
@define-color card_fg_color {c['onSurface']};
@define-color dialog_bg_color {c['surfaceContainer']};
@define-color dialog_fg_color {c['onSurface']};
@define-color popover_bg_color {c['surfaceContainerLow']};
@define-color popover_fg_color {c['onSurface']};
@define-color sidebar_bg_color {c['surfaceContainerLow']};
@define-color sidebar_fg_color {c['onSurface']};
@define-color sidebar_backdrop_color {c['surfaceContainerLowest']};
"""
    gtk3_body = f"""@define-color theme_fg_color {c['onSurface']};
@define-color theme_text_color {c['onSurface']};
@define-color theme_bg_color {c['surface']};
@define-color theme_base_color {c['surfaceContainerLow']};
@define-color theme_selected_bg_color {c['primary']};
@define-color theme_selected_fg_color {c['onPrimary']};
@define-color insensitive_bg_color {c['surfaceContainerLow']};
@define-color insensitive_fg_color {c['onSurfaceVariant']};
@define-color insensitive_base_color {c['surface']};
@define-color theme_unfocused_fg_color {c['onSurfaceVariant']};
@define-color theme_unfocused_text_color {c['onSurface']};
@define-color theme_unfocused_bg_color {c['surface']};
@define-color theme_unfocused_base_color {c['surfaceContainerLow']};
@define-color theme_unfocused_selected_bg_color {c['surfaceContainerHigh']};
@define-color theme_unfocused_selected_fg_color {c['onSurface']};
@define-color borders {c['outlineVariant']};
@define-color unfocused_borders {c['outlineVariant']};

decoration, window.csd > decoration, window.solid-csd > decoration, .csd, .solid-csd {{
    box-shadow: none; margin: 0px; padding: 0px; border: none; border-width: 0px; border-radius: 0px; background: transparent;
}}
headerbar, .titlebar {{
    background-image: none; background-color: {c['surfaceContainer']}; color: {c['onSurface']};
    border: none; box-shadow: none; border-radius: 0px;
}}
headerbar button.titlebutton, .titlebar button.titlebutton {{
    opacity: 0; min-width: 0; min-height: 0; padding: 0; margin: 0;
}}
dialog, messagedialog, popover, menu, .context-menu {{
    background-color: {c['surfaceContainerLow']}; color: {c['onSurface']}; border: none;
}}
entry, textview, treeview, .view {{
    background-color: {c['surfaceContainerLow']}; color: {c['onSurface']};
}}
selection, *:selected {{
    background-color: {c['primary']}; color: {c['onPrimary']};
}}
"""
    gtk4_body = f"""@define-color theme_fg_color {c['onSurface']};
@define-color theme_text_color {c['onSurface']};
@define-color theme_bg_color {c['surface']};
@define-color theme_base_color {c['surfaceContainerLow']};
@define-color theme_selected_bg_color {c['primary']};
@define-color theme_selected_fg_color {c['onPrimary']};

window, window.csd, window.solid-csd {{
    background-color: {c['surface']}; color: {c['onSurface']}; outline: none; box-shadow: none; margin: 0px; border: none; border-radius: 0px;
}}
headerbar, .titlebar {{
    background-color: {c['surfaceContainer']}; color: {c['onSurface']}; border: none; box-shadow: none; border-radius: 0px;
}}
popover > contents, dialog, messagedialog {{
    background-color: {c['surfaceContainerLow']}; color: {c['onSurface']}; border: none;
}}
entry, textview, .view {{
    background-color: {c['surfaceContainerLow']}; color: {c['onSurface']};
}}
selection, *:selected {{
    background-color: {c['primary']}; color: {c['onPrimary']};
}}
windowcontrols {{
    opacity: 0; min-width: 0; min-height: 0;
}}
"""
    atomic_write(os.path.join(GTK3_DIR, "gtk.css"), gtk_common + gtk3_body)
    atomic_write(os.path.join(GTK4_DIR, "gtk.css"), gtk_common + gtk4_body)

    sh = lambda h: norm_hex(h).lstrip("#")
    mango_txt = f"""# Auto-generated by manage-themes.sh ({tag_label} / {scheme_str})
root_color=0x{sh(c['background'])}ff
border_color=0x{sh(c['outlineVariant'])}ff
focus_color=0x{sh(c['primary'])}ff
maximized_screen_color=0x{sh(c['secondary'])}ff
urgent_color=0x{sh(c['error'])}ff
scratchpad_color=0x{sh(c['tertiary'])}ff
global_color=0x{sh(c['secondary'])}ff
overlay_color=0x{sh(c['primaryContainer'])}ff
drop_color=0x{sh(c['primary'])}55
split_color=0x{sh(c['tertiary'])}ff
shadows_color=0x{sh(c['shadow'])}cc
dim_focused_color=0x00000000
dim_unfocused_color=0x00000044
"""
    atomic_write(MANGO_THEME, mango_txt)

    ansi = c["ansi"]
    foot_txt = f"""# Auto-generated by manage-themes.sh ({tag_label} / {scheme_str})
[colors]
background={sh(c['surfaceContainerLowest'])}
foreground={sh(c['onSurface'])}
cursor={sh(c['onPrimary'])} {sh(c['primary'])}
selection-foreground={sh(c['onPrimaryContainer'])}
selection-background={sh(c['primaryContainer'])}

regular0={sh(ansi[0])}
regular1={sh(ansi[1])}
regular2={sh(ansi[2])}
regular3={sh(ansi[3])}
regular4={sh(ansi[4])}
regular5={sh(ansi[5])}
regular6={sh(ansi[6])}
regular7={sh(ansi[7])}

bright0={sh(ansi[8])}
bright1={sh(ansi[9])}
bright2={sh(ansi[10])}
bright3={sh(ansi[11])}
bright4={sh(ansi[12])}
bright5={sh(ansi[13])}
bright6={sh(ansi[14])}
bright7={sh(ansi[15])}
"""
    atomic_write(os.path.join(FOOT_DIR, "colors.ini"), foot_txt)

    kitty_txt = f"""# Auto-generated by manage-themes.sh ({tag_label} / {scheme_str})
foreground {c['onSurface']}
background {c['surfaceContainerLowest']}
cursor {c['primary']}
cursor_text_color {c['onPrimary']}
selection_foreground {c['onPrimaryContainer']}
selection_background {c['primaryContainer']}
url_color {c['secondary']}

active_border_color {c['primary']}
inactive_border_color {c['outlineVariant']}
active_tab_foreground {c['onPrimary']}
active_tab_background {c['primary']}
inactive_tab_foreground {c['onSurfaceVariant']}
inactive_tab_background {c['surfaceContainer']}

""" + "\n".join(f"color{i} {norm_hex(ansi[i])}" for i in range(16)) + "\n"
    atomic_write(os.path.join(KITTY_DIR, "colors.conf"), kitty_txt)


def apply_mango_color_overrides(do_reload=False):
    if not os.path.isfile(MANGO_THEME):
        return
    prefs = load_json_dict(PREFS_JSON)
    colors = load_json_dict(COLORS_JSON)

    focus_ov = norm_hex(prefs.get("mangoFocusColor", ""), "") if str(prefs.get("mangoFocusColor", "")).strip() else ""
    border_ov = norm_hex(prefs.get("mangoBorderColor", ""), "") if str(prefs.get("mangoBorderColor", "")).strip() else ""
    shadow_tint = bool(prefs.get("mangoShadowTint", False))
    shadow_alpha = max(0.0, min(1.0, float(prefs.get("mangoShadowAlpha", 0.80))))
    dim_alpha = max(0.0, min(0.75, float(prefs.get("mangoDimAlpha", 0.27))))

    sa_hex = f"{int(round(shadow_alpha * 255)):02x}"
    da_hex = f"{int(round(dim_alpha * 255)):02x}"
    default_focus = norm_hex(colors.get("primary"), "#cba6f7").lstrip("#")
    default_border = norm_hex(colors.get("outlineVariant"), "#313244").lstrip("#")
    final_focus = focus_ov.lstrip("#") if focus_ov else default_focus
    final_border = border_ov.lstrip("#") if border_ov else default_border
    shadow_rgb = default_focus if shadow_tint else "000000"

    lines = []
    with open(MANGO_THEME, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    out = []
    seen = set()
    for line in lines:
        s = line.strip()
        if s.startswith("focus_color="):
            out.append(f"focus_color=0x{final_focus}ff\n")
            seen.add("focus_color")
        elif s.startswith("border_color="):
            out.append(f"border_color=0x{final_border}ff\n")
            seen.add("border_color")
        elif s.startswith("shadows_color="):
            out.append(f"shadows_color=0x{shadow_rgb}{sa_hex}\n")
            seen.add("shadows_color")
        elif s.startswith("dim_unfocused_color="):
            out.append(f"dim_unfocused_color=0x000000{da_hex}\n")
            seen.add("dim_unfocused_color")
        else:
            out.append(line)

    if "focus_color" not in seen:
        out.append(f"focus_color=0x{final_focus}ff\n")
    if "border_color" not in seen:
        out.append(f"border_color=0x{final_border}ff\n")
    if "shadows_color" not in seen:
        out.append(f"shadows_color=0x{shadow_rgb}{sa_hex}\n")
    if "dim_unfocused_color" not in seen:
        out.append(f"dim_unfocused_color=0x000000{da_hex}\n")

    atomic_write(MANGO_THEME, "".join(out))
    if do_reload and shutil.which("mmsg"):
        subprocess.run(["mmsg", "dispatch", "reload_config"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def push_terminal_osc_and_reload():
    foot_ini = os.path.join(FOOT_DIR, "colors.ini")
    if os.path.isfile(foot_ini):
        vals = {}
        with open(foot_ini, "r", encoding="utf-8", errors="ignore") as f:
            for raw in f:
                line = raw.strip()
                if "=" in line and not line.startswith("[") and not line.startswith("#"):
                    k, v = [x.strip() for x in line.split("=", 1)]
                    vals[k] = v
        out = []
        if "foreground" in vals: out.append(f"\033]10;#{vals['foreground']}\033\\")
        if "background" in vals: out.append(f"\033]11;#{vals['background']}\033\\")
        if "cursor" in vals and len(vals["cursor"].split()) >= 2:
            out.append(f"\033]12;#{vals['cursor'].split()[1]}\033\\")
        for idx in range(8):
            if f"regular{idx}" in vals: out.append(f"\033]4;{idx};#{vals[f'regular{idx}']}\033\\")
            if f"bright{idx}" in vals: out.append(f"\033]4;{idx + 8};#{vals[f'bright{idx}']}\033\\")
        seq = "".join(out)
        if seq:
            ttys = set()
            try:
                uid_str = str(os.getuid())
                ps_out = subprocess.check_output(["ps", "-eo", "uid=,tty=,comm="], text=True, stderr=subprocess.DEVNULL, timeout=2.0)
                for row in ps_out.splitlines():
                    parts = row.split()
                    if len(parts) >= 3 and parts[0] == uid_str and parts[1].startswith("pts/") and parts[2] in ("bash", "zsh", "fish", "sh", "nu"):
                        ttys.add("/dev/" + parts[1])
            except Exception:
                pass
            for pts in sorted(ttys):
                try:
                    with open(pts, "w", encoding="utf-8") as f:
                        f.write(seq)
                except Exception:
                    pass
    subprocess.run(["pkill", "-x", "-USR1", "kitty"], stderr=subprocess.DEVNULL)
    if shutil.which("mmsg"):
        subprocess.run(["mmsg", "dispatch", "reload_config"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cmd_list_presets():
    out = []
    for pid, data in PRESETS.items():
        d = data["dark"]
        l = data["light"]
        out.append({
            "id": pid,
            "label": data["label"],
            "swatch": d["primary"],
            "secondary": d["secondary"],
            "bg": d["surface"],
            "lightBg": l["surface"],
        })
    print(json.dumps(out))


def cmd_render_preset():
    if len(args) < 2:
        sys.exit("Usage: manage-themes.sh render-preset <preset_id> <dark|light>")
    pid = args[0]
    scheme = args[1] if args[1] in ("dark", "light") else "dark"
    if pid not in PRESETS:
        sys.exit(f"Unknown preset: {pid}")
    full = complete_palette(PRESETS[pid][scheme], scheme == "dark")
    write_palette_outputs(full, pid)


def cmd_apply_mango_overrides():
    reload_flag = "--reload" in args
    apply_mango_color_overrides(do_reload=reload_flag)


def cmd_tweak_colors():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh tweak-colors <json>")
    edits = json.loads(args[0])
    cur = load_json_dict(COLORS_JSON)
    is_dark = bool(edits.get("isDark", cur.get("isDark", True)))
    merged_base = dict(cur)
    for k, v in edits.items():
        if k == "isDark":
            is_dark = bool(v)
        elif str(v).strip().startswith("#"):
            merged_base[k] = norm_hex(v, cur.get(k, "#cba6f7"))
    # Clear derived containers so complete_palette recalculates harmonious containers when primary/surface changed
    for k in ("onPrimary", "primaryContainer", "onPrimaryContainer", "onSecondary", "secondaryContainer", "onSecondaryContainer", "onTertiary", "tertiaryContainer", "onTertiaryContainer", "surfaceLow", "surfaceHigh", "surfaceHighest", "onError", "ansi"):
        merged_base.pop(k, None)
    merged_base["surfaceLow"] = mix(merged_base.get("surface", "#1e1e2e"), merged_base.get("background", "#11111b"), 0.5)
    full = complete_palette(merged_base, is_dark)
    write_palette_outputs(full, "tweak")
    apply_mango_color_overrides(do_reload=False)
    st = load_json_dict(STATE_JSON)
    st["mode"] = "custom"
    st["scheme"] = "dark" if is_dark else "light"
    st["customTheme"] = "live-tweak"
    atomic_write(STATE_JSON, json.dumps(st, indent=2) + "\n")
    push_terminal_osc_and_reload()
    print(json.dumps({"applied": "custom"}))


def slugify(name):
    s = re.sub(r"[^a-zA-Z0-9_-]+", "-", name.strip().lower()).strip("-")
    return s or "custom-theme"


def read_custom_themes():
    os.makedirs(CUSTOM_DIR, exist_ok=True)
    items = []
    for p in sorted(glob.glob(os.path.join(CUSTOM_DIR, "*.json"))):
        slug = os.path.basename(p)[:-5]
        d = load_json_dict(p)
        if not d:
            continue
        items.append({
            "slug": slug,
            "name": d.get("_name", slug),
            "isDark": bool(d.get("isDark", True)),
            "primary": norm_hex(d.get("primary"), "#cba6f7"),
            "secondary": norm_hex(d.get("secondary"), "#89b4fa"),
            "surface": norm_hex(d.get("surface"), "#1e1e2e"),
        })
    return items


def cmd_custom_list():
    print(json.dumps({"themes": read_custom_themes()}))


def cmd_custom_save():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh custom-save <name>")
    name = " ".join(args).strip()
    slug = slugify(name)
    cur = load_json_dict(COLORS_JSON)
    if not cur:
        sys.exit("No current colors.json found")
    data = dict(cur)
    data["_name"] = name
    atomic_write(os.path.join(CUSTOM_DIR, f"{slug}.json"), json.dumps(data, indent=2) + "\n")
    print(json.dumps({"saved": slug, "themes": read_custom_themes()}))


def cmd_custom_apply():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh custom-apply <slug> [--no-reload]")
    slug = slugify(args[0])
    no_reload = "--no-reload" in args
    p = os.path.join(CUSTOM_DIR, f"{slug}.json")
    if not os.path.isfile(p):
        sys.exit(f"Custom theme not found: {slug}")
    d = load_json_dict(p)
    is_dark = bool(d.get("isDark", True))
    full = complete_palette(d, is_dark)
    write_palette_outputs(full, f"custom:{slug}")
    if not no_reload:
        apply_mango_color_overrides(do_reload=False)
        st = load_json_dict(STATE_JSON)
        st["mode"] = "custom"
        st["scheme"] = "dark" if is_dark else "light"
        st["customTheme"] = slug
        atomic_write(STATE_JSON, json.dumps(st, indent=2) + "\n")
        push_terminal_osc_and_reload()
    print(json.dumps({"applied": slug}))


def cmd_custom_delete():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh custom-delete <slug>")
    slug = slugify(args[0])
    p = os.path.join(CUSTOM_DIR, f"{slug}.json")
    if os.path.isfile(p):
        os.remove(p)
    print(json.dumps({"themes": read_custom_themes()}))


def cmd_custom_export():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh custom-export <slug>")
    slug = slugify(args[0])
    src = os.path.join(CUSTOM_DIR, f"{slug}.json")
    if not os.path.isfile(src):
        sys.exit(f"Custom theme not found: {slug}")
    dest = os.path.expanduser(f"~/aurora-theme-{slug}.json")
    shutil.copy2(src, dest)
    print(json.dumps({"path": dest}))


def cmd_custom_import():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh custom-import <filepath>")
    src = os.path.expanduser(" ".join(args).strip())
    if not os.path.isfile(src):
        sys.exit(f"File not found: {src}")
    if os.path.getsize(src) > 262144:
        sys.exit("Theme JSON file exceeds 256 KB limit")
    try:
        with open(src, "r", encoding="utf-8") as f:
            d = json.load(f)
    except Exception as exc:
        sys.exit(f"Invalid JSON file: {exc}")
    if not isinstance(d, dict):
        sys.exit("Invalid theme JSON (root must be an object)")

    strict_hex_re = re.compile(r"^#?[0-9a-fA-F]{6}$")
    for req_key in ("primary", "surface"):
        val = d.get(req_key)
        if not isinstance(val, str) or not strict_hex_re.match(val.strip()):
            sys.exit(f"Invalid theme JSON: '{req_key}' must be a #RRGGBB hex color")

    palette_keys = {
        "primary", "onPrimary", "primaryContainer", "onPrimaryContainer",
        "secondary", "onSecondary", "secondaryContainer", "onSecondaryContainer",
        "tertiary", "onTertiary", "tertiaryContainer", "onTertiaryContainer",
        "background", "onBackground", "surface", "surfaceDim", "surfaceBright",
        "surfaceContainerLowest", "surfaceContainerLow", "surfaceLow",
        "surfaceContainer", "surfaceContainerHigh", "surfaceHigh",
        "surfaceContainerHighest", "surfaceHighest",
        "onSurface", "onSurfaceVariant", "outline", "outlineVariant",
        "error", "onError", "success", "warning", "info", "shadow",
    }
    cleaned = {}
    for k, v in d.items():
        if k in palette_keys:
            if not isinstance(v, str) or not strict_hex_re.match(v.strip()):
                sys.exit(f"Invalid hex color for '{k}'")
            cleaned[k] = "#" + v.strip().lstrip("#").lower()
    if isinstance(d.get("ansi"), list) and len(d["ansi"]) == 16:
        ansi_clean = []
        for idx, item in enumerate(d["ansi"]):
            if not isinstance(item, str) or not strict_hex_re.match(item.strip()):
                sys.exit(f"Invalid hex color in ansi[{idx}]")
            ansi_clean.append("#" + item.strip().lstrip("#").lower())
        cleaned["ansi"] = ansi_clean

    raw_dark = d.get("isDark", True)
    is_dark = raw_dark if isinstance(raw_dark, bool) else str(raw_dark).strip().lower() != "false"
    raw_name = d.get("_name") or os.path.basename(src).replace(".json", "")
    safe_name = re.sub(r"[\x00-\x1f\x7f]+", "", str(raw_name)).strip()[:64] or "custom-theme"
    slug = slugify(safe_name)

    validated = complete_palette(cleaned, is_dark)
    validated["_name"] = safe_name
    atomic_write(os.path.join(CUSTOM_DIR, f"{slug}.json"), json.dumps(validated, indent=2) + "\n")
    print(json.dumps({"imported": slug, "themes": read_custom_themes()}))


def cmd_wallpaper_colors():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh wallpaper-colors <image_path>")
    img = os.path.expanduser(" ".join(args).strip())
    cols = []
    if shutil.which("matugen") and os.path.isfile(img):
        try:
            out = subprocess.check_output(
                ["matugen", "image", img, "--show-source-colors", "--dry-run"],
                text=True, stderr=subprocess.STDOUT, timeout=8.0
            )
            cols = re.findall(r"#[0-9a-fA-F]{6}", out)
        except Exception:
            pass
    print(json.dumps({"colors": cols[:6]}))


def cmd_wallpapers_list():
    prefs = load_json_dict(PREFS_JSON)
    wdir = os.path.expanduser(args[0] if args else prefs.get("wallpaperDir", "~/Pictures/Wallpapers"))
    exts = (".jpg", ".jpeg", ".png", ".webp")
    items = []
    if os.path.isdir(wdir):
        for name in sorted(os.listdir(wdir)):
            if name.lower().endswith(exts):
                full = os.path.join(wdir, name)
                if os.path.isfile(full):
                    items.append({"name": name, "path": full})
    print(json.dumps({"dir": wdir, "wallpapers": items}))


def resolve_wp_engine():
    # Match apply-theme.sh & autostart.sh resolution: running daemon first, else awww -> swww
    awww_up = subprocess.run(["pgrep", "-x", "awww-daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    swww_up = subprocess.run(["pgrep", "-x", "swww-daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if awww_up and shutil.which("awww"):
        return "awww", "awww-daemon"
    if swww_up and shutil.which("swww"):
        return "swww", "swww-daemon"
    if shutil.which("awww"):
        return "awww", "awww-daemon"
    if shutil.which("swww"):
        return "swww", "swww-daemon"
    return "", ""


def cmd_solid_wallpaper():
    if len(args) < 1:
        sys.exit("Usage: manage-themes.sh solid-wallpaper <hex>")
    h = norm_hex(args[0], "#1e1e2e")
    prefs = load_json_dict(PREFS_JSON)
    prefs["solidWallpaperColor"] = h
    if os.path.isfile(PREFS_JSON):
        atomic_write(PREFS_JSON, json.dumps(prefs, indent=2) + "\n")
    wp_cmd, daemon_cmd = resolve_wp_engine()
    if wp_cmd:
        if subprocess.run([wp_cmd, "query"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0 and shutil.which(daemon_cmd):
            subprocess.Popen([daemon_cmd], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            import time as _t
            for _ in range(25):
                if subprocess.run([wp_cmd, "query"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                    break
                _t.sleep(0.1)
        subprocess.run([wp_cmd, "clear", h.lstrip("#")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps({"solid": h}))


def cmd_random_wallpaper():
    prefs = load_json_dict(PREFS_JSON)
    st = load_json_dict(STATE_JSON)
    cur_wp = st.get("wallpaper", "")
    wdir = os.path.expanduser(args[0] if args else prefs.get("wallpaperDir", "~/Pictures/Wallpapers"))
    exts = (".jpg", ".jpeg", ".png", ".webp")
    pool = [os.path.join(wdir, n) for n in os.listdir(wdir) if n.lower().endswith(exts)] if os.path.isdir(wdir) else []
    if not pool:
        sys.exit("No wallpapers found in directory")
    candidates = [p for p in pool if p != cur_wp] or pool
    pick = random.choice(candidates)
    subprocess.run([APPLY_THEME_SH, "--wallpaper", pick], check=False)
    print(json.dumps({"wallpaper": pick}))


VIBES = {
    "aurora-glass": {
        "wmMode": "blur", "preset": "catppuccin-mocha", "scheme": "dark",
        "surfaceStyle": "glass", "islandStyle": "pill", "uiRadiusScale": 1.0,
        "borderStyle": "subtle", "uiBorderWidth": 1, "shellOpacity": 0.78, "cardOpacity": 0.38, "mangoShadowTint": False,
    },
    "minimal-square": {
        "wmMode": "simple", "preset": "nord", "scheme": "dark",
        "surfaceStyle": "flat", "islandStyle": "pill", "uiRadiusScale": 0.0,
        "borderStyle": "subtle", "uiBorderWidth": 1, "shellOpacity": 1.00, "cardOpacity": 1.00, "mangoShadowTint": False,
    },
    "oled-stealth": {
        "wmMode": "default", "preset": "oled-black", "scheme": "dark",
        "surfaceStyle": "oled", "islandStyle": "notch", "uiRadiusScale": 1.0,
        "borderStyle": "subtle", "uiBorderWidth": 1, "shellOpacity": 0.98, "cardOpacity": 0.65, "mangoShadowTint": False,
    },
    "neon-cyber": {
        "wmMode": "blur", "preset": "cyberpunk", "scheme": "dark",
        "surfaceStyle": "tinted", "islandStyle": "pill", "uiRadiusScale": 0.8,
        "borderStyle": "glow", "uiBorderWidth": 1, "shellOpacity": 0.76, "cardOpacity": 0.44, "mangoShadowTint": True,
    },
    "cozy-paper": {
        "wmMode": "default", "preset": "rose-pine", "scheme": "light",
        "surfaceStyle": "flat", "islandStyle": "pill", "uiRadiusScale": 1.0,
        "borderStyle": "subtle", "uiBorderWidth": 1, "shellOpacity": 0.96, "cardOpacity": 0.72, "mangoShadowTint": False,
    },
    "full-dock-bar": {
        "wmMode": "blur", "preset": "tokyo-night", "scheme": "dark",
        "surfaceStyle": "glass", "islandStyle": "bar", "uiRadiusScale": 0.6,
        "borderStyle": "accent", "uiBorderWidth": 1, "shellOpacity": 0.82, "cardOpacity": 0.42, "mangoShadowTint": False,
    },
    "warm-gruvbox": {
        "label": "Warm Gruvbox",
        "wmMode": "default", "preset": "gruvbox", "scheme": "dark",
        "surfaceStyle": "default", "islandStyle": "pill", "uiRadiusScale": 0.5,
        "borderStyle": "subtle", "uiBorderWidth": 1, "shellOpacity": 0.95, "cardOpacity": 0.55, "mangoShadowTint": False,
    },
    "dracula-notch": {
        "wmMode": "blur", "preset": "dracula", "scheme": "dark",
        "surfaceStyle": "glass", "islandStyle": "notch", "uiRadiusScale": 1.2,
        "borderStyle": "accent", "uiBorderWidth": 1, "shellOpacity": 0.76, "cardOpacity": 0.40, "mangoShadowTint": True,
    },
}


def cmd_apply_vibe():
    if len(args) < 1 or args[0] not in VIBES:
        sys.exit("Usage: manage-themes.sh apply-vibe <" + "|".join(VIBES.keys()) + ">")
    v = VIBES[args[0]]
    prefs = load_json_dict(PREFS_JSON)
    for k in ("surfaceStyle", "islandStyle", "uiRadiusScale", "borderStyle", "uiBorderWidth", "shellOpacity", "cardOpacity", "mangoShadowTint"):
        prefs[k] = v[k]
    atomic_write(PREFS_JSON, json.dumps(prefs, indent=2) + "\n")
    subprocess.run([APPLY_MODE_SH, v["wmMode"], "--no-reload"], check=False)
    subprocess.run([APPLY_THEME_SH, "--mode", "preset", "--preset", v["preset"], "--scheme", v["scheme"], "--no-wallpaper"], check=False)
    print(json.dumps({"vibe": args[0]}))


MUTATING_CMDS = {
    "render-preset",
    "apply-mango-overrides",
    "tweak-colors",
    "custom-save",
    "custom-apply",
    "custom-delete",
    "custom-import",
    "solid-wallpaper",
    "random-wallpaper",
    "apply-vibe",
}
_LOCK_FH = None


def acquire_theme_lock():
    global _LOCK_FH
    if cmd not in MUTATING_CMDS or os.environ.get("MANGO_THEME_LOCKED") == "1":
        return
    try:
        import fcntl
        rdir = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(
            os.path.expanduser(os.environ.get("XDG_CACHE_HOME", "~/.cache")),
            "quickshell",
        )
        os.makedirs(rdir, mode=0o700, exist_ok=True)
        lpath = os.path.join(rdir, "aurora-theme.lock")
        _LOCK_FH = open(lpath, "w", encoding="utf-8")
        fcntl.flock(_LOCK_FH.fileno(), fcntl.LOCK_EX)
        os.environ["MANGO_THEME_LOCKED"] = "1"
    except Exception:
        pass


DISPATCH = {
    "list-presets": cmd_list_presets,
    "render-preset": cmd_render_preset,
    "apply-mango-overrides": cmd_apply_mango_overrides,
    "tweak-colors": cmd_tweak_colors,
    "custom-list": cmd_custom_list,
    "custom-save": cmd_custom_save,
    "custom-apply": cmd_custom_apply,
    "custom-delete": cmd_custom_delete,
    "custom-export": cmd_custom_export,
    "custom-import": cmd_custom_import,
    "wallpaper-colors": cmd_wallpaper_colors,
    "wallpapers-list": cmd_wallpapers_list,
    "solid-wallpaper": cmd_solid_wallpaper,
    "random-wallpaper": cmd_random_wallpaper,
    "apply-vibe": cmd_apply_vibe,
}

acquire_theme_lock()
DISPATCH[cmd]()
PY
