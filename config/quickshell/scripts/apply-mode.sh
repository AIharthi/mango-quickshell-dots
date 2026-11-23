#!/usr/bin/env bash
set -euo pipefail

# Unified MangoWC & Quickshell Visual Mode Switcher
# Modes:
#   default — Island: Dynamic Island + balanced rounded windows & soft shadows
#   blur    — Frosted: Frosted glass shell + multi-pass blurred translucent windows
#   neon    — Cyber: Deep obsidian HUD + primary neon rims + glowing top accent
#   minimal — Zen: Calm solid matte surfaces + thin hairlines + wide breathing gaps
#   retro   — Tactile: Neo-brutalist solid cards + thick structural borders + snappy motion
#   oled    — Obsidian: True #000000 AMOLED pitch shell + sharp accent hairlines
#   simple  — Simple: 0px square corners, flat 28px bar, zero gaps/shadows/animations

QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
MANGO_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
MODE_JSON="$QUICKSHELL_DIR/shell-mode.json"
PREFS_JSON="$QUICKSHELL_DIR/mode-prefs.json"
MANGO_MODE_CONF="$MANGO_DIR/mode.conf"

mkdir -p "$QUICKSHELL_DIR" "$MANGO_DIR"

if [[ "${MANGO_MODE_LOCKED:-0}" != "1" ]] && command -v flock >/dev/null 2>&1; then
    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mango-mode-$(id -u).lock"
    exec 8>"$LOCK_FILE"
    flock -x 8
    export MANGO_MODE_LOCKED=1
fi

atomic_write() {
    local target="$1"
    local tmp="${target}.tmp.$$"
    cat > "$tmp"
    mv -f "$tmp" "$target"
}

read_saved_mode() {
    if [[ -f "$MODE_JSON" ]] && command -v python3 >/dev/null 2>&1; then
        python3 - "$MODE_JSON" <<'PY'
import json, sys
valid = ("default", "simple", "blur", "neon", "minimal", "retro", "oled")
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        mode = json.load(f).get("mode", "default")
    print(mode if mode in valid else "default")
except Exception:
    print("default")
PY
    else
        echo "default"
    fi
}

next_cycle_mode() {
    local cur
    cur="$(read_saved_mode)"
    case "$cur" in
        default) echo "blur" ;;
        blur) echo "neon" ;;
        neon) echo "minimal" ;;
        minimal) echo "retro" ;;
        retro) echo "oled" ;;
        oled) echo "simple" ;;
        *) echo "default" ;;
    esac
}

write_default_prefs_json() {
    local target_mode="${1:-default}"
    python3 - "$PREFS_JSON" "$target_mode" <<'PY'
import json, os, sys
path, mode = sys.argv[1:3]
base = {
    "blurEnabled": False,
    "blurFocusedOpacity": 1.00,
    "blurUnfocusedOpacity": 1.00,
    "blurRadius": 5,
    "blurPasses": 2,
    "blurSaturation": 1.20,
    "blurBrightness": 0.90,
    "defaultRadius": 20,
    "defaultGaps": 8,
    "defaultBorderPx": 0,
    "shadows": True,
    "animations": True,
    "animationTypeOpen": "zoom",
    "animationTypeClose": "slide",
    "animationDuration": 180,
    "tagAnimationDirection": 1,
    "blurLayer": False,
    "blurOptimized": True,
    "blurNoise": 0.01,
    "blurContrast": 0.95,
    "layerShadows": False,
    "shadowOnlyFloating": False,
    "shadowsSize": 10,
    "shadowsBlur": 14,
    "layerAnimations": True,
    "animFadeIn": True,
    "animFadeOut": True,
    "dimEnable": False,
}
mode_presets = {
    "default": {},
    "blur": {
        "blurEnabled": True,
        "blurLayer": True,
        "blurFocusedOpacity": 0.86,
        "blurUnfocusedOpacity": 0.76,
        "blurRadius": 7,
        "blurPasses": 3,
        "defaultRadius": 20,
        "defaultGaps": 10,
        "defaultBorderPx": 1,
        "shadows": True,
        "layerShadows": True,
        "shadowsSize": 12,
        "shadowsBlur": 16,
    },
    "neon": {
        "blurEnabled": True,
        "blurLayer": True,
        "blurFocusedOpacity": 0.94,
        "blurUnfocusedOpacity": 0.84,
        "blurRadius": 6,
        "blurPasses": 2,
        "blurNoise": 0.015,
        "blurBrightness": 0.88,
        "blurContrast": 1.06,
        "blurSaturation": 1.28,
        "defaultRadius": 8,
        "defaultGaps": 10,
        "defaultBorderPx": 2,
        "shadows": True,
        "layerShadows": True,
        "shadowsSize": 14,
        "shadowsBlur": 22,
        "dimEnable": True,
        "animationDuration": 140,
    },
    "minimal": {
        "blurEnabled": False,
        "blurLayer": False,
        "blurFocusedOpacity": 1.00,
        "blurUnfocusedOpacity": 0.96,
        "defaultRadius": 12,
        "defaultGaps": 14,
        "defaultBorderPx": 1,
        "shadows": False,
        "layerShadows": False,
        "animationTypeOpen": "fade",
        "animationTypeClose": "fade",
        "animationDuration": 220,
    },
    "retro": {
        "blurEnabled": False,
        "blurLayer": False,
        "blurFocusedOpacity": 1.00,
        "blurUnfocusedOpacity": 1.00,
        "defaultRadius": 4,
        "defaultGaps": 6,
        "defaultBorderPx": 3,
        "shadows": True,
        "layerShadows": True,
        "shadowsSize": 6,
        "shadowsBlur": 2,
        "animationTypeOpen": "slide",
        "animationTypeClose": "slide",
        "animationDuration": 110,
    },
    "oled": {
        "blurEnabled": False,
        "blurLayer": False,
        "blurFocusedOpacity": 1.00,
        "blurUnfocusedOpacity": 0.92,
        "defaultRadius": 16,
        "defaultGaps": 6,
        "defaultBorderPx": 1,
        "shadows": False,
        "layerShadows": False,
        "dimEnable": True,
        "animationDuration": 160,
    },
    "simple": {
        "blurEnabled": False,
        "blurLayer": False,
        "blurFocusedOpacity": 1.00,
        "blurUnfocusedOpacity": 1.00,
        "defaultRadius": 0,
        "defaultGaps": 0,
        "defaultBorderPx": 2,
        "shadows": False,
        "layerShadows": False,
        "shadowsSize": 4,
        "shadowsBlur": 4,
        "animations": False,
        "layerAnimations": False,
        "animFadeIn": False,
        "animFadeOut": False,
        "dimEnable": False,
    },
}
base.update(mode_presets.get(mode, {}))
tmp = f"{path}.tmp.{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(base, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
}

