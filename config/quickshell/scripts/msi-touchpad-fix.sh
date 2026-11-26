#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

PRIVILEGED=0
if [[ "${1:-}" == "--privileged" ]]; then
    PRIVILEGED=1
    shift
fi

CMD="${1:-status}"
shift || true

case "$CMD" in
    status|restart|install|uninstall)
        ;;
    *)
        echo '{"ok":false,"error":"Usage: msi-touchpad-fix.sh <status|restart|install|uninstall> [device]"}'
        exit 1
        ;;
esac

validate_device() {
    local dev="${1:-i2c_designware.0}"
    if [[ ! "$dev" =~ ^i2c_designware\.[0-9A-Za-z._:-]+$ ]]; then
        python3 - "$dev" <<'PY'
import json, sys
print(json.dumps({"ok": False, "error": f"Invalid i2c_designware device name: {sys.argv[1]}"}))
PY
        exit 1
    fi
    printf '%s\n' "$dev"
}

emit_status_json() {
    local msg="${1:-}"
    python3 - "$msg" <<'PY'
import glob, json, os, re, shutil, subprocess, sys

msg = sys.argv[1] if len(sys.argv) > 1 else ""
drv_dir = "/sys/bus/platform/drivers/i2c_designware"
driver_present = os.path.isdir(drv_dir)

devices = []
if driver_present:
    for entry in sorted(glob.glob(os.path.join(drv_dir, "i2c_designware.*"))):
        name = os.path.basename(entry)
        if name:
            devices.append(name)

# Also discover unbound i2c_designware platform devices if available
for entry in sorted(glob.glob("/sys/bus/platform/devices/i2c_designware.*")):
    name = os.path.basename(entry)
    if name and name not in devices:
        devices.append(name)

if not devices:
    devices = ["i2c_designware.0"]

script_path = "/usr/local/bin/restart-i2c.sh"
script_installed = os.path.isfile(script_path) and os.access(script_path, os.X_OK)

selected_device = devices[0]
if os.path.isfile(script_path):
    try:
        with open(script_path, "r", encoding="utf-8", errors="ignore") as f:
            txt = f.read()
        m = re.search(r'(i2c_designware\.[0-9A-Za-z._:-]+)', txt)
        if m:
            selected_device = m.group(1)
            if selected_device not in devices:
                devices.append(selected_device)
    except OSError:
        pass

has_systemd = os.path.isdir("/run/systemd/system") and shutil.which("systemctl") is not None
has_openrc = shutil.which("rc-service") is not None or os.path.isdir("/run/openrc")
init_system = "systemd" if has_systemd else ("openrc" if has_openrc else "unknown")

systemd_unit = "/etc/systemd/system/restart-i2c.service"
openrc_init = "/etc/init.d/restart-i2c"
service_installed = os.path.isfile(systemd_unit) or os.path.isfile(openrc_init)

service_enabled = False
if has_systemd and os.path.isfile(systemd_unit):
    res = subprocess.run(
        ["systemctl", "is-enabled", "--quiet", "restart-i2c.service"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    service_enabled = res.returncode == 0
elif os.path.isfile(openrc_init):
    service_enabled = os.path.exists("/etc/runlevels/default/restart-i2c")

def read_txt(p):
    try:
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except OSError:
        return ""

dmi_vendor = read_txt("/sys/class/dmi/id/sys_vendor")
dmi_product = read_txt("/sys/class/dmi/id/product_name")
is_msi = ("msi" in dmi_vendor.lower()) or ("micro-star" in dmi_vendor.lower())

payload = {
    "ok": True,
    "driverPresent": driver_present,
    "devices": devices,
    "selectedDevice": selected_device,
    "initSystem": init_system,
    "scriptInstalled": script_installed,
    "serviceInstalled": service_installed,
    "serviceEnabled": service_enabled,
    "dmiVendor": dmi_vendor,
    "dmiProduct": dmi_product,
    "isMsi": is_msi,
}
if msg:
    payload["message"] = msg
print(json.dumps(payload))
PY
}

if [[ "$CMD" == "status" ]]; then
    emit_status_json ""
    exit 0
fi

run_privileged_self() {
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi
    if [[ "$PRIVILEGED" -eq 1 ]]; then
        echo '{"ok":false,"error":"Root privileges required"}'
        exit 1
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        exec sudo -n "$SCRIPT_PATH" --privileged "$CMD" "$@"
    fi
    if command -v pkexec >/dev/null 2>&1; then
        exec pkexec "$SCRIPT_PATH" --privileged "$CMD" "$@"
    fi
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$SCRIPT_PATH" --privileged "$CMD" "$@"
    fi
    echo '{"ok":false,"error":"Neither sudo nor pkexec is available for root action"}'
    exit 1
}

DRV_DIR="/sys/bus/platform/drivers/i2c_designware"
RESTART_BIN="/usr/local/bin/restart-i2c.sh"
SYSTEMD_UNIT="/etc/systemd/system/restart-i2c.service"
OPENRC_INIT="/etc/init.d/restart-i2c"

if [[ "$CMD" == "restart" ]]; then
    DEV="$(validate_device "${1:-i2c_designware.0}")"
    run_privileged_self "$DEV"
    if [[ ! -d "$DRV_DIR" ]]; then
        echo '{"ok":false,"error":"i2c_designware driver directory not found in /sys/bus/platform/drivers"}'
        exit 1
    fi
    if [[ -e "$DRV_DIR/$DEV" ]]; then
        if ! printf '%s\n' "$DEV" > "$DRV_DIR/unbind" 2>/dev/null; then
            echo "{\"ok\":false,\"error\":\"Failed to unbind ${DEV}\"}"
            exit 1
        fi
        sleep 1
    fi
    if ! printf '%s\n' "$DEV" > "$DRV_DIR/bind" 2>/dev/null; then
        echo "{\"ok\":false,\"error\":\"Failed to bind ${DEV} (check if device exists on this system)\"}"
        exit 1
    fi
    emit_status_json "Restarted ${DEV} driver binding"
    exit 0
fi

if [[ "$CMD" == "install" ]]; then
    DEV="$(validate_device "${1:-i2c_designware.0}")"
    run_privileged_self "$DEV"

    cat > "$RESTART_BIN" <<EOF
#!/usr/bin/env bash
set -euo pipefail
DEV="${DEV}"
DRV_DIR="/sys/bus/platform/drivers/i2c_designware"
if [[ -e "\${DRV_DIR}/\${DEV}" ]]; then
    printf '%s\n' "\${DEV}" > "\${DRV_DIR}/unbind"
    sleep 1
fi
if [[ -w "\${DRV_DIR}/bind" ]]; then
    printf '%s\n' "\${DEV}" > "\${DRV_DIR}/bind"
fi
EOF
    chmod 755 "$RESTART_BIN"

    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        cat > "$SYSTEMD_UNIT" <<'EOF'
[Unit]
Description=Restart i2c_designware module at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restart-i2c.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 "$SYSTEMD_UNIT"
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable restart-i2c.service >/dev/null 2>&1
        systemctl start restart-i2c.service >/dev/null 2>&1 || true
        emit_status_json "Installed systemd boot fix for ${DEV}"
        exit 0
    elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        cat > "$OPENRC_INIT" <<'EOF'
#!/sbin/openrc-run

name="restart-i2c"
description="Restart i2c_designware driver at boot for MSI touchpad"

depend() {
    after localmount
}

start() {
    ebegin "Restarting i2c_designware touchpad controller"
    /usr/local/bin/restart-i2c.sh
    eend $?
}
EOF
        chmod 755 "$OPENRC_INIT"
        rc-update add restart-i2c default >/dev/null 2>&1 || true
        rc-service restart-i2c start >/dev/null 2>&1 || true
        emit_status_json "Installed OpenRC boot fix for ${DEV}"
        exit 0
    else
        echo '{"ok":false,"error":"Unsupported init system (requires systemd or OpenRC)"}'
        exit 1
    fi
fi

if [[ "$CMD" == "uninstall" ]]; then
    run_privileged_self
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now restart-i2c.service >/dev/null 2>&1 || true
        rm -f "$SYSTEMD_UNIT"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service restart-i2c stop >/dev/null 2>&1 || true
        if command -v rc-update >/dev/null 2>&1; then
            rc-update del restart-i2c default >/dev/null 2>&1 || true
        fi
        rm -f "$OPENRC_INIT"
    fi
    rm -f "$RESTART_BIN"
    emit_status_json "Removed MSI touchpad I2C boot fix"
    exit 0
fi
