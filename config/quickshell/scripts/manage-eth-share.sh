#!/usr/bin/env bash
set -euo pipefail

# Manage two-sided Wi-Fi -> Ethernet tethering (Laptop Host / PC Client)
# Supports both NetworkManager (Arch, CachyOS, Fedora) and standalone Linux
# stacks (Gentoo OpenRC / dhcpcd / nftables / iptables / dnsmasq / static link).

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
RUN_DIR="/run/aurora-eth-share"
STATE_FILE="${RUN_DIR}/state.json"
CLIENT_STATE_FILE="${RUN_DIR}/client-state.json"
DNSMASQ_PID="${RUN_DIR}/dnsmasq.pid"
DNSMASQ_LEASES="${RUN_DIR}/dnsmasq.leases"
DNSMASQ_LOG="${RUN_DIR}/dnsmasq.log"
NM_HOST_CON="aurora-eth-share"
NM_CLIENT_CON="aurora-eth-client"

PRIVILEGED=0
if [[ "${1:-}" == "--privileged" ]]; then
    PRIVILEGED=1
    shift
fi

CMD="${1:-status}"
shift || true

emit_json_error() {
    python3 - "$1" <<'PY'
import json, sys
print(json.dumps({"ok": False, "error": sys.argv[1]}))
PY
    exit 1
}

validate_iface() {
    local name="${1:-}"
    if [[ ! "$name" =~ ^[A-Za-z0-9._:-]+$ ]] || [[ "$name" == "lo" ]] || [[ ! -d "/sys/class/net/$name" ]]; then
        emit_json_error "Invalid or missing network interface: $name"
    fi
}

run_privileged_self() {
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi
    if [[ "$PRIVILEGED" -eq 1 ]]; then
        emit_json_error "Root privileges are required for Ethernet sharing"
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
    emit_json_error "Neither pkexec nor sudo is available for privilege elevation"
}