ensure_prefs_json() {
    if [[ ! -f "$PREFS_JSON" ]]; then
        write_default_prefs_json "$(read_saved_mode)"
    fi
}

update_pref() {
    local key="$1"
    local val="$2"
    ensure_prefs_json
    python3 - "$PREFS_JSON" "$key" "$val" <<'PY'
import json, os, sys
path, key, raw = sys.argv[1:4]
defaults = {
    "blurEnabled": False,
    "blurFocusedOpacity": 1.00,
    "blurUnfocusedOpacity": 1.00,
    "blurRadius": 5,
    "blurPasses": 2,
    "blurSaturation": 1.20,
    "blurBrightness": 0.90,
    "defaultRadius": 20,
    "defaultGaps": 8,
    "defaultBorderPx": 0,
    "shadows": True,
    "animations": True,
    "animationTypeOpen": "zoom",
    "animationTypeClose": "slide",
    "animationDuration": 180,
    "tagAnimationDirection": 1,
    "blurLayer": False,
    "blurOptimized": True,
    "blurNoise": 0.01,
    "blurContrast": 0.95,
    "layerShadows": False,
    "shadowOnlyFloating": False,
    "shadowsSize": 10,
    "shadowsBlur": 14,
    "layerAnimations": True,
    "animFadeIn": True,
    "animFadeOut": True,
    "dimEnable": False,
}
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
merged = dict(defaults)
merged.update(data)

if key in ("blurFocusedOpacity", "blurUnfocusedOpacity"):
    merged[key] = round(max(0.50, min(1.0, float(raw))), 2)
elif key == "blurSaturation":
    merged[key] = round(max(0.80, min(1.60, float(raw))), 2)
elif key == "blurBrightness":
    merged[key] = round(max(0.65, min(1.15, float(raw))), 2)
elif key == "blurRadius":
    merged[key] = max(2, min(16, int(round(float(raw)))))
elif key == "blurPasses":
    merged[key] = max(1, min(6, int(round(float(raw)))))
elif key in ("defaultRadius", "defaultGaps"):
    merged[key] = max(0, min(28, int(round(float(raw)))))
elif key == "defaultBorderPx":
    merged[key] = max(0, min(4, int(round(float(raw)))))
elif key in ("shadows", "animations", "blurEnabled"):
    merged[key] = str(raw).strip().lower() in ("1", "true", "yes", "on")
elif key in ("animationTypeOpen", "animationTypeClose"):
    v = str(raw).strip().lower()
    if v not in ("zoom", "slide", "fade", "none"):
        sys.exit(f"Invalid animation type: {v}")
    merged[key] = v
elif key == "animationDuration":
    merged[key] = max(100, min(600, int(round(float(raw)))))
elif key == "tagAnimationDirection":
    merged[key] = 1 if int(round(float(raw))) != 0 else 0
elif key in ("blurLayer", "blurOptimized", "layerShadows", "shadowOnlyFloating", "layerAnimations", "animFadeIn", "animFadeOut", "dimEnable"):
    merged[key] = str(raw).strip().lower() in ("1", "true", "yes", "on")
elif key == "blurNoise":
    merged[key] = round(max(0.0, min(0.10, float(raw))), 3)
elif key == "blurContrast":
    merged[key] = round(max(0.70, min(1.30, float(raw))), 2)
elif key == "shadowsSize":
    merged[key] = max(2, min(40, int(round(float(raw)))))
elif key == "shadowsBlur":
    merged[key] = max(2, min(48, int(round(float(raw)))))
else:
    sys.exit(f"Unknown pref key: {key}")

tmp = f"{path}.tmp.{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
}

