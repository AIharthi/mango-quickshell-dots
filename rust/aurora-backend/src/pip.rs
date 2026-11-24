use std::collections::HashSet;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

use crate::json::{self, JsonOut, JsonVal};
use crate::util::{config_dir, run_stdout, runtime_dir, which};

const CORNER_ORDER: [&str; 4] = ["bottom-right", "bottom-left", "top-left", "top-right"];

#[derive(Clone, Debug)]
pub struct PipPrefs {
    pub auto_manage: bool,
    pub sticky: bool,
    pub always_on_top: bool,
    pub corner: String,
    pub width_pct: i64,
    pub margin: i64,
}

impl Default for PipPrefs {
    fn default() -> Self {
        Self {
            auto_manage: true,
            sticky: true,
            always_on_top: true,
            corner: "bottom-right".to_string(),
            width_pct: 25,
            margin: 20,
        }
    }
}

#[derive(Clone, Debug)]
pub struct ClientInfo {
    pub id: i64,
    pub title: String,
    pub appid: String,
    pub monitor: String,
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
    pub is_floating: bool,
    pub is_fullscreen: bool,
    pub is_global: bool,
    pub is_overlay: bool,
}

#[derive(Clone, Debug)]
pub struct MonitorInfo {
    pub name: String,
    pub active: bool,
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
}

impl Default for MonitorInfo {
    fn default() -> Self {
        Self {
            name: String::new(),
            active: true,
            x: 0,
            y: 0,
            width: 1920,
            height: 1080,
        }
    }
}

fn load_pip_prefs() -> PipPrefs {
    let mut prefs = PipPrefs::default();
    let path = config_dir().join("quickshell").join("shell-prefs.json");
    let Ok(raw) = fs::read_to_string(&path) else {
        return prefs;
    };
    let Ok(val) = json::parse(&raw) else {
        return prefs;
    };
    if let Some(b) = val.get_bool("pipAutoManage") {
        prefs.auto_manage = b;
    }
    if let Some(b) = val.get_bool("pipSticky") {
        prefs.sticky = b;
    }
    if let Some(b) = val.get_bool("pipAlwaysOnTop") {
        prefs.always_on_top = b;
    }
    if let Some(c) = val.get_str("pipCorner") {
        let low = c.trim().to_ascii_lowercase();
        if CORNER_ORDER.contains(&low.as_str()) {
            prefs.corner = low;
        }
    }
    if let Some(w) = val.get_f64("pipWidthPct") {
        prefs.width_pct = (w as i64).clamp(18, 45);
    }
    if let Some(m) = val.get_f64("pipMargin") {
        prefs.margin = (m as i64).clamp(6, 64);
    }
    prefs
}

pub fn is_pip_client(title: &str, appid: &str) -> bool {
    let t = title.trim().to_lowercase();
    let a = appid.trim().to_ascii_lowercase();
    if a.contains("picture-in-picture") || a.contains("pictureinpicture") {
        return true;
    }
    matches!(
        t.as_str(),
        "picture-in-picture"
            | "picture in picture"
            | "picture-in picture"
            | "picture in-picture"
            | "discord popout"
            | "صورة داخل صورة"
            | "bild-im-bild"
            | "incrustation"
            | "incrustation vidéo"
            | "imagen en imagen"
            | "画中画"
            | "картинка в картинке"
            | "resim içinde resim"
            | "obraz w obrazie"
    ) || (t.starts_with("ピクチャー") && t.ends_with("ピクチャー") && t.contains("イン"))
}

fn parse_client(v: &JsonVal) -> Option<ClientInfo> {
    let id = v.get_i64("id")?;
    if id <= 0 {
        return None;
    }
    if v.get("error").is_some_and(|e| match e {
        JsonVal::Bool(b) => *b,
        JsonVal::Str(s) => !s.is_empty(),
        JsonVal::Null => false,
        _ => true,
    }) {
        return None;
    }
    Some(ClientInfo {
        id,
        title: v.get_str("title").unwrap_or("").to_string(),
        appid: v.get_str("appid").unwrap_or("").to_string(),
        monitor: v.get_str("monitor").unwrap_or("").to_string(),
        x: v.get_i64("x").unwrap_or(0),
        y: v.get_i64("y").unwrap_or(0),
        width: v.get_i64("width").unwrap_or(480),
        height: v.get_i64("height").unwrap_or(270),
        is_floating: v.get_bool("is_floating").unwrap_or(false),
        is_fullscreen: v.get_bool("is_fullscreen").unwrap_or(false),
        is_global: v.get_bool("is_global").unwrap_or(false),
        is_overlay: v.get_bool("is_overlay").unwrap_or(false),
    })
}

fn mmsg_json(args: &[&str]) -> Option<JsonVal> {
    let raw = run_stdout("mmsg", args)?;
    json::parse(&raw).ok()
}

