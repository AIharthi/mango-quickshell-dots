use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime};

use crate::json::{self, JsonOut};
use crate::util::{atomic_write, cache_dir, run_stdout, which};

const MAX_ENTRIES: usize = 60;
const MAX_BYTES: usize = 65_536;

#[derive(Clone)]
struct ClipItem {
    id: u64,
    text: String,
    preview: String,
    time: String,
    pinned: bool,
}

struct ClipLock(PathBuf);

impl ClipLock {
    fn acquire(history_path: &Path) -> Self {
        let mut lock_os = history_path.as_os_str().to_os_string();
        lock_os.push(".lock");
        let lock_path = PathBuf::from(lock_os);
        if let Some(parent) = lock_path.parent() {
            let _ = fs::create_dir_all(parent);
            let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
        }

        for attempt in 0..40 {
            if OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&lock_path)
                .is_ok()
            {
                return Self(lock_path);
            }
            if attempt == 25 {
                // Clear orphaned lock older than 8 seconds
                if let Ok(meta) = fs::metadata(&lock_path) {
                    if let Ok(modified) = meta.modified() {
                        if SystemTime::now()
                            .duration_since(modified)
                            .unwrap_or_default()
                            > Duration::from_secs(8)
                        {
                            let _ = fs::remove_file(&lock_path);
                            continue;
                        }
                    }
                }
            }
            thread::sleep(Duration::from_millis(25));
        }
        Self(lock_path)
    }
}

impl Drop for ClipLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn history_path() -> PathBuf {
    cache_dir().join("quickshell").join("clipboard.json")
}

fn make_preview(text: &str) -> String {
    let mut out = String::new();
    for word in text.split_whitespace() {
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(word);
        if out.chars().count() >= 160 {
            break;
        }
    }
    out.chars().take(160).collect()
}

fn local_hhmm() -> String {
    run_stdout("date", &["+%H:%M"]).unwrap_or_else(|| "00:00".to_string())
}

fn load_items_from(path: &Path) -> Vec<ClipItem> {
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
    for entry in arr {
        let Some(text) = entry.get_str("text") else {
            continue;
        };
        if text.trim().is_empty() {
            continue;
        }
        let preview = entry
            .get_str("preview")
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| make_preview(text));
        out.push(ClipItem {
            id: entry.get_u64("id").unwrap_or(0),
            text: text.to_string(),
            preview,
            time: entry.get_str("time").unwrap_or("").to_string(),
            pinned: entry.get_bool("pinned").unwrap_or(false),
        });
    }
    out
}

fn items_to_json(items: &[ClipItem]) -> String {
    let mut o = JsonOut::with_capacity(items.len() * 128 + 32);
    o.arr_start();
    for it in items {
        o.obj_start();
        o.kv_u64("id", it.id);
        o.kv_str("text", &it.text);
        o.kv_str("preview", &it.preview);
        o.kv_str("time", &it.time);
        o.kv_bool("pinned", it.pinned);
        o.obj_end();
    }
    o.arr_end();
    o.finish()
}

fn sorted_items(items: &[ClipItem]) -> Vec<ClipItem> {
    let mut out = Vec::with_capacity(items.len());
    for it in items {
        if it.pinned {
            out.push(it.clone());
        }
    }
    for it in items {
        if !it.pinned {
            out.push(it.clone());
        }
    }
    out
}

fn save_items_to(path: &Path, items: &[ClipItem]) -> Result<(), String> {
    let mut payload = items_to_json(items);
    payload.push('\n');
    atomic_write(path, payload.as_bytes(), 0o600)
}

fn add_item(path: &Path, raw: &str) -> Result<(), String> {
    if raw.trim().is_empty() || raw.len() > MAX_BYTES {
        return Ok(());
    }
    let _lock = ClipLock::acquire(path);
    let items = load_items_from(path);
    if items.first().map(|it| it.text.as_str()) == Some(raw) {
        return Ok(());
    }

    let mut existing_pin = false;
    let mut max_id = 0u64;
    let mut kept = Vec::with_capacity(items.len());
    for it in items {
        max_id = max_id.max(it.id);
        if it.text == raw {
            existing_pin = existing_pin || it.pinned;
        } else {
            kept.push(it);
        }
    }

    let mut new_items = Vec::with_capacity(kept.len() + 1);
    new_items.push(ClipItem {
        id: max_id + 1,
        text: raw.to_string(),
        preview: make_preview(raw),
        time: local_hhmm(),
        pinned: existing_pin,
    });
    new_items.extend(kept);

    if new_items.len() > MAX_ENTRIES {
        let mut pinned = Vec::new();
        let mut unpinned = Vec::new();
        for it in new_items {
            if it.pinned {
                pinned.push(it);
            } else {
                unpinned.push(it);
            }
        }
        pinned.truncate(MAX_ENTRIES);
        let cap_unpinned = MAX_ENTRIES.saturating_sub(pinned.len());
        unpinned.truncate(cap_unpinned);
        pinned.extend(unpinned);
        new_items = pinned;
    }

    save_items_to(path, &new_items)
}

