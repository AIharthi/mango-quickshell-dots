#!/usr/bin/env bash
set -euo pipefail

# Unified Dynamic Theme & Live GTK/WM/Terminal Sync Pipeline
# Synchronizes: swww/awww wallpaper -> Quickshell colors.json -> GTK3/GTK4 CSS & gsettings
#               -> MangoWC theme.conf -> Foot & Kitty live terminal colors.

QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
COLORS_JSON="$QUICKSHELL_DIR/colors.json"
STATE_JSON="$QUICKSHELL_DIR/theme-state.json"
MANGO_THEME="$CONFIG_DIR/mango/theme.conf"
GTK3_DIR="$CONFIG_DIR/gtk-3.0"
GTK4_DIR="$CONFIG_DIR/gtk-4.0"
FOOT_DIR="$CONFIG_DIR/foot"
KITTY_DIR="$CONFIG_DIR/kitty"

mkdir -p "$QUICKSHELL_DIR" "$CONFIG_DIR/mango" "$GTK3_DIR" "$GTK4_DIR" "$FOOT_DIR" "$KITTY_DIR"

if [[ "${MANGO_THEME_LOCKED:-0}" != "1" ]] && command -v flock >/dev/null 2>&1; then
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mango-theme-$(id -u).lock"
    exec 9>"$LOCK_FILE"
    flock -x 9
    export MANGO_THEME_LOCKED=1
fi

# --- Read Existing State Defaults ---
DEFAULT_MODE="preset"
DEFAULT_SCHEME="dark"
DEFAULT_PRESET="catppuccin-mocha"
DEFAULT_WALLPAPER=""
DEFAULT_ACCENT="#cba6f7"
DEFAULT_CUSTOM=""

if [[ -f "$STATE_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    IFS=$'\t' read -r DEFAULT_MODE DEFAULT_SCHEME DEFAULT_PRESET DEFAULT_WALLPAPER DEFAULT_ACCENT DEFAULT_CUSTOM < <(
        python3 - "$STATE_JSON" "$DEFAULT_MODE" "$DEFAULT_SCHEME" "$DEFAULT_PRESET" "$DEFAULT_WALLPAPER" "$DEFAULT_ACCENT" "$DEFAULT_CUSTOM" <<'PY'
import json, sys
path, d_mode, d_scheme, d_preset, d_wall, d_acc, d_cust = sys.argv[1:8]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    print(
        data.get("mode", d_mode),
        data.get("scheme", d_scheme),
        data.get("preset", d_preset),
        data.get("wallpaper", d_wall),
        data.get("accent", d_acc) or d_acc,
        data.get("customTheme", d_cust) or "",
        sep="\t",
    )
except Exception:
    print(d_mode, d_scheme, d_preset, d_wall, d_acc, d_cust, sep="\t")
PY
    )
fi

MODE="$DEFAULT_MODE"
SCHEME="$DEFAULT_SCHEME"
PRESET="$DEFAULT_PRESET"
WALLPAPER="$DEFAULT_WALLPAPER"
ACCENT="$DEFAULT_ACCENT"
CUSTOM_THEME="$DEFAULT_CUSTOM"
SET_WALLPAPER=1
INIT_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="${2:?Missing value for --mode}"
            shift 2
            ;;
        --scheme)
            SCHEME="${2:?Missing value for --scheme}"
            shift 2
            ;;
        --preset)
            PRESET="${2:?Missing value for --preset}"
            shift 2
            ;;
        --accent)
            ACCENT="${2:?Missing value for --accent}"
            shift 2
            ;;
        --custom)
            CUSTOM_THEME="${2-}"
            shift 2
            ;;
        --wallpaper)
            WALLPAPER="${2:?Missing value for --wallpaper}"
            shift 2
            ;;
        --no-wallpaper)
            SET_WALLPAPER=0
            shift
            ;;
        --init)
            INIT_ONLY=1
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: apply-theme.sh [OPTIONS]
  --mode <dynamic|preset|accent|custom>
  --scheme <dark|light>
  --preset <preset-id>
  --accent <#RRGGBB>
  --custom <slug>
  --wallpaper <path>
  --no-wallpaper
  --init
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ "$MODE" != "dynamic" && "$MODE" != "preset" && "$MODE" != "accent" && "$MODE" != "custom" ]]; then
    echo "Invalid mode: $MODE (expected dynamic, preset, accent, or custom)" >&2
    exit 1
fi
if [[ "$SCHEME" != "dark" && "$SCHEME" != "light" ]]; then
    echo "Invalid scheme: $SCHEME (expected dark or light)" >&2
    exit 1
fi

# --- Atomic Write Helper ---
atomic_write() {
    local target="$1"
    local tmp="${target}.tmp.$$"
    cat > "$tmp"
    mv -f "$tmp" "$target"
}