fn dispatch(cid: i64, ops: &[&str]) {
    if cid <= 0 {
        return;
    }
    let client_arg = format!("client,{cid}");
    for op in ops {
        let _ = Command::new("mmsg")
            .args(["dispatch", op, &client_arg])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn get_monitors() -> Vec<MonitorInfo> {
    let Some(val) = mmsg_json(&["get", "all-monitors"]) else {
        return Vec::new();
    };
    let Some(arr) = val.get("monitors").and_then(|v| v.as_arr()) else {
        return Vec::new();
    };
    arr.iter()
        .map(|m| MonitorInfo {
            name: m.get_str("name").unwrap_or("").to_string(),
            active: m.get_bool("active").unwrap_or(false),
            x: m.get_i64("x").unwrap_or(0),
            y: m.get_i64("y").unwrap_or(0),
            width: m.get_i64("width").unwrap_or(1920),
            height: m.get_i64("height").unwrap_or(1080),
        })
        .collect()
}

fn find_monitor(mon_name: &str) -> MonitorInfo {
    let mons = get_monitors();
    if let Some(m) = mons
        .iter()
        .find(|m| !mon_name.is_empty() && m.name == mon_name)
    {
        return m.clone();
    }
    if let Some(m) = mons.iter().find(|m| m.active) {
        return m.clone();
    }
    mons.into_iter().next().unwrap_or_default()
}

fn get_all_clients() -> Vec<ClientInfo> {
    let Some(val) = mmsg_json(&["get", "all-clients"]) else {
        return Vec::new();
    };
    let arr = val
        .get("clients")
        .and_then(|v| v.as_arr())
        .or_else(|| val.as_arr());
    let Some(list) = arr else {
        return Vec::new();
    };
    list.iter().filter_map(parse_client).collect()
}

fn get_client(cid: i64) -> Option<ClientInfo> {
    let id_s = cid.to_string();
    if let Some(val) = mmsg_json(&["get", "client", &id_s]) {
        if let Some(c) = parse_client(&val) {
            if c.id == cid {
                return Some(c);
            }
        }
    }
    get_all_clients().into_iter().find(|c| c.id == cid)
}

fn get_focused_client() -> Option<ClientInfo> {
    let val = mmsg_json(&["get", "focusing-client"])?;
    parse_client(&val)
}

pub fn compute_target_size(mon: &MonitorInfo, width_pct: i64) -> (i64, i64) {
    let tw = ((mon.width as f64) * (width_pct as f64) / 100.0)
        .round()
        .clamp(280.0, 960.0) as i64;
    let th = ((tw as f64) * 9.0 / 16.0).round().max(158.0) as i64;
    (tw, th)
}

pub fn compute_corner_xy(
    mon: &MonitorInfo,
    cw: i64,
    ch: i64,
    margin: i64,
    corner: &str,
) -> (i64, i64) {
    let mx = mon.x;
    let my = mon.y;
    let mw = mon.width;
    let mh = mon.height;
    let top_inset = 44;

    let (raw_tx, raw_ty) = match corner {
        "bottom-left" => (mx + margin, my + mh - ch - margin),
        "top-left" => (mx + margin, my + top_inset + (margin - 8).max(0)),
        "top-right" => (mx + mw - cw - margin, my + top_inset + (margin - 8).max(0)),
        _ => (mx + mw - cw - margin, my + mh - ch - margin),
    };

    let tx = raw_tx.clamp(mx + 4, (mx + mw - cw - 4).max(mx + 4));
    let ty = raw_ty.clamp(my + 4, (my + mh - ch - 4).max(my + 4));
    (tx, ty)
}

pub fn detect_corner(c: &ClientInfo, mon: &MonitorInfo) -> &'static str {
    let cx = (c.x as f64) + (c.width as f64) / 2.0;
    let cy = (c.y as f64) + (c.height as f64) / 2.0;
    let is_right = cx >= (mon.x as f64) + (mon.width as f64) / 2.0;
    let is_bottom = cy >= (mon.y as f64) + (mon.height as f64) / 2.0;
    match (is_right, is_bottom) {
        (true, true) => "bottom-right",
        (false, true) => "bottom-left",
        (false, false) => "top-left",
        (true, false) => "top-right",
    }
}

fn format_delta(d: i64) -> String {
    if d >= 0 {
        format!("+{d}")
    } else {
        format!("{d}")
    }
}

fn position_client(cid: i64, corner: &str, tw: i64, th: i64, margin: i64, do_resize: bool) {
    let Some(mut c) = get_client(cid) else {
        return;
    };
    let mut mon = find_monitor(&c.monitor);
    if do_resize {
        let dw = tw - c.width;
        let dh = th - c.height;
        if dw.abs() > 6 || dh.abs() > 6 {
            let cmd = format!("resizewin,{},{}", format_delta(dw), format_delta(dh));
            dispatch(cid, &[&cmd]);
            thread::sleep(Duration::from_millis(60));
            if let Some(fresh) = get_client(cid) {
                c = fresh;
                mon = find_monitor(&c.monitor);
            }
        }
    }

    let (tx, ty) = compute_corner_xy(&mon, c.width, c.height, margin, corner);
    let dx = tx - c.x;
    let dy = ty - c.y;
    if dx.abs() > 4 || dy.abs() > 4 {
        let cmd = format!("movewin,{},{}", format_delta(dx), format_delta(dy));
        dispatch(cid, &[&cmd]);
    }
}

fn apply_pip_to_client(client: &ClientInfo, prefs: &PipPrefs, corner_override: Option<&str>) {
    let cid = client.id;
    if client.is_fullscreen {
        dispatch(cid, &["togglefullscreen"]);
        thread::sleep(Duration::from_millis(40));
    }
    if !client.is_floating {
        dispatch(cid, &["togglefloating"]);
        thread::sleep(Duration::from_millis(40));
    }

    let fresh = get_client(cid).unwrap_or_else(|| client.clone());
    if fresh.is_global != prefs.sticky {
        dispatch(cid, &["toggleglobal"]);
    }
    if fresh.is_overlay != prefs.always_on_top {
        dispatch(cid, &["toggleoverlay"]);
    }

    thread::sleep(Duration::from_millis(50));
    let fresh = get_client(cid).unwrap_or(fresh);
    let mon = find_monitor(&fresh.monitor);
    let (tw, th) = compute_target_size(&mon, prefs.width_pct);
    let corner = corner_override.unwrap_or(&prefs.corner);
    position_client(cid, corner, tw, th, prefs.margin, true);
}

fn find_active_pip_clients() -> Vec<ClientInfo> {
    let clients = get_all_clients();
    let exact: Vec<ClientInfo> = clients
        .iter()
        .filter(|c| is_pip_client(&c.title, &c.appid))
        .cloned()
        .collect();
    if !exact.is_empty() {
        return exact;
    }
    clients
        .into_iter()
        .filter(|c| c.is_floating && c.is_overlay)
        .collect()
}

fn wayland_socket_alive() -> bool {
    let Ok(wd) = env::var("WAYLAND_DISPLAY") else {
        return true;
    };
    if wd.is_empty() {
        return false;
    }
    if wd.starts_with('/') {
        std::path::Path::new(&wd).exists()
    } else {
        runtime_dir().join(&wd).exists()
    }
}

fn cmd_watch() -> Result<(), String> {
    if which("mmsg").is_none() {
        return Err("mmsg is required for pip watch".to_string());
    }
    let mut managed_ids: HashSet<i64> = HashSet::new();
    let mut backoff_ms = 500u64;

    loop {
        if !wayland_socket_alive() {
            return Ok(());
        }
        let mut child = match Command::new("mmsg")
            .args(["watch", "all-clients"])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(_) => {
                thread::sleep(Duration::from_millis(backoff_ms));
                backoff_ms = (backoff_ms * 2).min(8000);
                continue;
            }
        };

        if let Some(stdout) = child.stdout.take() {
            let reader = BufReader::new(stdout);
            for line in reader.lines().map_while(Result::ok) {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let Ok(val) = json::parse(trimmed) else {
                    continue;
                };
                let Some(arr) = val.get("clients").and_then(|v| v.as_arr()) else {
                    continue;
                };
                backoff_ms = 500;
                let clients: Vec<ClientInfo> = arr.iter().filter_map(parse_client).collect();
                let alive_ids: HashSet<i64> = clients.iter().map(|c| c.id).collect();
                managed_ids.retain(|id| alive_ids.contains(id));

                for c in clients {
                    if managed_ids.contains(&c.id) {
                        continue;
                    }
                    if is_pip_client(&c.title, &c.appid) {
                        managed_ids.insert(c.id);
                        let prefs = load_pip_prefs();
                        if prefs.auto_manage {
                            thread::sleep(Duration::from_millis(80));
                            if let Some(fresh) = get_client(c.id) {
                                if is_pip_client(&fresh.title, &fresh.appid) {
                                    apply_pip_to_client(&fresh, &prefs, None);
                                }
                            }
                        }
                    }
                }
            }
        }

        let _ = child.kill();
        let _ = child.wait();
        if !wayland_socket_alive() {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(backoff_ms));
        backoff_ms = (backoff_ms * 2).min(8000);
    }
}

