use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use crate::json::JsonOut;
use crate::list::EntryInfo;
use crate::util::{expand_path, natural_cmp};

struct MatchEntry {
    score: u32,
    rel_path: String,
    info: EntryInfo,
}

fn score_match(name_lower: &str, rel_lower: &str, query_lower: &str) -> Option<u32> {
    if query_lower.is_empty() {
        return Some(1);
    }
    if name_lower == query_lower {
        return Some(1000);
    }
    if name_lower.starts_with(query_lower) {
        return Some(850 - (name_lower.len().min(200) as u32));
    }
    if let Some(pos) = name_lower.find(query_lower) {
        return Some(650 - (pos.min(200) as u32));
    }
    if let Some(pos) = rel_lower.find(query_lower) {
        return Some(450 - (pos.min(200) as u32));
    }
    // Fuzzy ordered subsequence check on name
    let mut q_chars = query_lower.chars();
    let mut cur = q_chars.next()?;
    let mut gaps = 0u32;
    let mut last_idx = 0usize;
    for (idx, ch) in name_lower.chars().enumerate() {
        if ch == cur {
            if idx > last_idx + 1 {
                gaps += (idx - last_idx - 1) as u32;
            }
            last_idx = idx;
            match q_chars.next() {
                Some(next_ch) => cur = next_ch,
                None => return Some(250u32.saturating_sub(gaps.min(200))),
            }
        }
    }
    None
}

pub fn search_dir(
    raw_root: &str,
    query: &str,
    show_hidden: bool,
    max_results: usize,
    cancel_token: &AtomicU64,
    my_id: u64,
    shutdown: &AtomicBool,
) -> Result<String, String> {
    let target = expand_path(raw_root);
    let canonical = fs::canonicalize(&target).unwrap_or_else(|_| target.clone());
    let root_meta = fs::metadata(&canonical)
        .map_err(|_| format!("Not a directory: {}", canonical.display()))?;
    if !root_meta.is_dir() {
        return Err(format!("Not a directory: {}", canonical.display()));
    }

    let query_trimmed = query.trim();
    let query_lower = query_trimmed.to_ascii_lowercase();
    let include_hidden = show_hidden || query_lower.starts_with('.');
    let cap = max_results.clamp(10, 400);

    let mut seen_dirs: HashSet<(u64, u64)> = HashSet::new();
    seen_dirs.insert((root_meta.dev(), root_meta.ino()));

    let mut stack: Vec<PathBuf> = vec![canonical.clone()];
    let mut hits: Vec<MatchEntry> = Vec::with_capacity(cap.min(128));
    let mut visited = 0usize;
    let mut cancelled = false;

    while let Some(dir) = stack.pop() {
        if cancel_token.load(Ordering::Relaxed) != my_id || shutdown.load(Ordering::Relaxed) {
            cancelled = true;
            break;
        }
        let Ok(rd) = fs::read_dir(&dir) else { continue };
        for item in rd.flatten() {
            visited += 1;
            if (visited & 63) == 0
                && (cancel_token.load(Ordering::Relaxed) != my_id
                    || shutdown.load(Ordering::Relaxed))
            {
                cancelled = true;
                break;
            }
            let fname = item.file_name().to_string_lossy().into_owned();
            if !include_hidden && fname.starts_with('.') {
                continue;
            }
            let full = dir.join(&fname);
            let Ok(lmeta) = fs::symlink_metadata(&full) else {
                continue;
            };
            let is_symlink = lmeta.file_type().is_symlink();
            let is_real_dir = lmeta.is_dir(); // symlink_metadata never follows symlinks

            if !include_hidden
                && is_real_dir
                && matches!(
                    fname.as_str(),
                    "node_modules" | "target" | "__pycache__" | ".git" | ".cache"
                )
            {
                continue;
            }

            let rel = full
                .strip_prefix(&canonical)
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_else(|_| full.to_string_lossy().into_owned());

            if let Some(score) = score_match(
                &fname.to_ascii_lowercase(),
                &rel.to_ascii_lowercase(),
                &query_lower,
            ) {
                if let Some(info) = EntryInfo::from_path(fname, &full) {
                    hits.push(MatchEntry {
                        score,
                        rel_path: rel,
                        info,
                    });
                }
            }

            // Never recurse into symlinks or revisit (dev, ino) bind-mount/directory cycles
            if is_real_dir
                && !is_symlink
                && visited < 80_000
                && seen_dirs.insert((lmeta.dev(), lmeta.ino()))
            {
                stack.push(full);
            }
            if hits.len() >= cap * 4 {
                break;
            }
        }
        if cancelled || hits.len() >= cap * 4 {
            break;
        }
    }

    hits.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then_with(|| b.info.is_dir.cmp(&a.info.is_dir))
            .then_with(|| natural_cmp(&a.info.name, &b.info.name))
    });
    hits.truncate(cap);

    let mut out = JsonOut::with_capacity(hits.len() * 240 + 128);
    out.obj_start();
    out.kv_str("root", &canonical.to_string_lossy());
    out.kv_str("query", query_trimmed);
    out.kv_u64("totalCount", hits.len() as u64);
    out.kv_bool("cancelled", cancelled);
    out.key("entries");
    out.arr_start();
    for h in &hits {
        h.info.write_json(&mut out, Some(&h.rel_path));
    }
    out.arr_end();
    out.obj_end();
    Ok(out.finish())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json;
    use std::os::unix::fs::symlink;

    #[test]
    fn symlink_loop_detection_terminates() {
        let base = std::env::temp_dir().join(format!("mango_fm_loop_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let sub = base.join("a/b");
        fs::create_dir_all(&sub).unwrap();
        fs::write(sub.join("target_file.txt"), b"ok").unwrap();
        // Cyclic symlink pointing back to root
        symlink(base.join("a"), sub.join("loop_back")).unwrap();

        let tok = AtomicU64::new(1);
        let shutdown = AtomicBool::new(false);
        let out = search_dir(
            &base.to_string_lossy(),
            "target_file",
            false,
            50,
            &tok,
            1,
            &shutdown,
        )
        .expect("search terminates");
        let v = json::parse(&out).expect("valid search json");
        let entries = v.get_arr("entries").expect("entries array");
        assert!(entries
            .iter()
            .any(|e| e.get_str("name") == Some("target_file.txt")));

        let _ = fs::remove_dir_all(&base);
    }
}
