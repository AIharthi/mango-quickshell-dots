#!/usr/bin/env bash
set -euo pipefail

# Unified MangoWC & Quickshell Visual Mode Switcher
# Modes:
#   default — Current Dynamic Island + rounded opaque windows
#   simple  — Everything square (0px radius), no blur/shadows/animations/gaps, 2px crisp borders, minimal square bar
#   blur    — Current Dynamic Island with frosted glass styling + translucent blurry MangoWC windows

QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
MANGO_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
MODE_JSON="$QUICKSHELL_DIR/shell-mode.json"
PREFS_JSON="$QUICKSHELL_DIR/mode-prefs.json"
MANGO_MODE_CONF="$MANGO_DIR/mode.conf"

mkdir -p "$QUICKSHELL_DIR" "$MANGO_DIR"

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
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        mode = json.load(f).get("mode", "default")
    print(mode if mode in ("default", "simple", "blur") else "default")
except Exception:
    print("default")
PY
    else
        echo "default"
    fi
}

write_default_prefs_json() {
    atomic_write "$PREFS_JSON" <<'EOF'
{
  "blurFocusedOpacity": 0.86,
  "blurUnfocusedOpacity": 0.76,
  "blurRadius": 8,
  "blurPasses": 4,
  "blurSaturation": 1.25,
  "blurBrightness": 0.90,
  "defaultRadius": 20,
  "defaultGaps": 8,
  "defaultBorderPx": 0,
  "shadows": true,
  "animations": true,
  "animationTypeOpen": "zoom",
  "animationTypeClose": "slide",
  "animationDuration": 300,
  "tagAnimationDirection": 1,
  "blurLayer": true,
  "blurOptimized": true,
  "blurNoise": 0.02,
  "blurContrast": 0.95,
  "layerShadows": false,
  "shadowOnlyFloating": false,
  "shadowsSize": 14,
  "shadowsBlur": 20,
  "layerAnimations": true,
  "animFadeIn": true,
  "animFadeOut": true,
  "dimEnable": false
}
EOF
}

ensure_prefs_json() {
    if [[ ! -f "$PREFS_JSON" ]]; then
        write_default_prefs_json
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
    "blurFocusedOpacity": 0.86,
    "blurUnfocusedOpacity": 0.76,
    "blurRadius": 8,
    "blurPasses": 4,
    "blurSaturation": 1.25,
    "blurBrightness": 0.90,
    "defaultRadius": 20,
    "defaultGaps": 8,
    "defaultBorderPx": 0,
    "shadows": True,
    "animations": True,
    "animationTypeOpen": "zoom",
    "animationTypeClose": "slide",
    "animationDuration": 300,
    "tagAnimationDirection": 1,
    "blurLayer": True,
    "blurOptimized": True,
    "blurNoise": 0.02,
    "blurContrast": 0.95,
    "layerShadows": False,
    "shadowOnlyFloating": False,
    "shadowsSize": 14,
    "shadowsBlur": 20,
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
elif key in ("shadows", "animations"):
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
    write_default_prefs_json
}

MODE=""
DO_RELOAD=1

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
        default|simple|blur)
            MODE="$1"
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: apply-mode.sh [default|simple|blur|--init] [--update-pref <key> <val>] [--reset-prefs] [--no-reload]
EOF
            exit 0
            ;;
        *)
            echo "Invalid argument: $1 (expected default, simple, blur, or --init)" >&2
            exit 1
            ;;
    esac
done

ensure_prefs_json

if [[ -z "$MODE" ]]; then
    MODE="$(read_saved_mode)"
fi

if [[ "$MODE" != "default" && "$MODE" != "simple" && "$MODE" != "blur" ]]; then
    echo "Invalid mode: $MODE (expected default, simple, or blur)" >&2
    exit 1
fi

