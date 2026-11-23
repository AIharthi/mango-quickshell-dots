#!/usr/bin/env bash
set -euo pipefail

# Wayland Screen Recorder (wf-recorder / gpu-screen-recorder + Dynamic Island pill sync)

CMD="${1:-status}"
shift || true

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_FILE="${RUNTIME_DIR}/mango-recording.json"
QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
PREFS_JSON="${QUICKSHELL_DIR}/shell-prefs.json"
COLORS_JSON="${QUICKSHELL_DIR}/colors.json"

notify_user() {
    local summary="$1"
    local body="$2"
    if command -v notify-send >/dev/null 2>&1; then
        if [[ ( -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS:-}" == "disabled:" ) && -S "${RUNTIME_DIR}/bus" ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus"
        fi
        notify-send -a "Screen Recorder" "$summary" "$body" -t 4000 >/dev/null 2>&1 || true
    fi
}

sync_shell() {
    if command -v qs >/dev/null 2>&1 && pgrep -x qs >/dev/null 2>&1; then
        qs ipc call island syncRecordingState >/dev/null 2>&1 || true
    fi
}

read_recording_dir() {
    local default_dir="$HOME/Videos/Recordings"
    if [[ -f "$PREFS_JSON" ]] && command -v python3 >/dev/null 2>&1; then
        python3 - "$PREFS_JSON" "$default_dir" <<'PY' 2>/dev/null || printf '%s\n' "$default_dir"
import json, os, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    rdir = os.path.expanduser(str(d.get("recordingDir", sys.argv[2])).strip() or sys.argv[2])
    print(rdir)
except Exception:
    print(sys.argv[2])
PY
    else
        printf '%s\n' "$default_dir"
    fi
}

is_recording_active() {
    [[ -f "$STATE_FILE" ]] || return 1
    local pid
    pid=$(python3 - "$STATE_FILE" <<'PY' 2>/dev/null || echo ""
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        print(int(json.load(f).get("pid", 0)))
except Exception:
    pass
PY
)
    if [[ -n "$pid" && "$pid" -gt 1 ]] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    rm -f "$STATE_FILE"
    return 1
}

read_status() {
    if is_recording_active; then
        cat "$STATE_FILE"
    else
        printf '{"active":false,"elapsed":0,"file":""}\n'
    fi
}

stop_recording() {
    if ! [[ -f "$STATE_FILE" ]]; then
        sync_shell
        exit 0
    fi
    local pid="" filepath=""
    IFS=$'\t' read -r pid filepath < <(python3 - "$STATE_FILE" <<'PY' 2>/dev/null || printf '\t\n'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        d = json.load(f)
    print(f"{int(d.get('pid', 0))}\t{d.get('file', '')}")
except Exception:
    print("\t")
PY
)
    if [[ -n "$pid" && "$pid" -gt 1 ]] && kill -0 "$pid" 2>/dev/null; then
        kill -INT "$pid" 2>/dev/null || true
        local i
        for i in $(seq 1 30); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$STATE_FILE"
    sync_shell

    if [[ -n "$filepath" && -f "$filepath" ]]; then
        if command -v wl-copy >/dev/null 2>&1; then
            printf '%s' "$filepath" | wl-copy --type text/plain 2>/dev/null || true
        fi
        notify_user "Recording Saved" "Saved to ${filepath} (path copied to clipboard)"
    else
        notify_user "Recording Stopped" "Screen recording finished."
    fi
}

start_recording() {
    if is_recording_active; then
        echo "Recording is already active." >&2
        exit 0
    fi

    local mode="area"
    local with_audio=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            --full) mode="full" ;;
            --area) mode="area" ;;
            --audio) with_audio=1 ;;
        esac
    done

    local recorder=""
    if command -v wf-recorder >/dev/null 2>&1; then
        recorder="wf-recorder"
    elif command -v gpu-screen-recorder >/dev/null 2>&1; then
        recorder="gpu-screen-recorder"
    else
        notify_user "No Screen Recorder Installed" \
            "Install wf-recorder (Arch: pacman -S wf-recorder | Fedora: dnf install wf-recorder | Gentoo: emerge gui-apps/wf-recorder)"
        exit 1
    fi

    local rec_dir
    rec_dir="$(read_recording_dir)"
    mkdir -p "$rec_dir"
    local ts
    ts=$(date +"%Y-%m-%d_%H-%M-%S")
    local filepath="${rec_dir}/Recording_${ts}.mp4"

    local geom=""
    if [[ "$mode" == "area" && "$recorder" == "wf-recorder" ]]; then
        if ! command -v slurp >/dev/null 2>&1; then
            notify_user "Recording Failed" "'slurp' is required for area recording."
            exit 1
        fi
        local sel_border="#cba6f7ff"
        local sel_fill="#cba6f724"
        if [[ -f "$COLORS_JSON" ]] && command -v python3 >/dev/null 2>&1; then
            IFS=$'\t' read -r sel_border sel_fill < <(python3 - "$COLORS_JSON" <<'PY' 2>/dev/null || printf '#cba6f7ff\t#cba6f724\n'
import json, re, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        p = str(json.load(f).get("primary", "#cba6f7")).strip().lstrip("#")
    if re.fullmatch(r"[0-9a-fA-F]{6}", p):
        print(f"#{p}ff\t#{p}24")
    else:
        print("#cba6f7ff\t#cba6f724")
except Exception:
    print("#cba6f7ff\t#cba6f724")
PY
)
        fi
        geom=$(slurp -b "#00000077" -c "$sel_border" -s "$sel_fill" -w 2 2>/dev/null) || exit 0
        [[ -n "$geom" ]] || exit 0
    fi

    local rec_pid=""
    if [[ "$recorder" == "wf-recorder" ]]; then
        local -a rec_args=(-f "$filepath")
        [[ -n "$geom" ]] && rec_args+=(-g "$geom")
        [[ "$with_audio" -eq 1 ]] && rec_args+=(--audio)
        wf-recorder "${rec_args[@]}" </dev/null >/dev/null 2>&1 &
        rec_pid=$!
    else
        local -a gsr_args=(-w screen -f 60 -o "$filepath")
        [[ "$with_audio" -eq 1 ]] && gsr_args+=(-a default_output)
        gpu-screen-recorder "${gsr_args[@]}" </dev/null >/dev/null 2>&1 &
        rec_pid=$!
    fi

    local started_at
    started_at=$(date +%s)
    python3 - "$STATE_FILE" "$rec_pid" "$started_at" "$filepath" <<'PY'
import json, os, sys, tempfile
state_path, pid_s, ts_s, fpath = sys.argv[1:5]
parent = os.path.dirname(state_path)
os.makedirs(parent, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_rec_", text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({
            "active": True,
            "pid": int(pid_s),
            "startedAt": int(ts_s),
            "file": fpath,
        }, f)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, state_path)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
PY
    sync_shell
}

case "$CMD" in
    start)
        start_recording "$@"
        ;;
    stop)
        stop_recording
        ;;
    toggle)
        if is_recording_active; then
            stop_recording
        else
            start_recording "$@"
        fi
        ;;
    status)
        read_status
        ;;
    *)
        echo "Usage: record-screen.sh <start|stop|toggle|status> [--area|--full] [--audio]" >&2
        exit 1
        ;;
esac
