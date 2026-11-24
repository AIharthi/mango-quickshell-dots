#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
shift || true

case "$CMD" in
    gtk-get|gtk-set|terminal-get|terminal-set|network-info|network-action|power-action|audio-cards|audio-set-profile|audio-test|privacy-get|privacy-set|clear-clipboard|clear-recent|hwmon|processes|kill-proc|services|service-action|user-info|backup-settings|list-backups|restore-settings|doctor)
        ;;
    *)
        echo "Usage: manage-system.sh <gtk-get|gtk-set|terminal-get|terminal-set|network-info|network-action|power-action|audio-cards|audio-set-profile|audio-test|privacy-get|privacy-set|clear-clipboard|clear-recent|hwmon|processes|kill-proc|services|service-action|user-info|backup-settings|list-backups|restore-settings|doctor> [args...]" >&2
        exit 1
        ;;
esac

BACKEND_BIN="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bin/aurora-backend"
if [[ -x "$BACKEND_BIN" ]]; then
    case "$CMD" in
        hwmon|processes|doctor)
            exec "$BACKEND_BIN" "$CMD" "$@"
            ;;
    esac
fi

exec python3 - "$CMD" "$@" <<'PY'
import glob
import grp
import json
import os
import pwd
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time

cmd = sys.argv[1]
args = sys.argv[2:]

CONFIG_DIR = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
DATA_DIR = os.path.expanduser(os.environ.get("XDG_DATA_HOME", "~/.local/share"))
QS_DIR = os.path.join(CONFIG_DIR, "quickshell")
MANGO_DIR = os.path.join(CONFIG_DIR, "mango")
PREFS_FILE = os.path.join(QS_DIR, "shell-prefs.json")


