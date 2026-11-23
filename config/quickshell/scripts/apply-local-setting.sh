#!/usr/bin/env bash
set -euo pipefail

# Manage per-device MangoWC overrides in ~/.config/mango/local.conf
# Usage:
#   apply-local-setting.sh get
#   apply-local-setting.sh set <key> <value>
#   apply-local-setting.sh set-monitor <name> <width> <height> <refresh> <scale> [rr] [vrr]
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
    "default_master_count": "int",
    "center_master_overspread": "bool",
    "monocle_no_border": "bool",
    "monocle_no_gap": "bool",
    "monocle_no_radius": "bool",
    "no_border_when_single": "bool",
    "no_radius_when_single": "bool",
    "enable_border_resize": "bool",
    "border_resize_size": "int",
    "dwindle_smart_split": "bool",
    "dwindle_smart_resize": "bool",
    "scroller_focus_center": "bool",
    "scroller_prefer_center": "bool",
    "scroller_prefer_overspread": "bool",
    "scroller_default_proportion_single": "float",
    "focus_cross_monitor": "bool",
    "focus_cross_tag": "bool",
    "exchange_cross_monitor": "bool",
    "scratchpad_cross_monitor": "bool",
    "tag_carousel": "bool",
    "enable_hotarea": "bool",
    "hotarea_size": "int",
    "hotarea_corner": "int",
    "hotarea_disable_on_fullscreen": "bool",
    "overview_gap_inner": "int",
    "overview_gap_outer": "int",
    "allow_tearing": "bool",
    "dim_enable": "bool",
    "disable_middle_paste": "bool",
    "xkb_rules_model": "str",
    "mouse_left_handed": "bool",
    "mouse_middle_button_emulation": "bool",
    "axis_scroll_factor": "float",
    "mouse_scroll_method": "int",
    "trackpad_left_handed": "bool",
    "trackpad_middle_button_emulation": "bool",
    "trackpad_scroll_factor": "float",
    "trackpad_click_method": "int",
    "trackpad_scroll_method": "int",
    "tap_and_drag": "bool",
    "drag_lock": "bool",
    "swipe_min_threshold": "int",
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
    "xkb_rules_layout": "us",
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
    "default_master_count": 1,
    "center_master_overspread": False,
    "monocle_no_border": False,
    "monocle_no_gap": False,
    "monocle_no_radius": False,
    "no_border_when_single": True,
    "no_radius_when_single": False,
    "enable_border_resize": True,
    "border_resize_size": 8,
    "dwindle_smart_split": True,
    "dwindle_smart_resize": False,
    "scroller_focus_center": False,
    "scroller_prefer_center": False,
    "scroller_prefer_overspread": False,
    "scroller_default_proportion_single": 1.0,
    "focus_cross_monitor": False,
    "focus_cross_tag": False,
    "exchange_cross_monitor": True,
    "scratchpad_cross_monitor": False,
    "tag_carousel": True,
    "enable_hotarea": False,
    "hotarea_size": 10,
    "hotarea_corner": 1,
    "hotarea_disable_on_fullscreen": True,
    "overview_gap_inner": 5,
    "overview_gap_outer": 30,
    "allow_tearing": False,
    "dim_enable": False,
    "disable_middle_paste": False,
    "xkb_rules_model": "pc105",
    "mouse_left_handed": False,
    "mouse_middle_button_emulation": False,
    "axis_scroll_factor": 1.0,
    "mouse_scroll_method": 0,
    "trackpad_left_handed": False,
    "trackpad_middle_button_emulation": False,
    "trackpad_scroll_factor": 1.0,
    "trackpad_click_method": 2,
    "trackpad_scroll_method": 1,
    "tap_and_drag": True,
    "drag_lock": False,
    "swipe_min_threshold": 1,
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
        elif key == "default_master_count":
            v = max(1, min(5, v))
        elif key == "border_resize_size":
            v = max(2, min(24, v))
        elif key == "hotarea_size":
            v = max(4, min(40, v))
        elif key == "hotarea_corner":
            v = max(1, min(4, v))
        elif key == "overview_gap_inner":
            v = max(0, min(40, v))
        elif key == "overview_gap_outer":
            v = max(0, min(60, v))
        elif key == "mouse_scroll_method":
            v = max(0, min(3, v))
        elif key == "trackpad_click_method":
            v = max(0, min(2, v))
        elif key == "trackpad_scroll_method":
            v = max(0, min(3, v))
        elif key == "swipe_min_threshold":
            v = max(1, min(10, v))
        return str(v)
    if kind == "float":
        v = round(float(raw_val), 2)
        if key in ("mouse_accel_speed", "trackpad_accel_speed"):
            v = max(-1.0, min(1.0, v))
        elif key == "default_master_factor":
            v = max(0.35, min(0.80, v))
        elif key in ("scroller_default_proportion", "scroller_default_proportion_single"):
            v = max(0.30, min(1.0, v))
        elif key in ("axis_scroll_factor", "trackpad_scroll_factor"):
            v = max(0.20, min(4.0, v))
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

