use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::json::{self, JsonOut};
use crate::util::{atomic_write, config_dir, run_stdout, which, FileLock};

const MAX_SNIPPETS: usize = 200;
const MAX_TITLE_CHARS: usize = 80;
const MAX_TAG_CHARS: usize = 24;
const MAX_BODY_BYTES: usize = 32_768;

#[derive(Clone)]
pub struct Snippet {
    pub id: u64,
    pub title: String,
    pub tag: String,
    pub body: String,
    pub preview: String,
    pub pinned: bool,
    pub updated: String,
}

fn vault_path() -> PathBuf {
    config_dir().join("quickshell").join("snippets.json")
}

fn sanitize_text(raw: &str, keep_newlines: bool) -> String {
    raw.chars()
        .filter(|&c| {
            if c == '\0' {
                return false;
            }
            if c == '\n' || c == '\t' {
                return keep_newlines;
            }
            !c.is_control()
        })
        .collect()
}

fn make_preview(body: &str) -> String {
    let mut out = String::new();
    for word in body.split_whitespace() {
        if !out.is_empty() {
            out.push(' ');
        }
        out.push_str(word);
        if out.chars().count() >= 140 {
            break;
        }
    }
    out.chars().take(140).collect()
}

fn load_snippets_from(path: &Path) -> Vec<Snippet> {
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
        let Some(title) = ent.get_str("title") else {
            continue;
        };
        let Some(body) = ent.get_str("body") else {
            continue;
        };
        if title.trim().is_empty() || body.trim().is_empty() {
            continue;
        }
        let tag = ent
            .get_str("tag")
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or("general")
            .to_string();
        let preview = ent
            .get_str("preview")
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| make_preview(body));
        out.push(Snippet {
            id: ent.get_u64("id").unwrap_or(0),
            title: title.to_string(),
            tag,
            body: body.to_string(),
            preview,
            pinned: ent.get_bool("pinned").unwrap_or(false),
            updated: ent.get_str("updated").unwrap_or("").to_string(),
        });
    }
    out
}

fn sort_snippets(items: &[Snippet]) -> Vec<Snippet> {
    let mut out = items.to_vec();
    out.sort_by(|a, b| b.pinned.cmp(&a.pinned).then_with(|| b.id.cmp(&a.id)));
    out
}

fn snippets_to_json(items: &[Snippet]) -> String {
    let mut o = JsonOut::with_capacity(items.len() * 160 + 32);
    o.arr_start();
    for it in items {
        o.obj_start();
        o.kv_u64("id", it.id);
        o.kv_str("title", &it.title);
        o.kv_str("tag", &it.tag);
        o.kv_str("body", &it.body);
        o.kv_str("preview", &it.preview);
        o.kv_bool("pinned", it.pinned);
        o.kv_str("updated", &it.updated);
        o.obj_end();
    }
    o.arr_end();
    o.finish()
}

fn save_snippets_to(path: &Path, items: &[Snippet]) -> Result<(), String> {
    let mut payload = snippets_to_json(items);
    payload.push('\n');
    atomic_write(path, payload.as_bytes(), 0o600)
}

fn local_stamp() -> String {
    run_stdout("date", &["+%Y-%m-%d %H:%M"]).unwrap_or_else(|| "now".to_string())
}

fn read_stdin_capped() -> Result<String, String> {
    let mut buf = Vec::new();
    io::stdin()
        .take((MAX_BODY_BYTES + 1) as u64)
        .read_to_end(&mut buf)
        .map_err(|e| format!("Failed reading stdin: {e}"))?;
    if buf.len() > MAX_BODY_BYTES {
        return Err(format!("Snippet body exceeds {MAX_BODY_BYTES} byte limit"));
    }
    Ok(String::from_utf8_lossy(&buf).into_owned())
}

fn is_sensitive_clipboard() -> bool {
    if let Some(raw) = which("mmsg").and_then(|_| run_stdout("mmsg", &["get", "focusing-client"])) {
        let low = raw.to_ascii_lowercase();
        if [
            "bitwarden",
            "keepassxc",
            "1password",
            "enpass",
            "protonpass",
            "passff",
        ]
        .iter()
        .any(|kw| low.contains(kw))
        {
            return true;
        }
    }
    if let Some(types) = which("wl-paste").and_then(|_| run_stdout("wl-paste", &["--list-types"])) {
        if types.to_ascii_lowercase().contains("passwordmanagerhint") {
            return true;
        }
    }
    false
}