# --- Wallpaper Engine (running daemon first, else awww -> swww) ---
apply_wallpaper() {
    local img="$1"
    [[ -f "$img" ]] || return 0

    local wp_cmd=""
    local daemon_cmd=""
    if pgrep -x awww-daemon >/dev/null 2>&1 && command -v awww >/dev/null 2>&1; then
        wp_cmd="awww"
        daemon_cmd="awww-daemon"
    elif pgrep -x swww-daemon >/dev/null 2>&1 && command -v swww >/dev/null 2>&1; then
        wp_cmd="swww"
        daemon_cmd="swww-daemon"
    elif command -v awww >/dev/null 2>&1; then
        wp_cmd="awww"
        daemon_cmd="awww-daemon"
    elif command -v swww >/dev/null 2>&1; then
        wp_cmd="swww"
        daemon_cmd="swww-daemon"
    else
        echo "Warning: neither awww nor swww found in PATH; skipping wallpaper update." >&2
        return 0
    fi

    if ! "$wp_cmd" query >/dev/null 2>&1; then
        if command -v "$daemon_cmd" >/dev/null 2>&1; then
            nohup "$daemon_cmd" >/dev/null 2>&1 &
            local _i
            for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
                if "$wp_cmd" query >/dev/null 2>&1; then
                    break
                fi
                sleep 0.1
            done
        fi
    fi

    local wp_trans="grow" wp_fps="60" wp_dur="0.85" wp_resize="crop"
    local prefs_file="$QUICKSHELL_DIR/shell-prefs.json"
    if [[ -f "$prefs_file" ]] && command -v python3 >/dev/null 2>&1; then
        IFS=$'\t' read -r wp_trans wp_fps wp_dur wp_resize < <(
            python3 - "$prefs_file" <<'PY' 2>/dev/null || printf 'grow\t60\t0.85\tcrop\n'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    tr = str(d.get("wallpaperTransition", "grow")).strip() or "grow"
    fps = max(24, min(240, int(d.get("wallpaperFps", 60))))
    dur = max(0.1, min(3.0, float(d.get("wallpaperDuration", 0.85))))
    rz = str(d.get("wallpaperResize", "crop")).strip() or "crop"
    print(f"{tr}\t{fps}\t{dur:.2f}\t{rz}")
except Exception:
    print("grow\t60\t0.85\tcrop")
PY
        )
    fi

    "$wp_cmd" img "$img" \
        --transition-type "$wp_trans" \
        --transition-pos 0.5,0.05 \
        --transition-fps "$wp_fps" \
        --transition-duration "$wp_dur" \
        --resize "$wp_resize" \
        >/dev/null 2>&1 || true
}

# --- Preset Palette Table ---
declare -A C

set_palette() {
    local is_dark="$1"
    local primary="$2" on_primary="$3" primary_cont="$4" on_primary_cont="$5"
    local secondary="$6" on_secondary="$7" secondary_cont="$8" on_secondary_cont="$9"
    local tertiary="${10}" on_tertiary="${11}" tertiary_cont="${12}" on_tertiary_cont="${13}"
    local bg="${14}" on_bg="${15}" surface="${16}" surface_dim="${17}" surface_bright="${18}"
    local sc_lowest="${19}" sc_low="${20}" sc="${21}" sc_high="${22}" sc_highest="${23}"
    local on_surface="${24}" on_surface_var="${25}" outline="${26}" outline_var="${27}"
    local error="${28}" on_error="${29}" success="${30}" warning="${31}" info="${32}"
    shift 32

    C[isDark]="$is_dark"
    C[primary]="$primary";           C[onPrimary]="$on_primary"
    C[primaryContainer]="$primary_cont"; C[onPrimaryContainer]="$on_primary_cont"
    C[secondary]="$secondary";       C[onSecondary]="$on_secondary"
    C[secondaryContainer]="$secondary_cont"; C[onSecondaryContainer]="$on_secondary_cont"
    C[tertiary]="$tertiary";         C[onTertiary]="$on_tertiary"
    C[tertiaryContainer]="$tertiary_cont"; C[onTertiaryContainer]="$on_tertiary_cont"
    C[background]="$bg";             C[onBackground]="$on_bg"
    C[surface]="$surface";           C[surfaceDim]="$surface_dim"; C[surfaceBright]="$surface_bright"
    C[surfaceContainerLowest]="$sc_lowest"
    C[surfaceContainerLow]="$sc_low"
    C[surfaceContainer]="$sc"
    C[surfaceContainerHigh]="$sc_high"
    C[surfaceContainerHighest]="$sc_highest"
    C[onSurface]="$on_surface";      C[onSurfaceVariant]="$on_surface_var"
    C[outline]="$outline";           C[outlineVariant]="$outline_var"
    C[error]="$error";               C[onError]="$on_error"
    C[success]="$success";           C[warning]="$warning";       C[info]="$info"
    C[shadow]="#000000"

    local idx=0
    for hex in "$@"; do
        C["ansi${idx}"]="$hex"
        idx=$((idx + 1))
    done
}