def atomic_write(path, content):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def run_out(argv, timeout=4.0):
    try:
        return subprocess.check_output(argv, text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()
    except Exception:
        return ""


def gsettings_get(schema, key, fallback):
    if not shutil.which("gsettings"):
        return fallback
    val = run_out(["gsettings", "get", schema, key])
    if not val:
        return fallback
    if val.startswith("'") and val.endswith("'"):
        return val[1:-1]
    if val == "true":
        return True
    if val == "false":
        return False
    try:
        if "." in val:
            return float(val)
        return int(val)
    except ValueError:
        return val


def list_icon_themes():
    themes = set()
    for base in (os.path.join(DATA_DIR, "icons"), "/usr/share/icons"):
        if not os.path.isdir(base):
            continue
        try:
            entries = os.listdir(base)
        except Exception:
            continue
        for name in entries:
            idx = os.path.join(base, name, "index.theme")
            if not os.path.isfile(idx):
                continue
            try:
                with open(idx, "r", encoding="utf-8", errors="ignore") as f:
                    txt = f.read()
                m = re.search(r"^Directories\s*=\s*(.+)$", txt, re.M)
                if m and m.group(1).strip():
                    themes.add(name)
            except Exception:
                continue
    if "Adwaita" not in themes and os.path.isdir("/usr/share/icons/Adwaita"):
        themes.add("Adwaita")
    return sorted(themes, key=str.lower)


def update_ini_kv(path, key, value):
    lines = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    else:
        lines = ["[Settings]\n"]
    out = []
    found = False
    for line in lines:
        if re.match(rf"^\s*{re.escape(key)}\s*=", line):
            out.append(f"{key}={value}\n")
            found = True
        else:
            out.append(line)
    if not found:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        out.append(f"{key}={value}\n")
    atomic_write(path, "".join(out))


def update_pref_key(key, value):
    if not os.path.isfile(PREFS_FILE):
        return
    try:
        with open(PREFS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            data[key] = value
            atomic_write(PREFS_FILE, json.dumps(data, indent=2) + "\n")
    except Exception:
        pass


def cmd_gtk_get():
    payload = {
        "hasGsettings": bool(shutil.which("gsettings")),
        "iconTheme": str(gsettings_get("org.gnome.desktop.interface", "icon-theme", "Adwaita")),
        "availableIconThemes": list_icon_themes(),
        "fontHinting": str(gsettings_get("org.gnome.desktop.interface", "font-hinting", "slight")),
        "fontAntialiasing": str(gsettings_get("org.gnome.desktop.interface", "font-antialiasing", "grayscale")),
        "fontRgbaOrder": str(gsettings_get("org.gnome.desktop.interface", "font-rgba-order", "rgb")),
        "textScalingFactor": float(gsettings_get("org.gnome.desktop.interface", "text-scaling-factor", 1.0)),
        "enableAnimations": bool(gsettings_get("org.gnome.desktop.interface", "enable-animations", True)),
        "cursorBlink": bool(gsettings_get("org.gnome.desktop.interface", "cursor-blink", True)),
        "cursorBlinkTime": int(gsettings_get("org.gnome.desktop.interface", "cursor-blink-time", 1200)),
        "primaryPaste": bool(gsettings_get("org.gnome.desktop.interface", "gtk-enable-primary-paste", True)),
    }
    print(json.dumps(payload))


def cmd_gtk_set():
    if len(args) < 2:
        sys.exit("Usage: manage-system.sh gtk-set <key> <value>")
    key, val = args[0], args[1]
    allowed = {
        "icon-theme": "str",
        "font-hinting": "str",
        "font-antialiasing": "str",
        "font-rgba-order": "str",
        "text-scaling-factor": "float",
        "enable-animations": "bool",
        "cursor-blink": "bool",
        "cursor-blink-time": "int",
        "gtk-enable-primary-paste": "bool",
    }
    if key not in allowed:
        sys.exit(f"Unsupported GTK key: {key}")

    kind = allowed[key]
    if kind == "bool":
        clean_val = "true" if str(val).lower() in ("1", "true", "yes", "on") else "false"
    elif kind == "float":
        clean_val = f"{max(0.75, min(2.0, float(val))):.2f}"
    elif kind == "int":
        clean_val = str(max(200, min(2500, int(float(val)))))
    else:
        clean_val = re.sub(r"[^A-Za-z0-9._+-]", "", str(val).strip())
        if not clean_val:
            sys.exit("Invalid GTK string value")

    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", key, clean_val], stderr=subprocess.DEVNULL)

    gtk3 = os.path.join(CONFIG_DIR, "gtk-3.0", "settings.ini")
    gtk4 = os.path.join(CONFIG_DIR, "gtk-4.0", "settings.ini")
    if key == "icon-theme":
        for p in (gtk3, gtk4):
            update_ini_kv(p, "gtk-icon-theme-name", clean_val)
        update_pref_key("iconTheme", clean_val)
    elif key == "gtk-enable-primary-paste":
        for p in (gtk3, gtk4):
            update_ini_kv(p, "gtk-enable-primary-paste", "1" if clean_val == "true" else "0")

    cmd_gtk_get()


def parse_foot_ini(path):
    res = {
        "exists": os.path.isfile(path),
        "alpha": 1.0,
        "pad": 10,
        "cursorStyle": "block",
        "cursorBlink": False,
        "scrollback": 1000,
    }
    if not res["exists"]:
        return res
    section = "main"
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for raw in f:
                s = raw.strip()
                if not s or s.startswith("#") or s.startswith(";"):
                    continue
                if s.startswith("[") and s.endswith("]"):
                    section = s[1:-1].strip().lower()
                    continue
                if "=" not in s:
                    continue
                k, v = [x.strip() for x in s.split("=", 1)]
                if section == "colors" and k == "alpha":
                    res["alpha"] = max(0.5, min(1.0, float(v)))
                elif section == "main" and k == "pad":
                    m = re.match(r"(\d+)", v)
                    if m:
                        res["pad"] = int(m.group(1))
                elif section == "cursor" and k == "style":
                    if v in ("block", "underline", "beam"):
                        res["cursorStyle"] = v
                elif section == "cursor" and k == "blink":
                    res["cursorBlink"] = v.lower() in ("yes", "true", "1")
                elif section == "scrollback" and k == "lines":
                    res["scrollback"] = int(v)
    except Exception:
        pass
    return res


def update_ini_section_kv(path, target_section, key, value):
    lines = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

    out = []
    cur_sec = "main"
    inserted = False
    sec_re = re.compile(r"^\s*\[([^\]]+)\]\s*$")
    kv_re = re.compile(rf"^\s*{re.escape(key)}\s*=")

    for line in lines:
        m = sec_re.match(line)
        if m:
            if cur_sec == target_section and not inserted:
                out.append(f"{key}={value}\n")
                inserted = True
            cur_sec = m.group(1).strip().lower()
            out.append(line)
            continue
        if cur_sec == target_section and kv_re.match(line):
            if not inserted:
                out.append(f"{key}={value}\n")
                inserted = True
            continue
        out.append(line)

    if not inserted:
        if cur_sec == target_section:
            if out and not out[-1].endswith("\n"):
                out[-1] += "\n"
            out.append(f"{key}={value}\n")
        else:
            if out and not out[-1].endswith("\n"):
                out[-1] += "\n"
            out.append(f"\n[{target_section}]\n{key}={value}\n")

    atomic_write(path, "".join(out))


def parse_kitty_conf(path):
    res = {
        "exists": os.path.isfile(path),
        "opacity": 1.0,
        "padding": 10,
        "cursorShape": "block",
        "cursorBlink": 0.5,
        "scrollback": 2000,
        "confirmClose": 0,
    }
    if not res["exists"]:
        return res
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for raw in f:
                s = raw.strip()
                if not s or s.startswith("#"):
                    continue
                parts = s.split(None, 1)
                if len(parts) < 2:
                    continue
                k, v = parts[0], parts[1].strip()
                if k == "background_opacity":
                    res["opacity"] = max(0.5, min(1.0, float(v)))
                elif k == "window_padding_width":
                    res["padding"] = int(float(v.split()[0]))
                elif k == "cursor_shape" and v in ("block", "beam", "underline"):
                    res["cursorShape"] = v
                elif k == "cursor_blink_interval":
                    res["cursorBlink"] = float(v)
                elif k == "scrollback_lines":
                    res["scrollback"] = int(float(v))
                elif k == "confirm_os_window_close":
                    res["confirmClose"] = int(float(v))
    except Exception:
        pass
    return res


def update_kitty_kv(path, key, value):
    lines = []
    if os.path.isfile(path):
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    out = []
    found = False
    kv_re = re.compile(rf"^\s*{re.escape(key)}\s+")
    for line in lines:
        if kv_re.match(line):
            if not found:
                out.append(f"{key} {value}\n")
                found = True
        else:
            out.append(line)
    if not found:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        out.append(f"{key} {value}\n")
    atomic_write(path, "".join(out))
    subprocess.run(["pkill", "-USR1", "kitty"], stderr=subprocess.DEVNULL)


def cmd_terminal_get():
    foot_path = os.path.join(CONFIG_DIR, "foot", "foot.ini")
    kitty_path = os.path.join(CONFIG_DIR, "kitty", "kitty.conf")
    print(json.dumps({"foot": parse_foot_ini(foot_path), "kitty": parse_kitty_conf(kitty_path)}))


def cmd_terminal_set():
    if len(args) < 3:
        sys.exit("Usage: manage-system.sh terminal-set <foot|kitty> <key> <value>")
    term, key, val = args[0].lower(), args[1], args[2]
    if term == "foot":
        foot_path = os.path.join(CONFIG_DIR, "foot", "foot.ini")
        if key == "alpha":
            v = f"{max(0.50, min(1.00, float(val))):.2f}"
            update_ini_section_kv(foot_path, "colors", "alpha", v)
        elif key == "pad":
            n = max(0, min(32, int(float(val))))
            update_ini_section_kv(foot_path, "main", "pad", f"{n}x{n}")
        elif key == "cursorStyle":
            if val not in ("block", "underline", "beam"):
                sys.exit("Invalid foot cursorStyle")
            update_ini_section_kv(foot_path, "cursor", "style", val)
        elif key == "cursorBlink":
            b = "yes" if str(val).lower() in ("1", "true", "yes", "on") else "no"
            update_ini_section_kv(foot_path, "cursor", "blink", b)
        elif key == "scrollback":
            n = max(500, min(100000, int(float(val))))
            update_ini_section_kv(foot_path, "scrollback", "lines", str(n))
        else:
            sys.exit(f"Unsupported foot key: {key}")
    elif term == "kitty":
        kitty_path = os.path.join(CONFIG_DIR, "kitty", "kitty.conf")
        if key == "opacity":
            v = f"{max(0.50, min(1.00, float(val))):.2f}"
            update_kitty_kv(kitty_path, "background_opacity", v)
        elif key == "padding":
            n = max(0, min(32, int(float(val))))
            update_kitty_kv(kitty_path, "window_padding_width", str(n))
        elif key == "cursorShape":
            if val not in ("block", "beam", "underline"):
                sys.exit("Invalid kitty cursorShape")
            update_kitty_kv(kitty_path, "cursor_shape", val)
        elif key == "cursorBlink":
            v = f"{max(-1.0, min(2.0, float(val))):.1f}"
            update_kitty_kv(kitty_path, "cursor_blink_interval", v)
        elif key == "scrollback":
            n = max(500, min(100000, int(float(val))))
            update_kitty_kv(kitty_path, "scrollback_lines", str(n))
        elif key == "confirmClose":
            n = 1 if str(val).lower() in ("1", "true", "yes", "on") else 0
            update_kitty_kv(kitty_path, "confirm_os_window_close", str(n))
        else:
            sys.exit(f"Unsupported kitty key: {key}")
    else:
        sys.exit(f"Unknown terminal: {term}")
    cmd_terminal_get()


def cmd_network_info():
    ifaces = []
    addr_raw = run_out(["ip", "-j", "addr"])
    if addr_raw:
        try:
            for item in json.loads(addr_raw):
                name = item.get("ifname", "")
                if not name or name == "lo":
                    continue
                addrs = []
                for a in item.get("addr_info", []):
                    if a.get("family") in ("inet", "inet6") and a.get("scope") != "host":
                        addrs.append(f"{a.get('local')}/{a.get('prefixlen')}")
                sys_base = f"/sys/class/net/{name}"
                speed_str = ""
                try:
                    with open(f"{sys_base}/speed", "r") as sf:
                        sp = int(sf.read().strip())
                        if sp > 0:
                            speed_str = f"{sp} Mbps"
                except Exception:
                    pass
                rx_mb, tx_mb = 0.0, 0.0
                try:
                    with open(f"{sys_base}/statistics/rx_bytes", "r", encoding="utf-8") as rf:
                        rx_mb = round(int(rf.read().strip()) / (1024 ** 2), 1)
                    with open(f"{sys_base}/statistics/tx_bytes", "r", encoding="utf-8") as tf:
                        tx_mb = round(int(tf.read().strip()) / (1024 ** 2), 1)
                except Exception:
                    pass
                is_wifi = os.path.isdir(f"{sys_base}/wireless") or os.path.isdir(f"{sys_base}/phy80211")
                ifaces.append({
                    "name": name,
                    "kind": "wifi" if is_wifi else "ethernet",
                    "state": item.get("operstate", "UNKNOWN"),
                    "mac": item.get("address", ""),
                    "speed": speed_str,
                    "addrs": addrs,
                    "rxMb": rx_mb,
                    "txMb": tx_mb,
                })
        except Exception:
            pass

    gateway = ""
    route_raw = run_out(["ip", "-j", "route", "show", "default"])
    if route_raw:
        try:
            routes = json.loads(route_raw)
            if routes:
                gateway = routes[0].get("gateway", "")
        except Exception:
            pass

    dns = []
    if os.path.isfile("/etc/resolv.conf"):
        try:
            with open("/etc/resolv.conf", "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    s = line.strip()
                    if s.startswith("nameserver "):
                        dns.append(s.split()[1])
        except Exception:
            pass

    connections = []
    has_nmcli = bool(shutil.which("nmcli"))
    if has_nmcli:
        nm_out = run_out(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show"], timeout=3.0)
        for line in nm_out.splitlines():
            parts = re.split(r"(?<!\\):", line)
            if len(parts) >= 4:
                cname = parts[0].replace("\\:", ":")
                ctype, cdev, cstate = parts[1], parts[2], parts[3]
                if ctype == "loopback":
                    continue
                connections.append({"name": cname, "type": ctype, "device": cdev, "active": cstate == "activated", "state": cstate})

    print(json.dumps({
        "interfaces": ifaces,
        "gateway": gateway,
        "dns": dns,
        "hasNmcli": has_nmcli,
        "connections": connections,
    }))


def cmd_network_action():
    if not shutil.which("nmcli"):
        sys.exit("nmcli is not available")
    if len(args) < 1:
        sys.exit("Usage: manage-system.sh network-action <up|down|dns|wifi-disconnect> [conn] [dns_servers]")
    act = args[0]
    if act == "wifi-disconnect":
        dev_raw = run_out(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "dev"], timeout=3.0)
        for line in dev_raw.splitlines():
            parts = line.split(":")
            if len(parts) >= 2 and parts[1] == "wifi" and (len(parts) < 3 or parts[2] == "connected"):
                subprocess.run(["timeout", "5", "nmcli", "dev", "disconnect", parts[0]], stderr=subprocess.DEVNULL)
                break
        cmd_network_info()
        return
    if len(args) < 2:
        sys.exit("Missing connection name")
    conn = args[1]
    if act == "up":
        subprocess.run(["timeout", "8", "nmcli", "connection", "up", "id", conn], stderr=subprocess.DEVNULL)
    elif act == "down":
        subprocess.run(["timeout", "8", "nmcli", "connection", "down", "id", conn], stderr=subprocess.DEVNULL)
    elif act == "dns":
        dns_val = " ".join(args[2:]).strip() if len(args) >= 3 else "auto"
        if dns_val == "auto" or not dns_val:
            subprocess.run(["nmcli", "connection", "modify", "id", conn, "ipv4.ignore-auto-dns", "no", "ipv4.dns", ""], stderr=subprocess.DEVNULL)
        else:
            if not re.match(r"^[0-9a-fA-F.: ]+$", dns_val):
                sys.exit("Invalid DNS IP list")
            subprocess.run(["nmcli", "connection", "modify", "id", conn, "ipv4.ignore-auto-dns", "yes", "ipv4.dns", dns_val], stderr=subprocess.DEVNULL)
        subprocess.run(["timeout", "8", "nmcli", "connection", "up", "id", conn], stderr=subprocess.DEVNULL)
    else:
        sys.exit(f"Unknown network action: {act}")
    cmd_network_info()


def cmd_power_action():
    if len(args) < 1 or args[0] not in ("suspend", "reboot", "poweroff"):
        sys.exit("Usage: manage-system.sh power-action <suspend|reboot|poweroff>")
    act = args[0]
    if shutil.which("loginctl"):
        res = subprocess.run(["loginctl", act], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode == 0:
            return
    if shutil.which("systemctl") and os.path.isdir("/run/systemd/system"):
        subprocess.Popen(["systemctl", act], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    fallback_map = {
        "suspend": ["zzz"],
        "reboot": ["reboot"],
        "poweroff": ["poweroff"],
    }
    for exe in fallback_map[act]:
        if shutil.which(exe):
            subprocess.Popen([exe], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
    sys.exit(f"No supported power backend found for '{act}'")


def cmd_audio_cards():
    raw = run_out(["pactl", "--format=json", "list", "cards"])
    cards = []
    if raw:
        try:
            for c in json.loads(raw):
                props = c.get("properties") or {}
                desc = props.get("device.description") or props.get("alsa.card_name") or c.get("name", "")
                profs = []
                for pname, pmeta in (c.get("profiles") or {}).items():
                    if not pmeta.get("available", True):
                        continue
                    profs.append({"name": pname, "desc": pmeta.get("description") or pname})
                cards.append({
                    "name": c.get("name", ""),
                    "desc": desc,
                    "activeProfile": c.get("active_profile") or "",
                    "profiles": profs,
                })
        except Exception:
            pass
    print(json.dumps({"cards": cards}))


def cmd_audio_set_profile():
    if len(args) < 2:
        sys.exit("Usage: manage-system.sh audio-set-profile <card> <profile>")
    subprocess.run(["pactl", "set-card-profile", args[0], args[1]], check=False)
    cmd_audio_cards()


def cmd_audio_test():
    ch = args[0].lower() if args else "stereo"
    if shutil.which("speaker-test"):
        cmd_vec = ["timeout", "0.9", "speaker-test", "-c", "2", "-t", "sine", "-f", "440", "-l", "1"]
        if ch == "left":
            cmd_vec += ["-s", "1"]
        elif ch == "right":
            cmd_vec += ["-s", "2"]
        subprocess.run(cmd_vec, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif shutil.which("paplay"):
        for snd in (
            "/usr/share/sounds/freedesktop/stereo/audio-channel-front-left.oga",
            "/usr/share/sounds/freedesktop/stereo/bell.oga",
            "/usr/share/sounds/freedesktop/stereo/message.oga",
        ):
            if os.path.isfile(snd):
                subprocess.run(["paplay", snd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                break
    print(json.dumps({"tested": ch}))


def cmd_privacy_get():
    xbel = os.path.join(DATA_DIR, "recently-used.xbel")
    xbel_kb = round(os.path.getsize(xbel) / 1024.0, 1) if os.path.isfile(xbel) else 0.0
    print(json.dumps({
        "hasGsettings": bool(shutil.which("gsettings")),
        "rememberRecent": bool(gsettings_get("org.gnome.desktop.privacy", "remember-recent-files", True)),
        "rememberApps": bool(gsettings_get("org.gnome.desktop.privacy", "remember-app-usage", True)),
        "disableCamera": bool(gsettings_get("org.gnome.desktop.privacy", "disable-camera", False)),
        "disableMicrophone": bool(gsettings_get("org.gnome.desktop.privacy", "disable-microphone", False)),
        "hideIdentity": bool(gsettings_get("org.gnome.desktop.privacy", "hide-identity", False)),
        "recentExists": os.path.isfile(xbel),
        "recentSizeKb": xbel_kb,
    }))


def cmd_privacy_set():
    if len(args) < 2:
        sys.exit("Usage: manage-system.sh privacy-set <key> <bool>")
    key, raw = args[0], args[1]
    allowed = ("remember-recent-files", "remember-app-usage", "disable-camera", "disable-microphone", "hide-identity")
    if key not in allowed:
        sys.exit(f"Unsupported privacy key: {key}")
    b = str(raw).lower() in ("1", "true", "yes", "on")
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.privacy", key, "true" if b else "false"], stderr=subprocess.DEVNULL)
    if key == "disable-microphone" and shutil.which("pactl"):
        subprocess.run(["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "1" if b else "0"], stderr=subprocess.DEVNULL)
    cmd_privacy_get()


def cmd_clear_clipboard():
    if shutil.which("wl-copy"):
        subprocess.run(["wl-copy", "--clear"], stderr=subprocess.DEVNULL)
        subprocess.run(["wl-copy", "-p", "--clear"], stderr=subprocess.DEVNULL)
    print(json.dumps({"cleared": True}))


def cmd_clear_recent():
    xbel = os.path.join(DATA_DIR, "recently-used.xbel")
    if os.path.isfile(xbel):
        os.remove(xbel)
    cmd_privacy_get()


def cmd_hwmon():
    sensors = []
    for hw in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        try:
            with open(os.path.join(hw, "name"), "r", encoding="utf-8", errors="ignore") as nf:
                chip = nf.read().strip()
        except Exception:
            chip = os.path.basename(hw)
        for inp in sorted(glob.glob(os.path.join(hw, "temp*_input"))):
            base = inp[:-6]
            try:
                with open(inp, "r", encoding="utf-8", errors="ignore") as vf:
                    val = int(vf.read().strip()) / 1000.0
            except Exception:
                continue
            if val < -20 or val > 180:
                continue
            lbl = ""
            try:
                with open(base + "_label", "r", encoding="utf-8", errors="ignore") as lf:
                    lbl = lf.read().strip()
            except Exception:
                lbl = os.path.basename(base)
            crit = 100.0
            try:
                with open(base + "_crit", "r", encoding="utf-8", errors="ignore") as cf:
                    cval = int(cf.read().strip()) / 1000.0
                if 30.0 <= cval <= 150.0:
                    crit = cval
            except Exception:
                pass
            sensors.append({
                "chip": chip,
                "label": lbl,
                "tempC": round(val, 1),
                "critC": round(crit, 1),
            })
    print(json.dumps({"sensors": sensors}))


def cmd_processes():
    sort_mode = args[0].lower() if args else "cpu"
    sort_flag = "--sort=-rss" if sort_mode == "mem" else "--sort=-pcpu"
    out = run_out(["ps", "-eo", "pid,pcpu,rss,comm", "--no-headers", sort_flag], timeout=3.0)
    procs = []
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        try:
            pid = int(parts[0])
            cpu = float(parts[1])
            mem_mb = round(int(parts[2]) / 1024.0, 1)
            comm = parts[3].strip()
        except Exception:
            continue
        if pid <= 1:
            continue
        procs.append({"pid": pid, "cpuPct": cpu, "memMb": mem_mb, "name": comm})
        if len(procs) >= 25:
            break
    print(json.dumps({"sort": sort_mode, "processes": procs}))


def cmd_kill_proc():
    if len(args) < 1:
        sys.exit("Usage: manage-system.sh kill-proc <pid> [TERM|KILL]")
    pid = int(args[0])
    sig_name = args[1].upper() if len(args) >= 2 else "TERM"
    if pid <= 1 or pid == os.getpid():
        sys.exit("Refusing to signal protected PID")
    comm = ""
    try:
        with open(f"/proc/{pid}/comm", "r", encoding="utf-8", errors="ignore") as cf:
            comm = cf.read().strip()
    except Exception:
        pass
    if comm in ("mango", "qs", "quickshell", "systemd", "openrc-init", "init"):
        sys.exit(f"Refusing to terminate critical session process: {comm}")
    sig = signal.SIGKILL if sig_name == "KILL" else signal.SIGTERM
    os.kill(pid, sig)
    print(json.dumps({"signaled": pid, "signal": sig_name}))


def cmd_services():
    svcs = []
    init_sys = "unknown"
    if shutil.which("rc-status"):
        init_sys = "openrc"
        out = run_out(["rc-status", "-a"], timeout=3.0)
        cur_runlevel = "default"
        for line in out.splitlines():
            s = line.strip()
            if s.startswith("Runlevel:"):
                cur_runlevel = s.split(":", 1)[1].strip()
            elif "[" in line and "]" in line:
                m = re.match(r"^\s*([^\s\[]+)\s+\[\s*([^\]]+?)\s*\]", line)
                if m:
                    svcs.append({"name": m.group(1), "status": m.group(2).strip(), "scope": cur_runlevel})
    elif shutil.which("systemctl") and os.path.isdir("/run/systemd/system"):
        init_sys = "systemd"
        out = run_out(["systemctl", "--user", "list-units", "--type=service", "--no-pager", "--no-legend"], timeout=3.0)
        for line in out.splitlines():
            parts = line.split(None, 4)
            if len(parts) >= 4:
                svcs.append({"name": parts[0].replace(".service", ""), "status": parts[3], "scope": "user"})
    print(json.dumps({"initSystem": init_sys, "services": svcs}))


def cmd_service_action():
    if len(args) < 2:
        sys.exit("Usage: manage-system.sh service-action <name> <start|stop|restart>")
    svc_name = re.sub(r"[^A-Za-z0-9_.@-]", "", args[0].strip())
    act = args[1].strip().lower()
    if not svc_name or act not in ("start", "stop", "restart"):
        sys.exit("Invalid service name or action")
    if shutil.which("systemctl") and os.path.isdir("/run/systemd/system"):
        subprocess.run(["timeout", "6", "systemctl", "--user", act, svc_name], stderr=subprocess.DEVNULL)
    elif shutil.which("rc-service"):
        subprocess.run(["timeout", "6", "sudo", "-n", "rc-service", svc_name, act], stderr=subprocess.DEVNULL)
    cmd_services()


def cmd_user_info():
    pw = pwd.getpwuid(os.getuid())
    group_names = []
    for gid in os.getgroups():
        try:
            group_names.append(grp.getgrgid(gid).gr_name)
        except KeyError:
            pass
    gecos = pw.pw_gecos.split(",")[0].strip() if pw.pw_gecos else ""
    print(json.dumps({
        "user": pw.pw_name,
        "fullName": gecos or pw.pw_name,
        "uid": pw.pw_uid,
        "gid": pw.pw_gid,
        "shell": pw.pw_shell,
        "home": pw.pw_dir,
        "groups": group_names,
        "lang": os.environ.get("LANG", "C.UTF-8"),
        "sessionType": os.environ.get("XDG_SESSION_TYPE", "wayland"),
        "desktop": os.environ.get("XDG_CURRENT_DESKTOP", "mango"),
    }))


def list_backup_files():
    patterns = [
        os.path.expanduser("~/aurora-settings-backup-*.tar.gz"),
        os.path.expanduser("~/mango-settings-backup-*.tar.gz"),
    ]
    matched = []
    for pat in patterns:
        matched.extend(glob.glob(pat))
    files = sorted(set(matched), key=lambda p: os.path.getmtime(p), reverse=True)
    out = []
    for p in files[:6]:
        try:
            out.append({
                "name": os.path.basename(p),
                "path": p,
                "sizeKb": round(os.path.getsize(p) / 1024.0, 1),
            })
        except Exception:
            pass
    return out


def cmd_list_backups():
    print(json.dumps({"backups": list_backup_files()}))


def cmd_backup_settings():
    ts = time.strftime("%Y%m%d_%H%M%S")
    dest = os.path.expanduser(f"~/aurora-settings-backup-{ts}.tar.gz")
    sources = [
        (os.path.join(QS_DIR, "shell-prefs.json"), "quickshell/shell-prefs.json"),
        (os.path.join(QS_DIR, "mode-prefs.json"), "quickshell/mode-prefs.json"),
        (os.path.join(QS_DIR, "hidden-apps.json"), "quickshell/hidden-apps.json"),
        (os.path.join(QS_DIR, "theme-state.json"), "quickshell/theme-state.json"),
        (os.path.join(QS_DIR, "shell-mode.json"), "quickshell/shell-mode.json"),
        (os.path.join(MANGO_DIR, "local.conf"), "mango/local.conf"),
    ]
    with tarfile.open(dest, "w:gz") as tf:
        for src, arcname in sources:
            if os.path.isfile(src):
                tf.add(src, arcname=arcname)
    size_kb = round(os.path.getsize(dest) / 1024.0, 1)
    print(json.dumps({"path": dest, "sizeKb": size_kb, "backups": list_backup_files()}))


def cmd_restore_settings():
    if len(args) < 1:
        sys.exit("Usage: manage-system.sh restore-settings <archive_path>")
    src_path = os.path.expanduser(args[0].strip())
    if not os.path.isfile(src_path):
        sys.exit(f"Backup archive not found: {src_path}")
    allowed_members = {
        "quickshell/shell-prefs.json": os.path.join(QS_DIR, "shell-prefs.json"),
        "quickshell/mode-prefs.json": os.path.join(QS_DIR, "mode-prefs.json"),
        "quickshell/hidden-apps.json": os.path.join(QS_DIR, "hidden-apps.json"),
        "quickshell/theme-state.json": os.path.join(QS_DIR, "theme-state.json"),
        "quickshell/shell-mode.json": os.path.join(QS_DIR, "shell-mode.json"),
        "mango/local.conf": os.path.join(MANGO_DIR, "local.conf"),
    }
    restored = []
    with tarfile.open(src_path, "r:gz") as tf:
        for member in tf.getmembers():
            if not member.isfile() or member.name not in allowed_members:
                continue
            fobj = tf.extractfile(member)
            if fobj is None:
                continue
            content = fobj.read().decode("utf-8", errors="replace")
            atomic_write(allowed_members[member.name], content)
            restored.append(member.name)
    apply_mode = os.path.join(QS_DIR, "scripts", "apply-mode.sh")
    apply_theme = os.path.join(QS_DIR, "scripts", "apply-theme.sh")
    if os.path.isfile(apply_mode):
        subprocess.run([apply_mode, "--init"], stderr=subprocess.DEVNULL)
    if os.path.isfile(apply_theme):
        subprocess.run([apply_theme, "--init", "--no-wallpaper"], stderr=subprocess.DEVNULL)
    if shutil.which("mmsg"):
        subprocess.run(["mmsg", "dispatch", "reload_config"], stderr=subprocess.DEVNULL)
    print(json.dumps({"restored": restored, "path": src_path, "backups": list_backup_files()}))


def cmd_doctor():
    checks = []
    if shutil.which("mango"):
        res = subprocess.run(["mango", "-p"], capture_output=True, text=True)
        checks.append({
            "id": "mango-config",
            "label": "MangoWC & Config",
            "status": "ok" if res.returncode == 0 else "fail",
            "detail": "mango -p configuration syntax valid" if res.returncode == 0 else (res.stderr.strip().splitlines()[:1] or ["Validation failed"])[0],
        })
    else:
        checks.append({"id": "mango-config", "label": "MangoWC & Config", "status": "fail", "detail": "'mango' binary not found"})
    has_fm = os.path.exists(os.path.join(QS_DIR, "bin", "aurora-fm"))
    has_be = os.path.exists(os.path.join(QS_DIR, "bin", "aurora-backend"))
    checks.append({
        "id": "aurora-bins",
        "label": "Aurora Rust Backends",
        "status": "ok" if (has_fm and has_be) else "warn",
        "detail": "aurora-fm and aurora-backend installed" if (has_fm and has_be) else "Run ./install.sh to compile Rust backends",
    })
    pass_c = sum(1 for c in checks if c["status"] == "ok")
    warn_c = sum(1 for c in checks if c["status"] == "warn")
    fail_c = sum(1 for c in checks if c["status"] == "fail")
    print(json.dumps({
        "ok": fail_c == 0,
        "summary": f"{pass_c} passed, {warn_c} warnings, {fail_c} failed",
        "passCount": pass_c,
        "warnCount": warn_c,
        "failCount": fail_c,
        "checks": checks,
    }))


DISPATCH = {
    "gtk-get": cmd_gtk_get,
    "gtk-set": cmd_gtk_set,
    "terminal-get": cmd_terminal_get,
    "terminal-set": cmd_terminal_set,
    "network-info": cmd_network_info,
    "network-action": cmd_network_action,
    "power-action": cmd_power_action,
    "audio-cards": cmd_audio_cards,
    "audio-set-profile": cmd_audio_set_profile,
    "audio-test": cmd_audio_test,
    "privacy-get": cmd_privacy_get,
    "privacy-set": cmd_privacy_set,
    "clear-clipboard": cmd_clear_clipboard,
    "clear-recent": cmd_clear_recent,
    "hwmon": cmd_hwmon,
    "processes": cmd_processes,
    "kill-proc": cmd_kill_proc,
    "services": cmd_services,
    "service-action": cmd_service_action,
    "user-info": cmd_user_info,
    "backup-settings": cmd_backup_settings,
    "list-backups": cmd_list_backups,
    "restore-settings": cmd_restore_settings,
    "doctor": cmd_doctor,
}

DISPATCH[cmd]()
PY
