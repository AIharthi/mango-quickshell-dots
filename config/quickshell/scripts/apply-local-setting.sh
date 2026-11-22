#!/usr/bin/env bash
set -euo pipefail

# Manage per-device MangoWC overrides in ~/.config/mango/local.conf
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
import glob
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
    # Cursor & Pointer
    "cursor_theme": "str",
    "cursor_size": "int",
    "cursor_hide_timeout": "int",
    "cursor_hide_on_keypress": "bool",
    "mouse_accel_profile": "int",
    "mouse_accel_speed": "float",
    "trackpad_accel_profile": "int",
    "trackpad_accel_speed": "float",
    "mouse_natural_scrolling": "bool",
    "tap_to_click": "bool",
    "trackpad_natural_scrolling": "bool",
    "trackpad_disable_while_typing": "bool",
    "disable_trackpad": "bool",
    # Keyboard
    "xkb_rules_layout": "str",
    "xkb_rules_options": "str_allow_empty",
    "numlock_on": "bool",
    "repeat_rate": "int",
    "repeat_delay": "int",
    # Window Behavior & Tiling
    "sloppy_focus": "bool",
    "warp_cursor": "bool",
    "focus_on_activate": "bool",
    "new_is_master": "bool",
    "default_master_factor": "float",
    "smart_gaps": "bool",
    "enable_floating_snap": "bool",
    "snap_distance": "int",
    "drag_tile_to_tile": "bool",
    "scroller_default_proportion": "float",
}

DEFAULTS = {
    "cursor_theme": "catppuccin-mocha-dark-cursors",
    "cursor_size": 24,
    "cursor_hide_timeout": 0,
    "cursor_hide_on_keypress": False,
    "mouse_accel_profile": 2,
    "mouse_accel_speed": 0.0,
    "trackpad_accel_profile": 2,
    "trackpad_accel_speed": 0.0,
    "mouse_natural_scrolling": False,
    "tap_to_click": True,
    "trackpad_natural_scrolling": False,
    "trackpad_disable_while_typing": True,
    "disable_trackpad": False,
    "xkb_rules_layout": "us,ara",
    "xkb_rules_options": "grp:alt_shift_toggle",
    "numlock_on": False,
    "repeat_rate": 30,
    "repeat_delay": 450,
    "sloppy_focus": True,
    "warp_cursor": True,
    "focus_on_activate": True,
    "new_is_master": True,
    "default_master_factor": 0.55,
    "smart_gaps": False,
    "enable_floating_snap": True,
    "snap_distance": 24,
    "drag_tile_to_tile": True,
    "scroller_default_proportion": 0.8,
}

HEADER = "# Per-device MangoWC overrides (auto-managed by Quickshell Settings; untracked in git)\n"