load_preset_palette() {
    local preset="$1"
    local scheme="$2"

    case "${preset}:${scheme}" in
        catppuccin-mocha:dark)
            set_palette true \
                "#cba6f7" "#11111b" "#3e2f56" "#f2e5ff" \
                "#89b4fa" "#11111b" "#293954" "#dce9ff" \
                "#f5c2e7" "#11111b" "#4b3146" "#ffe4f7" \
                "#11111b" "#cdd6f4" "#1e1e2e" "#181825" "#313244" \
                "#11111b" "#181825" "#1e1e2e" "#313244" "#45475a" \
                "#cdd6f4" "#a6adc8" "#6c7086" "#313244" \
                "#f38ba8" "#11111b" "#a6e3a1" "#f9e2af" "#89dceb" \
                "#45475a" "#f38ba8" "#a6e3a1" "#f9e2af" "#89b4fa" "#f5c2e7" "#94e2d5" "#bac2de" \
                "#585b70" "#f38ba8" "#a6e3a1" "#f9e2af" "#89b4fa" "#f5c2e7" "#94e2d5" "#a6adc8"
            ;;
        catppuccin-mocha:light)
            set_palette false \
                "#8839ef" "#ffffff" "#dfd0f9" "#2b0859" \
                "#1e66f5" "#ffffff" "#d3e2fd" "#07245e" \
                "#ea76cb" "#ffffff" "#fad9f1" "#4f1040" \
                "#eff1f5" "#4c4f69" "#eff1f5" "#dce0e8" "#ffffff" \
                "#ffffff" "#e6e9ef" "#e6e9ef" "#ccd0da" "#bcc0cc" \
                "#4c4f69" "#6c6f85" "#8c8fa1" "#ccd0da" \
                "#d20f39" "#ffffff" "#40a02b" "#df8e1d" "#04a5e5" \
                "#5c5f77" "#d20f39" "#40a02b" "#df8e1d" "#1e66f5" "#ea76cb" "#179299" "#acb0be" \
                "#6c6f85" "#d20f39" "#40a02b" "#df8e1d" "#1e66f5" "#ea76cb" "#179299" "#4c4f69"
            ;;
        tokyo-night:dark)
            set_palette true \
                "#7aa2f7" "#15161e" "#2b3b63" "#dbe6ff" \
                "#bb9af7" "#15161e" "#392f59" "#efe5ff" \
                "#7dcfff" "#15161e" "#204459" "#d8f4ff" \
                "#16161e" "#c0caf5" "#1a1b26" "#16161e" "#292e42" \
                "#15161e" "#1a1b26" "#1f2335" "#292e42" "#3b4261" \
                "#c0caf5" "#9aa5ce" "#565f89" "#292e42" \
                "#f7768e" "#15161e" "#9ece6a" "#e0af68" "#7dcfff" \
                "#15161e" "#f7768e" "#9ece6a" "#e0af68" "#7aa2f7" "#bb9af7" "#7dcfff" "#a9b1d6" \
                "#414868" "#f7768e" "#9ece6a" "#e0af68" "#7aa2f7" "#bb9af7" "#7dcfff" "#c0caf5"
            ;;
        tokyo-night:light)
            set_palette false \
                "#2e7de9" "#ffffff" "#c9ddfc" "#0b2859" \
                "#9854f1" "#ffffff" "#e5d6fc" "#320b63" \
                "#007197" "#ffffff" "#c4e9f5" "#002e40" \
                "#e1e2e7" "#3760bf" "#e1e2e7" "#c4c8da" "#f4f5fa" \
                "#eef0f6" "#d5d6db" "#d5d6db" "#c4c8da" "#b4b8cc" \
                "#3760bf" "#6172b0" "#848cb5" "#c4c8da" \
                "#f52a65" "#ffffff" "#587539" "#8c6c3e" "#007197" \
                "#e9e9ed" "#f52a65" "#587539" "#8c6c3e" "#2e7de9" "#9854f1" "#007197" "#6172b0" \
                "#a1a6c5" "#f52a65" "#587539" "#8c6c3e" "#2e7de9" "#9854f1" "#007197" "#3760bf"
            ;;
        gruvbox:dark)
            set_palette true \
                "#fabd2f" "#1d2021" "#4f3d16" "#fae6b1" \
                "#83a598" "#1d2021" "#2b3b37" "#d3e5de" \
                "#fe8019" "#1d2021" "#542d12" "#ffd8ba" \
                "#1d2021" "#ebdbb2" "#282828" "#1d2021" "#3c3836" \
                "#1d2021" "#282828" "#282828" "#3c3836" "#504945" \
                "#ebdbb2" "#bdae93" "#665c54" "#3c3836" \
                "#fb4934" "#1d2021" "#b8bb26" "#fabd2f" "#8ec07c" \
                "#282828" "#cc241d" "#98971a" "#d79921" "#458588" "#b16286" "#689d6a" "#a89984" \
                "#928374" "#fb4934" "#b8bb26" "#fabd2f" "#83a598" "#d3869b" "#8ec07c" "#ebdbb2"
            ;;
        gruvbox:light)
            set_palette false \
                "#b57614" "#fbf1c7" "#ebdbb2" "#3c2706" \
                "#076678" "#fbf1c7" "#d3e4e0" "#032e36" \
                "#af3a03" "#fbf1c7" "#f4d6c4" "#421501" \
                "#fbf1c7" "#3c3836" "#fbf1c7" "#ebdbb2" "#f9f5d7" \
                "#f9f5d7" "#f2e5bc" "#f2e5bc" "#ebdbb2" "#d5c4a1" \
                "#3c3836" "#665c54" "#928374" "#d5c4a1" \
                "#9d0006" "#fbf1c7" "#79740e" "#b57614" "#427b58" \
                "#fbf1c7" "#cc241d" "#98971a" "#d79921" "#458588" "#b16286" "#689d6a" "#7c6f64" \
                "#928374" "#9d0006" "#79740e" "#b57614" "#076678" "#8f3f71" "#427b58" "#3c3836"
            ;;
        nord:dark)
            set_palette true \
                "#88c0d0" "#242933" "#2f4956" "#d9f0f7" \
                "#81a1c1" "#242933" "#2f3f52" "#dae6f2" \
                "#b48ead" "#242933" "#473645" "#f3e4f0" \
                "#242933" "#eceff4" "#2e3440" "#242933" "#3b4252" \
                "#242933" "#2e3440" "#2e3440" "#3b4252" "#434c5e" \
                "#eceff4" "#d8dee9" "#4c566a" "#3b4252" \
                "#bf616a" "#eceff4" "#a3be8c" "#ebcb8b" "#8fbcbb" \
                "#3b4252" "#bf616a" "#a3be8c" "#ebcb8b" "#81a1c1" "#b48ead" "#88c0d0" "#e5e9f0" \
                "#4c566a" "#bf616a" "#a3be8c" "#ebcb8b" "#81a1c1" "#b48ead" "#8fbcbb" "#eceff4"
            ;;
        nord:light)
            set_palette false \
                "#5e81ac" "#eceff4" "#d4e0ee" "#1f3147" \
                "#4c566a" "#eceff4" "#d8dee9" "#242933" \
                "#b48ead" "#242933" "#eddce9" "#3e273a" \
                "#eceff4" "#2e3440" "#eceff4" "#d8dee9" "#ffffff" \
                "#f8f9fc" "#e5e9f0" "#e5e9f0" "#d8dee9" "#c8d0e0" \
                "#2e3440" "#4c566a" "#7b88a1" "#d8dee9" \
                "#bf616a" "#eceff4" "#73935c" "#b88936" "#4f8f9b" \
                "#2e3440" "#bf616a" "#a3be8c" "#ebcb8b" "#5e81ac" "#b48ead" "#88c0d0" "#4c566a" \
                "#434c5e" "#bf616a" "#a3be8c" "#ebcb8b" "#5e81ac" "#b48ead" "#8fbcbb" "#3b4252"
            ;;
        *)
            echo "Unknown preset: $preset" >&2
            exit 1
            ;;
    esac
}

