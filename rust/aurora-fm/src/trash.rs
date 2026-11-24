use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::json::JsonOut;
use crate::util::{
    classify_file, data_dir, expand_path, human_size, natural_cmp, now_unix_secs, percent_decode,
    percent_encode_path, unix_secs_to_iso,
};

static TRASH_TMP_SEQ: AtomicU64 = AtomicU64::new(0);

fn trash_dirs() -> Result<(PathBuf, PathBuf), String> {
    let base = data_dir().join("Trash");
    let files = base.join("files");
    let info = base.join("info");
    fs::create_dir_all(&files).map_err(|e| format!("create trash files dir: {e}"))?;
    fs::create_dir_all(&info).map_err(|e| format!("create trash info dir: {e}"))?;
    Ok((files, info))
}

fn unique_trash_name(files_dir: &Path, info_dir: &Path, base_name: &str) -> String {
    let clean = if base_name.is_empty() {
        "item"
    } else {
        base_name
    };
    let stem_ext = match clean.rfind('.') {
        Some(idx) if idx > 0 => (&clean[..idx], Some(&clean[idx..])),
        _ => (clean, None),
    };
    let mut n = 0u32;
    loop {
        let candidate = if n == 0 {
            clean.to_string()
        } else if let Some(ext) = stem_ext.1 {
            format!("{}.{n}{ext}", stem_ext.0)
        } else {
            format!("{clean}.{n}")
        };
        let f_path = files_dir.join(&candidate);
        let i_path = info_dir.join(format!("{candidate}.trashinfo"));
        if !f_path.exists() && fs::symlink_metadata(&f_path).is_err() && !i_path.exists() {
            return candidate;
        }
        n += 1;
    }
}

pub fn trash_paths(raw_paths: &[String]) -> Result<String, String> {
    let (files_dir, info_dir) = trash_dirs()?;
    trash_paths_in(&files_dir, &info_dir, raw_paths)
}

pub(crate) fn trash_paths_in(
    files_dir: &Path,
    info_dir: &Path,
    raw_paths: &[String],
) -> Result<String, String> {
    fs::create_dir_all(files_dir).map_err(|e| format!("create trash files dir: {e}"))?;
    fs::create_dir_all(info_dir).map_err(|e| format!("create trash info dir: {e}"))?;
    let mut trashed = 0u64;
    let mut last_err = None;

    for raw in raw_paths {
        let src = expand_path(raw);
        let Ok(lmeta) = fs::symlink_metadata(&src) else {
            last_err = Some(format!("Path does not exist: {}", src.display()));
            continue;
        };
        let orig_abs = fs::canonicalize(&src).unwrap_or_else(|_| src.clone());
        let fname = src
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("item")
            .to_string();
        let trash_name = unique_trash_name(files_dir, info_dir, &fname);
        let info_path = info_dir.join(format!("{trash_name}.trashinfo"));
        let dest_path = files_dir.join(&trash_name);

        let orig_str = if lmeta.file_type().is_symlink() {
            src.to_string_lossy().into_owned()
        } else {
            orig_abs.to_string_lossy().into_owned()
        };
        let encoded_path = percent_encode_path(&orig_str);
        let del_date = unix_secs_to_iso(now_unix_secs());
        let info_body = format!("[Trash Info]\nPath={encoded_path}\nDeletionDate={del_date}\n");

        let seq = TRASH_TMP_SEQ.fetch_add(1, Ordering::Relaxed);
        let tmp_info = info_dir.join(format!(".tmp_{}_{}.trashinfo", std::process::id(), seq));
        {
            let mut f = fs::File::create(&tmp_info)
                .map_err(|e| format!("write trashinfo '{}': {e}", tmp_info.display()))?;
            if let Err(e) = f
                .write_all(info_body.as_bytes())
                .and_then(|()| f.sync_all())
            {
                let _ = fs::remove_file(&tmp_info);
                return Err(format!("write trashinfo body: {e}"));
            }
        }
        if let Err(e) = fs::rename(&tmp_info, &info_path) {
            let _ = fs::remove_file(&tmp_info);
            return Err(format!("commit trashinfo '{}': {e}", info_path.display()));
        }

        if let Err(e) = crate::ops::move_single(&src, &dest_path) {
            let _ = fs::remove_file(&info_path);
            return Err(format!("Failed to move '{}' to Trash: {e}", src.display()));
        }
        trashed += 1;
    }

    if trashed == 0 {
        if let Some(e) = last_err {
            return Err(e);
        }
    }

    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_u64("trashed", trashed);
    out.obj_end();
    Ok(out.finish())
}

