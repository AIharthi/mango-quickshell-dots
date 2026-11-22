#!/usr/bin/env bash
set -euo pipefail

# Probe hardware capabilities & host environment for Quickshell multi-device adaptation.
# Outputs compact JSON on stdout.

python3 - <<'PY'
import glob
import json
import os
import platform
import re
import shutil
import socket
import subprocess

def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except OSError:
        return ""

has_wifi = bool(
    glob.glob("/sys/class/net/*/wireless") or glob.glob("/sys/class/net/*/phy80211")
) and (shutil.which("nmcli") is not None)

has_bluetooth = bool(glob.glob("/sys/class/bluetooth/hci*")) and (
    shutil.which("bluetoothctl") is not None
)

has_backlight = bool(glob.glob("/sys/class/backlight/*")) and (
    shutil.which("brightnessctl") is not None
)

has_battery = False
battery_path = ""
for ps in sorted(glob.glob("/sys/class/power_supply/*")):
    if read_text(os.path.join(ps, "type")) == "Battery":
        scope = read_text(os.path.join(ps, "scope"))
        if scope == "Device":
            continue
        has_battery = True
        battery_path = ps
        break

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
    "hasBluetooth": has_bluetooth,
    "hasBacklight": has_backlight,
    "hasBattery": has_battery,
    "batteryPath": battery_path,
    "hasTouchpad": has_touchpad,
    "hasWlrRandr": has_wlr_randr,
    "hasAudio": has_audio,
    "hasPavucontrol": has_pavucontrol,
    "nightLightCmd": night_light_cmd,
    "hasNightLight": has_night_light,
    "hasPowerProfiles": has_power_profiles,
    "hasXdgMime": has_xdg_mime,
    "lockerCmd": locker_cmd,
    "hasLocker": has_locker,
    "deviceType": device_type,
    "hostname": socket.gethostname(),
    "kernel": platform.release(),
    "distro": distro,
}
print(json.dumps(payload, separators=(",", ":")))
PY