collect_status_json() {
    local extra_ok="${1:-true}"
    local extra_msg="${2:-}"
    local extra_err="${3:-}"
    python3 - "$extra_ok" "$extra_msg" "$extra_err" <<'PY'
import glob
import json
import os
import re
import shutil
import subprocess
import sys

extra_ok = sys.argv[1].lower() == "true"
extra_msg = sys.argv[2]
extra_err = sys.argv[3]

RUN_DIR = "/run/aurora-eth-share"
STATE_FILE = os.path.join(RUN_DIR, "state.json")
CLIENT_STATE_FILE = os.path.join(RUN_DIR, "client-state.json")
DNSMASQ_PID = os.path.join(RUN_DIR, "dnsmasq.pid")
DNSMASQ_LEASES = os.path.join(RUN_DIR, "dnsmasq.leases")
NM_HOST_CON = "aurora-eth-share"
NM_CLIENT_CON = "aurora-eth-client"

VIRT_PREFIXES = (
    "lo", "docker", "veth", "br-", "virbr", "tailscale", "wg",
    "tun", "tap", "zt", "ham", "vboxnet", "vmnet", "cni",
    "flannel", "podman", "nm-", "p2p-"
)


def run_out(argv, timeout=2.0):
    try:
        return subprocess.check_output(argv, text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()
    except Exception:
        return ""


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read().strip()
    except OSError:
        return ""


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else None
    except Exception:
        return None


def pid_alive(pid_path):
    raw = read_text(pid_path)
    if not raw.isdigit():
        return False
    pid = int(raw)
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def is_virtual_name(name):
    if name == "lo":
        return True
    for pfx in VIRT_PREFIXES:
        if pfx != "lo" and name.startswith(pfx):
            return True
    return False


has_nmcli = shutil.which("nmcli") is not None
nm_running = False
nm_dev_states = {}
nm_active_conns = {}
nm_all_conns = {}

if has_nmcli:
    if run_out(["timeout", "2", "nmcli", "-t", "-f", "RUNNING", "general"]) == "running":
        nm_running = True
        for line in run_out(["timeout", "2", "nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"]).splitlines():
            parts = re.split(r"(?<!\\):", line)
            if len(parts) >= 3:
                dev = parts[0].replace("\\:", ":")
                nm_dev_states[dev] = {
                    "type": parts[1],
                    "state": parts[2],
                    "conn": parts[3].replace("\\:", ":") if len(parts) >= 4 else "",
                    "managed": parts[2] != "unmanaged",
                }
        for line in run_out(["timeout", "2", "nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]).splitlines():
            parts = re.split(r"(?<!\\):", line)
            if len(parts) >= 3:
                cname = parts[0].replace("\\:", ":")
                nm_active_conns[cname] = {"type": parts[1], "device": parts[2].replace("\\:", ":")}
        for line in run_out(["timeout", "2", "nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show"]).splitlines():
            parts = re.split(r"(?<!\\):", line)
            if len(parts) >= 4:
                cname = parts[0].replace("\\:", ":")
                nm_all_conns[cname] = {"type": parts[1], "device": parts[2].replace("\\:", ":"), "state": parts[3]}

has_dnsmasq = shutil.which("dnsmasq") is not None
has_nft = shutil.which("nft") is not None
has_iptables = shutil.which("iptables") is not None
has_dhcpcd = shutil.which("dhcpcd") is not None
has_firewalld = False
if shutil.which("firewall-cmd") is not None:
    has_firewalld = run_out(["timeout", "2", "firewall-cmd", "--state"]) == "running"
has_ufw = False
if shutil.which("ufw") is not None:
    ufw_out = run_out(["timeout", "2", "ufw", "status"])
    has_ufw = "Status: active" in ufw_out

default_iface = ""
default_gw = ""
route_raw = run_out(["ip", "-j", "-4", "route", "show", "default"])
if not route_raw:
    route_raw = run_out(["ip", "-j", "route", "show", "default"])
if route_raw:
    try:
        routes = json.loads(route_raw)
        if routes:
            default_iface = routes[0].get("dev", "") or ""
            default_gw = routes[0].get("gateway", "") or ""
    except Exception:
        pass

addr_map = {}
addr_raw = run_out(["ip", "-j", "addr"])
if addr_raw:
    try:
        for item in json.loads(addr_raw):
            addr_map[item.get("ifname", "")] = item
    except Exception:
        pass

wifi_ssids = {}
if nm_running:
    for dev, info in nm_dev_states.items():
        if info.get("type") == "wifi" and info.get("state") == "connected" and info.get("conn"):
            wifi_ssids[dev] = info["conn"]

interfaces = []
wifi_ifaces = []
eth_ifaces = []

for name in sorted(os.listdir("/sys/class/net")):
    if is_virtual_name(name):
        continue
    sys_base = os.path.join("/sys/class/net", name)
    is_wifi = os.path.isdir(os.path.join(sys_base, "wireless")) or os.path.isdir(os.path.join(sys_base, "phy80211"))
    is_phys = os.path.exists(os.path.join(sys_base, "device"))
    if not is_wifi and not is_phys:
        continue

    item = addr_map.get(name, {})
    state = (read_text(os.path.join(sys_base, "operstate")) or item.get("operstate") or "unknown").upper()
    carrier_raw = read_text(os.path.join(sys_base, "carrier"))
    carrier = carrier_raw == "1"

    speed_str = ""
    sp_raw = read_text(os.path.join(sys_base, "speed"))
    if sp_raw and sp_raw.lstrip("-").isdigit():
        sp_val = int(sp_raw)
        if sp_val > 0:
            speed_str = f"{sp_val} Mbps"

    addrs = []
    ipv4 = ""
    for a in item.get("addr_info", []):
        if a.get("family") in ("inet", "inet6") and a.get("scope") != "host":
            local_ip = a.get("local", "")
            plen = a.get("prefixlen", "")
            if local_ip:
                addrs.append(f"{local_ip}/{plen}")
                if a.get("family") == "inet" and not ipv4:
                    ipv4 = local_ip

    rx_mb, tx_mb = 0.0, 0.0
    rx_raw = read_text(os.path.join(sys_base, "statistics", "rx_bytes"))
    tx_raw = read_text(os.path.join(sys_base, "statistics", "tx_bytes"))
    if rx_raw.isdigit():
        rx_mb = round(int(rx_raw) / (1024 ** 2), 1)
    if tx_raw.isdigit():
        tx_mb = round(int(tx_raw) / (1024 ** 2), 1)

    ssid = wifi_ssids.get(name, "")
    if is_wifi and not ssid:
        if shutil.which("iwgetid"):
            ssid = run_out(["timeout", "1", "iwgetid", "-r", name])
        if not ssid and shutil.which("iw"):
            iw_out = run_out(["timeout", "1", "iw", "dev", name, "link"])
            m = re.search(r"^\s*SSID:\s*(.+)$", iw_out, re.M)
            if m:
                ssid = m.group(1).strip()

    nm_info = nm_dev_states.get(name, {})
    entry = {
        "name": name,
        "kind": "wifi" if is_wifi else "ethernet",
        "state": state,
        "carrier": carrier,
        "speed": speed_str,
        "addrs": addrs,
        "ipv4": ipv4,
        "mac": read_text(os.path.join(sys_base, "address")) or item.get("address", ""),
        "ssid": ssid,
        "rxMb": rx_mb,
        "txMb": tx_mb,
        "isDefaultRoute": name == default_iface,
        "nmManaged": bool(nm_running and nm_info.get("managed", False)),
    }
    interfaces.append(entry)
    if is_wifi:
        wifi_ifaces.append(entry)
    else:
        eth_ifaces.append(entry)


def pick_default_source():
    for i in wifi_ifaces:
        if i["isDefaultRoute"] and i["state"] == "UP":
            return i["name"]
    for i in wifi_ifaces:
        if i["state"] == "UP" or i["ipv4"]:
            return i["name"]
    for i in wifi_ifaces:
        return i["name"]
    if default_iface and len(eth_ifaces) >= 2:
        return default_iface
    return ""


def pick_default_eth(exclude=""):
    for i in eth_ifaces:
        if i["name"] != exclude and i["carrier"]:
            return i["name"]
    for i in eth_ifaces:
        if i["name"] != exclude:
            return i["name"]
    return eth_ifaces[0]["name"] if eth_ifaces else ""


def find_iface(name):
    for i in interfaces:
        if i["name"] == name:
            return i
    return None


standalone_host = read_json(STATE_FILE)
standalone_client = read_json(CLIENT_STATE_FILE)

active = False
role = "off"
backend = ""
host_eth = ""
host_upstream = ""
client_eth = ""
client_ip = ""

# 1. Check active NetworkManager host share
if nm_running and NM_HOST_CON in nm_active_conns:
    active = True
    role = "host"
    backend = "nmcli"
    host_eth = nm_active_conns[NM_HOST_CON].get("device", "")
    host_upstream = pick_default_source()

# 2. Check active standalone NAT host share
if not active and standalone_host:
    s_eth = standalone_host.get("ethIface", "")
    s_up = standalone_host.get("upstreamIface", "")
    eth_entry = find_iface(s_eth)
    has_gw_ip = bool(eth_entry and any(a.startswith("10.42.0.1/") for a in eth_entry.get("addrs", [])))
    if has_gw_ip or pid_alive(DNSMASQ_PID):
        active = True
        role = "host"
        backend = "static-host" if standalone_host.get("dnsMode") == "static" else "standalone"
        host_eth = s_eth
        host_upstream = s_up

# 3. Check active static PC client
if not active and nm_running and NM_CLIENT_CON in nm_active_conns:
    active = True
    role = "client"
    backend = "static-client"
    client_eth = nm_active_conns[NM_CLIENT_CON].get("device", "")
    c_entry = find_iface(client_eth)
    client_ip = c_entry["ipv4"] if c_entry else "10.42.0.2"

if not active and standalone_client:
    c_eth = standalone_client.get("ethIface", "")
    c_entry = find_iface(c_eth)
    if c_entry and c_entry.get("ipv4") == "10.42.0.2":
        active = True
        role = "client"
        backend = "static-client"
        client_eth = c_eth
        client_ip = "10.42.0.2"

# 4. Auto-detect PC receiving DHCP from laptop share (10.42.0.2..254 or gw 10.42.0.1)
if not active:
    for e in eth_ifaces:
        ip_v4 = e.get("ipv4", "")
        if ip_v4.startswith("10.42.0.") and ip_v4 != "10.42.0.1":
            active = True
            role = "client"
            backend = "dhcp-client"
            client_eth = e["name"]
            client_ip = ip_v4
            break
    if not active and default_gw == "10.42.0.1" and default_iface:
        d_entry = find_iface(default_iface)
        if d_entry and d_entry.get("kind") == "ethernet":
            active = True
            role = "client"
            backend = "dhcp-client"
            client_eth = default_iface
            client_ip = d_entry.get("ipv4", "")

clients = []
if role == "host" and host_eth:
    by_mac = {}
    lease_files = []
    if os.path.isfile(DNSMASQ_LEASES):
        lease_files.append(DNSMASQ_LEASES)
    lease_files.extend(sorted(glob.glob("/var/lib/NetworkManager/dnsmasq-*.leases")))
    for lf in lease_files:
        txt = read_text(lf)
        for line in txt.splitlines():
            parts = line.split()
            if len(parts) >= 4:
                mac = parts[1].lower()
                ip = parts[2]
                host = parts[3] if parts[3] != "*" else "PC Client"
                if ip.startswith("10.42.0."):
                    by_mac[mac] = {"ip": ip, "mac": mac, "hostname": host, "state": "LEASED"}

    neigh_raw = run_out(["ip", "-j", "neigh", "show", "dev", host_eth])
    if neigh_raw:
        try:
            for n in json.loads(neigh_raw):
                ip = n.get("dst", "")
                if not ip.startswith("10.42.0."):
                    continue
                mac = (n.get("lladdr", "") or "").lower()
                st_list = n.get("state", [])
                st_str = st_list[0] if isinstance(st_list, list) and st_list else str(st_list or "ONLINE")
                if st_str in ("FAILED", "INCOMPLETE"):
                    continue
                if mac and mac in by_mac:
                    by_mac[mac]["state"] = st_str
                else:
                    key = mac or ip
                    by_mac[key] = {"ip": ip, "mac": mac or "-", "hostname": "Connected PC", "state": st_str}
        except Exception:
            pass
    clients = sorted(by_mac.values(), key=lambda c: c["ip"])

src_iface = host_upstream or pick_default_source()
tgt_iface = host_eth or client_eth or pick_default_eth(src_iface)
recommended_role = "host" if (wifi_ifaces and eth_ifaces) else "client"

tgt_entry = find_iface(tgt_iface)
carrier = bool(tgt_entry and tgt_entry["carrier"])
link_speed = tgt_entry["speed"] if tgt_entry else ""

warnings = []
if recommended_role == "host" and not has_dnsmasq and not standalone_host:
    warnings.append("dnsmasq is not installed: Auto DHCP requires dnsmasq, or use Direct Static on PC (10.42.0.2 -> 10.42.0.1).")
if eth_ifaces and not any(e["carrier"] for e in eth_ifaces):
    warnings.append("No Ethernet cable link detected.")

peer_summary = ""
if role == "host":
    if clients:
        first = clients[0]
        name_lbl = first["hostname"] if first["hostname"] else first["ip"]
        peer_summary = f"{name_lbl} ({first['ip']})"
    else:
        peer_summary = "Waiting for PC"
elif role == "client":
    peer_summary = f"Via {client_eth} ({client_ip or '10.42.0.x'})"

payload = {
    "ok": extra_ok,
    "active": active,
    "role": role,
    "backend": backend,
    "ethIface": tgt_iface,
    "upstreamIface": src_iface,
    "clientEthIface": client_eth or tgt_iface,
    "clientIp": client_ip,
    "sourceIface": src_iface,
    "targetIface": tgt_iface,
    "recommendedRole": recommended_role,
    "gatewayIp": "10.42.0.1",
    "subnet": "10.42.0.0/24",
    "carrier": carrier,
    "linkSpeed": link_speed,
    "defaultIface": default_iface,
    "defaultGateway": default_gw,
    "nmRunning": nm_running,
    "hasDnsmasq": has_dnsmasq,
    "hasNft": has_nft,
    "hasIptables": has_iptables,
    "hasFirewalld": has_firewalld,
    "hasUfw": has_ufw,
    "hasDhcpcd": has_dhcpcd,
    "interfaces": interfaces,
    "wifiInterfaces": wifi_ifaces,
    "ethInterfaces": eth_ifaces,
    "clients": clients,
    "peerSummary": peer_summary,
    "warnings": warnings,
}
if extra_msg:
    payload["message"] = extra_msg
if extra_err:
    payload["error"] = extra_err

print(json.dumps(payload))
PY
}

get_status_field() {
    local field="$1"
    collect_status_json "true" "" "" | python3 -c "import json,sys; d=json.load(sys.stdin); v=d.get('$field',''); print('true' if v is True else ('false' if v is False else str(v)))"
}

check_nm_manages_iface() {
    local iface="$1"
    timeout 2 nmcli -t -f DEVICE,STATE dev status 2>/dev/null | awk -F: -v dev="$iface" '$1==dev && $2!="unmanaged"{found=1} END{exit !found}'
}

cleanup_standalone_host() {
    if [[ -f "$DNSMASQ_PID" ]]; then
        local dpid
        dpid="$(cat "$DNSMASQ_PID" 2>/dev/null || true)"
        if [[ "$dpid" =~ ^[0-9]+$ ]] && kill -0 "$dpid" 2>/dev/null; then
            kill "$dpid" 2>/dev/null || true
            sleep 0.2
            kill -9 "$dpid" 2>/dev/null || true
        fi
    fi

    if command -v nft >/dev/null 2>&1; then
        nft delete table inet aurora_eth_share 2>/dev/null || true
    fi

    if command -v iptables >/dev/null 2>&1; then
        python3 - <<'PY'
import shlex, subprocess
for table, chain in (("nat", "POSTROUTING"), (None, "FORWARD"), (None, "INPUT")):
    cmd = ["iptables"] + (["-t", table] if table else []) + ["-S", chain]
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        continue
    for line in out.splitlines():
        if "aurora-eth-share" not in line:
            continue
        toks = shlex.split(line)
        if toks and toks[0] == "-A":
            del_cmd = ["iptables"] + (["-t", table] if table else []) + ["-D"] + toks[1:]
            subprocess.run(del_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
    fi

    if [[ -f "$STATE_FILE" ]]; then
        python3 - "$STATE_FILE" <<'PY'
import json, os, shutil, subprocess, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        st = json.load(f)
except Exception:
    st = {}

eth = st.get("ethIface", "")
up = st.get("upstreamIface", "")
prev_fwd = str(st.get("prevIpForward", "0")).strip()
prev_zone = st.get("firewalldPrevZone", "")

if eth:
    subprocess.run(["ip", "addr", "del", "10.42.0.1/24", "dev", eth], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if prev_fwd in ("0", "1"):
    try:
        with open("/proc/sys/net/ipv4/ip_forward", "w", encoding="utf-8") as f:
            f.write(prev_fwd + "\n")
    except OSError:
        pass

if st.get("firewalldChanged") and eth and shutil.which("firewall-cmd"):
    if prev_zone:
        subprocess.run(["firewall-cmd", f"--zone={prev_zone}", f"--change-interface={eth}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(["firewall-cmd", "--zone=trusted", f"--remove-interface={eth}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if st.get("ufwChanged") and eth and up and shutil.which("ufw"):
    subprocess.run(["ufw", "route", "delete", "allow", "in", "on", eth, "out", "on", up], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ufw", "delete", "allow", "in", "on", eth, "to", "any", "port", "67", "proto", "udp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ufw", "delete", "allow", "in", "on", eth, "to", "any", "port", "53"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
    fi

    rm -f "$STATE_FILE" "$DNSMASQ_PID" "$DNSMASQ_LEASES" "$DNSMASQ_LOG" 2>/dev/null || true
}

cleanup_standalone_client() {
    if [[ ! -f "$CLIENT_STATE_FILE" ]]; then
        return 0
    fi
    python3 - "$CLIENT_STATE_FILE" <<'PY'
import json, os, subprocess, sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        st = json.load(f)
except Exception:
    st = {}

eth = st.get("ethIface", "")
if eth:
    subprocess.run(["ip", "route", "del", "default", "via", "10.42.0.1", "dev", eth], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["ip", "addr", "del", "10.42.0.2/24", "dev", eth], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

prev_resolv = st.get("prevResolvConf")
if isinstance(prev_resolv, str) and not os.path.islink("/etc/resolv.conf"):
    try:
        with open("/etc/resolv.conf", "w", encoding="utf-8") as f:
            f.write(prev_resolv)
    except OSError:
        pass
PY
    rm -f "$CLIENT_STATE_FILE" 2>/dev/null || true
}

start_standalone_dnsmasq() {
    local eth="$1"
    local up_servers=()
    if [[ -r /etc/resolv.conf ]]; then
        while IFS= read -r ns; do
            [[ -n "$ns" ]] && up_servers+=("$ns")
        done < <(awk '/^nameserver[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ { if ($2 !~ /^127\./ && $2 != "0.0.0.0") print $2 }' /etc/resolv.conf | head -n 3)
    fi
    if [[ "${#up_servers[@]}" -eq 0 ]]; then
        up_servers=("1.1.1.1" "8.8.8.8")
    fi

    local srv_args=()
    for s in "${up_servers[@]}"; do
        srv_args+=("--server=$s")
    done
    local dns_csv
    dns_csv="$(IFS=,; echo "${up_servers[*]}")"

    touch "$DNSMASQ_LEASES"
    chmod 644 "$DNSMASQ_LEASES"

    if dnsmasq \
        --interface="$eth" \
        --bind-interfaces \
        --except-interface=lo \
        --listen-address=10.42.0.1 \
        --no-resolv \
        --no-hosts \
        --conf-file=/dev/null \
        --dhcp-authoritative \
        --dhcp-range=10.42.0.10,10.42.0.250,255.255.255.0,12h \
        --dhcp-option=option:router,10.42.0.1 \
        --dhcp-option=option:dns-server,10.42.0.1 \
        --dhcp-leasefile="$DNSMASQ_LEASES" \
        --pid-file="$DNSMASQ_PID" \
        --log-facility="$DNSMASQ_LOG" \
        "${srv_args[@]}" 2>/dev/null; then
        sleep 0.25
        local pid_val
        pid_val="$(cat "$DNSMASQ_PID" 2>/dev/null || true)"
        if [[ "$pid_val" =~ ^[0-9]+$ ]] && kill -0 "$pid_val" 2>/dev/null; then
            return 0
        fi
    fi

    # Fallback: if local port 53 is occupied by a wildcard resolver, run DHCP-only
    # and advertise upstream DNS directly to the PC.
    rm -f "$DNSMASQ_PID" 2>/dev/null || true
    if dnsmasq \
        --port=0 \
        --interface="$eth" \
        --bind-interfaces \
        --except-interface=lo \
        --listen-address=10.42.0.1 \
        --no-hosts \
        --conf-file=/dev/null \
        --dhcp-authoritative \
        --dhcp-range=10.42.0.10,10.42.0.250,255.255.255.0,12h \
        --dhcp-option=option:router,10.42.0.1 \
        --dhcp-option="option:dns-server,${dns_csv}" \
        --dhcp-leasefile="$DNSMASQ_LEASES" \
        --pid-file="$DNSMASQ_PID" \
        --log-facility="$DNSMASQ_LOG" 2>/dev/null; then
        sleep 0.25
        local pid_val
        pid_val="$(cat "$DNSMASQ_PID" 2>/dev/null || true)"
        if [[ "$pid_val" =~ ^[0-9]+$ ]] && kill -0 "$pid_val" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

cmd_start_host() {
    local req_eth="${1:-auto}"
    local req_up="${2:-auto}"
    local dns_mode="${3:-auto}"
    if [[ "$dns_mode" != "auto" && "$dns_mode" != "static" ]]; then
        dns_mode="auto"
    fi

    local status_json
    status_json="$(collect_status_json "true" "" "")"
    read -r eth up nm_run has_dnsmasq ufw_active carrier < <(python3 - "$req_eth" "$req_up" "$status_json" <<'PY'
import json, sys
req_eth, req_up = sys.argv[1], sys.argv[2]
st = json.loads(sys.argv[3])
up = st.get("sourceIface", "") if req_up in ("", "auto") else req_up
eth = st.get("targetIface", "") if req_eth in ("", "auto") else req_eth
if eth == up:
    for e in st.get("ethInterfaces", []):
        if e.get("name") != up:
            eth = e.get("name", "")
            break
carrier = False
for i in st.get("interfaces", []):
    if i.get("name") == eth:
        carrier = bool(i.get("carrier"))
        break
print(
    eth or "-",
    up or "-",
    "1" if st.get("nmRunning") else "0",
    "1" if st.get("hasDnsmasq") else "0",
    "1" if st.get("hasUfw") else "0",
    "1" if carrier else "0",
)
PY
    )

    if [[ "$up" == "-" ]]; then
        emit_json_error "No active Wi-Fi or upstream interface found to share"
    fi
    if [[ "$eth" == "-" ]]; then
        emit_json_error "No physical Ethernet interface detected on this device"
    fi

    validate_iface "$eth"
    validate_iface "$up"
    if [[ "$eth" == "$up" ]]; then
        emit_json_error "Upstream and Ethernet output interfaces cannot be the same ($eth)"
    fi

    local use_nm=0
    if [[ "$nm_run" == "1" ]] && [[ "$dns_mode" == "auto" ]] && [[ "$has_dnsmasq" == "1" ]] && [[ "$ufw_active" == "0" ]]; then
        if check_nm_manages_iface "$eth"; then
            use_nm=1
        fi
    fi

    if [[ "$use_nm" -eq 1 ]]; then
        if [[ "$carrier" == "0" ]]; then
            emit_json_error "No Ethernet cable link detected on ${eth}. Connect your laptop and PC with an Ethernet cable first."
        fi
        # Clean any stale standalone host state if migrating to NM
        if [[ -f "$STATE_FILE" || -f "$DNSMASQ_PID" ]]; then
            run_privileged_self "$eth" "$up" "$dns_mode"
            cleanup_standalone_host
        fi

        local nm_err=""
        nmcli connection down "$NM_HOST_CON" >/dev/null 2>&1 || true
        nmcli connection delete "$NM_HOST_CON" >/dev/null 2>&1 || true
        if nm_err="$(nmcli connection add type ethernet ifname "$eth" con-name "$NM_HOST_CON" ipv4.method shared ipv4.addresses 10.42.0.1/24 ipv6.method ignore connection.autoconnect no 2>&1)" \
           && nm_err="$(timeout 12 nmcli connection up "$NM_HOST_CON" 2>&1)"; then
            collect_status_json "true" "Sharing ${up} to ${eth} via NetworkManager (10.42.0.1/24)" ""
            return 0
        fi
        if [[ "$EUID" -ne 0 ]] && [[ "$nm_err" == *"Not authorized"* || "$nm_err" == *"insufficient privileges"* || "$nm_err" == *"permission"* ]]; then
            run_privileged_self "$eth" "$up" "$dns_mode"
        fi
        nmcli connection delete "$NM_HOST_CON" >/dev/null 2>&1 || true
        emit_json_error "NetworkManager failed to start Ethernet sharing on ${eth}: ${nm_err:-check cable link}"
    fi

    # Standalone Linux NAT + optional dnsmasq (Gentoo, unmanaged eth, UFW, or static mode)
    run_privileged_self "$eth" "$up" "$dns_mode"

    if [[ "$nm_run" == "1" ]]; then
        nmcli connection down "$NM_HOST_CON" >/dev/null 2>&1 || true
        nmcli connection delete "$NM_HOST_CON" >/dev/null 2>&1 || true
    fi

    cleanup_standalone_host
    cleanup_standalone_client
    mkdir -p "$RUN_DIR"
    chmod 755 "$RUN_DIR"

    local prev_fwd
    prev_fwd="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"

    local fw_backend="none"
    local firewalld_changed=0
    local firewalld_prev_zone=""
    local ufw_changed=0

    ip link set dev "$eth" up
    ip addr replace 10.42.0.1/24 dev "$eth"
    printf '1\n' > /proc/sys/net/ipv4/ip_forward

    if command -v nft >/dev/null 2>&1; then
        fw_backend="nft"
        nft delete table inet aurora_eth_share 2>/dev/null || true
        nft -f - <<EOF
table inet aurora_eth_share {
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 10.42.0.0/24 oifname "${up}" masquerade
    }
    chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "${eth}" oifname "${up}" accept
        iifname "${up}" oifname "${eth}" ct state related,established accept
    }
    chain input {
        type filter hook input priority filter; policy accept;
        iifname "${eth}" udp dport { 53, 67 } accept
        iifname "${eth}" tcp dport 53 accept
    }
}
EOF
        # If Docker or iptables FORWARD policy is DROP, punch targeted rules at top of FORWARD
        if command -v iptables >/dev/null 2>&1; then
            if iptables -S FORWARD 2>/dev/null | head -n1 | grep -q "\-P FORWARD DROP"; then
                iptables -I FORWARD 1 -i "$up" -o "$eth" -m state --state RELATED,ESTABLISHED -m comment --comment aurora-eth-share -j ACCEPT
                iptables -I FORWARD 1 -i "$eth" -o "$up" -m comment --comment aurora-eth-share -j ACCEPT
            fi
        fi
    elif command -v iptables >/dev/null 2>&1; then
        fw_backend="iptables"
        iptables -t nat -A POSTROUTING -s 10.42.0.0/24 -o "$up" -m comment --comment aurora-eth-share -j MASQUERADE
        iptables -I FORWARD 1 -i "$up" -o "$eth" -m state --state RELATED,ESTABLISHED -m comment --comment aurora-eth-share -j ACCEPT
        iptables -I FORWARD 1 -i "$eth" -o "$up" -m comment --comment aurora-eth-share -j ACCEPT
        iptables -I INPUT 1 -i "$eth" -p udp --dport 67 -m comment --comment aurora-eth-share -j ACCEPT
        iptables -I INPUT 1 -i "$eth" -p udp --dport 53 -m comment --comment aurora-eth-share -j ACCEPT
        iptables -I INPUT 1 -i "$eth" -p tcp --dport 53 -m comment --comment aurora-eth-share -j ACCEPT
    else
        cleanup_standalone_host
        emit_json_error "Neither nftables (nft) nor iptables is available for NAT forwarding"
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && [[ "$(firewall-cmd --state 2>/dev/null || true)" == "running" ]]; then
        firewalld_prev_zone="$(firewall-cmd --get-zone-of-interface="$eth" 2>/dev/null || true)"
        if firewall-cmd --zone=trusted --change-interface="$eth" >/dev/null 2>&1; then
            firewalld_changed=1
        fi
    fi

    if [[ "$ufw_active" == "1" ]] && command -v ufw >/dev/null 2>&1; then
        ufw route allow in on "$eth" out on "$up" >/dev/null 2>&1 || true
        ufw allow in on "$eth" to any port 67 proto udp >/dev/null 2>&1 || true
        ufw allow in on "$eth" to any port 53 >/dev/null 2>&1 || true
        ufw_changed=1
    fi

    local effective_dns="static"
    local note=""
    if [[ "$dns_mode" != "static" ]] && command -v dnsmasq >/dev/null 2>&1; then
        if start_standalone_dnsmasq "$eth"; then
            effective_dns="auto"
        else
            note=" (dnsmasq could not bind port 67/53; use Direct Static 10.42.0.2 on PC)"
        fi
    elif [[ "$dns_mode" != "static" ]]; then
        note=" (dnsmasq not installed; use Direct Static 10.42.0.2 on PC)"
    fi

    python3 - "$STATE_FILE" "$eth" "$up" "$effective_dns" "$prev_fwd" "$fw_backend" "$firewalld_changed" "$firewalld_prev_zone" "$ufw_changed" <<'PY'
import json, os, sys
st = {
    "ethIface": sys.argv[2],
    "upstreamIface": sys.argv[3],
    "dnsMode": sys.argv[4],
    "prevIpForward": sys.argv[5],
    "fwBackend": sys.argv[6],
    "firewalldChanged": sys.argv[7] == "1",
    "firewalldPrevZone": sys.argv[8],
    "ufwChanged": sys.argv[9] == "1",
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(st, f)
os.chmod(sys.argv[1], 0o644)
PY

    if [[ "$effective_dns" == "auto" ]]; then
        collect_status_json "true" "Sharing ${up} to ${eth} with DHCP + NAT (10.42.0.1/24)" ""
    else
        collect_status_json "true" "NAT active ${up} -> ${eth} at 10.42.0.1/24${note}" ""
    fi
}

cmd_stop_host() {
    local nm_has=0
    if command -v nmcli >/dev/null 2>&1 && [[ "$(timeout 2 nmcli -t -f RUNNING general 2>/dev/null || true)" == "running" ]]; then
        if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$NM_HOST_CON"; then
            nm_has=1
        fi
    fi

    local has_standalone=0
    if [[ -f "$STATE_FILE" || -f "$DNSMASQ_PID" ]]; then
        has_standalone=1
    fi

    if [[ "$nm_has" -eq 1 && "$has_standalone" -eq 0 ]]; then
        local nm_err=""
        nmcli connection down "$NM_HOST_CON" >/dev/null 2>&1 || true
        if nm_err="$(nmcli connection delete "$NM_HOST_CON" 2>&1)"; then
            collect_status_json "true" "Stopped Ethernet Wi-Fi sharing" ""
            return 0
        fi
        if [[ "$EUID" -ne 0 ]] && [[ "$nm_err" == *"Not authorized"* || "$nm_err" == *"insufficient privileges"* || "$nm_err" == *"permission"* ]]; then
            run_privileged_self
        fi
    fi

    if [[ "$has_standalone" -eq 1 ]]; then
        run_privileged_self
        local prev_eth=""
        if [[ -f "$STATE_FILE" ]]; then
            prev_eth="$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('ethIface',''))" 2>/dev/null || true)"
        fi
        cleanup_standalone_host
        if [[ -n "$prev_eth" ]] && command -v dhcpcd >/dev/null 2>&1 && pgrep -x dhcpcd >/dev/null 2>&1; then
            timeout 2 dhcpcd -n "$prev_eth" >/dev/null 2>&1 || true
        fi
    fi

    collect_status_json "true" "Stopped Ethernet Wi-Fi sharing" ""
}

cmd_connect_client() {
    local req_eth="${1:-auto}"
    local mode="${2:-auto}"
    if [[ "$mode" != "auto" && "$mode" != "static" ]]; then
        mode="auto"
    fi

    local status_json
    status_json="$(collect_status_json "true" "" "")"
    read -r eth nm_run carrier < <(python3 - "$req_eth" "$status_json" <<'PY'
import json, sys
req_eth = sys.argv[1]
st = json.loads(sys.argv[2])
eth = st.get("clientEthIface", "") if req_eth in ("", "auto") else req_eth
carrier = False
for i in st.get("interfaces", []):
    if i.get("name") == eth:
        carrier = bool(i.get("carrier"))
        break
print(eth or "-", "1" if st.get("nmRunning") else "0", "1" if carrier else "0")
PY
    )

    if [[ "$eth" == "-" ]]; then
        emit_json_error "No physical Ethernet interface detected on this PC"
    fi
    validate_iface "$eth"

    if [[ "$carrier" == "0" ]]; then
        emit_json_error "No Ethernet cable link detected on ${eth}. Connect your PC to the laptop first."
    fi

    local use_nm=0
    if [[ "$nm_run" == "1" ]] && check_nm_manages_iface "$eth"; then
        use_nm=1
    fi

    if [[ "$mode" == "auto" ]]; then
        if [[ "$use_nm" -eq 1 ]]; then
            if [[ -f "$CLIENT_STATE_FILE" ]]; then
                run_privileged_self "$eth" "$mode"
                cleanup_standalone_client
            fi
            local nm_err=""
            nmcli connection down "$NM_CLIENT_CON" >/dev/null 2>&1 || true
            nmcli connection delete "$NM_CLIENT_CON" >/dev/null 2>&1 || true
            if ! nm_err="$(timeout 10 nmcli device connect "$eth" 2>&1)"; then
                if [[ "$EUID" -ne 0 ]] && [[ "$nm_err" == *"Not authorized"* || "$nm_err" == *"insufficient privileges"* || "$nm_err" == *"permission"* ]]; then
                    run_privileged_self "$eth" "$mode"
                fi
                emit_json_error "DHCP connect failed on ${eth}. Try Direct Static (10.42.0.2) if the laptop has no DHCP server."
            fi
            sleep 0.6
            collect_status_json "true" "Requested DHCP lease on ${eth}" ""
            return 0
        fi

        run_privileged_self "$eth" "$mode"
        cleanup_standalone_client
        ip link set dev "$eth" up
        if command -v dhcpcd >/dev/null 2>&1; then
            if pgrep -x dhcpcd >/dev/null 2>&1; then
                timeout 6 dhcpcd -n "$eth" >/dev/null 2>&1 || true
            else
                timeout 6 dhcpcd -1 "$eth" >/dev/null 2>&1 || true
            fi
        elif command -v dhclient >/dev/null 2>&1; then
            timeout 6 dhclient -1 "$eth" >/dev/null 2>&1 || true
        elif command -v udhcpc >/dev/null 2>&1; then
            timeout 6 udhcpc -i "$eth" -n -q >/dev/null 2>&1 || true
        else
            emit_json_error "No DHCP client found (dhcpcd/dhclient/udhcpc). Use Direct Static (10.42.0.2)."
        fi

        local i=0
        while [[ "$i" -lt 8 ]]; do
            if ip -4 addr show dev "$eth" | grep -qE "inet [0-9]+\."; then
                break
            fi
            sleep 0.5
            i=$((i + 1))
        done
        collect_status_json "true" "Updated DHCP configuration on ${eth}" ""
        return 0
    fi

    # Static direct link: 10.42.0.2/24 -> 10.42.0.1
    if [[ "$use_nm" -eq 1 ]]; then
        local nm_err=""
        nmcli connection down "$NM_CLIENT_CON" >/dev/null 2>&1 || true
        nmcli connection delete "$NM_CLIENT_CON" >/dev/null 2>&1 || true
        if nm_err="$(nmcli connection add type ethernet ifname "$eth" con-name "$NM_CLIENT_CON" ipv4.method manual ipv4.addresses 10.42.0.2/24 ipv4.gateway 10.42.0.1 ipv4.dns "1.1.1.1 8.8.8.8" ipv6.method ignore connection.autoconnect no 2>&1)" \
           && nm_err="$(timeout 10 nmcli connection up "$NM_CLIENT_CON" 2>&1)"; then
            collect_status_json "true" "Connected static Ethernet link 10.42.0.2/24 -> 10.42.0.1" ""
            return 0
        fi
        if [[ "$EUID" -ne 0 ]] && [[ "$nm_err" == *"Not authorized"* || "$nm_err" == *"insufficient privileges"* || "$nm_err" == *"permission"* ]]; then
            run_privileged_self "$eth" "$mode"
        fi
        emit_json_error "Failed static NM link on ${eth}: ${nm_err:-error}"
    fi

    run_privileged_self "$eth" "$mode"
    cleanup_standalone_client
    mkdir -p "$RUN_DIR"
    chmod 755 "$RUN_DIR"

    python3 - "$CLIENT_STATE_FILE" "$eth" <<'PY'
import json, os, sys
prev_resolv = None
if os.path.isfile("/etc/resolv.conf") and not os.path.islink("/etc/resolv.conf"):
    try:
        with open("/etc/resolv.conf", "r", encoding="utf-8", errors="ignore") as f:
            prev_resolv = f.read()
    except OSError:
        prev_resolv = None
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump({"ethIface": sys.argv[2], "prevResolvConf": prev_resolv}, f)
os.chmod(sys.argv[1], 0o644)
PY

    ip link set dev "$eth" up
    ip addr flush dev "$eth" scope global 2>/dev/null || true
    ip addr add 10.42.0.2/24 dev "$eth"
    ip route replace default via 10.42.0.1 dev "$eth"

    if [[ -L /etc/resolv.conf ]] && command -v resolvectl >/dev/null 2>&1; then
        resolvectl dns "$eth" 1.1.1.1 8.8.8.8 >/dev/null 2>&1 || true
    elif [[ ! -L /etc/resolv.conf ]]; then
        printf '# Generated by Aurora Ethernet Wi-Fi Share\nnameserver 10.42.0.1\nnameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    fi

    collect_status_json "true" "Direct static link active on ${eth} (10.42.0.2/24 -> 10.42.0.1)" ""
}

cmd_disconnect_client() {
    local req_eth="${1:-auto}"
    local eth="$req_eth"
    if [[ "$eth" == "auto" || -z "$eth" ]]; then
        eth="$(get_status_field clientEthIface)"
    fi
    if [[ -n "$eth" && "$eth" != "-" ]]; then
        validate_iface "$eth"
    fi

    if command -v nmcli >/dev/null 2>&1 && [[ "$(timeout 2 nmcli -t -f RUNNING general 2>/dev/null || true)" == "running" ]]; then
        if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$NM_CLIENT_CON"; then
            local nm_err=""
            nmcli connection down "$NM_CLIENT_CON" >/dev/null 2>&1 || true
            if ! nm_err="$(nmcli connection delete "$NM_CLIENT_CON" 2>&1)"; then
                if [[ "$EUID" -ne 0 ]] && [[ "$nm_err" == *"Not authorized"* || "$nm_err" == *"insufficient privileges"* || "$nm_err" == *"permission"* ]]; then
                    run_privileged_self "$eth"
                fi
            fi
            if [[ -n "$eth" && "$eth" != "-" ]]; then
                timeout 6 nmcli device connect "$eth" >/dev/null 2>&1 || true
            fi
        fi
    fi

    if [[ -f "$CLIENT_STATE_FILE" ]]; then
        run_privileged_self "$eth"
        cleanup_standalone_client
        if [[ -n "$eth" && "$eth" != "-" ]] && command -v dhcpcd >/dev/null 2>&1 && pgrep -x dhcpcd >/dev/null 2>&1; then
            timeout 3 dhcpcd -n "$eth" >/dev/null 2>&1 || true
        fi
    fi

    collect_status_json "true" "Restored normal Ethernet configuration" ""
}

cmd_test_link() {
    local gw="${1:-}"
    python3 - "$gw" <<'PY'
import json, re, subprocess, sys

req_gw = sys.argv[1].strip() if len(sys.argv) > 1 else ""


def run_ping(target, wait_sec):
    try:
        proc = subprocess.run(
            ["ping", "-n", "-c", "1", "-W", str(wait_sec), target],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=wait_sec + 2,
        )
        ok = proc.returncode == 0
        ms = None
        m = re.search(r"time=([0-9.]+)\s*ms", proc.stdout or "")
        if m:
            ms = round(float(m.group(1)), 1)
        return ok, ms
    except Exception:
        return False, None


gw = req_gw
if not gw:
    try:
        out = subprocess.check_output(["ip", "-j", "route", "show", "default"], text=True, stderr=subprocess.DEVNULL, timeout=2.0)
        routes = json.loads(out)
        if routes:
            gw = routes[0].get("gateway", "") or ""
    except Exception:
        gw = ""
if not gw:
    gw = "10.42.0.1"

gw_ok, gw_ms = run_ping(gw, 1)
inet_ok, inet_ms = run_ping("1.1.1.1", 2)

print(json.dumps({
    "ok": True,
    "gateway": gw,
    "gatewayOk": gw_ok,
    "gatewayMs": gw_ms,
    "internetOk": inet_ok,
    "internetMs": inet_ms,
}))
PY
}

case "$CMD" in
    status)
        collect_status_json "true" "" ""
        ;;
    start-host)
        cmd_start_host "${1:-auto}" "${2:-auto}" "${3:-auto}"
        ;;
    stop-host)
        cmd_stop_host
        ;;
    connect-client)
        cmd_connect_client "${1:-auto}" "${2:-auto}"
        ;;
    disconnect-client)
        cmd_disconnect_client "${1:-auto}"
        ;;
    test-link)
        cmd_test_link "${1:-}"
        ;;
    *)
        emit_json_error "Usage: manage-eth-share.sh <status|start-host|stop-host|connect-client|disconnect-client|test-link> [args...]"
        ;;
esac
