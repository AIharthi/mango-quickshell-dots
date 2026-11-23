#!/usr/bin/env bash
set -euo pipefail

# Wayland Screenshot & Color Picker Suite (grim + slurp + wl-copy + Dynamic Island notification)

MODE="${1:---area}"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
COPY_CLIP=1
SEND_NOTIFY=1
DELAY_SEC=0
QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
COLORS_JSON="${QUICKSHELL_DIR}/colors.json"
PREFS_JSON="${QUICKSHELL_DIR}/shell-prefs.json"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

notify_msg() {
    local summary="$1"
    local body="$2"
    local icon_arg="${3:-}"
    if [[ "$SEND_NOTIFY" -eq 1 ]] && command -v notify-send >/dev/null 2>&1; then
        if [[ ( -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS:-}" == "disabled:" ) && -S "${RUNTIME_DIR}/bus" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus"
        fi
        if [[ -n "$icon_arg" ]]; then
            notify-send -a "Screenshot" -i "$icon_arg" "$summary" "$body" -t 4000 >/dev/null 2>&1 || true
        else
            notify-send -a "Screenshot" "$summary" "$body" -t 4000 >/dev/null 2>&1 || true
        fi
    fi
}

if [[ -f "$PREFS_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    IFS=$'\t' read -r SCREENSHOT_DIR COPY_CLIP SEND_NOTIFY DELAY_SEC < <(
        python3 - "$PREFS_JSON" <<'PY' 2>/dev/null || printf '%s\t1\t1\t0\n' "$HOME/Pictures/Screenshots"
import json, os, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    sdir = os.path.expanduser(str(d.get("screenshotDir", "~/Pictures/Screenshots")).strip() or "~/Pictures/Screenshots")
    clip = 1 if d.get("screenshotCopyClipboard", True) else 0
    notf = 1 if d.get("screenshotNotify", True) else 0
    dly = max(0, min(10, int(d.get("screenshotDelay", 0))))
    print(f"{sdir}\t{clip}\t{notf}\t{dly}")
except Exception:
    print(f"{os.path.expanduser('~/Pictures/Screenshots')}\t1\t1\t0")
PY
    )
fi

# Read active Quickshell theme accent for slurp selection box
SEL_BORDER="#cba6f7ff"
SEL_FILL="#cba6f722"
if [[ -f "$COLORS_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    IFS=$'\t' read -r SEL_BORDER SEL_FILL < <(
        python3 - "$COLORS_JSON" <<'PY' 2>/dev/null || printf '#cba6f7ff\t#cba6f722\n'
import json, re, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        p = str(json.load(f).get("primary", "#cba6f7")).strip().lstrip("#")
    if re.fullmatch(r"[0-9a-fA-F]{6}", p):
        print(f"#{p}ff\t#{p}24")
    else:
        print("#cba6f7ff\t#cba6f722")
except Exception:
    print("#cba6f7ff\t#cba6f722")
PY
    )
fi

# Eyedropper Color Picker mode
if [[ "$MODE" == "--color" ]]; then
    PICKED=""
    if command -v hyprpicker >/dev/null 2>&1; then
        PICKED=$(hyprpicker -a 2>/dev/null || true)
    elif command -v grim >/dev/null 2>&1 && command -v slurp >/dev/null 2>&1; then
        PT=$(slurp -p -b "#00000044" -c "$SEL_BORDER" 2>/dev/null) || exit 0
        [[ -n "$PT" ]] || exit 0
        PICKED=$(grim -g "$PT" -t ppm - 2>/dev/null | python3 - <<'PY' 2>/dev/null || true
import sys
data = sys.stdin.buffer.read()
i = 0
tokens = []
n = len(data)
while i < n and len(tokens) < 4:
    while i < n and data[i] in b" \t\r\n":
        i += 1
    if i < n and data[i] == ord("#"):
        while i < n and data[i] != ord("\n"):
            i += 1
        continue
    start = i
    while i < n and data[i] not in b" \t\r\n#":
        i += 1
    if i > start:
        tokens.append(data[start:i].decode("ascii", errors="ignore"))
if len(tokens) >= 4 and tokens[0] == "P6" and i < n:
    # Skip single whitespace delimiter after maxval
    if data[i] in b" \t\r\n":
        i += 1
    rgb = data[i:i + 3]
    if len(rgb) == 3:
        print(f"#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}")
PY
)
    else
        notify_msg "Color Picker Failed" "Install hyprpicker or grim + slurp."
        exit 1
    fi

    if [[ -n "$PICKED" ]]; then
        if command -v wl-copy >/dev/null 2>&1; then
            printf '%s' "$PICKED" | wl-copy -n --type text/plain
        fi
        notify_msg "Color Picked" "${PICKED} copied to clipboard"
    fi
    exit 0
fi

if ! command -v grim >/dev/null 2>&1; then
    echo "Error: 'grim' is required for screenshots." >&2
    notify_msg "Screenshot Failed" "'grim' is not installed"
    exit 1
fi

mkdir -p "$SCREENSHOT_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="Screenshot_${TIMESTAMP}.png"
FILEPATH="${SCREENSHOT_DIR}/${FILENAME}"

select_area_and_capture() {
    if ! command -v slurp >/dev/null 2>&1; then
        echo "Error: 'slurp' is required for area screenshots." >&2
        notify_msg "Screenshot Failed" "'slurp' is not installed"
        exit 1
    fi
    local geom
    geom=$(slurp -b "#00000077" -c "$SEL_BORDER" -s "$SEL_FILL" -w 2 2>/dev/null) || exit 0
    [[ -n "$geom" ]] || exit 0
    [[ "$DELAY_SEC" -gt 0 ]] && sleep "$DELAY_SEC"
    grim -g "$geom" "$FILEPATH"
}

if [[ "$MODE" == "--full" ]]; then
    [[ "$DELAY_SEC" -gt 0 ]] && sleep "$DELAY_SEC"
    grim "$FILEPATH"
    TITLE="Fullscreen Screenshot"
elif [[ "$MODE" == "--window" ]]; then
    WIN_GEOM=""
    if command -v mmsg >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        WIN_GEOM=$(mmsg get focusing-client 2>/dev/null | python3 - <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.loads(sys.stdin.read())
    w = int(d.get("width", 0))
    h = int(d.get("height", 0))
    x = int(d.get("x", 0))
    y = int(d.get("y", 0))
    if w > 0 and h > 0 and not d.get("error"):
        print(f"{x},{y} {w}x{h}")
except Exception:
    pass
PY
)
    fi
    if [[ -n "$WIN_GEOM" ]]; then
        [[ "$DELAY_SEC" -gt 0 ]] && sleep "$DELAY_SEC"
        grim -g "$WIN_GEOM" "$FILEPATH"
        TITLE="Window Screenshot"
    else
        select_area_and_capture
        TITLE="Area Screenshot"
    fi
elif [[ "$MODE" == "--edit" ]]; then
    select_area_and_capture
    TITLE="Annotated Screenshot"
    if [[ -f "$FILEPATH" ]]; then
        if command -v satty >/dev/null 2>&1; then
            satty --filename "$FILEPATH" --output-filename "$FILEPATH" >/dev/null 2>&1 &
            exit 0
        elif command -v swappy >/dev/null 2>&1; then
            swappy -f "$FILEPATH" -o "$FILEPATH" >/dev/null 2>&1 &
            exit 0
        fi
    fi
else
    select_area_and_capture
    TITLE="Area Screenshot"
fi

if [[ -f "$FILEPATH" ]]; then
    if [[ "$COPY_CLIP" -eq 1 ]] && command -v wl-copy >/dev/null 2>&1; then
        wl-copy --type image/png < "$FILEPATH"
    fi

    local_msg="Saved to ${SCREENSHOT_DIR}/${FILENAME}"
    [[ "$COPY_CLIP" -eq 1 ]] && local_msg="${local_msg} and copied to clipboard"
    notify_msg "$TITLE Captured" "$local_msg" "$FILEPATH"
fi
