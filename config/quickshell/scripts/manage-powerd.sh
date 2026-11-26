#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

PRIVILEGED=0
SRC_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --privileged)
            PRIVILEGED=1
            shift
            ;;
        --src)
            SRC_ARG="${2:-}"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

CMD="${1:-status}"
shift || true

case "$CMD" in
    status|set|config|install-service|uninstall-service)
        ;;
    *)
        echo '{"ok":false,"error":"Usage: manage-powerd.sh <status|set|config|install-service|uninstall-service> [args...]"}'
        exit 1
        ;;
esac

find_powerd_bin() {
    if [[ -n "$SRC_ARG" && -x "$SRC_ARG" ]]; then
        printf '%s\n' "$SRC_ARG"
        return 0
    fi
    local user_bin="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bin/aurora-powerd"
    if [[ -x "$user_bin" ]]; then
        printf '%s\n' "$user_bin"
        return 0
    fi
    if [[ -x "/usr/local/bin/aurora-powerd" ]]; then
        printf '%s\n' "/usr/local/bin/aurora-powerd"
        return 0
    fi
    if command -v aurora-powerd >/dev/null 2>&1; then
        command -v aurora-powerd
        return 0
    fi
    return 1
}

python_status_fallback() {
    python3 - <<'PY'
import glob, json, os, shutil, subprocess

def read_txt(p):
    try:
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except OSError:
        return ""

policies = sorted(glob.glob("/sys/devices/system/cpu/cpufreq/policy[0-9]*"))
has_cpufreq = len(policies) > 0
p0 = policies[0] if policies else ""
driver = read_txt(os.path.join(p0, "scaling_driver")) if p0 else ""
gov = read_txt(os.path.join(p0, "scaling_governor")) if p0 else ""
epp = read_txt(os.path.join(p0, "energy_performance_preference")) if p0 else ""
ppd = None
if shutil.which("powerprofilesctl"):
    try:
        ppd = subprocess.check_output(["powerprofilesctl", "get"], text=True, stderr=subprocess.DEVNULL).strip() or None
    except Exception:
        ppd = None
daemon_installed = os.path.exists("/etc/init.d/aurora-powerd") or os.path.exists("/etc/systemd/system/aurora-powerd.service")
init_sys = "systemd" if os.path.isdir("/run/systemd/system") else ("openrc" if shutil.which("rc-service") else "unknown")
has_pp = has_cpufreq or (ppd is not None)
active = ppd or ("performance" if epp == "performance" or gov == "performance" else ("power-saver" if epp in ("power", "balance_power") else "balanced"))
print(json.dumps({
    "ok": True,
    "hasPowerProfiles": has_pp,
    "backend": "power-profiles-daemon" if ppd else "direct",
    "daemonRunning": False,
    "daemonInstalled": daemon_installed,
    "initSystem": init_sys,
    "active": active,
    "available": ["power-saver", "balanced", "performance"] if has_pp else [],
    "governor": gov,
    "epp": epp,
    "driver": driver,
    "boostSupported": os.path.exists("/sys/devices/system/cpu/cpufreq/boost"),
    "boostEnabled": read_txt("/sys/devices/system/cpu/cpufreq/boost") == "1",
    "platformProfile": read_txt("/sys/firmware/acpi/platform_profile"),
    "hasPlatformProfile": os.path.exists("/sys/firmware/acpi/platform_profile"),
    "gpuDpmSupported": bool(glob.glob("/sys/class/drm/card[0-9]*/device/power_dpm_force_performance_level")),
    "gpuDpmLevel": "",
    "cpuFreqMhz": 0,
    "hasBattery": False,
    "onAc": True,
    "autoSwitch": False,
    "acProfile": "balanced",
    "batteryProfile": "power-saver",
    "gpuDpmControl": True,
    "boostOnSaver": False,
}))
PY
}

if [[ "$CMD" == "status" || "$CMD" == "set" || "$CMD" == "config" ]]; then
    if BIN="$(find_powerd_bin)"; then
        exec "$BIN" "$CMD" "$@"
    fi
    if [[ "$CMD" == "status" ]]; then
        python_status_fallback
        exit 0
    fi
    echo '{"ok":false,"error":"aurora-powerd binary not found; run ./install.sh first"}'
    exit 1
fi

run_privileged_self() {
    local src_opt=()
    local bin_found=""
    if bin_found="$(find_powerd_bin 2>/dev/null)"; then
        src_opt=(--src "$bin_found")
    fi
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi
    if [[ "$PRIVILEGED" -eq 1 ]]; then
        echo '{"ok":false,"error":"Root privileges required"}'
        exit 1
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        exec sudo -n "$SCRIPT_PATH" --privileged "${src_opt[@]}" "$CMD" "$@"
    fi
    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec "$SCRIPT_PATH" --privileged "${src_opt[@]}" "$CMD" "$@"
    fi
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$SCRIPT_PATH" --privileged "${src_opt[@]}" "$CMD" "$@"
    fi
    echo '{"ok":false,"error":"Neither sudo nor pkexec is available for service setup"}'
    exit 1
}

run_privileged_self "$@"

if [[ "$CMD" == "install-service" ]]; then
    SRC_BIN="$(find_powerd_bin)" || {
        echo '{"ok":false,"error":"aurora-powerd binary not found; compile via ./install.sh first"}'
        exit 1
    }
    install -Dm755 "$SRC_BIN" /usr/local/bin/aurora-powerd

    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        cat > /etc/systemd/system/aurora-powerd.service <<'EOF'
[Unit]
Description=Aurora Shell Power Profile Daemon
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/aurora-powerd daemon
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 /etc/systemd/system/aurora-powerd.service
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable --now aurora-powerd.service >/dev/null 2>&1
    elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        cat > /etc/init.d/aurora-powerd <<'EOF'
#!/sbin/openrc-run

name="aurora-powerd"
description="Aurora Shell Power Profile Daemon"
command="/usr/local/bin/aurora-powerd"
command_args="daemon"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need localmount
}
EOF
        chmod 755 /etc/init.d/aurora-powerd
        rc-update add aurora-powerd default >/dev/null 2>&1 || true
        rc-service aurora-powerd restart >/dev/null 2>&1
    else
        echo '{"ok":false,"error":"Unsupported init system (requires systemd or OpenRC)"}'
        exit 1
    fi

    for _ in $(seq 1 15); do
        [[ -S /run/aurora-powerd.sock ]] && break
        sleep 0.1
    done
    exec /usr/local/bin/aurora-powerd status
fi

if [[ "$CMD" == "uninstall-service" ]]; then
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now aurora-powerd.service >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/aurora-powerd.service
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service aurora-powerd stop >/dev/null 2>&1 || true
        if command -v rc-update >/dev/null 2>&1; then
            rc-update del aurora-powerd default >/dev/null 2>&1 || true
        fi
        rm -f /etc/init.d/aurora-powerd
    fi
    rm -f /usr/local/bin/aurora-powerd /run/aurora-powerd.sock
    if BIN="$(find_powerd_bin 2>/dev/null)"; then
        exec "$BIN" status
    fi
    python_status_fallback
    exit 0
fi