strip_hash() {
    echo "${1#\#}"
}

# --- Writers for Preset Mode ---
write_colors_json() {
    atomic_write "$COLORS_JSON" <<EOF
{
  "isDark": ${C[isDark]},
  "primary": "${C[primary]}",
  "onPrimary": "${C[onPrimary]}",
  "primaryContainer": "${C[primaryContainer]}",
  "onPrimaryContainer": "${C[onPrimaryContainer]}",
  "secondary": "${C[secondary]}",
  "onSecondary": "${C[onSecondary]}",
  "secondaryContainer": "${C[secondaryContainer]}",
  "onSecondaryContainer": "${C[onSecondaryContainer]}",
  "tertiary": "${C[tertiary]}",
  "onTertiary": "${C[onTertiary]}",
  "tertiaryContainer": "${C[tertiaryContainer]}",
  "onTertiaryContainer": "${C[onTertiaryContainer]}",
  "background": "${C[background]}",
  "onBackground": "${C[onBackground]}",
  "surface": "${C[surface]}",
  "surfaceDim": "${C[surfaceDim]}",
  "surfaceBright": "${C[surfaceBright]}",
  "surfaceContainerLowest": "${C[surfaceContainerLowest]}",
  "surfaceContainerLow": "${C[surfaceContainerLow]}",
  "surfaceContainer": "${C[surfaceContainer]}",
  "surfaceContainerHigh": "${C[surfaceContainerHigh]}",
  "surfaceContainerHighest": "${C[surfaceContainerHighest]}",
  "onSurface": "${C[onSurface]}",
  "onSurfaceVariant": "${C[onSurfaceVariant]}",
  "outline": "${C[outline]}",
  "outlineVariant": "${C[outlineVariant]}",
  "error": "${C[error]}",
  "onError": "${C[onError]}",
  "success": "${C[success]}",
  "warning": "${C[warning]}",
  "info": "${C[info]}",
  "shadow": "${C[shadow]}"
}
EOF
}

write_gtk_css() {
    local target="$1"
    local kind="$2" # gtk3 | gtk4

    {
        cat <<EOF
/* Auto-generated by apply-theme.sh (${PRESET} / ${SCHEME}) */
@define-color accent_color ${C[primary]};
@define-color accent_bg_color ${C[primary]};
@define-color accent_fg_color ${C[onPrimary]};
@define-color destructive_color ${C[error]};
@define-color destructive_bg_color ${C[error]};
@define-color destructive_fg_color ${C[onError]};
@define-color success_color ${C[success]};
@define-color success_bg_color ${C[success]};
@define-color success_fg_color ${C[onPrimary]};
@define-color warning_color ${C[warning]};
@define-color warning_bg_color ${C[warning]};
@define-color warning_fg_color ${C[onPrimary]};
@define-color error_color ${C[error]};
@define-color error_bg_color ${C[error]};
@define-color error_fg_color ${C[onError]};
@define-color window_bg_color ${C[surface]};
@define-color window_fg_color ${C[onSurface]};
@define-color view_bg_color ${C[surfaceContainerLow]};
@define-color view_fg_color ${C[onSurface]};
@define-color headerbar_bg_color ${C[surfaceContainer]};
@define-color headerbar_fg_color ${C[onSurface]};
@define-color headerbar_border_color ${C[outlineVariant]};
@define-color headerbar_backdrop_color ${C[surfaceContainerLowest]};
@define-color card_bg_color ${C[surfaceContainerHigh]};
@define-color card_fg_color ${C[onSurface]};
@define-color dialog_bg_color ${C[surfaceContainer]};
@define-color dialog_fg_color ${C[onSurface]};
@define-color popover_bg_color ${C[surfaceContainerLow]};
@define-color popover_fg_color ${C[onSurface]};
@define-color sidebar_bg_color ${C[surfaceContainerLow]};
@define-color sidebar_fg_color ${C[onSurface]};
@define-color sidebar_backdrop_color ${C[surfaceContainerLowest]};
EOF
        if [[ "$kind" == "gtk3" ]]; then
            cat <<EOF
@define-color theme_fg_color ${C[onSurface]};
@define-color theme_text_color ${C[onSurface]};
@define-color theme_bg_color ${C[surface]};
@define-color theme_base_color ${C[surfaceContainerLow]};
@define-color theme_selected_bg_color ${C[primary]};
@define-color theme_selected_fg_color ${C[onPrimary]};
@define-color insensitive_bg_color ${C[surfaceContainerLow]};
@define-color insensitive_fg_color ${C[onSurfaceVariant]};
@define-color insensitive_base_color ${C[surface]};
@define-color theme_unfocused_fg_color ${C[onSurfaceVariant]};
@define-color theme_unfocused_text_color ${C[onSurface]};
@define-color theme_unfocused_bg_color ${C[surface]};
@define-color theme_unfocused_base_color ${C[surfaceContainerLow]};
@define-color theme_unfocused_selected_bg_color ${C[surfaceContainerHigh]};
@define-color theme_unfocused_selected_fg_color ${C[onSurface]};
@define-color borders ${C[outlineVariant]};
@define-color unfocused_borders ${C[outlineVariant]};

decoration,
window.csd > decoration,
window.solid-csd > decoration,
.csd,
.solid-csd {
    box-shadow: none;
    margin: 0px;
    padding: 0px;
    border: none;
    border-width: 0px;
    border-radius: 0px;
    background: transparent;
}

headerbar,
.titlebar {
    background-image: none;
    background-color: ${C[surfaceContainer]};
    color: ${C[onSurface]};
    border: none;
    box-shadow: none;
    border-radius: 0px;
}

headerbar button.titlebutton,
.titlebar button.titlebutton {
    opacity: 0;
    min-width: 0;
    min-height: 0;
    padding: 0;
    margin: 0;
}

dialog,
messagedialog,
popover,
menu,
.context-menu {
    background-color: ${C[surfaceContainerLow]};
    color: ${C[onSurface]};
    border: none;
}

entry,
textview,
treeview,
.view {
    background-color: ${C[surfaceContainerLow]};
    color: ${C[onSurface]};
}

selection,
*:selected {
    background-color: ${C[primary]};
    color: ${C[onPrimary]};
}
EOF
        else
            cat <<EOF
@define-color theme_fg_color ${C[onSurface]};
@define-color theme_text_color ${C[onSurface]};
@define-color theme_bg_color ${C[surface]};
@define-color theme_base_color ${C[surfaceContainerLow]};
@define-color theme_selected_bg_color ${C[primary]};
@define-color theme_selected_fg_color ${C[onPrimary]};

window,
window.csd,
window.solid-csd {
    background-color: ${C[surface]};
    color: ${C[onSurface]};
    outline: none;
    box-shadow: none;
    margin: 0px;
    border: none;
    border-radius: 0px;
}

headerbar,
.titlebar {
    background-color: ${C[surfaceContainer]};
    color: ${C[onSurface]};
    border: none;
    box-shadow: none;
    border-radius: 0px;
}

popover > contents,
dialog,
messagedialog {
    background-color: ${C[surfaceContainerLow]};
    color: ${C[onSurface]};
    border: none;
}

entry,
textview,
.view {
    background-color: ${C[surfaceContainerLow]};
    color: ${C[onSurface]};
}

selection,
*:selected {
    background-color: ${C[primary]};
    color: ${C[onPrimary]};
}

windowcontrols {
    opacity: 0;
    min-width: 0;
    min-height: 0;
}
EOF
        fi
    } | atomic_write "$target"
}