reset_prefs() {
    write_default_prefs_json "$(read_saved_mode)"
}

MODE=""
DO_RELOAD=1
EXPLICIT_MODE_SWITCH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --init)
            MODE="$(read_saved_mode)"
            shift
            ;;
        --no-reload)
            DO_RELOAD=0
            shift
            ;;
        --update-pref)
            update_pref "${2:?Missing key for --update-pref}" "${3:?Missing value for --update-pref}"
            shift 3
            ;;
        --reset-prefs)
            reset_prefs
            shift
            ;;
        --cycle)
            MODE="$(next_cycle_mode)"
            EXPLICIT_MODE_SWITCH=1
            shift
            ;;
        default|simple|blur|neon|minimal|retro|oled)
            MODE="$1"
            EXPLICIT_MODE_SWITCH=1
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: apply-mode.sh [default|blur|neon|minimal|retro|oled|simple|--cycle|--init] [--update-pref <key> <val>] [--reset-prefs] [--no-reload]
EOF
            exit 0
            ;;
        *)
            echo "Invalid argument: $1 (expected default, blur, neon, minimal, retro, oled, simple, or --init)" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    MODE="$(read_saved_mode)"
fi

case "$MODE" in
    default|simple|blur|neon|minimal|retro|oled) ;;
    *)
        echo "Invalid mode: $MODE" >&2
        exit 1
        ;;
esac

if [[ "$EXPLICIT_MODE_SWITCH" -eq 1 ]]; then
    write_default_prefs_json "$MODE"
else
    ensure_prefs_json
fi

read -r BLUR_ENABLED BLUR_FOCUSED BLUR_UNFOCUSED BLUR_RADIUS BLUR_PASSES BLUR_SAT BLUR_BRIGHT DEF_RADIUS DEF_GAPS DEF_BORDER SHADOWS_FLAG ANIM_FLAG ANIM_OPEN ANIM_CLOSE ANIM_DUR TAG_DIR BLUR_LAYER BLUR_OPT BLUR_NOISE BLUR_CONTRAST LAYER_SHADOWS SHADOW_FLOAT SHADOW_SIZE SHADOW_BLUR LAYER_ANIM FADE_IN FADE_OUT DIM_ENABLE < <(
    python3 - "$PREFS_JSON" <<'PY'
import json, sys
defaults = {
    "blurEnabled": False,
    "blurFocusedOpacity": 1.00,
    "blurUnfocusedOpacity": 1.00,
    "blurRadius": 5,
    "blurPasses": 2,
    "blurSaturation": 1.20,
    "blurBrightness": 0.90,
    "defaultRadius": 20,
    "defaultGaps": 8,
    "defaultBorderPx": 0,
    "shadows": True,
    "animations": True,
    "animationTypeOpen": "zoom",
    "animationTypeClose": "slide",
    "animationDuration": 180,
    "tagAnimationDirection": 1,
    "blurLayer": False,
    "blurOptimized": True,
    "blurNoise": 0.01,
    "blurContrast": 0.95,
    "layerShadows": False,
    "shadowOnlyFloating": False,
    "shadowsSize": 10,
    "shadowsBlur": 14,
    "layerAnimations": True,
    "animFadeIn": True,
    "animFadeOut": True,
    "dimEnable": False,
}
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    data = {}
m = dict(defaults)
if isinstance(data, dict):
    m.update(data)
print(
    1 if m["blurEnabled"] else 0,
    f"{float(m['blurFocusedOpacity']):.2f}",
    f"{float(m['blurUnfocusedOpacity']):.2f}",
    int(m["blurRadius"]),
    int(m["blurPasses"]),
    f"{float(m['blurSaturation']):.2f}",
    f"{float(m['blurBrightness']):.2f}",
    int(m["defaultRadius"]),
    int(m["defaultGaps"]),
    int(m["defaultBorderPx"]),
    1 if m["shadows"] else 0,
    1 if m["animations"] else 0,
    str(m["animationTypeOpen"]),
    str(m["animationTypeClose"]),
    int(m["animationDuration"]),
    1 if int(m["tagAnimationDirection"]) != 0 else 0,
    1 if m["blurLayer"] else 0,
    1 if m["blurOptimized"] else 0,
    f"{float(m['blurNoise']):.3f}",
    f"{float(m['blurContrast']):.2f}",
    1 if m["layerShadows"] else 0,
    1 if m["shadowOnlyFloating"] else 0,
    int(m["shadowsSize"]),
    int(m["shadowsBlur"]),
    1 if m["layerAnimations"] else 0,
    1 if m["animFadeIn"] else 0,
    1 if m["animFadeOut"] else 0,
    1 if m["dimEnable"] else 0,
)
PY
)