fn cmd_toggle() {
    let prefs = load_pip_prefs();
    let Some(c) = get_focused_client() else {
        return;
    };
    if c.is_floating && c.is_overlay {
        if c.is_overlay {
            dispatch(c.id, &["toggleoverlay"]);
        }
        if c.is_global {
            dispatch(c.id, &["toggleglobal"]);
        }
        dispatch(c.id, &["togglefloating"]);
    } else {
        apply_pip_to_client(&c, &prefs, None);
    }
}

fn cmd_cycle_corner() {
    let prefs = load_pip_prefs();
    let mut target = find_active_pip_clients().into_iter().next();
    if target.is_none() {
        if let Some(fc) = get_focused_client() {
            if fc.is_floating {
                target = Some(fc);
            }
        }
    }
    let Some(t) = target else {
        return;
    };
    let mon = find_monitor(&t.monitor);
    let cur = detect_corner(&t, &mon);
    let idx = CORNER_ORDER.iter().position(|&c| c == cur).unwrap_or(0);
    let next_corner = CORNER_ORDER[(idx + 1) % CORNER_ORDER.len()];
    position_client(t.id, next_corner, t.width, t.height, prefs.margin, false);
}

fn cmd_snap(args: &[String]) {
    let prefs = load_pip_prefs();
    let corner_override = args
        .first()
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| CORNER_ORDER.contains(&s.as_str()));
    for c in find_active_pip_clients() {
        apply_pip_to_client(&c, &prefs, corner_override.as_deref());
    }
}

