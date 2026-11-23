#!/usr/bin/env bash
set -euo pipefail

# Lock screen using native Quickshell session lock first, then external lockers.

if command -v qs >/dev/null 2>&1 && pgrep -x qs >/dev/null 2>&1; then
    if qs ipc call island lockSession >/dev/null 2>&1; then
        exit 0
    fi
fi

if command -v hyprlock >/dev/null 2>&1; then
    exec hyprlock
elif command -v swaylock >/dev/null 2>&1; then
    exec swaylock -f
elif command -v waylock >/dev/null 2>&1; then
    exec waylock
else
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Screen Lock" "No screen locker installed" \
            "Run Quickshell or install swaylock, hyprlock, or waylock to enable screen locking." -t 4000 >/dev/null 2>&1 || true
    fi
    exit 1
fi