ANIM_DUR_MOVE=$((ANIM_DUR))
ANIM_DUR_TAG=$((ANIM_DUR > 120 ? ANIM_DUR - 20 : 100))
ANIM_DUR_CLOSE=$((ANIM_DUR > 130 ? ANIM_DUR - 30 : 100))

write_mango_mode_conf() {
    local outer_h=$((DEF_GAPS > 0 ? DEF_GAPS + 2 : 0))
    local no_bdr_single=0
    [[ "$DEF_BORDER" -eq 0 ]] && no_bdr_single=1
    local no_rad_single=0
    [[ "$DEF_RADIUS" -eq 0 ]] && no_rad_single=1
    local b_layer=$((BLUR_ENABLED * BLUR_LAYER))
    local l_shd=$((SHADOWS_FLAG * LAYER_SHADOWS))
    local l_anim=$((ANIM_FLAG * LAYER_ANIM))
    local f_in=$((ANIM_FLAG * FADE_IN))
    local f_out=$((ANIM_FLAG * FADE_OUT))
    local shd_x=0
    local shd_y=4
    if [[ "$MODE" == "retro" ]]; then
        shd_x=4
        shd_y=4
    elif [[ "$MODE" == "blur" ]]; then
        shd_y=6
    fi

    atomic_write "$MANGO_MODE_CONF" <<EOF
# Auto-generated by apply-mode.sh — Mode: ${MODE}
blur=${BLUR_ENABLED}
blur_layer=${b_layer}
blur_optimized=${BLUR_OPT}
blur_params_num_passes=${BLUR_PASSES}
blur_params_radius=${BLUR_RADIUS}
blur_params_noise=${BLUR_NOISE}
blur_params_brightness=${BLUR_BRIGHT}
blur_params_contrast=${BLUR_CONTRAST}
blur_params_saturation=${BLUR_SAT}

shadows=${SHADOWS_FLAG}
layer_shadows=${l_shd}
shadow_only_floating=${SHADOW_FLOAT}
shadows_size=${SHADOW_SIZE}
shadows_blur=${SHADOW_BLUR}
shadows_position_x=${shd_x}
shadows_position_y=${shd_y}

border_radius=${DEF_RADIUS}
no_radius_when_single=${no_rad_single}
monocle_no_radius=${no_rad_single}
focused_opacity=${BLUR_FOCUSED}
unfocused_opacity=${BLUR_UNFOCUSED}
dim_enable=${DIM_ENABLE}

animations=${ANIM_FLAG}
layer_animations=${l_anim}
animation_type_open=${ANIM_OPEN}
animation_type_close=${ANIM_CLOSE}
animation_duration_open=${ANIM_DUR}
animation_duration_move=${ANIM_DUR_MOVE}
animation_duration_tag=${ANIM_DUR_TAG}
animation_duration_close=${ANIM_DUR_CLOSE}
tag_animation_direction=${TAG_DIR}
animation_fade_in=${f_in}
animation_fade_out=${f_out}

gap_inner_horizontal=${DEF_GAPS}
gap_inner_vertical=${DEF_GAPS}
gap_outer_horizontal=${outer_h}
gap_outer_vertical=${DEF_GAPS}
border_px=${DEF_BORDER}
no_border_when_single=${no_bdr_single}
EOF
}

write_mode_json() {
    atomic_write "$MODE_JSON" <<EOF
{
  "mode": "${MODE}"
}
EOF
}

write_mango_mode_conf
write_mode_json

if [[ "$DO_RELOAD" -eq 1 ]] && command -v mmsg >/dev/null 2>&1; then
    mmsg dispatch reload_config >/dev/null 2>&1 || mmsg -s -d reload_config >/dev/null 2>&1 || true
fi
