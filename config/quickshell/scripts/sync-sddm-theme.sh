#!/usr/bin/env bash
set -euo pipefail

# Sync active Quickshell / Matugen palette & wallpaper into SDDM Mango Island theme.

MODE="${1:-sync}"
QUICKSHELL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
COLORS_JSON="${QUICKSHELL_DIR}/colors.json"
STATE_JSON="${QUICKSHELL_DIR}/theme-state.json"
PREFS_JSON="${QUICKSHELL_DIR}/shell-prefs.json"
SDDM_DIR="/usr/share/sddm/themes/mango-island"
SDDM_CONF="${SDDM_DIR}/theme.conf"
SDDM_DROPIN="/etc/sddm.conf.d/99-mango-island.conf"

if [[ "$MODE" == "--status" ]]; then
    python3 - "$SDDM_DIR" "$SDDM_CONF" "$SDDM_DROPIN" <<'PY'
import json, os, sys
sddm_dir, sddm_conf, dropin = sys.argv[1:4]
installed = os.path.isdir(sddm_dir) and os.path.isfile(os.path.join(sddm_dir, "Main.qml"))
writable = installed and (os.access(sddm_dir, os.W_OK) or (os.path.exists(sddm_conf) and os.access(sddm_conf, os.W_OK)))
active = False
for p in (dropin, "/etc/sddm.conf.d/mango.conf", "/etc/sddm.conf"):
    if os.path.isfile(p):
        try:
            if "Current=mango-island" in open(p, encoding="utf-8", errors="ignore").read():
                active = True
                break
        except Exception:
            pass
print(json.dumps({"installed": installed, "writable": writable, "active": active}))
PY
    exit 0
fi

[[ -d "$SDDM_DIR" ]] || exit 0
if [[ ! -w "$SDDM_DIR" ]] && [[ ! -w "$SDDM_CONF" ]]; then
    exit 0
fi
[[ -f "$COLORS_JSON" ]] || exit 0

python3 - "$COLORS_JSON" "$STATE_JSON" "$PREFS_JSON" "$SDDM_DIR" <<'PY'
import hashlib
import json
import os
import shutil
import sys
import tempfile

colors_path, state_path, prefs_path, sddm_dir = sys.argv[1:5]
sddm_conf = os.path.join(sddm_dir, "theme.conf")
sddm_bg = os.path.join(sddm_dir, "background.img")


def read_json(path):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def write_text_safe(path, content):
    parent = os.path.dirname(path)
    if os.access(parent, os.W_OK):
        fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_sddm_", text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(content)
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        except Exception:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    elif os.path.exists(path) and os.access(path, os.W_OK):
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)


def write_file_copy_safe(src, dst):
    parent = os.path.dirname(dst)
    if os.access(parent, os.W_OK):
        fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_bg_")
        os.close(fd)
        try:
            shutil.copyfile(src, tmp)
            os.chmod(tmp, 0o644)
            os.replace(tmp, dst)
        except Exception:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    elif os.path.exists(dst) and os.access(dst, os.W_OK):
        with open(src, "rb") as fin, open(dst, "wb") as fout:
            shutil.copyfileobj(fin, fout)


colors = read_json(colors_path)
state = read_json(state_path)
prefs = read_json(prefs_path)

wp = os.path.expanduser(str(state.get("wallpaper", "")).strip())
bg_value = ""
if wp and os.path.isfile(wp) and os.access(wp, os.R_OK):
    try:
        src_hash = sha256_file(wp)
        dst_hash = sha256_file(sddm_bg) if os.path.isfile(sddm_bg) and os.path.getsize(sddm_bg) > 0 else ""
        if src_hash != dst_hash:
            write_file_copy_safe(wp, sddm_bg)
        if os.path.isfile(sddm_bg) and os.path.getsize(sddm_bg) > 0:
            bg_value = "background.img"
    except Exception:
        pass
elif os.path.isfile(sddm_bg) and os.path.getsize(sddm_bg) > 0:
    bg_value = "background.img"

font = str(prefs.get("uiFontFamily", "IBM Plex Sans")).strip() or "IBM Plex Sans"
mono_font = str(prefs.get("monoFontFamily", "IBM Plex Mono")).strip() or "IBM Plex Mono"
clock24h = "true" if prefs.get("clock24h", True) else "false"
reduced = "true" if prefs.get("reducedMotion", False) else "false"
is_dark = "true" if colors.get("isDark", True) else "false"
radius_scale = float(prefs.get("uiRadiusScale", 1.0) or 1.0)
radius = max(0, min(36, int(round(28 * radius_scale))))

conf_text = "\n".join([
    "[General]",
    f"background={bg_value}",
    f"font={font}",
    f"monoFont={mono_font}",
    "iconFont=Symbols Nerd Font",
    f"clock24h={clock24h}",
    f"isDark={is_dark}",
    f"reducedMotion={reduced}",
    f"radius={radius}",
    f"primary={colors.get('primary', '#cba6f7')}",
    f"onPrimary={colors.get('onPrimary', '#11111b')}",
    f"secondary={colors.get('secondary', '#89b4fa')}",
    f"surface={colors.get('surface', '#1e1e2e')}",
    f"surfaceLowest={colors.get('surfaceContainerLowest', '#11111b')}",
    f"cardBg={colors.get('surfaceContainerHigh', '#313244')}",
    f"fgSurface={colors.get('onSurface', '#cdd6f4')}",
    f"fgSurfaceVariant={colors.get('onSurfaceVariant', '#a6adc8')}",
    f"outline={colors.get('outline', '#6c7086')}",
    f"outlineVariant={colors.get('outlineVariant', '#313244')}",
    f"error={colors.get('error', '#f38ba8')}",
    f"onError={colors.get('onError', '#11111b')}",
    f"success={colors.get('success', '#a6e3a1')}",
    f"warning={colors.get('warning', '#f9e2af')}",
    "",
])

if os.access(sddm_dir, os.W_OK) or (os.path.exists(sddm_conf) and os.access(sddm_conf, os.W_OK)):
    write_text_safe(sddm_conf, conf_text)
PY
