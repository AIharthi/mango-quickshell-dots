#!/usr/bin/env bash
set -euo pipefail

# Probe hardware capabilities & host environment for Quickshell multi-device adaptation.
# Usage:
#   detect-hardware.sh            -> full capability probe JSON
#   detect-hardware.sh --battery  -> aggregated multi-battery status JSON

MODE="${1:-}"
BACKEND_BIN="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bin/aurora-backend"
if [[ -x "$BACKEND_BIN" ]]; then
    if [[ "$MODE" == "--battery" ]]; then
        exec "$BACKEND_BIN" battery
    fi
    exec "$BACKEND_BIN" probe
fi

python3 - "$MODE" <<'PY'
import glob
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else ""

def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except OSError:
        return ""

def read_int(path: str):
    raw = read_text(path)
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None

def find_system_batteries() -> list[str]:
    found = []
    for ps in sorted(glob.glob("/sys/class/power_supply/*")):
        if read_text(os.path.join(ps, "type")) == "Battery":
            scope = read_text(os.path.join(ps, "scope"))
            if scope == "Device":
                continue
            found.append(ps)
    return found

if mode == "--battery":
    bats = find_system_batteries()
    if not bats:
        print('{"percent":100,"status":"Full","charging":false,"count":0}')
        sys.exit(0)
    total_now = 0
    total_full = 0
    cap_fallbacks = []
    statuses = []
    for ps in bats:
        st = read_text(os.path.join(ps, "status")) or "Unknown"
        statuses.append(st)
        e_now = read_int(os.path.join(ps, "energy_now"))
        e_full = read_int(os.path.join(ps, "energy_full"))
        if e_now is not None and e_full is not None and e_full > 0:
            total_now += max(0, e_now)
            total_full += e_full
            continue
        c_now = read_int(os.path.join(ps, "charge_now"))
        c_full = read_int(os.path.join(ps, "charge_full"))
        if c_now is not None and c_full is not None and c_full > 0:
            total_now += max(0, c_now)
            total_full += c_full
            continue
        cap = read_int(os.path.join(ps, "capacity"))
        if cap is not None:
            cap_fallbacks.append(max(0, min(100, cap)))
    if total_full > 0:
        pct = max(0, min(100, int(round((total_now * 100.0) / total_full))))
    elif cap_fallbacks:
        pct = max(0, min(100, int(round(sum(cap_fallbacks) / len(cap_fallbacks)))))
    else:
        pct = 100
    if "Charging" in statuses:
        agg_status = "Charging"
    elif "Discharging" in statuses:
        agg_status = "Discharging"
    elif any(s == "Full" for s in statuses):
        agg_status = "Full"
    else:
        agg_status = statuses[0] if statuses else "Unknown"
    print(json.dumps({
        "percent": pct,
        "status": agg_status,
        "charging": agg_status in ("Charging", "Full"),
        "count": len(bats),
    }, separators=(",", ":")))
    sys.exit(0)

config_dir = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))

has_wifi_hw = bool(
    glob.glob("/sys/class/net/*/wireless")
    or glob.glob("/sys/class/net/*/phy80211")
    or glob.glob("/sys/class/ieee80211/*")
)
has_nmcli = shutil.which("nmcli") is not None
has_wifi = has_wifi_hw and has_nmcli

has_bluetooth = bool(glob.glob("/sys/class/bluetooth/hci*")) and (
    shutil.which("bluetoothctl") is not None
)

has_backlight = bool(glob.glob("/sys/class/backlight/*")) and (
    shutil.which("brightnessctl") is not None
)

battery_paths = find_system_batteries()
has_battery = len(battery_paths) > 0
battery_path = battery_paths[0] if battery_paths else ""

touchpad_re = re.compile(r"(touchpad|trackpad|synaptics|elan|syna|apple.*trackpad)", re.I)
has_touchpad = False

proc_devices = read_text("/proc/bus/input/devices")
for line in proc_devices.splitlines():
    if line.startswith("N: Name=") and touchpad_re.search(line):
        has_touchpad = True
        break

if not has_touchpad and shutil.which("mmsg"):
    try:
        out = subprocess.check_output(
            ["mmsg", "get", "all-devices"],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1.5,
        )
        data = json.loads(out)
        for dev in data.get("devices", []):
            if touchpad_re.search(dev.get("name", "")):
                has_touchpad = True
                break
    except Exception:
        pass

has_wlr_randr = shutil.which("wlr-randr") is not None
has_audio = shutil.which("pactl") is not None
has_pavucontrol = shutil.which("pavucontrol") is not None
has_power_profiles = shutil.which("powerprofilesctl") is not None
has_xdg_mime = shutil.which("xdg-mime") is not None
has_network = any(
    os.path.basename(p) != "lo" for p in glob.glob("/sys/class/net/*")
)
has_ddcutil = shutil.which("ddcutil") is not None
has_openrc = shutil.which("rc-status") is not None
has_systemd = (shutil.which("systemctl") is not None) and os.path.isdir("/run/systemd/system")
has_clipboard = shutil.which("wl-copy") is not None
has_speaker_test = (shutil.which("speaker-test") is not None) or (shutil.which("paplay") is not None)
has_foot = (shutil.which("foot") is not None) or os.path.exists(os.path.join(config_dir, "foot", "foot.ini"))
has_kitty = (shutil.which("kitty") is not None) or os.path.exists(os.path.join(config_dir, "kitty", "kitty.conf"))

night_light_cmd = ""
for candidate in ("hyprsunset", "wlsunset", "gammastep"):
    if shutil.which(candidate):
        night_light_cmd = candidate
        break
has_night_light = bool(night_light_cmd)

locker_cmd = ""
for candidate in ("hyprlock", "swaylock", "waylock"):
    if shutil.which(candidate):
        locker_cmd = candidate
        break
if not locker_cmd and (shutil.which("qs") or shutil.which("quickshell")):
    locker_cmd = "quickshell"
has_locker = bool(locker_cmd)

device_type = "laptop" if (has_battery or has_backlight or has_touchpad) else "desktop"

distro = "Linux"
os_release = read_text("/etc/os-release")
for line in os_release.splitlines():
    if line.startswith("PRETTY_NAME="):
        distro = line.split("=", 1)[1].strip().strip('"').strip("'")
        break

payload = {
    "probed": True,
    "hasWifi": has_wifi,
    "hasWifiHw": has_wifi_hw,
    "hasBluetooth": has_bluetooth,
    "hasBacklight": has_backlight,
    "hasBattery": has_battery,
    "batteryPath": battery_path,
    "batteryPaths": battery_paths,
    "hasTouchpad": has_touchpad,
    "hasWlrRandr": has_wlr_randr,
    "hasAudio": has_audio,
    "hasPavucontrol": has_pavucontrol,
    "nightLightCmd": night_light_cmd,
    "hasNightLight": has_night_light,
    "hasPowerProfiles": has_power_profiles,
    "hasXdgMime": has_xdg_mime,
    "hasNetwork": has_network,
    "hasNmcli": has_nmcli,
    "hasDdcutil": has_ddcutil,
    "hasOpenRc": has_openrc,
    "hasSystemd": has_systemd,
    "hasClipboard": has_clipboard,
    "hasSpeakerTest": has_speaker_test,
    "hasFoot": has_foot,
    "hasKitty": has_kitty,
    "lockerCmd": locker_cmd,
    "hasLocker": has_locker,
    "deviceType": device_type,
    "hostname": socket.gethostname(),
    "kernel": platform.release(),
    "distro": distro,
}
print(json.dumps(payload, separators=(",", ":")))
PY
