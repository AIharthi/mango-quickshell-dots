#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
shift || true

CONFIG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
PREFS_FILE="${CONFIG_BASE}/quickshell/shell-prefs.json"
LOCAL_CONF="${CONFIG_BASE}/mango/local.conf"
MANGO_CONF="${CONFIG_BASE}/mango/config.conf"
AUTOSTART_SH="${CONFIG_BASE}/mango/autostart.sh"

case "$CMD" in
    prefs-get|prefs-set|prefs-set-batch|prefs-reset|reset-appearance|reset-bar|reset-files|reset-all|set-font|set-mono-font|list-fonts|defaults-get|defaults-set|startup-list|startup-add|startup-remove|keybinds-list|system-info|night-light|hidden-apps-get|hidden-apps-add|hidden-apps-remove)
        ;;
    *)
        echo "Usage: manage-settings.sh <prefs-get|prefs-set|prefs-set-batch|prefs-reset|reset-appearance|reset-bar|reset-files|reset-all|set-font|set-mono-font|list-fonts|defaults-get|defaults-set|startup-list|startup-add|startup-remove|keybinds-list|system-info|night-light|hidden-apps-get|hidden-apps-add|hidden-apps-remove> [args...]" >&2
        exit 1
        ;;
esac

exec python3 - "$CMD" "$PREFS_FILE" "$LOCAL_CONF" "$MANGO_CONF" "$AUTOSTART_SH" "$@" <<'PY'
import configparser
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import tempfile

cmd = sys.argv[1]
prefs_path = sys.argv[2]
local_conf_path = sys.argv[3]
mango_conf_path = sys.argv[4]
autostart_path = sys.argv[5]
args = sys.argv[6:]


def atomic_write_text(path, text):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=parent, prefix=".tmp_", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def detect_first(candidates, fallback):
    for c in candidates:
        if shutil.which(c):
            return c
    return fallback


def default_prefs():
    return {
        "dnd": False,
        "dndAllowCritical": True,
        "notifSoundEnabled": False,
        "notifTimeoutMs": 4500,
        "notifMaxHistory": 40,
        "clock24h": True,
        "clockShowSeconds": False,
        "dateFormat": "ddd d MMM",
        "keepAwake": False,
        "uiFontFamily": "IBM Plex Sans",
        "monoFontFamily": "IBM Plex Mono",
        "uiFontSize": 10,
        "iconTheme": "Adwaita",
        "matugenType": "scheme-tonal-spot",
        "matugenContrast": 0.0,
        "wallpaperTransition": "grow",
        "wallpaperFps": 60,
        "wallpaperDuration": 0.85,
        "wallpaperResize": "crop",
        "nightLightEnabled": False,
        "nightLightTemp": 4500,
        "defaultTerminal": detect_first(["foot", "kitty", "alacritty", "wezterm", "ghostty", "konsole"], "foot"),
        "defaultBrowser": detect_first(["helium", "firefox", "librewolf", "chromium", "google-chrome", "brave"], "firefox"),
        "defaultEditor": detect_first(["zedit", "zed", "code", "codium", "kate", "mousepad"], "zedit"),
        "defaultFileManager": detect_first(["thunar", "dolphin", "nautilus", "nemo", "pcmanfm-qt", "pcmanfm"], "thunar"),
        "islandHoverExpand": True,
        "islandHoverDelayMs": 120,
        "islandCollapseDelayMs": 450,
        "pillShowMedia": True,
        "pillSpinArt": True,
        "pillShowEqualizer": True,
        "osdEnabled": True,
        "osdTimeoutMs": 1800,
        "simpleBarHeight": 28,
        "simpleBarPosition": "top",
        "simpleBarShowLayout": True,
        "simpleBarShowDate": True,
        "barShowDate": False,
        "barShowWindow": False,
        "barShowWorkspaces": False,
        "barShowLayout": False,
        "barShowSystem": False,
        "barShowNetSpeed": False,
        "barShowVolume": False,
        "barShowKbLayout": False,
        "barShowTray": False,
        "barShowQuickIcons": False,
        "barShowFiles": True,
        "barShowBattery": True,
        "fmViewMode": "list",
        "fmDensity": "cozy",
        "fmGridSize": 116,
        "fmIconStyle": "category",
        "fmSurfacePreset": "inherit",
        "fmOpacity": 0.94,
        "fmAccentOverride": "",
        "fmHeaderStyle": "pill",
        "fmSidebarVisible": True,
        "fmSidebarStyle": "standard",
        "fmPreviewVisible": True,
        "fmDualPane": False,
        "fmShowHidden": False,
        "fmShowThumbnails": True,
        "fmShowSizes": True,
        "fmShowDates": True,
        "fmShowPerms": False,
        "fmDirsFirst": True,
        "fmSortBy": "name",
        "fmSortDesc": False,
        "fmWindowSize": "balanced",
        "fmRowAlternating": False,
        "fmShowCheckboxes": False,
        "fmStartDir": "~",
        "fmLastDir": "~",
        "pipAutoManage": True,
        "pipSticky": True,
        "pipAlwaysOnTop": True,
        "pipCorner": "bottom-right",
        "pipWidthPct": 25,
        "pipMargin": 20,
        "reducedMotion": False,
        "highContrast": False,
        "audioOverAmp": False,
        "screenshotDir": "~/Pictures/Screenshots",
        "screenshotCopyClipboard": True,
        "screenshotNotify": True,
        "screenshotDelay": 0,
        "recordingDir": "~/Videos/Recordings",
        "idleLockEnabled": True,
        "idleLockSeconds": 300,
        "idleSuspendEnabled": False,
        "idleSuspendSeconds": 900,
        "scratchpadText": "",
        "weatherEnabled": False,
        "weatherLocation": "",
        "weatherUnits": "C",
        "barShowWeather": False,
        "wallpaperSlideshowEnabled": False,
        "wallpaperSlideshowMinutes": 15,
        "surfaceStyle": "default",
        "shellOpacity": 0.92,
        "cardOpacity": 0.50,
        "uiRadiusScale": 1.0,
        "borderStyle": "subtle",
        "uiBorderWidth": 1,
        "uiFontScale": 1.0,
        "islandStyle": "pill",
        "islandTopMargin": 6,
        "pillHeight": 32,
        "hubUiStyle": "cupertino",
        "barUiStyle": "apple",
        "matugenSourceIndex": 0,
        "matugenPrefer": "saturation",
        "matugenLightnessDark": 0.0,
        "matugenLightnessLight": 0.0,
        "wallpaperDir": "~/Pictures/Wallpapers",
        "accentSeedColor": "#cba6f7",
        "solidWallpaperColor": "#1e1e2e",
        "mangoFocusColor": "",
        "mangoBorderColor": "",
        "mangoShadowTint": False,
        "mangoShadowAlpha": 0.80,
        "mangoDimAlpha": 0.27,
    }