write_mango_theme() {
    atomic_write "$MANGO_THEME" <<EOF
# Auto-generated by apply-theme.sh (${PRESET} / ${SCHEME})
root_color=0x$(strip_hash "${C[background]}")ff
border_color=0x$(strip_hash "${C[outlineVariant]}")ff
focus_color=0x$(strip_hash "${C[primary]}")ff
maximized_screen_color=0x$(strip_hash "${C[secondary]}")ff
urgent_color=0x$(strip_hash "${C[error]}")ff
scratchpad_color=0x$(strip_hash "${C[tertiary]}")ff
global_color=0x$(strip_hash "${C[secondary]}")ff
overlay_color=0x$(strip_hash "${C[primaryContainer]}")ff
drop_color=0x$(strip_hash "${C[primary]}")55
split_color=0x$(strip_hash "${C[tertiary]}")ff
shadows_color=0x$(strip_hash "${C[shadow]}")cc
dim_focused_color=0x00000000
dim_unfocused_color=0x00000044
EOF
}

write_terminal_configs() {
    atomic_write "$FOOT_DIR/colors.ini" <<EOF
# Auto-generated by apply-theme.sh (${PRESET} / ${SCHEME})
[colors]
alpha=0.92
background=$(strip_hash "${C[surfaceContainerLowest]}")
foreground=$(strip_hash "${C[onSurface]}")
cursor=$(strip_hash "${C[onPrimary]}") $(strip_hash "${C[primary]}")
selection-foreground=$(strip_hash "${C[onPrimaryContainer]}")
selection-background=$(strip_hash "${C[primaryContainer]}")

regular0=$(strip_hash "${C[ansi0]}")
regular1=$(strip_hash "${C[ansi1]}")
regular2=$(strip_hash "${C[ansi2]}")
regular3=$(strip_hash "${C[ansi3]}")
regular4=$(strip_hash "${C[ansi4]}")
regular5=$(strip_hash "${C[ansi5]}")
regular6=$(strip_hash "${C[ansi6]}")
regular7=$(strip_hash "${C[ansi7]}")

bright0=$(strip_hash "${C[ansi8]}")
bright1=$(strip_hash "${C[ansi9]}")
bright2=$(strip_hash "${C[ansi10]}")
bright3=$(strip_hash "${C[ansi11]}")
bright4=$(strip_hash "${C[ansi12]}")
bright5=$(strip_hash "${C[ansi13]}")
bright6=$(strip_hash "${C[ansi14]}")
bright7=$(strip_hash "${C[ansi15]}")
EOF

    atomic_write "$KITTY_DIR/colors.conf" <<EOF
# Auto-generated by apply-theme.sh (${PRESET} / ${SCHEME})
foreground ${C[onSurface]}
background ${C[surfaceContainerLowest]}
background_opacity 0.92
cursor ${C[primary]}
cursor_text_color ${C[onPrimary]}
selection_foreground ${C[onPrimaryContainer]}
selection_background ${C[primaryContainer]}
url_color ${C[secondary]}

active_border_color ${C[primary]}
inactive_border_color ${C[outlineVariant]}
active_tab_foreground ${C[onPrimary]}
active_tab_background ${C[primary]}
inactive_tab_foreground ${C[onSurfaceVariant]}
inactive_tab_background ${C[surfaceContainer]}

color0 ${C[ansi0]}
color1 ${C[ansi1]}
color2 ${C[ansi2]}
color3 ${C[ansi3]}
color4 ${C[ansi4]}
color5 ${C[ansi5]}
color6 ${C[ansi6]}
color7 ${C[ansi7]}

color8 ${C[ansi8]}
color9 ${C[ansi9]}
color10 ${C[ansi10]}
color11 ${C[ansi11]}
color12 ${C[ansi12]}
color13 ${C[ansi13]}
color14 ${C[ansi14]}
color15 ${C[ansi15]}
EOF
}

ensure_terminal_includes() {
    if [[ ! -f "$FOOT_DIR/foot.ini" ]]; then
        cat > "$FOOT_DIR/foot.ini" <<'EOF'
font=JetBrains Mono:size=10
pad=10x10
include=~/.config/foot/colors.ini
EOF
    elif ! grep -q "colors.ini" "$FOOT_DIR/foot.ini"; then
        printf '\ninclude=~/.config/foot/colors.ini\n' >> "$FOOT_DIR/foot.ini"
    fi

    if [[ ! -f "$KITTY_DIR/kitty.conf" ]]; then
        cat > "$KITTY_DIR/kitty.conf" <<'EOF'
font_family JetBrains Mono
font_size 10.5
window_padding_width 10
confirm_os_window_close 0
include colors.conf
EOF
    elif ! grep -q "colors.conf" "$KITTY_DIR/kitty.conf"; then
        printf '\ninclude colors.conf\n' >> "$KITTY_DIR/kitty.conf"
    fi
}

