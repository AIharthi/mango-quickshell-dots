#!/usr/bin/env bash
set -euo pipefail

# Opt-in Weather Fetcher (wttr.in JSON with 30-min cache & offline resilience)

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
PREFS_JSON="${QUICKSHELL_DIR}/shell-prefs.json"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
CACHE_FILE="${CACHE_DIR}/weather.json"

mkdir -p "$CACHE_DIR"

exec python3 - "$PREFS_JSON" "$CACHE_FILE" "$FORCE" <<'PY'
import json
import os
import sys
import tempfile
import time
import urllib.parse
import urllib.request

prefs_path, cache_path, force_s = sys.argv[1:4]
force = force_s == "1"
ttl = 1800


def read_json(path):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def write_cache(payload):
    parent = os.path.dirname(cache_path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_weather_", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, cache_path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)


def map_icon(code_str):
    try:
        c = int(code_str)
    except Exception:
        return "󰖐"
    if c == 113:
        return "󰖙"
    if c == 116:
        return "󰖕"
    if c in (119, 122):
        return "󰖐"
    if c in (143, 248, 260):
        return "󰖑"
    if c in (200, 386, 389, 392, 395):
        return "󰙾"
    if c in (179, 182, 185, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377):
        return "󰖘"
    if c >= 176:
        return "󰖗"
    return "󰖐"


prefs = read_json(prefs_path)
if not prefs.get("weatherEnabled", False):
    print(json.dumps({"available": False}))
    sys.exit(0)

location = str(prefs.get("weatherLocation", "")).strip()
units = "F" if str(prefs.get("weatherUnits", "C")).strip().upper() == "F" else "C"

cached = read_json(cache_path)
if (
    not force
    and cached.get("available")
    and cached.get("_location", "") == location
    and cached.get("_units", "C") == units
    and (time.time() - float(cached.get("_ts", 0))) < ttl
):
    print(json.dumps(cached))
    sys.exit(0)

loc_seg = urllib.parse.quote(location.replace(" ", "+"), safe=",+")
url = f"https://wttr.in/{loc_seg}?format=j1" if loc_seg else "https://wttr.in/?format=j1"

try:
    req = urllib.request.Request(url, headers={"User-Agent": "Aurora-Shell/2.0"})
    with urllib.request.urlopen(req, timeout=4.0) as resp:
        data = json.loads(resp.read().decode("utf-8", errors="replace"))
    cur = (data.get("current_condition") or [{}])[0]
    area = (data.get("nearest_area") or [{}])[0]
    area_name = ((area.get("areaName") or [{}])[0]).get("value", "") or location or "Local"
    temp_val = cur.get("temp_F" if units == "F" else "temp_C", "")
    feels_val = cur.get("FeelsLikeF" if units == "F" else "FeelsLikeC", temp_val)
    cond_val = ((cur.get("weatherDesc") or [{}])[0]).get("value", "Clear")
    hum_val = str(cur.get("humidity", "0"))
    wind_val = str(cur.get("windspeedKmph", "0")) + " km/h"
    code = str(cur.get("weatherCode", "113"))
    payload = {
        "available": True,
        "temp": f"{temp_val}°{units}",
        "feelsLike": f"{feels_val}°{units}",
        "condition": cond_val,
        "humidity": f"{hum_val}%",
        "wind": wind_val,
        "location": area_name,
        "icon": map_icon(code),
        "updated": time.strftime("%H:%M"),
        "_ts": time.time(),
        "_location": location,
        "_units": units,
    }
    write_cache(payload)
    print(json.dumps(payload))
except Exception:
    if cached.get("available"):
        print(json.dumps(cached))
    else:
        print(json.dumps({"available": False}))
PY