def load_prefs(create_if_missing=True):
    defaults = default_prefs()
    loaded = {}
    exists = os.path.exists(prefs_path)
    if exists:
        try:
            with open(prefs_path, "r", encoding="utf-8") as f:
                raw = json.load(f)
            if isinstance(raw, dict):
                loaded = raw
        except Exception:
            loaded = {}
    merged = dict(defaults)
    for k, v in loaded.items():
        if k in merged:
            merged[k] = v
    if create_if_missing and (not exists or merged != loaded):
        atomic_write_text(prefs_path, json.dumps(merged, indent=2) + "\n")
    return merged


def save_prefs(data):
    atomic_write_text(prefs_path, json.dumps(data, indent=2) + "\n")
    return data


def coerce_value(key, raw, current):
    if isinstance(current, bool):
        low = str(raw).strip().lower()
        return low in ("1", "true", "yes", "on")
    if isinstance(current, int):
        return int(float(raw))
    if isinstance(current, float):
        return float(raw)
    return str(raw)


def update_ini_font(path, font_spec):
    if not os.path.exists(path):
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        out = []
        replaced = False
        for line in lines:
            if line.strip().startswith("gtk-font-name="):
                out.append(f"gtk-font-name={font_spec}\n")
                replaced = True
            else:
                out.append(line)
        if not replaced:
            out.append(f"gtk-font-name={font_spec}\n")
        atomic_write_text(path, "".join(out))
    except Exception:
        pass


def update_foot_font(family, size):
    cfg_dir = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
    path = os.path.join(cfg_dir, "foot", "foot.ini")
    if not os.path.exists(path):
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        out = []
        replaced = False
        for line in lines:
            if re.match(r"^\s*font\s*=", line):
                out.append(f"font={family}:size={size}\n")
                replaced = True
            else:
                out.append(line)
        if not replaced:
            out.insert(0, f"font={family}:size={size}\n")
        atomic_write_text(path, "".join(out))
    except Exception:
        pass


def update_kitty_font(family, size):
    cfg_dir = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
    path = os.path.join(cfg_dir, "kitty", "kitty.conf")
    if not os.path.exists(path):
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        out = []
        rep_fam = False
        rep_sz = False
        for line in lines:
            if re.match(r"^\s*font_family\s+", line):
                out.append(f"font_family {family}\n")
                rep_fam = True
            elif re.match(r"^\s*font_size\s+", line):
                out.append(f"font_size {size}\n")
                rep_sz = True
            else:
                out.append(line)
        if not rep_fam:
            out.insert(0, f"font_family {family}\n")
        if not rep_sz:
            out.insert(1, f"font_size {size}\n")
        atomic_write_text(path, "".join(out))
        subprocess.run(["pkill", "-x", "-USR1", "kitty"], stderr=subprocess.DEVNULL)
    except Exception:
        pass


def cmd_prefs_get():
    print(json.dumps(load_prefs(True)))


