#!/usr/bin/env bash
set -euo pipefail

# Wayland Clipboard History Manager (wl-paste + wl-copy + JSON store)

CMD="${1:-list}"
shift || true

CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
HISTORY_FILE="${CACHE_BASE}/clipboard.json"
MAX_ENTRIES=50
MAX_BYTES=65536

case "$CMD" in
    watch|list|copy|delete|pin|clear|add)
        ;;
    *)
        echo "Usage: manage-clipboard.sh <watch|list|copy <id>|delete <id>|pin <id>|clear|add <text>>" >&2
        exit 1
        ;;
esac

mkdir -p "$CACHE_BASE"
chmod 700 "$CACHE_BASE" 2>/dev/null || true

py_store() {
    local py_code=""
    IFS= read -r -d '' py_code <<'PY' || true
import fcntl
import json
import os
import sys
import tempfile
import time

history_path = sys.argv[1]
max_entries = int(sys.argv[2])
max_bytes = int(sys.argv[3])
op = sys.argv[4]
args = sys.argv[5:]

os.makedirs(os.path.dirname(history_path), exist_ok=True)
lock_path = history_path + ".lock"


def load_items():
    if not os.path.isfile(history_path):
        return []
    try:
        with open(history_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            out = []
            for it in data:
                if isinstance(it, dict) and isinstance(it.get("text"), str) and it["text"].strip():
                    out.append({
                        "id": int(it.get("id", 0)),
                        "text": it["text"],
                        "preview": str(it.get("preview") or make_preview(it["text"])),
                        "time": str(it.get("time") or ""),
                        "pinned": bool(it.get("pinned", False)),
                    })
            return out
    except Exception:
        pass
    return []


def make_preview(text):
    collapsed = " ".join(text.split())
    return collapsed[:160]


def save_items(items):
    parent = os.path.dirname(history_path)
    fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_clip_", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(items, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, history_path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def sort_items(items):
    pinned = [it for it in items if it.get("pinned")]
    unpinned = [it for it in items if not it.get("pinned")]
    return pinned + unpinned


with open(lock_path, "w", encoding="utf-8") as lock_fh:
    fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)
    items = load_items()

    if op == "list":
        print(json.dumps(sort_items(items), ensure_ascii=False))
    elif op == "add":
        raw = sys.stdin.read() if not args else " ".join(args)
        if raw and raw.strip() and len(raw.encode("utf-8", errors="ignore")) <= max_bytes:
            # Skip duplicate if already most recent unpinned entry or exact top entry
            if not (items and items[0].get("text") == raw):
                existing_pin = False
                kept = []
                for it in items:
                    if it.get("text") == raw:
                        existing_pin = existing_pin or bool(it.get("pinned", False))
                    else:
                        kept.append(it)
                next_id = max((int(it.get("id", 0)) for it in items), default=0) + 1
                entry = {
                    "id": next_id,
                    "text": raw,
                    "preview": make_preview(raw),
                    "time": time.strftime("%H:%M"),
                    "pinned": existing_pin,
                }
                new_items = [entry] + kept
                if len(new_items) > max_entries:
                    pinned = [it for it in new_items if it.get("pinned")]
                    unpinned = [it for it in new_items if not it.get("pinned")]
                    cap_unpinned = max(0, max_entries - len(pinned))
                    new_items = pinned[:max_entries] + unpinned[:cap_unpinned]
                save_items(new_items)
    elif op == "get":
        target = int(args[0]) if args else -1
        for it in items:
            if it.get("id") == target:
                sys.stdout.write(it["text"])
                break
    elif op == "delete":
        target = int(args[0]) if args else -1
        items = [it for it in items if it.get("id") != target]
        save_items(items)
        print(json.dumps(sort_items(items), ensure_ascii=False))
    elif op == "pin":
        target = int(args[0]) if args else -1
        for it in items:
            if it.get("id") == target:
                it["pinned"] = not bool(it.get("pinned", False))
                break
        save_items(items)
        print(json.dumps(sort_items(items), ensure_ascii=False))
    elif op == "clear":
        items = [it for it in items if it.get("pinned")]
        save_items(items)
        print(json.dumps(sort_items(items), ensure_ascii=False))
PY
    python3 -c "$py_code" "$HISTORY_FILE" "$MAX_ENTRIES" "$MAX_BYTES" "$@"
}

is_sensitive_client_focused() {
    command -v mmsg >/dev/null 2>&1 || return 1
    local info
    info=$(timeout 0.5 mmsg get focusing-client 2>/dev/null || true)
    [[ -n "$info" ]] || return 1
    if printf '%s' "$info" | grep -qiE 'bitwarden|keepassxc|1password|enpass|protonpass|passff'; then
        return 0
    fi
    return 1
}

if [[ "$CMD" == "list" ]]; then
    py_store list
elif [[ "$CMD" == "add" ]]; then
    py_store add "$@"
elif [[ "$CMD" == "copy" ]]; then
    item_id="${1:?Missing clipboard item id}"
    if ! command -v wl-copy >/dev/null 2>&1; then
        echo "Error: wl-copy is required" >&2
        exit 1
    fi
    payload=$(py_store get "$item_id")
    if [[ -n "$payload" ]]; then
        printf '%s' "$payload" | wl-copy --type text/plain
    fi
elif [[ "$CMD" == "delete" ]]; then
    item_id="${1:?Missing clipboard item id}"
    py_store delete "$item_id"
elif [[ "$CMD" == "pin" ]]; then
    item_id="${1:?Missing clipboard item id}"
    py_store pin "$item_id"
elif [[ "$CMD" == "clear" ]]; then
    if command -v wl-copy >/dev/null 2>&1; then
        wl-copy --clear >/dev/null 2>&1 || true
        wl-copy --primary --clear >/dev/null 2>&1 || true
    fi
    py_store clear
elif [[ "$CMD" == "watch" ]]; then
    if ! command -v wl-paste >/dev/null 2>&1; then
        exit 0
    fi
    last_hash=""
    while true; do
        if ! is_sensitive_client_focused; then
            clip_txt=$(timeout 1.0 wl-paste --no-newline --type text/plain 2>/dev/null || true)
            if [[ -n "$clip_txt" && "${#clip_txt}" -le "$MAX_BYTES" ]]; then
                cur_hash=$(printf '%s' "$clip_txt" | sha256sum | awk '{print $1}')
                if [[ "$cur_hash" != "$last_hash" ]]; then
                    last_hash="$cur_hash"
                    if ! timeout 0.5 wl-paste --list-types 2>/dev/null | grep -qi "passwordManagerHint"; then
                        printf '%s' "$clip_txt" | py_store add
                    fi
                fi
            fi
        fi
        sleep 1.5
    done
fi
