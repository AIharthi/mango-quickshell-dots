#!/usr/bin/env bash
set -euo pipefail

# Lock screen using the first available Wayland locker.

if command -v hyprlock >/dev/null 2>&1; then
    exec hyprlock
elif command -v swaylock >/dev/null 2>&1; then
    exec swaylock -f
elif command -v waylock >/dev/null 2>&1; then
    exec waylock
else
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Screen Lock" "No screen locker installed" \
            "Install swaylock, hyprlock, or waylock to enable screen locking." -t 4000 >/dev/null 2>&1 || true
    fi
    exit 1
fi