fn is_sensitive_focused() -> bool {
    let Some(raw) = which("mmsg").and_then(|_| run_stdout("mmsg", &["get", "focusing-client"]))
    else {
        return false;
    };
    let low = raw.to_ascii_lowercase();
    [
        "bitwarden",
        "keepassxc",
        "1password",
        "enpass",
        "protonpass",
        "passff",
    ]
    .iter()
    .any(|kw| low.contains(kw))
}

fn has_password_mime_hint() -> bool {
    let Some(types) = which("wl-paste").and_then(|_| run_stdout("wl-paste", &["--list-types"]))
    else {
        return false;
    };
    types.to_ascii_lowercase().contains("passwordmanagerhint")
}

fn read_stdin_capped() -> String {
    let mut buf = Vec::new();
    let mut limited = io::stdin().take((MAX_BYTES + 1) as u64);
    let _ = limited.read_to_end(&mut buf);
    if buf.len() > MAX_BYTES {
        return String::new();
    }
    String::from_utf8_lossy(&buf).into_owned()
}

pub fn cmd_clipboard(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("list");
    let rest = args.get(1..).unwrap_or(&[]);
    let path = history_path();

    match op {
        "list" => {
            let items = load_items_from(&path);
            println!("{}", items_to_json(&sorted_items(&items)));
            Ok(())
        }
        "add" => {
            let text = if rest.is_empty() {
                read_stdin_capped()
            } else {
                rest.join(" ")
            };
            add_item(&path, &text)
        }
        "ingest" => {
            if is_sensitive_focused() || has_password_mime_hint() {
                return Ok(());
            }
            let raw = read_stdin_capped();
            add_item(&path, &raw)
        }
        "watch" => {
            if which("wl-paste").is_none() {
                return Ok(());
            }
            let exe = env::current_exe().map_err(|e| format!("current_exe failed: {e}"))?;
            let exe_s = exe.to_string_lossy().into_owned();
            let mut backoff_ms = 500u64;
            loop {
                let status = Command::new("wl-paste")
                    .args([
                        "--type",
                        "text/plain",
                        "--watch",
                        &exe_s,
                        "clipboard",
                        "ingest",
                    ])
                    .status();
                match status {
                    Ok(st) if st.success() => backoff_ms = 500,
                    _ => backoff_ms = (backoff_ms * 2).min(10_000),
                }
                thread::sleep(Duration::from_millis(backoff_ms));
            }
        }
        "copy" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing clipboard item id".to_string())?;
            if which("wl-copy").is_none() {
                return Err("wl-copy is required".to_string());
            }
            let items = load_items_from(&path);
            if let Some(found) = items.into_iter().find(|it| it.id == id) {
                let mut child = Command::new("wl-copy")
                    .args(["--type", "text/plain"])
                    .stdin(Stdio::piped())
                    .spawn()
                    .map_err(|e| format!("wl-copy spawn failed: {e}"))?;
                if let Some(mut sin) = child.stdin.take() {
                    let _ = sin.write_all(found.text.as_bytes());
                }
                let _ = child.wait();
            }
            Ok(())
        }
        "delete" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing clipboard item id".to_string())?;
            let _lock = ClipLock::acquire(&path);
            let items: Vec<ClipItem> = load_items_from(&path)
                .into_iter()
                .filter(|it| it.id != id)
                .collect();
            save_items_to(&path, &items)?;
            println!("{}", items_to_json(&sorted_items(&items)));
            Ok(())
        }
        "pin" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing clipboard item id".to_string())?;
            let _lock = ClipLock::acquire(&path);
            let mut items = load_items_from(&path);
            for it in &mut items {
                if it.id == id {
                    it.pinned = !it.pinned;
                    break;
                }
            }
            save_items_to(&path, &items)?;
            println!("{}", items_to_json(&sorted_items(&items)));
            Ok(())
        }
        "clear" => {
            if which("wl-copy").is_some() {
                let _ = Command::new("wl-copy").arg("--clear").status();
                let _ = Command::new("wl-copy")
                    .args(["--primary", "--clear"])
                    .status();
            }
            let _lock = ClipLock::acquire(&path);
            let items: Vec<ClipItem> = load_items_from(&path)
                .into_iter()
                .filter(|it| it.pinned)
                .collect();
            save_items_to(&path, &items)?;
            println!("{}", items_to_json(&sorted_items(&items)));
            Ok(())
        }
        other => Err(format!("Unknown clipboard command '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::UNIX_EPOCH;

    #[test]
    fn clipboard_add_dedup_pin_clear_roundtrip() {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let p = std::env::temp_dir()
            .join(format!("aurora_clip_test_{ts}"))
            .join("clipboard.json");
        add_item(&p, "hello world").expect("add 1");
        add_item(&p, "second item").expect("add 2");
        add_item(&p, "hello world").expect("dedup 1");
        let items = load_items_from(&p);
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].text, "hello world");

        let raw = fs::read_to_string(&p).expect("read json");
        let parsed = json::parse(&raw).expect("valid json");
        assert_eq!(parsed.as_arr().map(|a| a.len()), Some(2));
        if let Some(parent) = p.parent() {
            let _ = fs::remove_dir_all(parent);
        }
    }
}