read -r BLUR_FOCUSED BLUR_UNFOCUSED BLUR_RADIUS BLUR_PASSES BLUR_SAT BLUR_BRIGHT DEF_RADIUS DEF_GAPS DEF_BORDER SHADOWS_FLAG ANIM_FLAG ANIM_OPEN ANIM_CLOSE ANIM_DUR TAG_DIR BLUR_LAYER BLUR_OPT BLUR_NOISE BLUR_CONTRAST LAYER_SHADOWS SHADOW_FLOAT SHADOW_SIZE SHADOW_BLUR LAYER_ANIM FADE_IN FADE_OUT DIM_ENABLE < <(
    python3 - "$PREFS_JSON" <<'PY'
import json, sys
defaults = {
    "blurFocusedOpacity": 0.86,
    "blurUnfocusedOpacity": 0.76,
    "blurRadius": 8,
    "blurPasses": 4,
    "blurSaturation": 1.25,
    "blurBrightness": 0.90,
    "defaultRadius": 20,
    "defaultGaps": 8,
    "defaultBorderPx": 0,
    "shadows": True,
    "animations": True,
    "animationTypeOpen": "zoom",
    "animationTypeClose": "slide",
    "animationDuration": 300,
    "tagAnimationDirection": 1,
    "blurLayer": True,
    "blurOptimized": True,
    "blurNoise": 0.02,
    "blurContrast": 0.95,
    "layerShadows": False,
    "shadowOnlyFloating": False,
    "shadowsSize": 14,
    "shadowsBlur": 20,
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

ANIM_DUR_MOVE=$((ANIM_DUR + 20))
ANIM_DUR_TAG=$((ANIM_DUR > 120 ? ANIM_DUR - 20 : 100))
ANIM_DUR_CLOSE=$((ANIM_DUR > 140 ? ANIM_DUR - 40 : 100))

write_mango_mode_conf() {
    case "$MODE" in
        default)
            local outer_h=$((DEF_GAPS + 2))
            local no_bdr_single=1
            [[ "$DEF_BORDER" -gt 0 ]] && no_bdr_single=0
            local l_anim=$((ANIM_FLAG * LAYER_ANIM))
            local f_in=$((ANIM_FLAG * FADE_IN))
            local f_out=$((ANIM_FLAG * FADE_OUT))
            atomic_write "$MANGO_MODE_CONF" <<EOF
# Auto-generated by apply-mode.sh — Mode: default (Dynamic Island)
blur=1
blur_layer=${BLUR_LAYER}
blur_optimized=${BLUR_OPT}
blur_params_num_passes=2
blur_params_radius=6
blur_params_noise=${BLUR_NOISE}
blur_params_brightness=0.92
blur_params_contrast=${BLUR_CONTRAST}
blur_params_saturation=1.15

shadows=${SHADOWS_FLAG}
layer_shadows=${LAYER_SHADOWS}
shadow_only_floating=${SHADOW_FLOAT}
shadows_size=${SHADOW_SIZE}
shadows_blur=${SHADOW_BLUR}
shadows_position_x=0
shadows_position_y=4

border_radius=${DEF_RADIUS}
no_radius_when_single=0
monocle_no_radius=0
focused_opacity=1.0
unfocused_opacity=0.98
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
            ;;
        simple)
            atomic_write "$MANGO_MODE_CONF" <<'EOF'
# Auto-generated by apply-mode.sh — Mode: simple (Everything Square & Minimal)
blur=0
blur_layer=0
blur_optimized=1

shadows=0
layer_shadows=0
shadow_only_floating=0

border_radius=0
no_radius_when_single=1
monocle_no_radius=1
focused_opacity=1.0
unfocused_opacity=1.0
dim_enable=0

animations=0
layer_animations=0
animation_fade_in=0
animation_fade_out=0

gap_inner_horizontal=0
gap_inner_vertical=0
gap_outer_horizontal=0
gap_outer_vertical=0
border_px=2
no_border_when_single=0
EOF
            ;;
        blur)
            local blur_inner=$((DEF_GAPS + 2))
            local blur_outer_h=$((DEF_GAPS + 4))
            local blur_outer_v=$((DEF_GAPS + 2))
            local blur_border=$DEF_BORDER
            [[ "$blur_border" -lt 1 ]] && blur_border=1
            local l_anim=$((ANIM_FLAG * LAYER_ANIM))
            local f_in=$((ANIM_FLAG * FADE_IN))
            local f_out=$((ANIM_FLAG * FADE_OUT))
            atomic_write "$MANGO_MODE_CONF" <<EOF
# Auto-generated by apply-mode.sh — Mode: blur (Dynamic Island + Frosted Blurry Windows)
blur=1
blur_layer=${BLUR_LAYER}
blur_optimized=${BLUR_OPT}
blur_params_num_passes=${BLUR_PASSES}
blur_params_radius=${BLUR_RADIUS}
blur_params_noise=${BLUR_NOISE}
blur_params_brightness=${BLUR_BRIGHT}
blur_params_contrast=${BLUR_CONTRAST}
blur_params_saturation=${BLUR_SAT}

shadows=${SHADOWS_FLAG}
layer_shadows=${LAYER_SHADOWS}
shadow_only_floating=${SHADOW_FLOAT}
shadows_size=${SHADOW_SIZE}
shadows_blur=${SHADOW_BLUR}
shadows_position_x=0
shadows_position_y=6

border_radius=${DEF_RADIUS}
no_radius_when_single=0
monocle_no_radius=0
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

gap_inner_horizontal=${blur_inner}
gap_inner_vertical=${blur_inner}
gap_outer_horizontal=${blur_outer_h}
gap_outer_vertical=${blur_outer_v}
border_px=${blur_border}
no_border_when_single=0
EOF
            ;;
    esac
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
