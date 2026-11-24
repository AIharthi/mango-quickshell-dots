use std::cmp::Ordering;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use crate::json::JsonOut;
use crate::util::{
    classify_file, display_path, expand_path, format_mode, human_size, mtime_secs, natural_cmp,
};

pub struct EntryInfo {
    pub name: String,
    pub path: String,
    pub kind: &'static str,
    pub is_dir: bool,
    pub is_symlink: bool,
    pub is_broken: bool,
    pub is_hidden: bool,
    pub is_exec: bool,
    pub size: u64,
    pub human_size: String,
    pub mtime: i64,
    pub perms: String,
    pub mode_octal: String,
    pub ext: String,
    pub category: &'static str,
    pub target: String,
}

impl EntryInfo {
    pub fn from_path(name: String, full_path: &Path) -> Option<Self> {
        let lmeta = fs::symlink_metadata(full_path).ok()?;
        let is_symlink = lmeta.file_type().is_symlink();
        let (target_meta, is_broken) = if is_symlink {
            match fs::metadata(full_path) {
                Ok(m) => (Some(m), false),
                Err(_) => (None, true),
            }
        } else {
            (None, false)
        };
        let eff_meta = target_meta.as_ref().unwrap_or(&lmeta);
        let is_dir = eff_meta.is_dir();
        let mode = eff_meta.mode();
        let is_exec = !is_dir && ((mode & 0o111) != 0);
        let kind = if is_symlink {
            "symlink"
        } else if is_dir {
            "dir"
        } else {
            "file"
        };
        let target = if is_symlink {
            fs::read_link(full_path)
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_default()
        } else {
            String::new()
        };
        let size = if is_dir { 0 } else { eff_meta.len() };
        let (category, ext) = classify_file(&name, is_dir, is_exec);
        let perms = format_mode(mode, is_dir, is_symlink);
        let mode_octal = format!("{:04o}", mode & 0o7777);
        let is_hidden = name.starts_with('.');
        Some(Self {
            name,
            path: full_path.to_string_lossy().into_owned(),
            kind,
            is_dir,
            is_symlink,
            is_broken,
            is_hidden,
            is_exec,
            size,
            human_size: if is_dir {
                "--".to_string()
            } else {
                human_size(size)
            },
            mtime: mtime_secs(eff_meta),
            perms,
            mode_octal,
            ext,
            category,
            target,
        })
    }

    pub fn write_json(&self, out: &mut JsonOut, extra_rel: Option<&str>) {
        out.obj_start();
        out.kv_str("name", &self.name);
        out.kv_str("path", &self.path);
        if let Some(rel) = extra_rel {
            out.kv_str("relPath", rel);
        }
        out.kv_str("kind", self.kind);
        out.kv_bool("isDir", self.is_dir);
        out.kv_bool("isSymlink", self.is_symlink);
        out.kv_bool("isBroken", self.is_broken);
        out.kv_bool("isHidden", self.is_hidden);
        out.kv_bool("isExec", self.is_exec);
        out.kv_u64("size", self.size);
        out.kv_str("humanSize", &self.human_size);
        out.kv_i64("mtime", self.mtime);
        out.kv_str("perms", &self.perms);
        out.kv_str("modeOctal", &self.mode_octal);
        out.kv_str("ext", &self.ext);
        out.kv_str("category", self.category);
        out.kv_str("target", &self.target);
        out.obj_end();
    }
}

pub fn build_breadcrumbs(path: &Path) -> Vec<(String, String)> {
    let mut crumbs = Vec::new();
    let mut acc = PathBuf::from("/");
    crumbs.push(("/".to_string(), "/".to_string()));
    for comp in path.components() {
        if let std::path::Component::Normal(seg) = comp {
            acc.push(seg);
            crumbs.push((
                seg.to_string_lossy().into_owned(),
                acc.to_string_lossy().into_owned(),
            ));
        }
    }
    crumbs
}

