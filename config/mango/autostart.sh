#!/usr/bin/env bash
set -euo pipefail

# MangoWC Session Autostart (Fedora / Arch / Gentoo — systemd & OpenRC + elogind)

CONFIG_BASE="${XDG_CONFIG_HOME:-$HOME/.config}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "${DBUS_SESSION_BUS_ADDRESS:-}" == "disabled:" ]]; then
    if [[ ! -S "${RUNTIME_DIR}/bus" ]] && command -v dbus-daemon >/dev/null 2>&1; then
        dbus-daemon --session --address="unix:path=${RUNTIME_DIR}/bus" --fork >/dev/null 2>&1 || true
    fi
    if [[ -S "${RUNTIME_DIR}/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME_DIR}/bus"
    fi
fi

# Export Wayland display & desktop identity to D-Bus / systemd activation environment
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY XDG_CURRENT_DESKTOP MANGO_INSTANCE_SIGNATURE >/dev/null 2>&1 \
        || dbus-update-activation-environment DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY XDG_CURRENT_DESKTOP MANGO_INSTANCE_SIGNATURE >/dev/null 2>&1 || true
fi

# Audio (PipeWire + WirePlumber fallback for OpenRC / non-systemd)
if ! pgrep -x pipewire >/dev/null 2>&1; then
    if command -v gentoo-pipewire-launcher >/dev/null 2>&1; then
        gentoo-pipewire-launcher restart >/dev/null 2>&1 &
    elif [[ ! -d /run/systemd/system ]] && command -v pipewire >/dev/null 2>&1; then
        pipewire </dev/null >/dev/null 2>&1 &
        if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -x pipewire-pulse >/dev/null 2>&1; then
            pipewire-pulse </dev/null >/dev/null 2>&1 &
        fi
        if command -v wireplumber >/dev/null 2>&1 && ! pgrep -x wireplumber >/dev/null 2>&1; then
            wireplumber </dev/null >/dev/null 2>&1 &
        fi
    fi
fi

# Polkit authentication agent (Gentoo / Fedora / Arch paths)
if ! pgrep -f 'polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|lxqt-policykit-agent|mate-polkit|xfce-polkit' >/dev/null 2>&1; then
    for agent in \
        /usr/libexec/polkit-gnome-authentication-agent-1 \
        /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
        /usr/libexec/lxqt-policykit-agent \
        /usr/lib/polkit-kde-authentication-agent-1 \
        /usr/libexec/polkit-kde-authentication-agent-1 \
        /usr/libexec/xfce-polkit \
        /usr/lib/mate-polkit/polkit-mate-authentication-agent-1; do
        if [[ -x "$agent" ]]; then
            "$agent" </dev/null >/dev/null 2>&1 &
            break
        fi
    done
fi

# Wallpaper daemon (prefer already-running daemon, else awww -> swww)
if ! pgrep -x awww-daemon >/dev/null 2>&1 && ! pgrep -x swww-daemon >/dev/null 2>&1; then
    if command -v awww-daemon >/dev/null 2>&1; then
        awww-daemon </dev/null >/dev/null 2>&1 &
    elif command -v swww-daemon >/dev/null 2>&1; then
        swww-daemon </dev/null >/dev/null 2>&1 &
    fi
fi

# Apply saved visual mode (default | simple | blur)
if [[ -x "${CONFIG_BASE}/quickshell/scripts/apply-mode.sh" ]]; then
    "${CONFIG_BASE}/quickshell/scripts/apply-mode.sh" --init </dev/null >/dev/null 2>&1 || true
fi

# Apply saved wallpaper & synced GTK/MangoWC/Terminal palette
if [[ -x "${CONFIG_BASE}/quickshell/scripts/apply-theme.sh" ]]; then
    "${CONFIG_BASE}/quickshell/scripts/apply-theme.sh" --init </dev/null >/dev/null 2>&1 &
fi

# Launch Quickshell Dynamic Island
if command -v qs >/dev/null 2>&1; then
    if ! pgrep -x qs >/dev/null 2>&1; then
        qs -d </dev/null >/dev/null 2>&1 &
    fi
fi