fn cmd_resize(args: &[String]) {
    let prefs = load_pip_prefs();
    let direction = args
        .first()
        .map(|s| s.trim().to_ascii_lowercase())
        .unwrap_or_else(|| "up".to_string());
    let Some(target) = find_active_pip_clients().into_iter().next() else {
        return;
    };
    let (dw, dh) = if direction == "down" {
        (-64, -36)
    } else {
        (64, 36)
    };
    let cmd = format!("resizewin,{},{}", format_delta(dw), format_delta(dh));
    dispatch(target.id, &[&cmd]);
    thread::sleep(Duration::from_millis(50));
    if let Some(fresh) = get_client(target.id) {
        let mon = find_monitor(&fresh.monitor);
        let corner = detect_corner(&fresh, &mon);
        position_client(
            fresh.id,
            corner,
            fresh.width,
            fresh.height,
            prefs.margin,
            false,
        );
    }
}

fn cmd_status() {
    let pips = find_active_pip_clients();
    let mut o = JsonOut::with_capacity(256);
    o.obj_start();
    o.kv_bool("active", !pips.is_empty());
    o.kv_u64("count", pips.len() as u64);
    o.key("clients");
    o.arr_start();
    for c in pips {
        o.obj_start();
        o.kv_i64("id", c.id);
        o.kv_str("title", &c.title);
        o.kv_str("appid", &c.appid);
        o.kv_str("monitor", &c.monitor);
        o.kv_i64("x", c.x);
        o.kv_i64("y", c.y);
        o.kv_i64("width", c.width);
        o.kv_i64("height", c.height);
        o.kv_bool("is_floating", c.is_floating);
        o.kv_bool("is_global", c.is_global);
        o.kv_bool("is_overlay", c.is_overlay);
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
}

pub fn cmd_pip(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("status");
    let rest = args.get(1..).unwrap_or(&[]);
    match op {
        "watch" => cmd_watch(),
        "toggle" => {
            cmd_toggle();
            Ok(())
        }
        "cycle-corner" => {
            cmd_cycle_corner();
            Ok(())
        }
        "snap" => {
            cmd_snap(rest);
            Ok(())
        }
        "resize" => {
            cmd_resize(rest);
            Ok(())
        }
        "status" => {
            cmd_status();
            Ok(())
        }
        other => Err(format!("Unknown pip command '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_localized_pip_titles_and_computes_corners() {
        assert!(is_pip_client("Picture-in-Picture", "firefox"));
        assert!(is_pip_client("Discord Popout", "discord"));
        assert!(is_pip_client("画中画", "chromium"));
        assert!(is_pip_client("صورة داخل صورة", "helium"));
        assert!(is_pip_client("Video", "org.example.pictureinpicture"));
        assert!(!is_pip_client("Mozilla Firefox", "firefox"));

        let mon = MonitorInfo {
            name: "HDMI-A-1".to_string(),
            active: true,
            x: 0,
            y: 0,
            width: 1920,
            height: 1080,
        };
        let (tw, th) = compute_target_size(&mon, 25);
        assert_eq!((tw, th), (480, 270));
        let (tx, ty) = compute_corner_xy(&mon, tw, th, 20, "bottom-right");
        assert_eq!((tx, ty), (1420, 790));
        let (tx_tl, ty_tl) = compute_corner_xy(&mon, tw, th, 20, "top-left");
        assert_eq!((tx_tl, ty_tl), (20, 56));
    }
}
