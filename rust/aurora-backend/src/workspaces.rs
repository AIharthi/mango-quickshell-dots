use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::json::{self, JsonOut};
use crate::util::{atomic_write, config_dir, data_dir, run_stdout, sanitize_id, which, FileLock};

const MAX_SESSIONS: usize = 20;
const MAX_APPS_PER_SESSION: usize = 24;
const MAX_NAME_CHARS: usize = 40;

#[derive(Clone)]
pub struct SavedApp {
    pub appid: String,
    pub desktop_id: String,
    pub exec_bin: String,
    pub tag: u64,
    pub floating: bool,
    pub title_hint: String,
}

#[derive(Clone)]
pub struct WorkspaceSession {
    pub id: u64,
    pub name: String,
    pub created: String,
    pub window_count: u64,
    pub apps: Vec<SavedApp>,
}

fn sessions_path() -> PathBuf {
    config_dir().join("quickshell").join("workspaces.json")
}

fn desktop_search_dirs() -> Vec<PathBuf> {
    let data = data_dir();
    vec![
        data.join("applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        data.join("flatpak/exports/share/applications"),
    ]
}

fn find_desktop_file(desktop_id: &str) -> Option<PathBuf> {
    let clean = sanitize_id(desktop_id, 128)?;
    let with_ext = if clean.ends_with(".desktop") {
        clean
    } else {
        format!("{clean}.desktop")
    };
    for dir in desktop_search_dirs() {
        let p = dir.join(&with_ext);
        if p.is_file() {
            return Some(p);
        }
    }
    None
}

pub fn resolve_appid_launch(appid: &str) -> (String, String) {
    let clean_app = appid.trim();
    if clean_app.is_empty() {
        return (String::new(), String::new());
    }

    let mut candidates = Vec::new();
    if let Some(s) = sanitize_id(clean_app, 120) {
        candidates.push(s.clone());
        let low = s.to_ascii_lowercase();
        if low != s {
            candidates.push(low);
        }
    }

    let dirs = desktop_search_dirs();
    for cand in &candidates {
        let with_ext = if cand.ends_with(".desktop") {
            cand.clone()
        } else {
            format!("{cand}.desktop")
        };
        for dir in &dirs {
            if dir.join(&with_ext).is_file() {
                return (with_ext, String::new());
            }
        }
    }

    let app_lower = clean_app.to_ascii_lowercase();
    for dir in &dirs {
        let Ok(rd) = fs::read_dir(dir) else {
            continue;
        };
        for ent in rd.flatten() {
            let fname = ent.file_name().to_string_lossy().into_owned();
            if !fname.ends_with(".desktop") || sanitize_id(&fname, 128).is_none() {
                continue;
            }
            let Ok(txt) = fs::read_to_string(ent.path()) else {
                continue;
            };
            for line in txt.lines() {
                if let Some(wm) = line.strip_prefix("StartupWMClass=") {
                    if wm.trim().eq_ignore_ascii_case(&app_lower) {
                        return (fname, String::new());
                    }
                }
            }
        }
    }

    if let Some(bin) = sanitize_id(&app_lower, 80) {
        if which(&bin).is_some() {
            return (String::new(), bin);
        }
    }
    if let Some(bin) = sanitize_id(clean_app, 80) {
        if which(&bin).is_some() {
            return (String::new(), bin);
        }
    }

    (String::new(), String::new())
}

fn sanitize_label(raw: &str, max_chars: usize) -> String {
    raw.chars()
        .filter(|&c| c != '\0' && !c.is_control())
        .collect::<String>()
        .trim()
        .chars()
        .take(max_chars)
        .collect()
}

fn load_sessions_from(path: &Path) -> Vec<WorkspaceSession> {
    let Ok(raw) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let Ok(val) = json::parse(&raw) else {
        return Vec::new();
    };
    let Some(arr) = val.as_arr() else {
        return Vec::new();
    };
    let mut out = Vec::with_capacity(arr.len());
    for ent in arr {
        let Some(name) = ent.get_str("name") else {
            continue;
        };
        if name.trim().is_empty() {
            continue;
        }
        let mut apps = Vec::new();
        if let Some(arr_apps) = ent.get("apps").and_then(|v| v.as_arr()) {
            for a in arr_apps.iter().take(MAX_APPS_PER_SESSION) {
                let appid = a.get_str("appid").unwrap_or("").to_string();
                let desktop_id = a.get_str("desktopId").unwrap_or("").to_string();
                let exec_bin = a.get_str("execBin").unwrap_or("").to_string();
                if desktop_id.is_empty() && exec_bin.is_empty() {
                    continue;
                }
                apps.push(SavedApp {
                    appid,
                    desktop_id,
                    exec_bin,
                    tag: a.get_u64("tag").unwrap_or(1).clamp(1, 9),
                    floating: a.get_bool("floating").unwrap_or(false),
                    title_hint: a.get_str("titleHint").unwrap_or("").to_string(),
                });
            }
        }
        out.push(WorkspaceSession {
            id: ent.get_u64("id").unwrap_or(0),
            name: name.to_string(),
            created: ent.get_str("created").unwrap_or("").to_string(),
            window_count: apps.len() as u64,
            apps,
        });
    }
    out
}

fn sessions_to_json(list: &[WorkspaceSession]) -> String {
    let mut o = JsonOut::with_capacity(list.len() * 256 + 32);
    o.arr_start();
    for s in list {
        o.obj_start();
        o.kv_u64("id", s.id);
        o.kv_str("name", &s.name);
        o.kv_str("created", &s.created);
        o.kv_u64("windowCount", s.window_count);
        o.key("apps");
        o.arr_start();
        for a in &s.apps {
            o.obj_start();
            o.kv_str("appid", &a.appid);
            o.kv_str("desktopId", &a.desktop_id);
            o.kv_str("execBin", &a.exec_bin);
            o.kv_u64("tag", a.tag);
            o.kv_bool("floating", a.floating);
            o.kv_str("titleHint", &a.title_hint);
            o.obj_end();
        }
        o.arr_end();
        o.obj_end();
    }
    o.arr_end();
    o.finish()
}

fn save_sessions_to(path: &Path, list: &[WorkspaceSession]) -> Result<(), String> {
    let mut payload = sessions_to_json(list);
    payload.push('\n');
    atomic_write(path, payload.as_bytes(), 0o600)
}

fn save_session_records(
    path: &Path,
    name: &str,
    apps: Vec<SavedApp>,
) -> Result<Vec<WorkspaceSession>, String> {
    let clean_name = sanitize_label(name, MAX_NAME_CHARS);
    if clean_name.is_empty() {
        return Err("Session name cannot be empty".to_string());
    }
    if apps.is_empty() {
        return Err("No launchable open application windows to save".to_string());
    }

    let created = run_stdout("date", &["+%H:%M"]).unwrap_or_else(|| "now".to_string());
    let _lock = FileLock::acquire(path)?;
    let mut sessions = load_sessions_from(path);
    let max_id = sessions.iter().map(|s| s.id).max().unwrap_or(0);
    sessions.retain(|s| !s.name.eq_ignore_ascii_case(&clean_name));

    let count = apps.len() as u64;
    let mut next = Vec::with_capacity(sessions.len() + 1);
    next.push(WorkspaceSession {
        id: max_id + 1,
        name: clean_name,
        created,
        window_count: count,
        apps,
    });
    next.extend(sessions);
    next.truncate(MAX_SESSIONS);
    save_sessions_to(path, &next)?;
    Ok(next)
}

fn collect_open_apps() -> Result<Vec<SavedApp>, String> {
    if which("mmsg").is_none() {
        return Err("mmsg is required to inspect open windows".to_string());
    }
    let raw = run_stdout("mmsg", &["get", "all-clients"])
        .ok_or_else(|| "Failed querying open windows from MangoWC".to_string())?;
    let val = json::parse(&raw)?;
    let arr = val
        .get("clients")
        .and_then(|v| v.as_arr())
        .or_else(|| val.as_arr())
        .ok_or_else(|| "Unexpected client list format".to_string())?;

    let mut apps = Vec::new();
    let mut seen_launch = HashSet::new();
    for c in arr {
        let appid = c.get_str("appid").unwrap_or("").trim();
        if appid.is_empty() {
            continue;
        }
        let low = appid.to_ascii_lowercase();
        if low.starts_with("quickshell") || low == "qs" {
            continue;
        }
        let (desktop_id, exec_bin) = resolve_appid_launch(appid);
        if desktop_id.is_empty() && exec_bin.is_empty() {
            continue;
        }
        let tag = c
            .get("tags")
            .and_then(|v| v.as_arr())
            .and_then(|a| a.first())
            .and_then(|v| v.as_u64())
            .unwrap_or(1)
            .clamp(1, 9);
        let dedup_key = format!("{desktop_id}|{exec_bin}|{tag}");
        if !seen_launch.insert(dedup_key) {
            continue;
        }
        apps.push(SavedApp {
            appid: appid.to_string(),
            desktop_id,
            exec_bin,
            tag,
            floating: c.get_bool("is_floating").unwrap_or(false),
            title_hint: sanitize_label(c.get_str("title").unwrap_or(""), 48),
        });
        if apps.len() >= MAX_APPS_PER_SESSION {
            break;
        }
    }
    Ok(apps)
}

fn launch_saved_app(app: &SavedApp) -> bool {
    if (1..=9).contains(&app.tag) && which("mmsg").is_some() {
        let _ = Command::new("mmsg")
            .args(["dispatch", &format!("view,{},0", app.tag)])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }

    if !app.desktop_id.is_empty() {
        if let Some(clean_id) = sanitize_id(&app.desktop_id, 128) {
            if which("gtk-launch").is_some()
                && find_desktop_file(&clean_id).is_some()
                && Command::new("gtk-launch")
                    .arg(&clean_id)
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn()
                    .is_ok()
            {
                return true;
            }
            if which("gio").is_some() {
                if let Some(full_desktop) = find_desktop_file(&clean_id) {
                    if Command::new("gio")
                        .arg("launch")
                        .arg(full_desktop)
                        .stdin(Stdio::null())
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn()
                        .is_ok()
                    {
                        return true;
                    }
                }
            }
        }
    }

    if !app.exec_bin.is_empty() {
        if let Some(clean_bin) = sanitize_id(&app.exec_bin, 80) {
            if let Some(exe) = which(&clean_bin) {
                return Command::new(exe)
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn()
                    .is_ok();
            }
        }
    }
    false
}

pub fn delete_session_in(path: &Path, id: u64) -> Result<Vec<WorkspaceSession>, String> {
    let _lock = FileLock::acquire(path)?;
    let list: Vec<WorkspaceSession> = load_sessions_from(path)
        .into_iter()
        .filter(|s| s.id != id)
        .collect();
    save_sessions_to(path, &list)?;
    Ok(list)
}

pub fn cmd_workspaces(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("list");
    let rest = args.get(1..).unwrap_or(&[]);
    let path = sessions_path();

    match op {
        "list" => {
            let sessions = load_sessions_from(&path);
            println!("{}", sessions_to_json(&sessions));
            Ok(())
        }
        "save" => {
            let name = rest.join(" ");
            let apps = collect_open_apps()?;
            let updated = save_session_records(&path, &name, apps)?;
            println!("{}", sessions_to_json(&updated));
            Ok(())
        }
        "restore" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing workspace session id".to_string())?;
            let sessions = load_sessions_from(&path);
            let target = sessions
                .into_iter()
                .find(|s| s.id == id)
                .ok_or_else(|| format!("Workspace session {id} not found"))?;
            let mut launched = 0u64;
            for app in &target.apps {
                if launch_saved_app(app) {
                    launched += 1;
                }
            }
            let mut o = JsonOut::new();
            o.obj_start();
            o.kv_bool("ok", true);
            o.kv_u64("launched", launched);
            o.obj_end();
            println!("{}", o.finish());
            Ok(())
        }
        "delete" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing workspace session id".to_string())?;
            let updated = delete_session_in(&path, id)?;
            println!("{}", sessions_to_json(&updated));
            Ok(())
        }
        other => Err(format!("Unknown workspaces command '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspaces_save_list_delete_and_sanitize() {
        let base = std::env::temp_dir().join(format!("aurora_ws_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let path = base.join("workspaces.json");

        assert!(load_sessions_from(&path).is_empty());

        let apps = vec![SavedApp {
            appid: "foot".to_string(),
            desktop_id: String::new(),
            exec_bin: "foot".to_string(),
            tag: 2,
            floating: false,
            title_hint: "terminal".to_string(),
        }];
        let saved = save_session_records(&path, "Dev Work", apps).expect("save ok");
        assert_eq!(saved.len(), 1);
        assert_eq!(saved[0].name, "Dev Work");
        assert_eq!(saved[0].window_count, 1);

        let after_del = delete_session_in(&path, saved[0].id).expect("delete ok");
        assert!(after_del.is_empty());

        assert!(sanitize_id("rm -rf /", 64).is_none());
        assert!(sanitize_id("org.mozilla.firefox.desktop", 64).is_some());

        let _ = fs::remove_dir_all(&base);
    }
}
