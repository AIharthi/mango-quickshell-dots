#!/usr/bin/env bash
set -euo pipefail

# Wayland Screenshot Capture (grim + slurp + wl-copy + Dynamic Island notification)

if ! command -v grim >/dev/null 2>&1; then
    echo "Error: 'grim' is required for screenshots." >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Screenshot" "Screenshot Failed" "'grim' is not installed" -t 3000 >/dev/null 2>&1 || true
    fi
    exit 1
fi

MODE="${1:---area}"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
COPY_CLIP=1
SEND_NOTIFY=1
DELAY_SEC=0
QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
COLORS_JSON="${QUICKSHELL_DIR}/colors.json"
PREFS_JSON="${QUICKSHELL_DIR}/shell-prefs.json"

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

mkdir -p "$SCREENSHOT_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="Screenshot_${TIMESTAMP}.png"
FILEPATH="${SCREENSHOT_DIR}/${FILENAME}"

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

if [[ "$MODE" == "--full" ]]; then
    [[ "$DELAY_SEC" -gt 0 ]] && sleep "$DELAY_SEC"
    grim "$FILEPATH"
    TITLE="Fullscreen Screenshot"
else
    if ! command -v slurp >/dev/null 2>&1; then
        echo "Error: 'slurp' is required for area screenshots." >&2
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -a "Screenshot" "Screenshot Failed" "'slurp' is not installed" -t 3000 >/dev/null 2>&1 || true
        fi
        exit 1
    fi
    GEOM=$(slurp -b "#00000077" -c "$SEL_BORDER" -s "$SEL_FILL" -w 2 2>/dev/null) || exit 0
    [[ -n "$GEOM" ]] || exit 0
    [[ "$DELAY_SEC" -gt 0 ]] && sleep "$DELAY_SEC"
    grim -g "$GEOM" "$FILEPATH"
    TITLE="Area Screenshot"
fi

if [[ -f "$FILEPATH" ]]; then
    if [[ "$COPY_CLIP" -eq 1 ]] && command -v wl-copy >/dev/null 2>&1; then
        wl-copy --type image/png < "$FILEPATH"
    fi

    if [[ "$SEND_NOTIFY" -eq 1 ]] && command -v notify-send >/dev/null 2>&1; then
        RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if [[ ( -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS:-}" == "disabled:" ) && -S "${RUNTIME_DIR}/bus" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus"
        fi
        local_msg="Saved to ${SCREENSHOT_DIR}/${FILENAME}"
        [[ "$COPY_CLIP" -eq 1 ]] && local_msg="${local_msg} and copied to clipboard"
        notify-send -a "Screenshot" -i "$FILEPATH" "$TITLE Captured" \
            "$local_msg" -t 4000 >/dev/null 2>&1 || true
    fi
fi
