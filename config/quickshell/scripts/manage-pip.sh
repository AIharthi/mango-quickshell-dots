#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
shift || true

case "$CMD" in
    watch|toggle|cycle-corner|snap|resize|status)
        ;;
    *)
        echo "Usage: manage-pip.sh <watch|toggle|cycle-corner|snap|resize|status> [args...]" >&2
        exit 1
        ;;
esac

BACKEND_BIN="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bin/aurora-backend"
if [[ -x "$BACKEND_BIN" ]]; then
    exec "$BACKEND_BIN" pip "$CMD" "$@"
fi

exec python3 - "$CMD" "$@" <<'PY'
import json
import os
import re
import signal
import subprocess
import sys
import time

cmd = sys.argv[1]
args = sys.argv[2:]

CONFIG_DIR = os.path.expanduser(os.environ.get("XDG_CONFIG_HOME", "~/.config"))
PREFS_PATH = os.path.join(CONFIG_DIR, "quickshell", "shell-prefs.json")
CORNER_ORDER = ("bottom-right", "bottom-left", "top-left", "top-right")
PIP_TITLE_RE = re.compile(
    r"^(picture[- ]in[- ]picture|picture in picture|discord popout|صورة داخل صورة|bild-im-bild|incrustation( vidéo)?|imagen en imagen|画中画|картинка в картинке|resim içinde resim|obraz w obrazie|ピクチャー.*イン.*ピクチャー)$",
    re.IGNORECASE,
)

_stop_requested = False


def _handle_sig(_signum, _frame):
    global _stop_requested
    _stop_requested = True


signal.signal(signal.SIGTERM, _handle_sig)
signal.signal(signal.SIGINT, _handle_sig)


def load_pip_prefs():
    defaults = {
        "pipAutoManage": True,
        "pipSticky": True,
        "pipAlwaysOnTop": True,
        "pipCorner": "bottom-right",
        "pipWidthPct": 25,
        "pipMargin": 20,
    }
    if not os.path.isfile(PREFS_PATH):
        return defaults
    try:
        with open(PREFS_PATH, "r", encoding="utf-8") as f:
            raw = json.load(f)
        if not isinstance(raw, dict):
            return defaults
        corner = str(raw.get("pipCorner", "bottom-right")).strip().lower()
        if corner not in CORNER_ORDER:
            corner = "bottom-right"
        width_pct = max(18, min(45, int(float(raw.get("pipWidthPct", 25)))))
        margin = max(6, min(64, int(float(raw.get("pipMargin", 20)))))
        return {
            "pipAutoManage": bool(raw.get("pipAutoManage", True)),
            "pipSticky": bool(raw.get("pipSticky", True)),
            "pipAlwaysOnTop": bool(raw.get("pipAlwaysOnTop", True)),
            "pipCorner": corner,
            "pipWidthPct": width_pct,
            "pipMargin": margin,
        }
    except Exception:
        return defaults


def is_pip_client(c):
    if not isinstance(c, dict):
        return False
    title = str(c.get("title") or "").strip()
    appid = str(c.get("appid") or "").strip().lower()
    if PIP_TITLE_RE.match(title):
        return True
    if "picture-in-picture" in appid or "pictureinpicture" in appid:
        return True
    return False


def mmsg_json(*margs):
    try:
        out = subprocess.check_output(["mmsg", *margs], text=True, stderr=subprocess.DEVNULL, timeout=2.0)
        return json.loads(out)
    except Exception:
        return {}