struct TrashRow {
    trash_name: String,
    name: String,
    original_path: String,
    deletion_date: String,
    is_dir: bool,
    size: u64,
    human_size: String,
    category: &'static str,
    files_path: String,
}

fn parse_trashinfo(path: &Path) -> (String, String) {
    let Ok(raw) = fs::read_to_string(path) else {
        return (String::new(), String::new());
    };
    let mut orig = String::new();
    let mut date = String::new();
    for line in raw.lines() {
        if let Some(v) = line.strip_prefix("Path=") {
            orig = percent_decode(v.trim());
        } else if let Some(v) = line.strip_prefix("DeletionDate=") {
            date = v.trim().to_string();
        }
    }
    (orig, date)
}

pub fn trash_list() -> Result<String, String> {
    let (files_dir, info_dir) = trash_dirs()?;
    let mut rows: Vec<TrashRow> = Vec::new();

    let Ok(rd) = fs::read_dir(&info_dir) else {
        return Ok("{\"entries\":[],\"totalCount\":0}".to_string());
    };

    for entry in rd.flatten() {
        let fname = entry.file_name().to_string_lossy().into_owned();
        let Some(trash_name) = fname.strip_suffix(".trashinfo") else {
            continue;
        };
        let item_path = files_dir.join(trash_name);
        let Ok(lmeta) = fs::symlink_metadata(&item_path) else {
            continue;
        };
        let (orig_path, del_date) = parse_trashinfo(&entry.path());
        let display_name = Path::new(&orig_path)
            .file_name()
            .and_then(|n| n.to_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(trash_name)
            .to_string();
        let is_dir = lmeta.is_dir();
        let size = if is_dir { 0 } else { lmeta.len() };
        let (cat, _) = classify_file(&display_name, is_dir, false);
        rows.push(TrashRow {
            trash_name: trash_name.to_string(),
            name: display_name,
            original_path: orig_path,
            deletion_date: del_date,
            is_dir,
            size,
            human_size: if is_dir {
                "--".to_string()
            } else {
                human_size(size)
            },
            category: cat,
            files_path: item_path.to_string_lossy().into_owned(),
        });
    }

    rows.sort_by(|a, b| {
        b.deletion_date
            .cmp(&a.deletion_date)
            .then_with(|| natural_cmp(&a.name, &b.name))
    });

    let mut out = JsonOut::with_capacity(rows.len() * 240 + 64);
    out.obj_start();
    out.kv_u64("totalCount", rows.len() as u64);
    out.key("entries");
    out.arr_start();
    for r in &rows {
        out.obj_start();
        out.kv_str("trashName", &r.trash_name);
        out.kv_str("name", &r.name);
        out.kv_str("path", &r.files_path);
        out.kv_str("originalPath", &r.original_path);
        out.kv_str("deletionDate", &r.deletion_date);
        out.kv_bool("isDir", r.is_dir);
        out.kv_u64("size", r.size);
        out.kv_str("humanSize", &r.human_size);
        out.kv_str("category", r.category);
        out.obj_end();
    }
    out.arr_end();
    out.obj_end();
    Ok(out.finish())
}

pub fn trash_restore(trash_name: &str) -> Result<String, String> {
    let (files_dir, info_dir) = trash_dirs()?;
    trash_restore_in(&files_dir, &info_dir, trash_name)
}

pub(crate) fn trash_restore_in(
    files_dir: &Path,
    info_dir: &Path,
    trash_name: &str,
) -> Result<String, String> {
    if trash_name.is_empty()
        || trash_name.contains('/')
        || trash_name.contains('\0')
        || trash_name == "."
        || trash_name == ".."
    {
        return Err("Invalid trash item name".to_string());
    }
    let src = files_dir.join(trash_name);
    let info_path = info_dir.join(format!("{trash_name}.trashinfo"));
    if fs::symlink_metadata(&src).is_err() {
        return Err(format!("Trash item '{}' not found", trash_name));
    }
    let (orig_path_str, _) = parse_trashinfo(&info_path);
    if orig_path_str.is_empty() {
        return Err("Missing original path in .trashinfo".to_string());
    }
    let mut dest = PathBuf::from(&orig_path_str);
    if !dest.is_absolute() {
        return Err("Invalid non-absolute restore path in .trashinfo".to_string());
    }
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("create restore parent '{}': {e}", parent.display()))?;
    }
    if fs::symlink_metadata(&dest).is_ok() {
        dest = crate::ops::unique_dest_path(&dest);
    }
    crate::ops::move_single(&src, &dest)?;
    let _ = fs::remove_file(&info_path);

    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("restoredTo", &dest.to_string_lossy());
    out.obj_end();
    Ok(out.finish())
}