def validate_and_write_local(content: str) -> None:
    had_local = os.path.isfile(local_conf)
    old_content = ""
    if had_local:
        with open(local_conf, "r", encoding="utf-8", errors="ignore") as f:
            old_content = f.read()
    atomic_write(local_conf, content)
    if shutil.which("mango"):
        res = subprocess.run(["mango", "-p"], capture_output=True, text=True)
        if res.returncode != 0:
            if had_local:
                atomic_write(local_conf, old_content)
            elif os.path.exists(local_conf):
                os.remove(local_conf)
            err = (res.stdout + "\n" + res.stderr).strip() or "MangoWC rejected rule"
            sys.stderr.write(err + "\n")
            sys.exit(2)

def get_tag_rules() -> dict:
    rules = {str(i): "tile" for i in range(1, 10)}
    pat = re.compile(r"^\s*tag_rule\s*=\s*.*?\bid:([1-9])\b.*?\blayout_name:([A-Za-z0-9_]+)")
    for path in (base_conf, local_conf):
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                m = pat.match(line)
                if m:
                    rules[m.group(1)] = m.group(2)
    return rules

def get_window_rules() -> list[str]:
    rules = []
    if os.path.isfile(local_conf):
        with open(local_conf, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                s = line.strip()
                if s.startswith("window_rule="):
                    rules.append(s.split("=", 1)[1].strip())
    return rules

def get_envs() -> list[dict]:
    envs = []
    if os.path.isfile(local_conf):
        with open(local_conf, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                s = line.strip()
                if s.startswith("env="):
                    body = s.split("=", 1)[1].strip()
                    if "," in body:
                        k, v = body.split(",", 1)
                        envs.append({"key": k.strip(), "value": v.strip()})
    return envs

def get_custom_binds() -> list[dict]:
    binds = []
    if os.path.isfile(local_conf):
        with open(local_conf, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                s = line.strip()
                if s.startswith("bind="):
                    body = s.split("=", 1)[1]
                    parts = [p.strip() for p in body.split(",", 3)]
                    if len(parts) >= 3:
                        binds.append({
                            "mods": parts[0],
                            "key": parts[1],
                            "action": parts[2],
                            "arg": parts[3] if len(parts) > 3 else "",
                            "raw": s,
                        })
    return binds

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
        sys.exit("Usage: apply-local-setting.sh set-monitor <name> <width> <height> <refresh> <scale> [rr] [vrr]")
    name, width, height, refresh, scale = args[:5]
    if not re.match(r"^[A-Za-z0-9._-]+$", name):
        sys.exit(f"Invalid monitor name: {name}")
    w = int(float(width))
    h = int(float(height))
    r_num = round(float(refresh), 2)
    r_str = str(int(r_num)) if float(r_num).is_integer() else f"{r_num:.2f}"
    s_num = round(float(scale), 2)
    s_str = str(int(s_num)) if float(s_num).is_integer() else f"{s_num:g}"
    rr_int = max(0, min(3, int(float(args[5])))) if len(args) >= 6 else 0
    vrr_int = 1 if (len(args) >= 7 and str(args[6]).strip().lower() in ("1", "true", "on", "yes", "enabled")) else 0

    rule_line = f"monitor_rule=name:{name},width:{w},height:{h},refresh:{r_str},scale:{s_str},rr:{rr_int},vrr:{vrr_int}\n"
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

elif cmd == "tag-rules-get":
    print(json.dumps(get_tag_rules(), separators=(",", ":")))

elif cmd == "tag-rule-set":
    if len(args) < 2:
        sys.exit("Usage: apply-local-setting.sh tag-rule-set <1..9> <layout_name>")
    tag_id = str(int(args[0]))
    layout = args[1].strip()
    if tag_id not in [str(i) for i in range(1, 10)]:
        sys.exit("Tag ID must be 1..9")
    valid_layouts = ("tile", "scroller", "grid", "monocle", "deck", "center_tile", "right_tile", "vertical_tile", "vertical_scroller", "dwindle")
    if layout not in valid_layouts:
        sys.exit(f"Invalid layout: {layout}")
    rule_line = f"tag_rule=id:{tag_id},layout_name:{layout}\n"
    lines = read_lines(local_conf)
    new_lines = []
    replaced = False
    tag_re = re.compile(rf"^\s*tag_rule\s*=.*\bid:{tag_id}\b")
    for line in lines:
        if tag_re.match(line):
            if not replaced:
                new_lines.append(rule_line)
                replaced = True
        else:
            new_lines.append(line)
    if not replaced:
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] += "\n"
        new_lines.append(rule_line)
    validate_and_write_local("".join(new_lines))
    reload_mango()
    print(json.dumps(get_tag_rules(), separators=(",", ":")))

elif cmd == "window-rules-get":
    print(json.dumps({"rules": get_window_rules()}, separators=(",", ":")))

elif cmd == "window-rule-add":
    if len(args) < 1:
        sys.exit("Usage: apply-local-setting.sh window-rule-add <rule_spec>")
    spec = " ".join(args).strip()
    if not spec or "\n" in spec or spec.startswith("window_rule="):
        spec = spec.replace("window_rule=", "", 1).strip()
    if not spec or "\n" in spec:
        sys.exit("Invalid window rule spec")
    lines = read_lines(local_conf)
    target_line = f"window_rule={spec}\n"
    if not any(line.strip() == f"window_rule={spec}" for line in lines):
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(target_line)
        validate_and_write_local("".join(lines))
        reload_mango()
    print(json.dumps({"rules": get_window_rules()}, separators=(",", ":")))

elif cmd == "window-rule-remove":
    if len(args) < 1:
        sys.exit("Usage: apply-local-setting.sh window-rule-remove <rule_spec>")
    spec = " ".join(args).strip()
    lines = read_lines(local_conf)
    kept = [line for line in lines if line.strip() != f"window_rule={spec}"]
    atomic_write(local_conf, "".join(kept))
    reload_mango()
    print(json.dumps({"rules": get_window_rules()}, separators=(",", ":")))

elif cmd == "env-list":
    print(json.dumps({"envs": get_envs()}, separators=(",", ":")))

elif cmd == "env-add":
    if len(args) < 2:
        sys.exit("Usage: apply-local-setting.sh env-add <KEY> <VALUE>")
    k = re.sub(r"[^A-Za-z0-9_]", "", args[0].strip())
    v = " ".join(args[1:]).strip()
    if not k or not v or "\n" in v:
        sys.exit("Invalid env key or value")
    env_line = f"env={k},{v}\n"
    lines = read_lines(local_conf)
    new_lines = []
    replaced = False
    env_re = re.compile(rf"^\s*env\s*=\s*{re.escape(k)},")
    for line in lines:
        if env_re.match(line):
            if not replaced:
                new_lines.append(env_line)
                replaced = True
        else:
            new_lines.append(line)
    if not replaced:
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] += "\n"
        new_lines.append(env_line)
    validate_and_write_local("".join(new_lines))
    reload_mango()
    print(json.dumps({"envs": get_envs()}, separators=(",", ":")))

elif cmd == "env-remove":
    if len(args) < 1:
        sys.exit("Usage: apply-local-setting.sh env-remove <KEY>")
    k = args[0].strip()
    lines = read_lines(local_conf)
    env_re = re.compile(rf"^\s*env\s*=\s*{re.escape(k)},")
    kept = [line for line in lines if not env_re.match(line)]
    atomic_write(local_conf, "".join(kept))
    reload_mango()
    print(json.dumps({"envs": get_envs()}, separators=(",", ":")))

elif cmd == "bind-list":
    print(json.dumps({"customBinds": get_custom_binds()}, separators=(",", ":")))

elif cmd == "bind-add":
    if len(args) < 3:
        sys.exit("Usage: apply-local-setting.sh bind-add <mods> <key> <action> [arg]")
    mods, bkey, action = args[0].strip(), args[1].strip(), args[2].strip()
    arg = " ".join(args[3:]).strip() if len(args) > 3 else ""
    if not mods or not bkey or not action or "\n" in (mods + bkey + action + arg):
        sys.exit("Invalid bind specification")
    bind_line = f"bind={mods},{bkey},{action},{arg}\n" if arg else f"bind={mods},{bkey},{action}\n"
    lines = read_lines(local_conf)
    if not any(line.strip() == bind_line.strip() for line in lines):
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.append(bind_line)
        validate_and_write_local("".join(lines))
        reload_mango()
    print(json.dumps({"customBinds": get_custom_binds()}, separators=(",", ":")))

elif cmd == "bind-remove":
    if len(args) < 1:
        sys.exit("Usage: apply-local-setting.sh bind-remove <raw_line>")
    raw_target = " ".join(args).strip()
    lines = read_lines(local_conf)
    kept = [line for line in lines if line.strip() != raw_target]
    atomic_write(local_conf, "".join(kept))
    reload_mango()
    print(json.dumps({"customBinds": get_custom_binds()}, separators=(",", ":")))

elif cmd == "reset":
    atomic_write(local_conf, HEADER)
    cur = merged_settings()
    sync_cursor_everywhere(str(cur["cursor_theme"]), int(cur["cursor_size"]))
    reload_mango()

else:
    sys.exit(f"Unknown command: {cmd}")
PY
