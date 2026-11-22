#!/usr/bin/env bash
set -euo pipefail

# Wayland Screenshot Capture (grim + slurp + wl-copy + Dynamic Island notification)

MODE="${1:---area}"
SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
COLORS_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/colors.json"
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

case "$MODE" in
    --full)
        grim "$FILEPATH"
        TITLE="Fullscreen Screenshot"
        ;;
    --area|*)
        GEOM=$(slurp -b "#00000077" -c "$SEL_BORDER" -s "$SEL_FILL" -w 2 2>/dev/null) || exit 0
        [[ -n "$GEOM" ]] || exit 0
        grim -g "$GEOM" "$FILEPATH"
        TITLE="Area Screenshot"
        ;;
esac

if [[ -f "$FILEPATH" ]]; then
    if command -v wl-copy >/dev/null 2>&1; then
        wl-copy --type image/png < "$FILEPATH"
    fi

    if command -v notify-send >/dev/null 2>&1; then
        RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if [[ ( -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS:-}" == "disabled:" ) && -S "${RUNTIME_DIR}/bus" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus"
        fi
        notify-send -a "Screenshot" -i "$FILEPATH" "$TITLE Captured" \
            "Saved to ~/Pictures/Screenshots/${FILENAME} and copied to clipboard" -t 4000 >/dev/null 2>&1 || true
    fi
fi
