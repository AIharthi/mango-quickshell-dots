#!/usr/bin/env bash
set -euo pipefail

# Wayland Screenshot Capture (grim + slurp + wl-copy + Dynamic Island notification)

MODE="${1:---area}"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
COPY_CLIP=1
SEND_NOTIFY=1
DELAY_SEC=0
QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
COLORS_JSON="${QUICKSHELL_DIR}/colors.json"
PREFS_JSON="${QUICKSHELL_DIR}/shell-prefs.json"

if [[ -f "$PREFS_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    read -r SCREENSHOT_DIR COPY_CLIP SEND_NOTIFY DELAY_SEC < <(
        python3 - "$PREFS_JSON" <<'PY' 2>/dev/null || echo "$HOME/Pictures/Screenshots 1 1 0"
import json, os, sys
try:
    d = json.load(open(sys.argv[1], "r", encoding="utf-8"))
    sdir = os.path.expanduser(str(d.get("screenshotDir", "~/Pictures/Screenshots")).strip() or "~/Pictures/Screenshots")
    clip = 1 if d.get("screenshotCopyClipboard", True) else 0
    notf = 1 if d.get("screenshotNotify", True) else 0
    dly = max(0, min(10, int(d.get("screenshotDelay", 0))))
    print(sdir, clip, notf, dly)
except Exception:
    print(os.path.expanduser("~/Pictures/Screenshots"), 1, 1, 0)
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
    read -r SEL_BORDER SEL_FILL < <(
        python3 - "$COLORS_JSON" <<'PY'
import json, sys
try:
    p = json.load(open(sys.argv[1], "r", encoding="utf-8")).get("primary", "#cba6f7").lstrip("#")
    print(f"#{p}ff", f"#{p}24")
except Exception:
    print("#cba6f7ff", "#cba6f722")
PY
    )
fi

if [[ "$MODE" == "--full" ]]; then
    [[ "$DELAY_SEC" -gt 0 ]] && sleep "$DELAY_SEC"
    grim "$FILEPATH"
    TITLE="Fullscreen Screenshot"
else
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