def dispatch(cid, *ops):
    for op in ops:
        subprocess.run(
            ["mmsg", "dispatch", op, f"client,{int(cid)}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2.0,
        )


def get_monitors():
    data = mmsg_json("get", "all-monitors")
    mons = data.get("monitors") or []
    return mons


def find_monitor(mon_name):
    mons = get_monitors()
    for m in mons:
        if m.get("name") == mon_name:
            return m
    for m in mons:
        if m.get("active"):
            return m
    return mons[0] if mons else {"x": 0, "y": 0, "width": 1920, "height": 1080}


def get_all_clients():
    return mmsg_json("get", "all-clients").get("clients") or []


def get_client(cid):
    c = mmsg_json("get", "client", str(int(cid)))
    if isinstance(c, dict) and c.get("id") == int(cid):
        return c
    for item in get_all_clients():
        if item.get("id") == int(cid):
            return item
    return None


def get_focused_client():
    c = mmsg_json("get", "focusing-client")
    if isinstance(c, dict) and c.get("id") and not c.get("error"):
        return c
    return None


def compute_target_size(mon, width_pct):
    mw = int(mon.get("width", 1920))
    tw = max(280, min(960, int(round(mw * width_pct / 100.0))))
    th = max(158, int(round(tw * 9.0 / 16.0)))
    return tw, th


def compute_corner_xy(mon, cw, ch, margin, corner):
    mx = int(mon.get("x", 0))
    my = int(mon.get("y", 0))
    mw = int(mon.get("width", 1920))
    mh = int(mon.get("height", 1080))
    top_inset = 44

    if corner == "bottom-left":
        tx = mx + margin
        ty = my + mh - ch - margin
    elif corner == "top-left":
        tx = mx + margin
        ty = my + top_inset + max(0, margin - 8)
    elif corner == "top-right":
        tx = mx + mw - cw - margin
        ty = my + top_inset + max(0, margin - 8)
    else:  # bottom-right
        tx = mx + mw - cw - margin
        ty = my + mh - ch - margin

    tx = max(mx + 4, min(mx + mw - cw - 4, tx))
    ty = max(my + 4, min(my + mh - ch - 4, ty))
    return int(round(tx)), int(round(ty))


def detect_corner(c, mon):
    mx = int(mon.get("x", 0))
    my = int(mon.get("y", 0))
    mw = int(mon.get("width", 1920))
    mh = int(mon.get("height", 1080))
    cx = int(c.get("x", 0)) + int(c.get("width", 0)) / 2.0
    cy = int(c.get("y", 0)) + int(c.get("height", 0)) / 2.0
    is_right = cx >= (mx + mw / 2.0)
    is_bottom = cy >= (my + mh / 2.0)
    if is_right and is_bottom:
        return "bottom-right"
    if not is_right and is_bottom:
        return "bottom-left"
    if not is_right and not is_bottom:
        return "top-left"
    return "top-right"


def position_client(cid, corner, tw, th, margin, do_resize=True):
    c = get_client(cid)
    if not c:
        return
    mon = find_monitor(c.get("monitor", ""))
    if do_resize:
        cw = int(c.get("width", tw))
        ch = int(c.get("height", th))
        dw = tw - cw
        dh = th - ch
        if abs(dw) > 6 or abs(dh) > 6:
            dispatch(cid, f"resizewin,{dw:+d},{dh:+d}")
            time.sleep(0.06)
            c = get_client(cid) or c
            mon = find_monitor(c.get("monitor", ""))

    actual_w = int(c.get("width", tw))
    actual_h = int(c.get("height", th))
    tx, ty = compute_corner_xy(mon, actual_w, actual_h, margin, corner)
    dx = tx - int(c.get("x", tx))
    dy = ty - int(c.get("y", ty))
    if abs(dx) > 4 or abs(dy) > 4:
        dispatch(cid, f"movewin,{dx:+d},{dy:+d}")


def apply_pip_to_client(client, prefs, corner_override=None):
    cid = client.get("id")
    if not cid:
        return
    if bool(client.get("is_fullscreen", False)):
        dispatch(cid, "togglefullscreen")
        time.sleep(0.04)
    if not bool(client.get("is_floating", False)):
        dispatch(cid, "togglefloating")
        time.sleep(0.04)

    fresh = get_client(cid) or client
    if bool(fresh.get("is_global", False)) != prefs["pipSticky"]:
        dispatch(cid, "toggleglobal")
    if bool(fresh.get("is_overlay", False)) != prefs["pipAlwaysOnTop"]:
        dispatch(cid, "toggleoverlay")

    time.sleep(0.05)
    fresh = get_client(cid) or fresh
    mon = find_monitor(fresh.get("monitor", ""))
    tw, th = compute_target_size(mon, prefs["pipWidthPct"])
    corner = corner_override or prefs["pipCorner"]
    position_client(cid, corner, tw, th, prefs["pipMargin"], do_resize=True)


def find_active_pip_clients():
    clients = get_all_clients()
    exact = [c for c in clients if is_pip_client(c)]
    if exact:
        return exact
    overlay_float = [c for c in clients if c.get("is_floating") and c.get("is_overlay")]
    return overlay_float


def cmd_watch():
    managed_ids = set()
    while not _stop_requested:
        proc = None
        try:
            proc = subprocess.Popen(
                ["mmsg", "watch", "all-clients"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
            while not _stop_requested:
                line = proc.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except Exception:
                    continue
                clients = data.get("clients")
                if not isinstance(clients, list):
                    continue
                alive_ids = {c.get("id") for c in clients if isinstance(c, dict) and c.get("id")}
                managed_ids &= alive_ids

                for c in clients:
                    cid = c.get("id")
                    if not cid or cid in managed_ids:
                        continue
                    if is_pip_client(c):
                        managed_ids.add(cid)
                        prefs = load_pip_prefs()
                        if prefs["pipAutoManage"]:
                            time.sleep(0.08)
                            fresh = get_client(cid)
                            if fresh and is_pip_client(fresh):
                                apply_pip_to_client(fresh, prefs)
        except Exception:
            pass
        finally:
            if proc is not None and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=1.0)
                except Exception:
                    proc.kill()
        if not _stop_requested:
            time.sleep(1.0)


def cmd_toggle():
    prefs = load_pip_prefs()
    c = get_focused_client()
    if not c:
        return
    cid = c["id"]
    if bool(c.get("is_floating", False)) and bool(c.get("is_overlay", False)):
        if bool(c.get("is_overlay", False)):
            dispatch(cid, "toggleoverlay")
        if bool(c.get("is_global", False)):
            dispatch(cid, "toggleglobal")
        dispatch(cid, "togglefloating")
    else:
        apply_pip_to_client(c, prefs)


def cmd_cycle_corner():
    prefs = load_pip_prefs()
    pips = find_active_pip_clients()
    target = pips[0] if pips else None
    if not target:
        fc = get_focused_client()
        if fc and fc.get("is_floating"):
            target = fc
    if not target:
        return

    cid = target["id"]
    mon = find_monitor(target.get("monitor", ""))
    cur_corner = detect_corner(target, mon)
    idx = CORNER_ORDER.index(cur_corner) if cur_corner in CORNER_ORDER else 0
    next_corner = CORNER_ORDER[(idx + 1) % len(CORNER_ORDER)]
    position_client(
        cid,
        next_corner,
        int(target.get("width", 480)),
        int(target.get("height", 270)),
        prefs["pipMargin"],
        do_resize=False,
    )


def cmd_snap():
    prefs = load_pip_prefs()
    corner_override = args[0].strip().lower() if args else None
    if corner_override and corner_override not in CORNER_ORDER:
        corner_override = None
    for c in find_active_pip_clients():
        apply_pip_to_client(c, prefs, corner_override=corner_override)


def cmd_resize():
    prefs = load_pip_prefs()
    direction = (args[0].strip().lower() if args else "up")
    pips = find_active_pip_clients()
    if not pips:
        return
    target = pips[0]
    cid = target["id"]
    dw, dh = (64, 36) if direction != "down" else (-64, -36)
    dispatch(cid, f"resizewin,{dw:+d},{dh:+d}")
    time.sleep(0.05)
    fresh = get_client(cid)
    if fresh:
        mon = find_monitor(fresh.get("monitor", ""))
        corner = detect_corner(fresh, mon)
        position_client(
            cid,
            corner,
            int(fresh.get("width", 480)),
            int(fresh.get("height", 270)),
            prefs["pipMargin"],
            do_resize=False,
        )


def cmd_status():
    pips = find_active_pip_clients()
    print(json.dumps({"active": len(pips) > 0, "count": len(pips), "clients": pips}))


DISPATCH = {
    "watch": cmd_watch,
    "toggle": cmd_toggle,
    "cycle-corner": cmd_cycle_corner,
    "snap": cmd_snap,
    "resize": cmd_resize,
    "status": cmd_status,
}

DISPATCH[cmd]()
PY