def validate_and_apply_pref(prefs, key, raw_val):
    if key not in prefs:
        return False
    prefs[key] = coerce_value(key, raw_val, prefs[key])
    if key == "notifTimeoutMs":
        prefs[key] = max(1500, min(15000, int(prefs[key])))
    elif key == "notifMaxHistory":
        prefs[key] = max(10, min(200, int(prefs[key])))
    elif key == "uiFontSize":
        prefs[key] = max(8, min(18, int(prefs[key])))
    elif key == "nightLightTemp":
        prefs[key] = max(2500, min(6500, int(prefs[key])))
    elif key == "islandHoverDelayMs":
        prefs[key] = max(50, min(1500, int(prefs[key])))
    elif key == "islandCollapseDelayMs":
        prefs[key] = max(200, min(4000, int(prefs[key])))
    elif key == "osdTimeoutMs":
        prefs[key] = max(800, min(6000, int(prefs[key])))
    elif key == "simpleBarHeight":
        prefs[key] = max(22, min(44, int(prefs[key])))
    elif key == "simpleBarPosition":
        prefs[key] = "bottom" if str(prefs[key]).strip().lower() == "bottom" else "top"
    elif key == "matugenContrast":
        prefs[key] = round(max(-1.0, min(1.0, float(prefs[key]))), 2)
    elif key == "wallpaperFps":
        prefs[key] = max(24, min(240, int(prefs[key])))
    elif key == "wallpaperDuration":
        prefs[key] = round(max(0.1, min(3.0, float(prefs[key]))), 2)
    elif key == "screenshotDelay":
        prefs[key] = max(0, min(10, int(prefs[key])))
    elif key == "recordingDir":
        prefs[key] = str(prefs[key]).strip() or "~/Videos/Recordings"
    elif key == "idleLockSeconds":
        prefs[key] = max(30, min(3600, int(prefs[key])))
    elif key == "idleSuspendSeconds":
        prefs[key] = max(60, min(7200, int(prefs[key])))
    elif key == "scratchpadText":
        prefs[key] = str(prefs[key])[:16384]
    elif key == "weatherLocation":
        prefs[key] = str(prefs[key]).strip()[:120]
    elif key == "weatherUnits":
        prefs[key] = "F" if str(prefs[key]).strip().upper() == "F" else "C"
    elif key == "wallpaperSlideshowMinutes":
        prefs[key] = max(1, min(1440, int(prefs[key])))
    elif key == "shellOpacity":
        prefs[key] = round(max(0.40, min(1.00, float(prefs[key]))), 2)
    elif key == "cardOpacity":
        prefs[key] = round(max(0.15, min(1.00, float(prefs[key]))), 2)
    elif key == "uiRadiusScale":
        prefs[key] = round(max(0.0, min(1.6, float(prefs[key]))), 2)
    elif key == "uiBorderWidth":
        prefs[key] = max(0, min(3, int(prefs[key])))
    elif key == "uiFontScale":
        prefs[key] = round(max(0.85, min(1.25, float(prefs[key]))), 2)
    elif key == "islandTopMargin":
        prefs[key] = max(0, min(20, int(prefs[key])))
    elif key == "pillHeight":
        prefs[key] = max(26, min(40, int(prefs[key])))
    elif key == "hubUiStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("cupertino", "stage", "cockpit", "bento") else "cupertino"
    elif key == "barUiStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("apple", "split", "menubar", "classic") else "apple"
    elif key == "matugenSourceIndex":
        prefs[key] = max(0, min(4, int(prefs[key])))
    elif key in ("matugenLightnessDark", "matugenLightnessLight"):
        prefs[key] = round(max(-0.50, min(0.30, float(prefs[key]))), 2)
    elif key == "mangoShadowAlpha":
        prefs[key] = round(max(0.0, min(1.0, float(prefs[key]))), 2)
    elif key == "mangoDimAlpha":
        prefs[key] = round(max(0.0, min(0.75, float(prefs[key]))), 2)
    elif key == "surfaceStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("default", "glass", "oled", "flat", "tinted") else "default"
    elif key == "borderStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("none", "subtle", "accent", "glow") else "subtle"
    elif key == "islandStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("pill", "notch", "bar") else "pill"
    elif key == "pipCorner":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("bottom-right", "bottom-left", "top-right", "top-left") else "bottom-right"
    elif key == "pipWidthPct":
        prefs[key] = max(18, min(45, int(prefs[key])))
    elif key == "pipMargin":
        prefs[key] = max(6, min(64, int(prefs[key])))
    elif key == "fmViewMode":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("list", "grid", "miller") else "list"
    elif key == "fmDensity":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("compact", "cozy", "spacious") else "cozy"
    elif key == "fmGridSize":
        prefs[key] = max(84, min(164, int(prefs[key])))
    elif key == "fmIconStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("category", "accent", "mono", "vivid") else "category"
    elif key == "fmSurfacePreset":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("inherit", "glass", "solid", "oled", "tinted") else "inherit"
    elif key == "fmOpacity":
        prefs[key] = round(max(0.55, min(1.00, float(prefs[key]))), 2)
    elif key == "fmAccentOverride":
        v = str(prefs[key]).strip()
        prefs[key] = v if re.match(r"^#[0-9a-fA-F]{6}$", v) else ""
    elif key == "fmHeaderStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("pill", "minimal", "underline") else "pill"
    elif key == "fmSidebarStyle":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("standard", "compact", "icons") else "standard"
    elif key == "fmSortBy":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("name", "size", "mtime", "ext") else "name"
    elif key == "fmWindowSize":
        v = str(prefs[key]).strip().lower()
        prefs[key] = v if v in ("compact", "balanced", "wide", "max") else "balanced"
    return True


def cmd_prefs_set():
    if len(args) < 2:
        sys.exit("Usage: manage-settings.sh prefs-set <key> <value>")
    key = args[0]
    raw_val = " ".join(args[1:])
    prefs = load_prefs(True)
    if not validate_and_apply_pref(prefs, key, raw_val):
        sys.exit(f"Unknown preference key: {key}")

    if shutil.which("gsettings"):
        if key == "clock24h":
            subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "clock-format", "24h" if prefs[key] else "12h"], stderr=subprocess.DEVNULL)
        elif key == "reducedMotion":
            subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", "false" if prefs[key] else "true"], stderr=subprocess.DEVNULL)
        elif key == "highContrast":
            subprocess.run(["gsettings", "set", "org.gnome.desktop.a11y.interface", "high-contrast", "true" if prefs[key] else "false"], stderr=subprocess.DEVNULL)

    print(json.dumps(save_prefs(prefs)))


def cmd_prefs_set_batch():
    if len(args) < 1:
        sys.exit("Usage: manage-settings.sh prefs-set-batch <json>")
    try:
        patch = json.loads(" ".join(args))
    except Exception as exc:
        sys.exit(f"Invalid JSON batch: {exc}")
    if not isinstance(patch, dict):
        sys.exit("Batch payload must be a JSON object")
    prefs = load_prefs(True)
    for key, val in patch.items():
        validate_and_apply_pref(prefs, key, val)
    print(json.dumps(save_prefs(prefs)))


def cmd_prefs_reset():
    defaults = default_prefs()
    print(json.dumps(save_prefs(defaults)))


