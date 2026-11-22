#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
PREFS_FILE="$HOME/.config/quickshell/shell-prefs.json"

if [[ -z "$ROLE" ]]; then
    echo "Usage: launch-app.sh <terminal|browser|editor|files>" >&2
    exit 1
fi

exec python3 - "$ROLE" "$PREFS_FILE" <<'PY'
import json
import os
import shlex
import shutil
import sys

role = sys.argv[1]
prefs_path = sys.argv[2]

ROLE_MAP = {
    "terminal": ("defaultTerminal", ["foot", "kitty", "alacritty", "wezterm", "ghostty", "konsole", "gnome-terminal", "xfce4-terminal", "xterm"]),
    "browser": ("defaultBrowser", ["helium", "firefox", "librewolf", "chromium", "google-chrome", "brave", "vivaldi", "qutebrowser", "falkon"]),
    "editor": ("defaultEditor", ["zedit", "zed", "code", "codium", "neovide", "kate", "mousepad", "gedit"]),
    "files": ("defaultFileManager", ["thunar", "dolphin", "nautilus", "nemo", "pcmanfm-qt", "pcmanfm", "caja"]),
}

if role not in ROLE_MAP:
    sys.stderr.write(f"Unknown app role: {role}\n")
    sys.exit(1)

pref_key, fallbacks = ROLE_MAP[role]
candidates = []

if os.path.exists(prefs_path):
    try:
        with open(prefs_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        val = str(data.get(pref_key, "")).strip()
        if val:
            candidates.append(val)
    except Exception:
        pass

for fb in fallbacks:
    if fb not in candidates:
        candidates.append(fb)

for cmd in candidates:
    if cmd.endswith(".desktop"):
        if shutil.which("gtk-launch"):
            os.execvp("gtk-launch", ["gtk-launch", cmd])
        elif shutil.which("gio"):
            for base in (os.path.expanduser("~/.local/share/applications"), "/usr/local/share/applications", "/usr/share/applications"):
                p = os.path.join(base, cmd)
                if os.path.exists(p):
                    os.execvp("gio", ["gio", "launch", p])
        continue
    try:
        parts = shlex.split(cmd)
    except ValueError:
        continue
    if not parts:
        continue
    exe = parts[0]
    if shutil.which(exe) or (os.path.isabs(exe) and os.access(exe, os.X_OK)):
        os.execvp(exe, parts)

# Final fallback for editor/files inside an available terminal
term_cmd = next((t for t in fallbacks if role == "terminal" and shutil.which(t)), None)
if role in ("editor", "files"):
    term_candidates = ["foot", "kitty", "alacritty", "wezterm", "xterm"]
    term = next((t for t in term_candidates if shutil.which(t)), None)
    if term:
        if role == "editor":
            for ed in ("nvim", "vim", "nano"):
                if shutil.which(ed):
                    os.execvp(term, [term, "-e", ed])
        else:
            for fm in ("yazi", "ranger", "lf", "mc"):
                if shutil.which(fm):
                    os.execvp(term, [term, "-e", fm])

sys.stderr.write(f"No available application found for role: {role}\n")
sys.exit(1)
PY
