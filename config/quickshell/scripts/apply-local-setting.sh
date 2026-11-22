#!/usr/bin/env bash
set -euo pipefail

# Manage per-device hardware/input/monitor overrides in ~/.config/mango/local.conf
# Usage:
#   apply-local-setting.sh get
#   apply-local-setting.sh set <key> <value>
#   apply-local-setting.sh set-monitor <name> <width> <height> <refresh> <scale>
#   apply-local-setting.sh reset

MANGO_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
BASE_CONF="$MANGO_DIR/config.conf"
LOCAL_CONF="$MANGO_DIR/local.conf"
mkdir -p "$MANGO_DIR"

CMD="${1:-get}"
shift || true

python3 - "$CMD" "$BASE_CONF" "$LOCAL_CONF" "$@" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys

cmd = sys.argv[1]
base_conf = sys.argv[2]
local_conf = sys.argv[3]
args = sys.argv[4:]

ALLOWED_KEYS = {
    "xkb_rules_layout": "str",
    "repeat_rate": "int",
    "repeat_delay": "int",
    "cursor_size": "int",
    "mouse_natural_scrolling": "bool",
    "tap_to_click": "bool",
    "trackpad_natural_scrolling": "bool",
    "trackpad_disable_while_typing": "bool",
    "disable_trackpad": "bool",
}

DEFAULTS = {
    "xkb_rules_layout": "us,ara",
    "repeat_rate": 30,
    "repeat_delay": 450,
    "cursor_size": 24,
    "mouse_natural_scrolling": False,
    "tap_to_click": True,
    "trackpad_natural_scrolling": False,
    "trackpad_disable_while_typing": True,
    "disable_trackpad": False,
}

HEADER = "# Per-device MangoWC overrides (auto-managed by Quickshell Settings; untracked in git)\n"

def atomic_write(path: str, content: str) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, path)

def reload_mango() -> None:
    if shutil.which("mmsg"):
        res = subprocess.run(["mmsg", "dispatch", "reload_config"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode != 0:
            subprocess.run(["mmsg", "-s", "-d", "reload_config"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def parse_kv(path: str) -> dict:
    vals = {}
    if not os.path.isfile(path):
        return vals
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    return vals

def coerce(key: str, raw_val: str):
    kind = ALLOWED_KEYS[key]
    if kind == "int":
        return int(float(raw_val))
    if kind == "bool":
        return str(raw_val).strip().lower() in ("1", "true", "yes", "on")
    return str(raw_val).strip()

def normalize_write_val(key: str, raw_val: str) -> str:
    kind = ALLOWED_KEYS[key]
    if kind == "int":
        v = int(float(raw_val))
        if key == "repeat_rate":
            v = max(10, min(100, v))
        elif key == "repeat_delay":
            v = max(150, min(1000, v))
        elif key == "cursor_size":
            v = max(16, min(64, v))
        return str(v)
    if kind == "bool":
        return "1" if str(raw_val).strip().lower() in ("1", "true", "yes", "on") else "0"
    cleaned = re.sub(r"[^a-zA-Z0-9_,+-]", "", str(raw_val).strip())
    if not cleaned:
        raise ValueError(f"Invalid value for {key}")
    return cleaned

def read_lines(path: str) -> list[str]:
    if not os.path.isfile(path):
        return [HEADER]
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    if not lines:
        return [HEADER]
    return lines

if cmd == "get":
    merged = dict(DEFAULTS)
    base_kv = parse_kv(base_conf)
    local_kv = parse_kv(local_conf)
    for k in ALLOWED_KEYS:
        if k in base_kv:
            try:
                merged[k] = coerce(k, base_kv[k])
            except Exception:
                pass
        if k in local_kv:
            try:
                merged[k] = coerce(k, local_kv[k])
            except Exception:
                pass

    override_count = 0
    if os.path.isfile(local_conf):
        with open(local_conf, "r", encoding="utf-8", errors="ignore") as f:
            for raw in f:
                s = raw.strip()
                if s and not s.startswith("#"):
                    override_count += 1
    merged["overrideCount"] = override_count
    print(json.dumps(merged, separators=(",", ":")))

elif cmd == "set":
    if len(args) < 2:
        sys.exit("Usage: apply-local-setting.sh set <key> <value>")
    key, raw_val = args[0], args[1]
    if key not in ALLOWED_KEYS:
        sys.exit(f"Unsupported key: {key}")
    val_str = normalize_write_val(key, raw_val)
    lines = read_lines(local_conf)
    new_lines = []
    replaced = False
    key_re = re.compile(rf"^\s*{re.escape(key)}\s*=")
    for line in lines:
        if key_re.match(line):
            if not replaced:
                new_lines.append(f"{key}={val_str}\n")
                replaced = True
        else:
            new_lines.append(line)
    if not replaced:
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] += "\n"
        new_lines.append(f"{key}={val_str}\n")
    atomic_write(local_conf, "".join(new_lines))
    reload_mango()

elif cmd == "set-monitor":
    if len(args) < 5:
        sys.exit("Usage: apply-local-setting.sh set-monitor <name> <width> <height> <refresh> <scale>")
    name, width, height, refresh, scale = args[:5]
    if not re.match(r"^[A-Za-z0-9._-]+$", name):
        sys.exit(f"Invalid monitor name: {name}")
    w = int(float(width))
    h = int(float(height))
    r_num = round(float(refresh), 2)
    r_str = str(int(r_num)) if float(r_num).is_integer() else f"{r_num:.2f}"
    s_num = round(float(scale), 2)
    s_str = str(int(s_num)) if float(s_num).is_integer() else f"{s_num:g}"

    rule_line = f"monitor_rule=name:{name},width:{w},height:{h},refresh:{r_str},scale:{s_str}\n"
    lines = read_lines(local_conf)
    new_lines = []
    replaced = False
    mon_re = re.compile(rf"^\s*monitor_rule\s*=.*\bname:{re.escape(name)}(?:,|$)")
    for line in lines:
        if mon_re.match(line):
            if not replaced:
                new_lines.append(rule_line)
                replaced = True
        else:
            new_lines.append(line)
    if not replaced:
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] += "\n"
        new_lines.append(rule_line)
    atomic_write(local_conf, "".join(new_lines))
    reload_mango()

elif cmd == "reset":
    atomic_write(local_conf, HEADER)
    reload_mango()

else:
    sys.exit(f"Unknown command: {cmd}")
PY