# --- GTK Live Sync via gsettings & settings.ini ---
apply_gtk_settings() {
    local prefer_dark=1
    local color_scheme="prefer-dark"
    local theme_name="adw-gtk3-dark"

    if [[ "$SCHEME" == "light" ]]; then
        prefer_dark=0
        color_scheme="prefer-light"
        theme_name="adw-gtk3"
    fi

    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    if [[ ! -d "/usr/share/themes/${theme_name}" && ! -d "${data_home}/themes/${theme_name}" ]]; then
        if [[ "$SCHEME" == "dark" ]]; then
            theme_name="Adwaita-dark"
        else
            theme_name="Adwaita"
        fi
    fi

    local cursor_theme="catppuccin-mocha-dark-cursors"
    local cursor_size="24"
    for cfg_src in "$CONFIG_DIR/mango/config.conf" "$CONFIG_DIR/mango/local.conf"; do
        if [[ -f "$cfg_src" ]]; then
            local ct cs
            ct=$(awk -F= '/^[[:space:]]*cursor_theme[[:space:]]*=/{val=$2} END{gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val}' "$cfg_src")
            cs=$(awk -F= '/^[[:space:]]*cursor_size[[:space:]]*=/{val=$2} END{gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val}' "$cfg_src")
            [[ -n "$ct" ]] && cursor_theme="$ct"
            [[ -n "$cs" ]] && cursor_size="$cs"
        fi
    done

    local font_name="JetBrains Mono 10"
    local icon_theme="Adwaita"
    local prefs_file="$QUICKSHELL_DIR/shell-prefs.json"
    if [[ -f "$prefs_file" ]]; then
        local parsed_font parsed_icon
        IFS=$'\t' read -r parsed_icon parsed_font < <(python3 - "$prefs_file" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    ic = str(d.get("iconTheme", "Adwaita")).strip() or "Adwaita"
    fam = str(d.get("uiFontFamily", "")).strip()
    sz = int(d.get("uiFontSize", 10))
    print(f"{ic}\t{fam} {sz}" if fam else f"{ic}\tJetBrains Mono 10")
except Exception:
    pass
PY
)
        if [[ -n "${parsed_icon:-}" ]]; then
            icon_theme="$parsed_icon"
        fi
        if [[ -n "${parsed_font:-}" ]]; then
            font_name="$parsed_font"
        fi
    fi

    for ini in "$GTK3_DIR/settings.ini" "$GTK4_DIR/settings.ini"; do
        atomic_write "$ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=${prefer_dark}
gtk-theme-name=${theme_name}
gtk-icon-theme-name=${icon_theme}
gtk-font-name=${font_name}
gtk-cursor-theme-name=${cursor_theme}
gtk-cursor-theme-size=${cursor_size}
EOF
    done

    if command -v gsettings >/dev/null 2>&1; then
        local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if [[ ( -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS:-}" == "disabled:" ) && -S "${runtime_dir}/bus" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus"
        fi
        local pulse_theme="Adwaita"
        [[ "$SCHEME" == "light" ]] && pulse_theme="Adwaita-dark"
        # Momentary value change forces running GTK3/GTK4 apps & xdg-desktop-portal to reload gtk.css live
        gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-size "$cursor_size" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface font-name "$font_name" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "$pulse_theme" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface color-scheme "default" 2>/dev/null || true
        sleep 0.05
        gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "$theme_name" 2>/dev/null || true
    fi
}

sync_qt6ct_and_zed() {
    [[ -f "$COLORS_JSON" ]] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    local qt6_dir="$CONFIG_DIR/qt6ct"
    local zed_dir="$CONFIG_DIR/zed"
    if [[ ! -d "$qt6_dir" && ! -d "$zed_dir" ]]; then
        return 0
    fi
    python3 - "$COLORS_JSON" "$qt6_dir" "$zed_dir" <<'PY' 2>/dev/null || true
import json, os, sys, tempfile

colors_path, qt6_dir, zed_dir = sys.argv[1:4]
with open(colors_path, "r", encoding="utf-8") as f:
    c = json.load(f)


def atomic_write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp_", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(content)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def argb(hex_str, fallback="#ff1e1e2e"):
    h = str(hex_str or "").strip().lstrip("#")
    if len(h) == 6:
        return f"#ff{h.lower()}"
    return fallback


if os.path.isdir(qt6_dir):
    fg = argb(c.get("onSurface"), "#ffcdd6f4")
    fg_var = argb(c.get("onSurfaceVariant"), "#ffa6adc8")
    bg = argb(c.get("surfaceContainerLow"), "#ff181825")
    base = argb(c.get("surfaceContainerLowest"), "#ff11111b")
    alt_base = argb(c.get("surfaceContainer"), "#ff1e1e2e")
    btn = argb(c.get("surfaceContainerHigh"), "#ff313244")
    hi = argb(c.get("primary"), "#ffcba6f7")
    on_hi = argb(c.get("onPrimary"), "#ff11111b")
    link = argb(c.get("secondary"), "#ff89b4fa")
    visited = argb(c.get("tertiary"), "#fff5c2e7")
    bright = argb(c.get("surfaceBright"), "#ff45475a")
    mid = argb(c.get("outlineVariant"), "#ff313244")
    dark = argb(c.get("outline"), "#ff6c7086")
    active = [fg, btn, bright, mid, dark, mid, fg, fg, fg, base, bg, dark, hi, on_hi, link, visited, alt_base, base, base, fg, fg_var]
    disabled = [fg_var, btn, bright, mid, dark, mid, fg_var, fg_var, fg_var, base, bg, dark, mid, fg_var, link, visited, alt_base, base, base, fg_var, fg_var]
    qt_conf = (
        "[ColorScheme]\n"
        f"active_colors={', '.join(active)}\n"
        f"disabled_colors={', '.join(disabled)}\n"
        f"inactive_colors={', '.join(active)}\n"
    )
    atomic_write(os.path.join(qt6_dir, "colors", "mango-matugen.conf"), qt_conf)

if os.path.isdir(zed_dir):
    is_dark = bool(c.get("isDark", True))
    theme_doc = {
        "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
        "name": "Mango Matugen",
        "author": "mango-quickshell-dots",
        "themes": [
            {
                "name": "Mango Matugen",
                "appearance": "dark" if is_dark else "light",
                "style": {
                    "border": c.get("outlineVariant", "#313244"),
                    "border.variant": c.get("outlineVariant", "#313244"),
                    "border.focused": c.get("primary", "#cba6f7"),
                    "elevated_surface.background": c.get("surfaceContainerHigh", "#313244"),
                    "surface.background": c.get("surfaceContainerLow", "#181825"),
                    "background": c.get("surfaceContainerLowest", "#11111b"),
                    "element.background": c.get("surfaceContainer", "#1e1e2e"),
                    "element.hover": c.get("surfaceBright", "#313244"),
                    "element.selected": c.get("primaryContainer", "#3e2f56"),
                    "text": c.get("onSurface", "#cdd6f4"),
                    "text.muted": c.get("onSurfaceVariant", "#a6adc8"),
                    "text.accent": c.get("primary", "#cba6f7"),
                    "editor.foreground": c.get("onSurface", "#cdd6f4"),
                    "editor.background": c.get("surfaceContainerLowest", "#11111b"),
                    "editor.gutter.background": c.get("surfaceContainerLowest", "#11111b"),
                    "editor.active_line.background": c.get("surfaceContainerLow", "#181825"),
                    "terminal.background": c.get("surfaceContainerLowest", "#11111b"),
                    "terminal.foreground": c.get("onSurface", "#cdd6f4"),
                    "error": c.get("error", "#f38ba8"),
                    "warning": c.get("warning", "#f9e2af"),
                    "info": c.get("info", "#89dceb"),
                    "success": c.get("success", "#a6e3a1"),
                    "syntax": {
                        "keyword": {"color": c.get("primary", "#cba6f7")},
                        "function": {"color": c.get("secondary", "#89b4fa")},
                        "string": {"color": c.get("success", "#a6e3a1")},
                        "type": {"color": c.get("warning", "#f9e2af")},
                        "constant": {"color": c.get("tertiary", "#f5c2e7")},
                        "comment": {"color": c.get("outline", "#6c7086"), "font_style": "italic"},
                    },
                },
            }
        ],
    }
    atomic_write(os.path.join(zed_dir, "themes", "mango-matugen.json"), json.dumps(theme_doc, indent=2) + "\n")
PY
}

# --- Live Reload Foot (OSC sequences) & Kitty (SIGUSR1) & MangoWC ---
push_foot_osc() {
    local foot_colors="$FOOT_DIR/colors.ini"
    [[ -f "$foot_colors" ]] || return 0

    local seq=""
    seq=$(python3 - "$foot_colors" <<'PY'
import sys
vals = {}
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("[") or "=" not in line:
            continue
        k, v = [x.strip() for x in line.split("=", 1)]
        vals[k] = v

out = []
if "foreground" in vals:
    out.append(f"\033]10;#{vals['foreground']}\033\\")
if "background" in vals:
    out.append(f"\033]11;#{vals['background']}\033\\")
if "cursor" in vals:
    parts = vals["cursor"].split()
    if len(parts) >= 2:
        out.append(f"\033]12;#{parts[1]}\033\\")
for i in range(8):
    k = f"regular{i}"
    if k in vals:
        out.append(f"\033]4;{i};#{vals[k]}\033\\")
for i in range(8):
    k = f"bright{i}"
    if k in vals:
        out.append(f"\033]4;{i+8};#{vals[k]}\033\\")
sys.stdout.write("".join(out))
PY
    )
    [[ -n "$seq" ]] || return 0

    local tty
    while IFS= read -r tty; do
        local dev="/dev/$tty"
        if [[ -w "$dev" && -O "$dev" ]]; then
            printf '%b' "$seq" > "$dev" 2>/dev/null || true
        fi
    done < <(ps -eo ppid=,tty=,comm= | awk '$3 ~ /^(bash|zsh|fish|sh|nu)$/ && $2 ~ /^pts\// { print $2 }' | sort -u)
}

reload_wm_and_terminals() {
    if command -v mmsg >/dev/null 2>&1; then
        mmsg dispatch reload_config >/dev/null 2>&1 || mmsg -s -d reload_config >/dev/null 2>&1 || true
    fi
    pkill -USR1 kitty >/dev/null 2>&1 || true
    push_foot_osc
}

write_theme_state() {
    python3 - "$STATE_JSON" "$MODE" "$SCHEME" "$PRESET" "$WALLPAPER" "$ACCENT" "$CUSTOM_THEME" <<'PY'
import json, os, sys
target, mode, scheme, preset, wallpaper, accent, custom_theme = sys.argv[1:8]
tmp = f"{target}.tmp.{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({
        "mode": mode,
        "scheme": scheme,
        "preset": preset,
        "wallpaper": wallpaper,
        "accent": accent,
        "customTheme": custom_theme,
    }, f, indent=2)
    f.write("\n")
os.replace(tmp, target)
PY
}