fn read_clipboard_plain() -> Result<String, String> {
    if which("wl-paste").is_none() {
        return Err("wl-paste is required to read clipboard".to_string());
    }
    if is_sensitive_clipboard() {
        return Err(
            "Refusing to save snippet from protected password manager clipboard".to_string(),
        );
    }
    let out = Command::new("wl-paste")
        .args(["--no-newline", "--type", "text/plain"])
        .output()
        .map_err(|e| format!("wl-paste failed: {e}"))?;
    if !out.status.success() {
        return Err("Clipboard does not contain plain text".to_string());
    }
    if out.stdout.len() > MAX_BODY_BYTES {
        return Err(format!(
            "Clipboard text exceeds {MAX_BODY_BYTES} byte limit"
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub fn add_snippet_to(
    path: &Path,
    raw_title: &str,
    raw_tag: &str,
    raw_body: &str,
) -> Result<Vec<Snippet>, String> {
    let title: String = sanitize_text(raw_title, false)
        .trim()
        .chars()
        .take(MAX_TITLE_CHARS)
        .collect();
    if title.is_empty() {
        return Err("Snippet title cannot be empty".to_string());
    }
    let clean_tag: String = sanitize_text(raw_tag, false)
        .trim()
        .chars()
        .take(MAX_TAG_CHARS)
        .collect();
    let tag = if clean_tag.is_empty() {
        "general".to_string()
    } else {
        clean_tag
    };

    let body = sanitize_text(raw_body, true);
    if body.trim().is_empty() {
        return Err("Snippet body cannot be empty".to_string());
    }
    if body.len() > MAX_BODY_BYTES {
        return Err(format!("Snippet body exceeds {MAX_BODY_BYTES} byte limit"));
    }

    let _lock = FileLock::acquire(path)?;
    let mut items = load_snippets_from(path);
    let max_id = items.iter().map(|s| s.id).max().unwrap_or(0);

    // Deduplicate exact title+body match by updating in place
    let mut existing_pin = false;
    items.retain(|it| {
        if it.title == title && it.body == body {
            existing_pin = existing_pin || it.pinned;
            false
        } else {
            true
        }
    });

    items.push(Snippet {
        id: max_id + 1,
        title,
        tag,
        preview: make_preview(&body),
        body,
        pinned: existing_pin,
        updated: local_stamp(),
    });

    let mut sorted = sort_snippets(&items);
    if sorted.len() > MAX_SNIPPETS {
        let mut pinned: Vec<Snippet> = sorted.iter().filter(|s| s.pinned).cloned().collect();
        let unpinned: Vec<Snippet> = sorted.iter().filter(|s| !s.pinned).cloned().collect();
        pinned.truncate(MAX_SNIPPETS);
        let cap_unpinned = MAX_SNIPPETS.saturating_sub(pinned.len());
        pinned.extend(unpinned.into_iter().take(cap_unpinned));
        sorted = sort_snippets(&pinned);
    }

    save_snippets_to(path, &sorted)?;
    Ok(sorted)
}

pub fn filter_snippets(items: &[Snippet], query: &str) -> Vec<Snippet> {
    let q = query.trim().to_ascii_lowercase();
    let sorted = sort_snippets(items);
    if q.is_empty() {
        return sorted;
    }
    sorted
        .into_iter()
        .filter(|s| {
            s.title.to_ascii_lowercase().contains(&q)
                || s.tag.to_ascii_lowercase().contains(&q)
                || s.body.to_ascii_lowercase().contains(&q)
        })
        .collect()
}

pub fn pin_snippet_in(path: &Path, id: u64) -> Result<Vec<Snippet>, String> {
    let _lock = FileLock::acquire(path)?;
    let mut items = load_snippets_from(path);
    for it in &mut items {
        if it.id == id {
            it.pinned = !it.pinned;
            break;
        }
    }
    let sorted = sort_snippets(&items);
    save_snippets_to(path, &sorted)?;
    Ok(sorted)
}

pub fn delete_snippet_in(path: &Path, id: u64) -> Result<Vec<Snippet>, String> {
    let _lock = FileLock::acquire(path)?;
    let items: Vec<Snippet> = load_snippets_from(path)
        .into_iter()
        .filter(|it| it.id != id)
        .collect();
    let sorted = sort_snippets(&items);
    save_snippets_to(path, &sorted)?;
    Ok(sorted)
}

pub fn cmd_snippets(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("list");
    let rest = args.get(1..).unwrap_or(&[]);
    let path = vault_path();

    match op {
        "list" => {
            let q = rest.join(" ");
            let items = load_snippets_from(&path);
            let filtered = filter_snippets(&items, &q);
            println!("{}", snippets_to_json(&filtered));
            Ok(())
        }
        "add" => {
            let title = rest.first().map(String::as_str).ok_or_else(|| {
                "Usage: snippets add <title> <tag> <body|--stdin|--from-clipboard>".to_string()
            })?;
            let tag = rest.get(1).map(String::as_str).unwrap_or("general");
            let body_args = rest.get(2..).unwrap_or(&[]);
            let body = match body_args.first().map(String::as_str) {
                Some("--stdin") | None => read_stdin_capped()?,
                Some("--from-clipboard") => read_clipboard_plain()?,
                Some(_) => body_args.join(" "),
            };
            let saved = add_snippet_to(&path, title, tag, &body)?;
            println!("{}", snippets_to_json(&saved));
            Ok(())
        }
        "copy" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing snippet id".to_string())?;
            if which("wl-copy").is_none() {
                return Err("wl-copy is required".to_string());
            }
            let items = load_snippets_from(&path);
            let found = items
                .into_iter()
                .find(|s| s.id == id)
                .ok_or_else(|| format!("Snippet {id} not found"))?;
            let mut child = Command::new("wl-copy")
                .args(["--type", "text/plain"])
                .stdin(Stdio::piped())
                .spawn()
                .map_err(|e| format!("wl-copy failed: {e}"))?;
            if let Some(mut sin) = child.stdin.take() {
                let _ = sin.write_all(found.body.as_bytes());
            }
            let status = child
                .wait()
                .map_err(|e| format!("wl-copy wait failed: {e}"))?;
            if !status.success() {
                return Err("wl-copy exited non-zero".to_string());
            }
            let mut o = JsonOut::new();
            o.obj_start();
            o.kv_bool("ok", true);
            o.kv_u64("id", id);
            o.obj_end();
            println!("{}", o.finish());
            Ok(())
        }
        "pin" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing snippet id".to_string())?;
            let updated = pin_snippet_in(&path, id)?;
            println!("{}", snippets_to_json(&updated));
            Ok(())
        }
        "delete" => {
            let id: u64 = rest
                .first()
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Missing snippet id".to_string())?;
            let updated = delete_snippet_in(&path, id)?;
            println!("{}", snippets_to_json(&updated));
            Ok(())
        }
        other => Err(format!("Unknown snippets command '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snippets_crud_pin_filter_and_caps() {
        let base = std::env::temp_dir().join(format!("aurora_snip_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let vault = base.join("snippets.json");

        assert!(load_snippets_from(&vault).is_empty());

        let s1 = add_snippet_to(
            &vault,
            "SSH Tunnel",
            "ops",
            "ssh -N -L 8080:127.0.0.1:80 host",
        )
        .expect("add 1");
        assert_eq!(s1.len(), 1);
        let id1 = s1[0].id;

        let s2 = add_snippet_to(&vault, "Cargo Check", "rust", "cargo clippy -- -D warnings")
            .expect("add 2");
        assert_eq!(s2.len(), 2);
        assert_eq!(s2[0].title, "Cargo Check");

        let pinned = pin_snippet_in(&vault, id1).expect("pin");
        assert_eq!(pinned[0].id, id1);
        assert!(pinned[0].pinned);

        let filtered = filter_snippets(&pinned, "clippy");
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].tag, "rust");

        let after_del = delete_snippet_in(&vault, id1).expect("del");
        assert_eq!(after_del.len(), 1);
        assert_eq!(after_del[0].title, "Cargo Check");

        assert!(add_snippet_to(&vault, "   ", "ops", "body").is_err());
        assert!(add_snippet_to(&vault, "Title", "ops", "\0  ").is_err());

        let _ = fs::remove_dir_all(&base);
    }
}