pub fn trash_empty() -> Result<String, String> {
    let (files_dir, info_dir) = trash_dirs()?;
    let mut removed = 0u64;
    if let Ok(rd) = fs::read_dir(&files_dir) {
        for e in rd.flatten() {
            if crate::ops::remove_any(&e.path()).is_ok() {
                removed += 1;
            }
        }
    }
    if let Ok(rd) = fs::read_dir(&info_dir) {
        for e in rd.flatten() {
            let _ = fs::remove_file(e.path());
        }
    }
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_u64("removed", removed);
    out.obj_end();
    Ok(out.finish())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xdg_trashinfo_and_restore_roundtrip() {
        let base = std::env::temp_dir().join(format!("mango_fm_trash_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let work = base.join("work");
        let files_dir = base.join("Trash/files");
        let info_dir = base.join("Trash/info");
        fs::create_dir_all(&work).unwrap();

        let f1 = work.join("my doc #1%.txt");
        let f2 = work.join("my doc #1%.txt");
        fs::write(&f1, b"first").unwrap();
        trash_paths_in(&files_dir, &info_dir, &[f1.to_string_lossy().into_owned()])
            .expect("first trash ok");
        assert!(!f1.exists());
        assert!(files_dir.join("my doc #1%.txt").is_file());

        // Check .trashinfo XDG format & RFC 3986 percent encoding
        let raw_info = fs::read_to_string(info_dir.join("my doc #1%.txt.trashinfo")).unwrap();
        assert!(raw_info.starts_with("[Trash Info]\nPath=/"));
        assert!(raw_info.contains("%20"));
        assert!(raw_info.contains("%231%25.txt\nDeletionDate="));

        // Collision naming when trashing same filename twice
        fs::write(&f2, b"second").unwrap();
        trash_paths_in(&files_dir, &info_dir, &[f2.to_string_lossy().into_owned()])
            .expect("second trash ok");
        assert!(files_dir.join("my doc #1%.1.txt").is_file());
        assert!(info_dir.join("my doc #1%.1.txt.trashinfo").is_file());

        // Restore first back to original location
        trash_restore_in(&files_dir, &info_dir, "my doc #1%.txt").expect("restore ok");
        assert_eq!(fs::read(&f1).unwrap(), b"first");
        assert!(!info_dir.join("my doc #1%.txt.trashinfo").exists());

        // Restore second gets collision-safe name since f1 exists again
        trash_restore_in(&files_dir, &info_dir, "my doc #1%.1.txt").expect("restore 2 ok");
        assert!(work.join("my doc #1% (copy).txt").is_file());

        let _ = fs::remove_dir_all(&base);
    }
}