pub fn list_dir(
    raw_path: &str,
    show_hidden: bool,
    sort_by: &str,
    desc: bool,
    dirs_first: bool,
) -> Result<String, String> {
    let target = expand_path(raw_path);
    let canonical = fs::canonicalize(&target).unwrap_or_else(|_| target.clone());
    let dir_meta = fs::metadata(&canonical)
        .map_err(|e| format!("Cannot access '{}': {e}", canonical.display()))?;
    if !dir_meta.is_dir() {
        return Err(format!("Not a directory: {}", canonical.display()));
    }

    let read = fs::read_dir(&canonical)
        .map_err(|e| format!("Cannot read directory '{}': {e}", canonical.display()))?;

    let mut entries = Vec::with_capacity(64);
    let mut dir_count = 0u64;
    let mut file_count = 0u64;
    let mut total_bytes = 0u64;
    let mut raw_count = 0u64;

    for item in read {
        raw_count += 1;
        let Ok(entry) = item else { continue };
        let fname = entry.file_name().to_string_lossy().into_owned();
        if !show_hidden && fname.starts_with('.') {
            continue;
        }
        let full = canonical.join(&fname);
        if let Some(info) = EntryInfo::from_path(fname, &full) {
            if info.is_dir {
                dir_count += 1;
            } else {
                file_count += 1;
                total_bytes = total_bytes.saturating_add(info.size);
            }
            entries.push(info);
        }
    }

    entries.sort_by(|a, b| {
        if dirs_first && a.is_dir != b.is_dir {
            return b.is_dir.cmp(&a.is_dir);
        }
        let mut ord = match sort_by {
            "size" => a.size.cmp(&b.size),
            "mtime" | "date" => a.mtime.cmp(&b.mtime),
            "ext" | "type" => a.ext.cmp(&b.ext).then_with(|| a.category.cmp(b.category)),
            _ => natural_cmp(&a.name, &b.name),
        };
        if ord == Ordering::Equal {
            ord = natural_cmp(&a.name, &b.name);
        }
        if desc {
            ord.reverse()
        } else {
            ord
        }
    });

    let parent = canonical
        .parent()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    let stamp = format!("{}:{}:{raw_count}", dir_meta.mtime(), dir_meta.ctime());
    let crumbs = build_breadcrumbs(&canonical);

    let mut out = JsonOut::with_capacity(entries.len() * 220 + 256);
    out.obj_start();
    out.kv_str("path", &canonical.to_string_lossy());
    out.kv_str("parent", &parent);
    out.kv_str("displayPath", &display_path(&canonical));
    out.kv_str("dirStamp", &stamp);
    out.kv_u64("totalCount", entries.len() as u64);
    out.kv_u64("dirCount", dir_count);
    out.kv_u64("fileCount", file_count);
    out.kv_u64("totalBytes", total_bytes);
    out.kv_str("totalHumanSize", &human_size(total_bytes));

    out.key("breadcrumbs");
    out.arr_start();
    for (label, path_str) in crumbs {
        out.obj_start();
        out.kv_str("label", &label);
        out.kv_str("path", &path_str);
        out.obj_end();
    }
    out.arr_end();

    out.key("entries");
    out.arr_start();
    for e in &entries {
        e.write_json(&mut out, None);
    }
    out.arr_end();

    out.obj_end();
    Ok(out.finish())
}

pub fn dir_stamp(raw_path: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let canonical = fs::canonicalize(&target).unwrap_or_else(|_| target.clone());
    let meta = fs::metadata(&canonical)
        .map_err(|e| format!("Cannot stat '{}': {e}", canonical.display()))?;
    let mut raw_count = 0u64;
    if let Ok(rd) = fs::read_dir(&canonical) {
        for _ in rd {
            raw_count += 1;
        }
    }
    let stamp = format!("{}:{}:{raw_count}", meta.mtime(), meta.ctime());
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("path", &canonical.to_string_lossy());
    out.kv_str("stamp", &stamp);
    out.obj_end();
    Ok(out.finish())
}
