use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};

use crate::json::JsonOut;
use crate::list::EntryInfo;
use crate::util::{display_path, expand_path, image_dimensions, natural_cmp};

pub fn preview_path(raw_path: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let name = target
        .file_name()
        .and_then(|n| n.to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("/")
        .to_string();

    let info = EntryInfo::from_path(name, &target)
        .ok_or_else(|| format!("Cannot inspect '{}'", target.display()))?;

    let mut out = JsonOut::with_capacity(2048);
    out.obj_start();
    out.kv_str("name", &info.name);
    out.kv_str("path", &info.path);
    out.kv_str("displayPath", &display_path(&target));
    out.kv_str("kind", info.kind);
    out.kv_bool("isDir", info.is_dir);
    out.kv_bool("isSymlink", info.is_symlink);
    out.kv_bool("isBroken", info.is_broken);
    out.kv_bool("isExec", info.is_exec);
    out.kv_u64("size", info.size);
    out.kv_str("humanSize", &info.human_size);
    out.kv_i64("mtime", info.mtime);
    out.kv_str("perms", &info.perms);
    out.kv_str("modeOctal", &info.mode_octal);
    out.kv_str("ext", &info.ext);
    out.kv_str("category", info.category);
    out.kv_str("target", &info.target);

    if info.is_broken {
        out.kv_str("previewKind", "broken");
        out.obj_end();
        return Ok(out.finish());
    }

    if info.is_dir {
        let mut dir_count = 0u64;
        let mut file_count = 0u64;
        let mut sample: Vec<(String, bool, &'static str)> = Vec::new();
        if let Ok(rd) = fs::read_dir(&target) {
            for item in rd.flatten() {
                let n = item.file_name().to_string_lossy().into_owned();
                let is_d = item.file_type().map(|t| t.is_dir()).unwrap_or(false);
                if is_d {
                    dir_count += 1;
                } else {
                    file_count += 1;
                }
                if sample.len() < 48 {
                    let (cat, _) = crate::util::classify_file(&n, is_d, false);
                    sample.push((n, is_d, cat));
                }
            }
        }
        sample.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| natural_cmp(&a.0, &b.0)));
        sample.truncate(24);

        out.kv_str("previewKind", "dir");
        out.kv_u64("dirCount", dir_count);
        out.kv_u64("fileCount", file_count);
        out.key("sample");
        out.arr_start();
        for (sn, is_d, cat) in &sample {
            out.obj_start();
            out.kv_str("name", sn);
            out.kv_bool("isDir", *is_d);
            out.kv_str("category", cat);
            out.obj_end();
        }
        out.arr_end();
        out.obj_end();
        return Ok(out.finish());
    }

    if info.category == "image" {
        out.kv_str("previewKind", "image");
        if let Some((w, h)) = image_dimensions(&target) {
            out.kv_u64("width", w as u64);
            out.kv_u64("height", h as u64);
        }
        let wp_ok = matches!(
            info.ext.as_str(),
            "png" | "jpg" | "jpeg" | "webp" | "gif" | "bmp"
        );
        out.kv_bool("isWallpaperCandidate", wp_ok);
        out.obj_end();
        return Ok(out.finish());
    }

    if info.category == "archive" {
        let (items, trunc) = list_archive_entries(&target, &info.ext);
        out.kv_str("previewKind", "archive");
        out.kv_bool("archiveTruncated", trunc);
        out.key("archiveEntries");
        out.arr_start();
        for line in &items {
            out.str(line);
        }
        out.arr_end();
        out.obj_end();
        return Ok(out.finish());
    }

    if matches!(info.category, "video" | "audio" | "pdf" | "font") {
        out.kv_str("previewKind", info.category);
        out.obj_end();
        return Ok(out.finish());
    }

    // Attempt safe text snippet read (max 8 KB)
    if let Ok(mut f) = File::open(&target) {
        let mut buf = vec![0u8; 8192];
        if let Ok(n) = f.read(&mut buf) {
            buf.truncate(n);
            if !buf.contains(&0u8) {
                let text_full = String::from_utf8_lossy(&buf);
                let mut lines = Vec::new();
                let mut truncated = info.size > n as u64;
                for (idx, line) in text_full.lines().enumerate() {
                    if idx >= 80 {
                        truncated = true;
                        break;
                    }
                    lines.push(line);
                }
                let joined = lines.join("\n");
                let is_theme_json = info.ext == "json"
                    && ((joined.contains("\"primary\"") && joined.contains("\"surface\""))
                        || joined.contains("\"colors\""));
                out.kv_str("previewKind", "text");
                out.kv_str("text", &joined);
                out.kv_u64("lineCount", lines.len() as u64);
                out.kv_bool("truncated", truncated);
                out.kv_bool("isThemeJson", is_theme_json);
                out.obj_end();
                return Ok(out.finish());
            }
        }
    }

    out.kv_str("previewKind", "binary");
    out.obj_end();
    Ok(out.finish())
}

fn list_archive_entries(path: &Path, ext: &str) -> (Vec<String>, bool) {
    let out = if ext == "zip" {
        Command::new("unzip")
            .args(["-Z1", "--"])
            .arg(path)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
    } else if matches!(
        ext,
        "tar" | "gz" | "tgz" | "bz2" | "tbz2" | "xz" | "txz" | "zst"
    ) {
        Command::new("tar")
            .arg("-tf")
            .arg(path)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
    } else {
        return (Vec::new(), false);
    };

    let Ok(res) = out else {
        return (Vec::new(), false);
    };
    if !res.status.success() {
        return (Vec::new(), false);
    }
    let text = String::from_utf8_lossy(&res.stdout);
    let mut entries = Vec::new();
    let mut trunc = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if entries.len() >= 60 {
            trunc = true;
            break;
        }
        entries.push(trimmed.to_string());
    }
    (entries, trunc)
}