def atomic_write(path: str, content: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
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
        return int(round(float(raw_val)))
    if kind == "float":
        return round(float(raw_val), 2)
    if kind == "bool":
        return str(raw_val).strip().lower() in ("1", "true", "yes", "on")
    return str(raw_val).strip()

def merged_settings() -> dict:
    merged = dict(DEFAULTS)
    for src in (base_conf, local_conf):
        kv = parse_kv(src)
        for k in ALLOWED_KEYS:
            if k in kv:
                try:
                    merged[k] = coerce(k, kv[k])
                except Exception:
                    pass
    return merged

def list_available_cursors() -> list[str]:
    home = os.path.expanduser("~")
    xdg_data = os.environ.get("XDG_DATA_HOME", os.path.join(home, ".local", "share"))
    roots = [
        os.path.join(home, ".icons"),
        os.path.join(xdg_data, "icons"),
        "/usr/local/share/icons",
        "/usr/share/icons",
    ]
    found = set()
    for root in roots:
        if not os.path.isdir(root):
            continue
        for entry in glob.glob(os.path.join(root, "*")):
            if os.path.isdir(os.path.join(entry, "cursors")):
                name = os.path.basename(entry)
                if name and name != "default":
                    found.add(name)
    if not found:
        found.add(DEFAULTS["cursor_theme"])
    return sorted(found, key=lambda s: s.lower())

def sync_cursor_everywhere(theme: str, size: int) -> None:
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.join(os.path.expanduser("~"), ".config"))
    for gtk_ver in ("gtk-3.0", "gtk-4.0"):
        ini = os.path.join(config_home, gtk_ver, "settings.ini")
        if os.path.isfile(ini):
            with open(ini, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
            out = []
            seen_name = False
            seen_size = False
            for line in lines:
                if re.match(r"^\s*gtk-cursor-theme-name\s*=", line):
                    out.append(f"gtk-cursor-theme-name={theme}\n")
                    seen_name = True
                elif re.match(r"^\s*gtk-cursor-theme-size\s*=", line):
                    out.append(f"gtk-cursor-theme-size={size}\n")
                    seen_size = True
                else:
                    out.append(line)
            if not seen_name:
                out.append(f"gtk-cursor-theme-name={theme}\n")
            if not seen_size:
                out.append(f"gtk-cursor-theme-size={size}\n")
            atomic_write(ini, "".join(out))
        else:
            atomic_write(ini, f"[Settings]\ngtk-cursor-theme-name={theme}\ngtk-cursor-theme-size={size}\n")

    default_icon_theme = os.path.join(os.path.expanduser("~"), ".icons", "default", "index.theme")
    atomic_write(default_icon_theme, f"[Icon Theme]\nInherits={theme}\n")

    if shutil.which("gsettings"):
        env = dict(os.environ)
        runtime_dir = env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        bus_sock = os.path.join(runtime_dir, "bus")
        if (not env.get("DBUS_SESSION_BUS_ADDRESS") or env.get("DBUS_SESSION_BUS_ADDRESS") == "disabled:") and os.path.exists(bus_sock):
            env["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={bus_sock}"
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(size)],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

def normalize_write_val(key: str, raw_val: str) -> str:
    kind = ALLOWED_KEYS[key]
    if kind == "int":
        v = int(round(float(raw_val)))
        if key == "repeat_rate":
            v = max(10, min(100, v))
        elif key == "repeat_delay":
            v = max(150, min(1000, v))
        elif key == "cursor_size":
            v = max(16, min(64, v))
        elif key == "cursor_hide_timeout":
            v = max(0, min(60, v))
        elif key in ("mouse_accel_profile", "trackpad_accel_profile"):
            v = 1 if v == 1 else 2
        elif key == "snap_distance":
            v = max(4, min(64, v))
        return str(v)
    if kind == "float":
        v = round(float(raw_val), 2)
        if key in ("mouse_accel_speed", "trackpad_accel_speed"):
            v = max(-1.0, min(1.0, v))
        elif key == "default_master_factor":
            v = max(0.35, min(0.80, v))
        elif key == "scroller_default_proportion":
            v = max(0.30, min(1.0, v))
        return f"{v:.2f}"
    if kind == "bool":
        return "1" if str(raw_val).strip().lower() in ("1", "true", "yes", "on") else "0"
    cleaned = re.sub(r"[^a-zA-Z0-9_.,:+/-]", "", str(raw_val).strip())
    if kind == "str" and not cleaned:
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
    merged = merged_settings()
    override_count = 0
    if os.path.isfile(local_conf):
        with open(local_conf, "r", encoding="utf-8", errors="ignore") as f:
            for raw in f:
                s = raw.strip()
                if s and not s.startswith("#"):
                    override_count += 1
    merged["overrideCount"] = override_count
    merged["availableCursors"] = list_available_cursors()
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
    if key in ("cursor_theme", "cursor_size"):
        cur = merged_settings()
        sync_cursor_everywhere(str(cur["cursor_theme"]), int(cur["cursor_size"]))
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
    cur = merged_settings()
    sync_cursor_everywhere(str(cur["cursor_theme"]), int(cur["cursor_size"]))
    reload_mango()

else:
    sys.exit(f"Unknown command: {cmd}")
PY