# On first-run --init, gracefully fall back to first available wallpaper or curated preset
if [[ "$INIT_ONLY" -eq 1 && "$MODE" == "dynamic" ]]; then
    if [[ -z "$WALLPAPER" || ! -f "$WALLPAPER" ]]; then
        WP_DIR="$HOME/Pictures/Wallpapers"
        if [[ -f "$QUICKSHELL_DIR/shell-prefs.json" ]] && command -v python3 >/dev/null 2>&1; then
            WP_DIR=$(python3 - "$QUICKSHELL_DIR/shell-prefs.json" <<'PY' 2>/dev/null || echo "$HOME/Pictures/Wallpapers"
import json, os, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    print(os.path.expanduser(str(d.get("wallpaperDir", "~/Pictures/Wallpapers")).strip() or "~/Pictures/Wallpapers"))
except Exception:
    print(os.path.expanduser("~/Pictures/Wallpapers"))
PY
)
        fi
        FIRST_WP=""
        if [[ -d "$WP_DIR" ]]; then
            FIRST_WP=$(find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n 1 || true)
        fi
        if [[ -n "$FIRST_WP" && -f "$FIRST_WP" ]]; then
            WALLPAPER="$FIRST_WP"
        else
            MODE="preset"
        fi
    fi
    if [[ "$MODE" == "dynamic" ]] && ! command -v matugen >/dev/null 2>&1; then
        MODE="preset"
    fi