def strip_local_conf_keys(keys_to_strip):
    if not os.path.isfile(local_conf_path):
        return
    try:
        with open(local_conf_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        out = []
        changed = False
        for line in lines:
            s = line.strip()
            matched = False
            for k in keys_to_strip:
                if s.startswith(f"{k}="):
                    matched = True
                    changed = True
                    break
            if not matched:
                out.append(line)
        if changed:
            atomic_write_text(local_conf_path, "".join(out))
    except Exception:
        pass


def reset_appearance_impl(prefs):
    defaults = default_prefs()
    appearance_keys = (
        "uiFontFamily", "monoFontFamily", "uiFontSize", "iconTheme",
        "matugenType", "matugenContrast", "matugenSourceIndex", "matugenPrefer",
        "matugenLightnessDark", "matugenLightnessLight",
        "wallpaperTransition", "wallpaperFps", "wallpaperDuration", "wallpaperResize",
        "surfaceStyle", "shellOpacity", "cardOpacity", "uiRadiusScale",
        "borderStyle", "uiBorderWidth", "uiFontScale",
        "islandStyle", "islandTopMargin", "pillHeight",
        "accentSeedColor", "solidWallpaperColor",
        "mangoFocusColor", "mangoBorderColor", "mangoShadowTint", "mangoShadowAlpha", "mangoDimAlpha",
        "reducedMotion", "highContrast",
    )
    for k in appearance_keys:
        if k in defaults:
            prefs[k] = defaults[k]
    save_prefs(prefs)

    ui_font_spec = "IBM Plex Sans 10"
    mono_font_spec = "IBM Plex Mono 10"
    cfg_dir = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
    update_ini_font(os.path.join(cfg_dir, "gtk-3.0", "settings.ini"), ui_font_spec)
    update_ini_font(os.path.join(cfg_dir, "gtk-4.0", "settings.ini"), ui_font_spec)
    update_foot_font("IBM Plex Mono", 10)
    update_kitty_font("IBM Plex Mono", 10)

    if shutil.which("gsettings"):
        gsettings_cmds = [
            ["gsettings", "set", "org.gnome.desktop.interface", "font-name", ui_font_spec],
            ["gsettings", "set", "org.gnome.desktop.interface", "monospace-font-name", mono_font_spec],
            ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "Adwaita"],
            ["gsettings", "set", "org.gnome.desktop.interface", "font-hinting", "slight"],
            ["gsettings", "set", "org.gnome.desktop.interface", "font-antialiasing", "grayscale"],
            ["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", "1.0"],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-blink", "true"],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-blink-time", "1200"],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", "catppuccin-mocha-dark-cursors"],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", "24"],
            ["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", "true"],
            ["gsettings", "set", "org.gnome.desktop.a11y.interface", "high-contrast", "false"],
        ]
        for gc_cmd in gsettings_cmds:
            subprocess.run(gc_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    strip_local_conf_keys(("cursor_theme", "cursor_size", "cursor_hide_timeout", "cursor_hide_on_keypress"))

    scripts_dir = os.path.join(os.path.dirname(prefs_path), "scripts")
    apply_mode_sh = os.path.join(scripts_dir, "apply-mode.sh")
    apply_theme_sh = os.path.join(scripts_dir, "apply-theme.sh")
    if os.path.isfile(apply_mode_sh):
        subprocess.run([apply_mode_sh, "--reset-prefs"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([apply_mode_sh, "default", "--no-reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.isfile(apply_theme_sh):
        subprocess.run(
            [apply_theme_sh, "--mode", "preset", "--preset", "catppuccin-mocha", "--scheme", "dark", "--no-wallpaper"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    return prefs


def cmd_reset_appearance():
    prefs = load_prefs(True)
    reset_appearance_impl(prefs)
    print(json.dumps(prefs))


def cmd_reset_bar():
    defaults = default_prefs()
    prefs = load_prefs(True)
    bar_keys = (
        "islandHoverExpand", "islandHoverDelayMs", "islandCollapseDelayMs",
        "pillShowMedia", "pillSpinArt", "pillShowEqualizer",
        "osdEnabled", "osdTimeoutMs",
        "hubUiStyle", "barUiStyle",
        "simpleBarHeight", "simpleBarPosition", "simpleBarShowLayout", "simpleBarShowDate",
        "barShowDate", "barShowWindow", "barShowWorkspaces", "barShowLayout",
        "barShowSystem", "barShowNetSpeed", "barShowVolume", "barShowKbLayout", "barShowTray",
        "barShowQuickIcons", "barShowFiles", "barShowBattery",
        "screenshotDir", "screenshotCopyClipboard", "screenshotNotify", "screenshotDelay",
        "reducedMotion", "highContrast",
    )
    for k in bar_keys:
        if k in defaults:
            prefs[k] = defaults[k]
    save_prefs(prefs)
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", "true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["gsettings", "set", "org.gnome.desktop.a11y.interface", "high-contrast", "false"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps(prefs))


def cmd_reset_files():
    defaults = default_prefs()
    prefs = load_prefs(True)
    for k in defaults:
        if k.startswith("fm"):
            prefs[k] = defaults[k]
    save_prefs(prefs)
    print(json.dumps(prefs))


def cmd_reset_all():
    defaults = default_prefs()
    scripts_dir = os.path.join(os.path.dirname(prefs_path), "scripts")
    apply_local_sh = os.path.join(scripts_dir, "apply-local-setting.sh")
    if os.path.isfile(apply_local_sh):
        subprocess.run([apply_local_sh, "reset"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    reset_appearance_impl(defaults)
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "clock-format", "24h"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps(defaults))


def cmd_set_font():
    if len(args) < 2:
        sys.exit("Usage: manage-settings.sh set-font <family> <size>")
    family = args[0].strip()
    size = max(8, min(18, int(float(args[1]))))
    if not family or "\n" in family or "=" in family:
        sys.exit("Invalid font family")
    prefs = load_prefs(True)
    prefs["uiFontFamily"] = family
    prefs["uiFontSize"] = size
    save_prefs(prefs)

    font_spec = f"{family} {size}"
    cfg_dir = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
    update_ini_font(os.path.join(cfg_dir, "gtk-3.0", "settings.ini"), font_spec)
    update_ini_font(os.path.join(cfg_dir, "gtk-4.0", "settings.ini"), font_spec)
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "font-name", font_spec], stderr=subprocess.DEVNULL)
    sync_sddm_sh = os.path.join(os.path.dirname(prefs_path), "scripts", "sync-sddm-theme.sh")
    if os.path.isfile(sync_sddm_sh):
        subprocess.run([sync_sddm_sh], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps(prefs))


def cmd_set_mono_font():
    if len(args) < 1:
        sys.exit("Usage: manage-settings.sh set-mono-font <family> [size]")
    family = args[0].strip()
    if not family or "\n" in family or "=" in family:
        sys.exit("Invalid monospace font family")
    prefs = load_prefs(True)
    size = max(8, min(18, int(float(args[1])))) if len(args) >= 2 else int(prefs.get("uiFontSize", 10))
    prefs["monoFontFamily"] = family
    prefs["uiFontSize"] = size
    save_prefs(prefs)

    font_spec = f"{family} {size}"
    if shutil.which("gsettings"):
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "monospace-font-name", font_spec], stderr=subprocess.DEVNULL)
    update_foot_font(family, size)
    update_kitty_font(family, size)
    sync_sddm_sh = os.path.join(os.path.dirname(prefs_path), "scripts", "sync-sddm-theme.sh")
    if os.path.isfile(sync_sddm_sh):
        subprocess.run([sync_sddm_sh], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps(prefs))


def run_fc_list(pattern):
    if not shutil.which("fc-list"):
        return []
    try:
        out = subprocess.check_output(
            ["fc-list", pattern, "--format=%{family[0]}\n"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        items = sorted({line.strip() for line in out.splitlines() if line.strip()}, key=lambda s: s.lower())
        return items
    except Exception:
        return []


def cmd_list_fonts():
    mono = run_fc_list(":spacing=100")
    all_fam = run_fc_list(":")
    for fallback in ("IBM Plex Mono", "JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono"):
        if fallback not in mono:
            mono.append(fallback)
        if fallback not in all_fam:
            all_fam.append(fallback)
    for ui_fb in ("IBM Plex Sans", "DejaVu Sans", "Liberation Sans"):
        if ui_fb not in all_fam:
            all_fam.append(ui_fb)
    mono = sorted(set(mono), key=lambda s: s.lower())
    all_fam = sorted(set(all_fam), key=lambda s: s.lower())
    mono_set = set(mono)
    sans = [
        f for f in all_fam
        if f not in mono_set
        and "nerd font" not in f.lower()
        and "emoji" not in f.lower()
        and "dingbats" not in f.lower()
    ]
    if "IBM Plex Sans" not in sans:
        sans.insert(0, "IBM Plex Sans")
    print(json.dumps({"sans": sans, "monospace": mono, "families": all_fam}))


def scan_desktop_apps():
    data_dir = os.path.expanduser(os.environ.get("XDG_DATA_HOME", "~/.local/share"))
    dirs = [
        os.path.join(data_dir, "applications"),
        "/usr/local/share/applications",
        "/usr/share/applications",
    ]
    seen = {}
    for d in dirs:
        if not os.path.isdir(d):
            continue
        try:
            entries = sorted(os.listdir(d))
        except Exception:
            continue
        for fname in entries:
            if not fname.endswith(".desktop") or fname in seen:
                continue
            full = os.path.join(d, fname)
            if not os.path.isfile(full):
                continue
            cp = configparser.ConfigParser(interpolation=None)
            try:
                cp.read(full, encoding="utf-8")
            except Exception:
                continue
            if "Desktop Entry" not in cp:
                continue
            sec = cp["Desktop Entry"]
            if sec.get("Type", "") != "Application":
                continue
            if sec.get("NoDisplay", "").lower() == "true" or sec.get("Hidden", "").lower() == "true":
                continue
            name = sec.get("Name", fname[:-8]).strip()
            cats = [c.strip() for c in sec.get("Categories", "").split(";") if c.strip()]
            mimes = [m.strip() for m in sec.get("MimeType", "").split(";") if m.strip()]
            seen[fname] = {
                "id": fname,
                "name": name,
                "categories": cats,
                "mimeTypes": mimes,
            }
    return sorted(seen.values(), key=lambda x: x["name"].lower())


def xdg_query(mime):
    if not shutil.which("xdg-mime"):
        return ""
    try:
        return subprocess.check_output(["xdg-mime", "query", "default", mime], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def cmd_defaults_get():
    prefs = load_prefs(True)
    role_pools = {
        "terminal": ["foot", "kitty", "alacritty", "wezterm", "ghostty", "konsole", "gnome-terminal", "xfce4-terminal", "xterm"],
        "browser": ["helium", "firefox", "librewolf", "chromium", "google-chrome", "brave", "vivaldi", "qutebrowser", "falkon"],
        "editor": ["zedit", "zed", "code", "codium", "neovide", "kate", "mousepad", "gedit", "nvim", "vim"],
        "files": ["thunar", "dolphin", "nautilus", "nemo", "pcmanfm-qt", "pcmanfm", "caja"],
    }
    candidates = {}
    for role, pool in role_pools.items():
        found = [c for c in pool if shutil.which(c)]
        cur = prefs.get({"terminal": "defaultTerminal", "browser": "defaultBrowser", "editor": "defaultEditor", "files": "defaultFileManager"}[role], "")
        if cur and cur not in found:
            found.insert(0, cur)
        candidates[role] = found

    apps = scan_desktop_apps()
    mime_targets = {
        "web": "x-scheme-handler/http",
        "files": "inode/directory",
        "text": "text/plain",
        "images": "image/png",
        "video": "video/mp4",
    }
    mime_defaults = {}
    for key, mime in mime_targets.items():
        cur_desktop = xdg_query(mime)
        matching_apps = [
            {"id": a["id"], "name": a["name"]}
            for a in apps
            if mime in a["mimeTypes"]
            or (key == "web" and ("WebBrowser" in a["categories"] or "text/html" in a["mimeTypes"]))
            or (key == "files" and "FileManager" in a["categories"])
            or (key == "text" and ("TextEditor" in a["categories"] or any(m.startswith("text/") for m in a["mimeTypes"])))
            or (key == "images" and any(m.startswith("image/") for m in a["mimeTypes"]))
            or (key == "video" and any(m.startswith("video/") for m in a["mimeTypes"]))
        ]
        mime_defaults[key] = {
            "mime": mime,
            "current": cur_desktop,
            "options": matching_apps[:30],
        }

    print(json.dumps({
        "hasXdgMime": bool(shutil.which("xdg-mime")),
        "quickLaunch": {
            "terminal": prefs["defaultTerminal"],
            "browser": prefs["defaultBrowser"],
            "editor": prefs["defaultEditor"],
            "files": prefs["defaultFileManager"],
        },
        "candidates": candidates,
        "mimeDefaults": mime_defaults,
    }))


def cmd_defaults_set():
    if len(args) < 2:
        sys.exit("Usage: manage-settings.sh defaults-set <mime_type> <desktop_id>")
    mime = args[0].strip()
    desktop_id = args[1].strip()
    if not re.match(r"^[a-zA-Z0-9.+_-]+/[a-zA-Z0-9.+_-]+$", mime):
        sys.exit("Invalid MIME type")
    if not re.match(r"^[A-Za-z0-9._-]+\.desktop$", desktop_id):
        sys.exit("Invalid desktop entry ID")
    if not shutil.which("xdg-mime"):
        sys.exit("xdg-mime not installed")

    subprocess.run(["xdg-mime", "default", desktop_id, mime], check=True)
    if mime == "x-scheme-handler/http":
        subprocess.run(["xdg-mime", "default", desktop_id, "x-scheme-handler/https"], check=False)
        subprocess.run(["xdg-mime", "default", desktop_id, "text/html"], check=False)
    cmd_defaults_get()


def read_startup_state():
    user_items = []
    if os.path.exists(local_conf_path):
        try:
            with open(local_conf_path, "r", encoding="utf-8") as f:
                for line in f:
                    s = line.strip()
                    if not s or s.startswith("#"):
                        continue
                    if s.startswith("exec_once="):
                        val = s.split("=", 1)[1].strip()
                        if val:
                            user_items.append({"cmd": val, "source": "local"})
        except Exception:
            pass

    builtin_items = []
    if os.path.exists(autostart_path):
        try:
            with open(autostart_path, "r", encoding="utf-8") as f:
                for line in f:
                    s = line.strip()
                    if not s or s.startswith("#") or s.startswith("export ") or s.startswith("dbus-") or s.startswith("if ") or s in ("fi", "then", "else") or s.startswith("pgrep ") or s.startswith("set "):
                        continue
                    if "command -v" in s or "mkdir " in s or "case " in s:
                        continue
                    if s.endswith("&") or "qs " in s or "swaybg" in s or "swww" in s or "awww" in s or "wl-paste" in s:
                        cleaned = re.sub(r"\s*(?:</dev/null|>/dev/null|2>&1)\s*", " ", s)
                        cleaned = re.sub(r"\s+&\s*$", "", cleaned).strip()
                        cleaned = re.sub(r"\s+", " ", cleaned)
                        if cleaned:
                            builtin_items.append({"cmd": cleaned, "source": "autostart"})
        except Exception:
            pass
    return {"items": user_items, "builtin": builtin_items}


def cmd_startup_list():
    print(json.dumps(read_startup_state()))


def cmd_startup_add():
    if len(args) < 1:
        sys.exit("Usage: manage-settings.sh startup-add <command>")
    new_cmd = " ".join(args).strip()
    if not new_cmd or "\n" in new_cmd or "\r" in new_cmd:
        sys.exit("Invalid startup command")

    lines = []
    if os.path.exists(local_conf_path):
        with open(local_conf_path, "r", encoding="utf-8") as f:
            lines = f.readlines()

    target_line = f"exec_once={new_cmd}\n"
    if not any(line.strip() == f"exec_once={new_cmd}" for line in lines):
        lines.append(target_line)
        atomic_write_text(local_conf_path, "".join(lines))
    print(json.dumps(read_startup_state()))


def cmd_startup_remove():
    if len(args) < 1:
        sys.exit("Usage: manage-settings.sh startup-remove <command>")
    target_cmd = " ".join(args).strip()
    if os.path.exists(local_conf_path):
        with open(local_conf_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        kept = [line for line in lines if line.strip() != f"exec_once={target_cmd}"]
        if any(line.strip() and not line.strip().startswith("#") for line in kept):
            atomic_write_text(local_conf_path, "".join(kept))
        elif kept:
            atomic_write_text(local_conf_path, "".join(kept))
        else:
            os.remove(local_conf_path)
    print(json.dumps(read_startup_state()))


def parse_binds(path, source_name="config"):
    binds = []
    if not os.path.exists(path):
        return binds
    current_cat = "General"
    try:
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                s = raw.strip()
                if not s:
                    continue
                if s.startswith("#"):
                    heading = s.lstrip("#").strip()
                    if heading and not heading.startswith("=") and not heading.startswith("-") and len(heading) <= 48:
                        if not re.match(r"^[a-z_]+\s*=", heading):
                            current_cat = heading
                    continue
                is_mouse = s.startswith("mousebind=")
                is_key = s.startswith("bind=")
                if not is_key and not is_mouse:
                    continue
                body = s.split("=", 1)[1]
                parts = [p.strip() for p in body.split(",", 3)]
                if len(parts) < 3:
                    continue
                mods_raw, key_raw, action = parts[0], parts[1], parts[2]
                arg = parts[3] if len(parts) > 3 else ""
                if arg and "launch-app.sh" in arg:
                    role = arg.strip().split()[-1]
                    arg_display = f"Default {role}"
                else:
                    arg_display = arg.replace("$HOME/.config/quickshell/scripts/", "").replace("$HOME/.config/mango/", "")
                mods = [m.strip() for m in mods_raw.split("+") if m.strip() and m.strip().lower() != "none"]
                binds.append({
                    "kind": "mouse" if is_mouse else "key",
                    "source": source_name,
                    "category": current_cat,
                    "mods": mods,
                    "modsRaw": mods_raw,
                    "key": key_raw,
                    "action": action,
                    "arg": arg_display,
                    "rawArg": arg,
                    "raw": s,
                })
    except Exception:
        pass
    return binds


def cmd_keybinds_list():
    binds = parse_binds(mango_conf_path, "config")
    binds.extend(parse_binds(local_conf_path, "local"))
    cats = []
    for b in binds:
        if b["category"] not in cats:
            cats.append(b["category"])
    print(json.dumps({"categories": cats, "binds": binds}))


def read_cpu_info():
    model = platform.processor() or "Unknown CPU"
    cores = os.cpu_count() or 1
    try:
        with open("/proc/cpuinfo", "r", encoding="utf-8") as f:
            for line in f:
                if line.lower().startswith("model name"):
                    model = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass
    return f"{model} ({cores}T)"


def read_gpu_info():
    if not shutil.which("lspci"):
        return []
    gpus = []
    try:
        out = subprocess.check_output(["lspci"], text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if any(tag in line for tag in ("VGA compatible controller", "3D controller", "Display controller")):
                desc = line.split(":", 2)[-1].strip()
                desc = re.sub(r"\s*\(rev [^)]+\)$", "", desc)
                gpus.append(desc)
    except Exception:
        pass
    return gpus


def read_mem_info():
    total_kb = 0
    avail_kb = 0
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    total_kb = int(line.split()[1])
                elif line.startswith("MemAvailable:"):
                    avail_kb = int(line.split()[1])
    except Exception:
        pass
    used_kb = max(0, total_kb - avail_kb)
    return {
        "totalGb": round(total_kb / (1024 * 1024), 1),
        "usedGb": round(used_kb / (1024 * 1024), 1),
        "usedPct": round((used_kb / total_kb) * 100) if total_kb > 0 else 0,
    }


def read_uptime():
    try:
        with open("/proc/uptime", "r", encoding="utf-8") as f:
            sec = int(float(f.read().split()[0]))
        days, rem = divmod(sec, 86400)
        hours, rem = divmod(rem, 3600)
        mins, _ = divmod(rem, 60)
        parts = []
        if days:
            parts.append(f"{days}d")
        if hours:
            parts.append(f"{hours}h")
        parts.append(f"{mins}m")
        return " ".join(parts)
    except Exception:
        return "0m"


def read_timezone():
    try:
        target = os.path.realpath("/etc/localtime")
        if "/zoneinfo/" in target:
            return target.split("/zoneinfo/", 1)[1]
    except Exception:
        pass
    return "Local"


def read_distro():
    try:
        with open("/etc/os-release", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"\'')
    except Exception:
        pass
    return platform.system()


def read_power_profiles():
    if not shutil.which("powerprofilesctl"):
        return {"hasPowerProfiles": False, "active": "", "available": []}
    try:
        active = subprocess.check_output(["powerprofilesctl", "get"], text=True, stderr=subprocess.DEVNULL).strip()
        listed = subprocess.check_output(["powerprofilesctl", "list"], text=True, stderr=subprocess.DEVNULL)
        avail = []
        for line in listed.splitlines():
            m = re.match(r"^\s*\*?\s*([a-z0-9-]+):\s*$", line)
            if m:
                avail.append(m.group(1))
        return {"hasPowerProfiles": True, "active": active, "available": avail or ["power-saver", "balanced", "performance"]}
    except Exception:
        return {"hasPowerProfiles": False, "active": "", "available": []}


def read_disks():
    disks = []
    seen_stats = set()
    try:
        with open("/proc/mounts", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                dev, mount, fstype = parts[0], parts[1].replace("\\040", " "), parts[2]
                if not dev.startswith("/dev/"):
                    continue
                if any(mount.startswith(skip) for skip in ("/snap", "/var/lib/docker", "/boot/efi")):
                    pass
                if fstype in ("squashfs", "tmpfs", "devtmpfs", "overlay"):
                    continue
                try:
                    st = os.statvfs(mount)
                except Exception:
                    continue
                total = st.f_blocks * st.f_frsize
                if total <= 0:
                    continue
                avail = st.f_bavail * st.f_frsize
                free_root = st.f_bfree * st.f_frsize
                used = max(0, total - free_root)
                sig = (dev, total)
                if sig in seen_stats and mount not in ("/", "/home"):
                    continue
                seen_stats.add(sig)
                disks.append({
                    "mount": mount,
                    "device": os.path.basename(dev),
                    "fs": fstype,
                    "totalGb": round(total / (1024 ** 3), 1),
                    "usedGb": round(used / (1024 ** 3), 1),
                    "availGb": round(avail / (1024 ** 3), 1),
                    "usedPct": round((used / total) * 100) if total > 0 else 0,
                })
    except Exception:
        pass
    return disks


def cmd_system_info():
    print(json.dumps({
        "hostname": socket.gethostname(),
        "distro": read_distro(),
        "kernel": platform.release(),
        "cpu": read_cpu_info(),
        "gpus": read_gpu_info(),
        "memory": read_mem_info(),
        "uptime": read_uptime(),
        "timezone": read_timezone(),
        "powerProfiles": read_power_profiles(),
        "disks": read_disks(),
    }))


def cmd_night_light():
    if len(args) < 1:
        sys.exit("Usage: manage-settings.sh night-light <on|off> [temp]")
    state = args[0].strip().lower() in ("1", "true", "on", "enable")
    prefs = load_prefs(True)
    temp = prefs["nightLightTemp"]
    if len(args) >= 2:
        temp = max(2500, min(6500, int(float(args[1]))))
    prefs["nightLightEnabled"] = state
    prefs["nightLightTemp"] = temp
    save_prefs(prefs)

    for tool in ("wlsunset", "hyprsunset", "gammastep"):
        subprocess.run(["pkill", "-x", tool], stderr=subprocess.DEVNULL)

    if state:
        if shutil.which("hyprsunset"):
            subprocess.Popen(["hyprsunset", "-t", str(temp)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif shutil.which("wlsunset"):
            subprocess.Popen(["wlsunset", "-T", str(temp + 100), "-t", str(temp)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif shutil.which("gammastep"):
            subprocess.Popen(["gammastep", "-O", str(temp)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps(prefs))


def load_hidden_apps_payload():
    hidden_path = os.path.join(os.path.dirname(prefs_path), "hidden-apps.json")
    data = {"hiddenIds": [], "hiddenNamePrefixes": []}
    if os.path.exists(hidden_path):
        try:
            with open(hidden_path, "r", encoding="utf-8") as f:
                raw = json.load(f)
            if isinstance(raw, dict):
                data["hiddenIds"] = [str(x) for x in raw.get("hiddenIds", []) if str(x).strip()]
                data["hiddenNamePrefixes"] = [str(x) for x in raw.get("hiddenNamePrefixes", []) if str(x).strip()]
        except Exception:
            pass
    installed = []
    for a in scan_desktop_apps():
        base_id = a["id"][:-8] if a["id"].endswith(".desktop") else a["id"]
        installed.append({"id": base_id, "name": a["name"]})
    data["installedApps"] = installed
    return hidden_path, data


def cmd_hidden_apps_get():
    _, payload = load_hidden_apps_payload()
    print(json.dumps(payload))


def cmd_hidden_apps_add():
    if len(args) < 2:
        sys.exit("Usage: manage-settings.sh hidden-apps-add <id|prefix> <value>")
    kind, val = args[0].strip().lower(), " ".join(args[1:]).strip()
    if not val:
        sys.exit("Empty value")
    hidden_path, payload = load_hidden_apps_payload()
    target_key = "hiddenNamePrefixes" if kind == "prefix" else "hiddenIds"
    lst = list(payload[target_key])
    if val not in lst:
        lst.append(val)
    to_save = {"hiddenIds": payload["hiddenIds"], "hiddenNamePrefixes": payload["hiddenNamePrefixes"]}
    to_save[target_key] = lst
    atomic_write_text(hidden_path, json.dumps(to_save, indent=2) + "\n")
    _, refreshed = load_hidden_apps_payload()
    print(json.dumps(refreshed))


def cmd_hidden_apps_remove():
    if len(args) < 2:
        sys.exit("Usage: manage-settings.sh hidden-apps-remove <id|prefix> <value>")
    kind, val = args[0].strip().lower(), " ".join(args[1:]).strip()
    hidden_path, payload = load_hidden_apps_payload()
    target_key = "hiddenNamePrefixes" if kind == "prefix" else "hiddenIds"
    lst = [x for x in payload[target_key] if x != val]
    to_save = {"hiddenIds": payload["hiddenIds"], "hiddenNamePrefixes": payload["hiddenNamePrefixes"]}
    to_save[target_key] = lst
    atomic_write_text(hidden_path, json.dumps(to_save, indent=2) + "\n")
    _, refreshed = load_hidden_apps_payload()
    print(json.dumps(refreshed))


DISPATCH = {
    "prefs-get": cmd_prefs_get,
    "prefs-set": cmd_prefs_set,
    "prefs-set-batch": cmd_prefs_set_batch,
    "prefs-reset": cmd_prefs_reset,
    "reset-appearance": cmd_reset_appearance,
    "reset-bar": cmd_reset_bar,
    "reset-files": cmd_reset_files,
    "reset-all": cmd_reset_all,
    "set-font": cmd_set_font,
    "set-mono-font": cmd_set_mono_font,
    "list-fonts": cmd_list_fonts,
    "defaults-get": cmd_defaults_get,
    "defaults-set": cmd_defaults_set,
    "startup-list": cmd_startup_list,
    "startup-add": cmd_startup_add,
    "startup-remove": cmd_startup_remove,
    "keybinds-list": cmd_keybinds_list,
    "system-info": cmd_system_info,
    "night-light": cmd_night_light,
    "hidden-apps-get": cmd_hidden_apps_get,
    "hidden-apps-add": cmd_hidden_apps_add,
    "hidden-apps-remove": cmd_hidden_apps_remove,
}

DISPATCH[cmd]()
PY