fi

# --- Main Pipeline ---
ensure_terminal_includes

if [[ "$SET_WALLPAPER" -eq 1 && -n "$WALLPAPER" ]]; then
    apply_wallpaper "$WALLPAPER"
fi

MAT_TYPE="scheme-tonal-spot"
MAT_CONTRAST="0.00"
MAT_SRC_IDX="0"
MAT_PREFER="saturation"
MAT_LDARK="0.00"
MAT_LLIGHT="0.00"
PREFS_FILE="$QUICKSHELL_DIR/shell-prefs.json"
if [[ -f "$PREFS_FILE" ]] && command -v python3 >/dev/null 2>&1; then
    IFS=$'\t' read -r MAT_TYPE MAT_CONTRAST MAT_SRC_IDX MAT_PREFER MAT_LDARK MAT_LLIGHT < <(
        python3 - "$PREFS_FILE" <<'PY' 2>/dev/null || printf 'scheme-tonal-spot\t0.00\t0\tsaturation\t0.00\t0.00\n'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    t = str(d.get("matugenType", "scheme-tonal-spot")).strip() or "scheme-tonal-spot"
    c = max(-1.0, min(1.0, float(d.get("matugenContrast", 0.0))))
    s = max(0, min(4, int(d.get("matugenSourceIndex", 0))))
    p = str(d.get("matugenPrefer", "saturation")).strip() or "saturation"
    ld = max(-0.8, min(0.8, float(d.get("matugenLightnessDark", 0.0))))
    ll = max(-0.8, min(0.8, float(d.get("matugenLightnessLight", 0.0))))
    print(f"{t}\t{c:.2f}\t{s}\t{p}\t{ld:.2f}\t{ll:.2f}")
except Exception:
    print("scheme-tonal-spot\t0.00\t0\tsaturation\t0.00\t0.00")
PY
    )
fi

if [[ "$MODE" == "dynamic" ]]; then
    if ! command -v matugen >/dev/null 2>&1; then
        echo "Error: matugen is not installed. Switch to Preset Mode or install matugen." >&2
        exit 2
    fi
    if [[ ! -f "$WALLPAPER" ]]; then
        echo "Error: wallpaper not found: $WALLPAPER" >&2
        exit 3
    fi
    matugen image "$WALLPAPER" -m "$SCHEME" -t "$MAT_TYPE" --contrast "$MAT_CONTRAST" \
        --source-color-index "$MAT_SRC_IDX" --prefer "$MAT_PREFER" \
        --lightness-dark "$MAT_LDARK" --lightness-light "$MAT_LLIGHT" -q 2>/dev/null \
        || matugen image "$WALLPAPER" -m "$SCHEME" -t "$MAT_TYPE" --contrast "$MAT_CONTRAST" -q 2>/dev/null \
        || matugen image "$WALLPAPER" -m "$SCHEME" -q
elif [[ "$MODE" == "accent" ]]; then
    if ! command -v matugen >/dev/null 2>&1; then
        echo "Error: matugen is not installed." >&2
        exit 2
    fi
    matugen color hex "$ACCENT" -m "$SCHEME" -t "$MAT_TYPE" --contrast "$MAT_CONTRAST" \
        --lightness-dark "$MAT_LDARK" --lightness-light "$MAT_LLIGHT" -q 2>/dev/null \
        || matugen color hex "$ACCENT" -m "$SCHEME" -q
elif [[ "$MODE" == "custom" ]]; then
    if [[ -n "$CUSTOM_THEME" && -f "$QUICKSHELL_DIR/custom-themes/${CUSTOM_THEME}.json" && -x "$QUICKSHELL_DIR/scripts/manage-themes.sh" ]]; then
        "$QUICKSHELL_DIR/scripts/manage-themes.sh" custom-apply "$CUSTOM_THEME" --no-reload >/dev/null
    elif [[ -f "$COLORS_JSON" ]]; then
        :
    elif [[ -x "$QUICKSHELL_DIR/scripts/manage-themes.sh" ]]; then
        "$QUICKSHELL_DIR/scripts/manage-themes.sh" render-preset "$PRESET" "$SCHEME"
    fi
elif [[ -x "$QUICKSHELL_DIR/scripts/manage-themes.sh" ]]; then
    "$QUICKSHELL_DIR/scripts/manage-themes.sh" render-preset "$PRESET" "$SCHEME"
else
    load_preset_palette "$PRESET" "$SCHEME"
    write_colors_json
    write_gtk_css "$GTK3_DIR/gtk.css" "gtk3"
    write_gtk_css "$GTK4_DIR/gtk.css" "gtk4"
    write_mango_theme
    write_terminal_configs
fi

if [[ -x "$QUICKSHELL_DIR/scripts/manage-themes.sh" ]]; then
    "$QUICKSHELL_DIR/scripts/manage-themes.sh" apply-mango-overrides >/dev/null 2>&1 || true
fi

apply_gtk_settings
sync_qt6ct_and_zed
reload_wm_and_terminals
write_theme_state
