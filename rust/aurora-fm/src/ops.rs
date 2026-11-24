use std::fs::{self, File};
use std::io::Write as _;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::json::JsonOut;
use crate::util::{expand_path, is_same_or_subpath, percent_encode_path};

pub fn unique_dest_path(target: &Path) -> PathBuf {
    if fs::symlink_metadata(target).is_err() {
        return target.to_path_buf();
    }
    let parent = target.parent().unwrap_or_else(|| Path::new("/"));
    let name = target
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("item");
    let (stem, ext) = match name.rfind('.') {
        Some(idx) if idx > 0 => (&name[..idx], Some(&name[idx..])),
        _ => (name, None),
    };
    for n in 1u32..10_000 {
        let cand_name = if n == 1 {
            if let Some(e) = ext {
                format!("{stem} (copy){e}")
            } else {
                format!("{stem} (copy)")
            }
        } else if let Some(e) = ext {
            format!("{stem} (copy {n}){e}")
        } else {
            format!("{stem} (copy {n})")
        };
        let cand = parent.join(cand_name);
        if fs::symlink_metadata(&cand).is_err() {
            return cand;
        }
    }
    target.to_path_buf()
}

pub fn remove_any(path: &Path) -> Result<(), String> {
    let lmeta =
        fs::symlink_metadata(path).map_err(|e| format!("Cannot stat '{}': {e}", path.display()))?;
    if lmeta.file_type().is_symlink() || !lmeta.is_dir() {
        fs::remove_file(path).map_err(|e| format!("Remove '{}': {e}", path.display()))
    } else {
        fs::remove_dir_all(path).map_err(|e| format!("Remove dir '{}': {e}", path.display()))
    }
}

pub fn copy_recursive_raw(src: &Path, dst: &Path) -> Result<u64, String> {
    let lmeta = fs::symlink_metadata(src).map_err(|e| format!("Stat '{}': {e}", src.display()))?;
    if lmeta.file_type().is_symlink() {
        let link_target =
            fs::read_link(src).map_err(|e| format!("Read symlink '{}': {e}", src.display()))?;
        std::os::unix::fs::symlink(&link_target, dst)
            .map_err(|e| format!("Create symlink '{}': {e}", dst.display()))?;
        return Ok(0);
    }
    if lmeta.is_dir() {
        fs::create_dir_all(dst).map_err(|e| format!("Create dir '{}': {e}", dst.display()))?;
        let _ = fs::set_permissions(dst, lmeta.permissions());
        let mut bytes = 0u64;
        let rd = fs::read_dir(src).map_err(|e| format!("Read dir '{}': {e}", src.display()))?;
        for entry in rd {
            let entry = entry.map_err(|e| format!("Dir entry: {e}"))?;
            let child_src = entry.path();
            let child_dst = dst.join(entry.file_name());
            bytes = bytes.saturating_add(copy_recursive_raw(&child_src, &child_dst)?);
        }
        Ok(bytes)
    } else {
        if let Some(p) = dst.parent() {
            fs::create_dir_all(p).map_err(|e| format!("Create parent dir: {e}"))?;
        }
        let copied = fs::copy(src, dst)
            .map_err(|e| format!("Copy '{}' -> '{}': {e}", src.display(), dst.display()))?;
        let _ = fs::set_permissions(dst, lmeta.permissions());
        Ok(copied)
    }
}

pub fn move_single(src: &Path, dst: &Path) -> Result<(), String> {
    match fs::rename(src, dst) {
        Ok(()) => Ok(()),
        Err(e) if e.raw_os_error() == Some(18) => {
            // EXDEV cross-device fallback
            copy_recursive_raw(src, dst)?;
            remove_any(src)?;
            Ok(())
        }
        Err(e) => Err(format!(
            "Move '{}' -> '{}': {e}",
            src.display(),
            dst.display()
        )),
    }
}

pub fn mkdir(raw_path: &str, name: Option<&str>) -> Result<String, String> {
    let base = expand_path(raw_path);
    let target = match name.map(str::trim).filter(|s| !s.is_empty()) {
        Some(n) => {
            if n.contains('/') || n == "." || n == ".." {
                return Err("Invalid folder name".to_string());
            }
            base.join(n)
        }
        None => base,
    };
    if fs::symlink_metadata(&target).is_ok() {
        return Err(format!("Already exists: {}", target.display()));
    }
    fs::create_dir_all(&target)
        .map_err(|e| format!("Create folder '{}': {e}", target.display()))?;
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("path", &target.to_string_lossy());
    out.obj_end();
    Ok(out.finish())
}

pub fn touch(raw_path: &str, name: Option<&str>) -> Result<String, String> {
    let base = expand_path(raw_path);
    let target = match name.map(str::trim).filter(|s| !s.is_empty()) {
        Some(n) => {
            if n.contains('/') || n == "." || n == ".." {
                return Err("Invalid file name".to_string());
            }
            base.join(n)
        }
        None => base,
    };
    if fs::symlink_metadata(&target).is_ok() {
        return Err(format!("Already exists: {}", target.display()));
    }
    if let Some(p) = target.parent() {
        fs::create_dir_all(p).map_err(|e| format!("Create parent dir: {e}"))?;
    }
    File::create(&target).map_err(|e| format!("Create file '{}': {e}", target.display()))?;
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("path", &target.to_string_lossy());
    out.obj_end();
    Ok(out.finish())
}

pub fn rename_item(raw_path: &str, new_name: &str) -> Result<String, String> {
    let clean = new_name.trim();
    if clean.is_empty() || clean.contains('/') || clean == "." || clean == ".." {
        return Err("Invalid target name".to_string());
    }
    let src = expand_path(raw_path);
    if fs::symlink_metadata(&src).is_err() {
        return Err(format!("Source does not exist: {}", src.display()));
    }
    let parent = src.parent().ok_or("Cannot rename root directory")?;
    let dst = parent.join(clean);
    if dst == src {
        return Ok("{\"renamed\":false}".to_string());
    }
    if fs::symlink_metadata(&dst).is_ok() {
        return Err(format!("Target already exists: {}", dst.display()));
    }
    fs::rename(&src, &dst)
        .map_err(|e| format!("Rename '{}' -> '{}': {e}", src.display(), dst.display()))?;
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_bool("renamed", true);
    out.kv_str("path", &dst.to_string_lossy());
    out.obj_end();
    Ok(out.finish())
}

pub fn delete_paths(raw_paths: &[String]) -> Result<String, String> {
    let mut count = 0u64;
    for raw in raw_paths {
        let p = expand_path(raw);
        remove_any(&p)?;
        count += 1;
    }
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_u64("deleted", count);
    out.obj_end();
    Ok(out.finish())
}

pub fn chmod_path(raw_path: &str, mode_str: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let clean = mode_str.trim().trim_start_matches("0o");
    let mode =
        u32::from_str_radix(clean, 8).map_err(|_| format!("Invalid octal mode '{mode_str}'"))?;
    let mut perms = fs::metadata(&target)
        .map_err(|e| format!("Stat '{}': {e}", target.display()))?
        .permissions();
    perms.set_mode(mode & 0o7777);
    fs::set_permissions(&target, perms)
        .map_err(|e| format!("Chmod '{}': {e}", target.display()))?;
    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("path", &target.to_string_lossy());
    out.kv_str("modeOctal", &format!("{:04o}", mode & 0o7777));
    out.obj_end();
    Ok(out.finish())
}

pub fn copy_or_move<F>(
    raw_sources: &[String],
    raw_dest_dir: &str,
    is_move: bool,
    overwrite: bool,
    mut on_progress: F,
) -> Result<String, String>
where
    F: FnMut(usize, usize, &str),
{
    let dest_dir = expand_path(raw_dest_dir);
    if !dest_dir.is_dir() {
        return Err(format!(
            "Destination is not a directory: {}",
            dest_dir.display()
        ));
    }
    let total = raw_sources.len();
    let mut last_emit = Instant::now() - Duration::from_secs(1);
    let mut done = 0usize;
    let mut created_paths = Vec::with_capacity(total);

    for (idx, raw) in raw_sources.iter().enumerate() {
        let src = expand_path(raw);
        if fs::symlink_metadata(&src).is_err() {
            return Err(format!("Source not found: {}", src.display()));
        }
        if is_same_or_subpath(&dest_dir, &src) {
            return Err(format!(
                "Cannot {} '{}' inside itself",
                if is_move { "move" } else { "copy" },
                src.display()
            ));
        }
        let fname = src
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or("Invalid source filename")?;
        if last_emit.elapsed() >= Duration::from_millis(75) || idx == 0 {
            on_progress(idx, total, fname);
            last_emit = Instant::now();
        }
        let mut target = dest_dir.join(fname);
        if is_move && target == src {
            done += 1;
            continue;
        }
        if fs::symlink_metadata(&target).is_ok() {
            if overwrite && target != src {
                remove_any(&target)?;
            } else {
                target = unique_dest_path(&target);
            }
        }
        if is_move {
            move_single(&src, &target)?;
        } else {
            copy_recursive_raw(&src, &target)?;
        }
        created_paths.push(target.to_string_lossy().into_owned());
        done += 1;
    }

    on_progress(total, total, "");

    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_u64("count", done as u64);
    out.kv_str("destDir", &dest_dir.to_string_lossy());
    out.key("created");
    out.arr_start();
    for p in &created_paths {
        out.str(p);
    }
    out.arr_end();
    out.obj_end();
    Ok(out.finish())
}

pub fn validate_archive_member(member: &str) -> Result<(), String> {
    if member.is_empty() {
        return Ok(());
    }
    if member.contains('\0') {
        return Err("Archive contains NUL byte in entry name".to_string());
    }
    if member.starts_with('/') || member.starts_with('\\') {
        return Err(format!("Unsafe absolute path in archive: {member}"));
    }
    let bytes = member.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        return Err(format!("Unsafe drive path in archive: {member}"));
    }
    for comp in member.split(['/', '\\']) {
        if comp == ".." {
            return Err(format!("Unsafe parent traversal in archive: {member}"));
        }
    }
    Ok(())
}

pub fn check_relative_within_root(member_path: &str, target: &str) -> Result<(), String> {
    if target.contains('\0') {
        return Err("Archive contains NUL byte in link target".to_string());
    }
    if target.starts_with('/') || target.starts_with('\\') {
        return Err(format!("Unsafe absolute link target in archive: {target}"));
    }
    let bytes = target.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        return Err(format!("Unsafe drive link target in archive: {target}"));
    }
    let parent = Path::new(member_path)
        .parent()
        .unwrap_or_else(|| Path::new(""));
    let mut depth: isize = 0;
    for comp in parent.components() {
        match comp {
            std::path::Component::Normal(_) => depth += 1,
            std::path::Component::CurDir => {}
            _ => return Err(format!("Unsafe archive member path: {member_path}")),
        }
    }
    for comp in target.split(['/', '\\']) {
        if comp.is_empty() || comp == "." {
            continue;
        }
        if comp == ".." {
            depth -= 1;
            if depth < 0 {
                return Err(format!(
                    "Unsafe link target escapes archive root: {member_path} -> {target}"
                ));
            }
        } else {
            depth += 1;
        }
    }
    Ok(())
}

fn validate_archive_before_extract(archive: &Path, is_zip: bool) -> Result<(), String> {
    if is_zip {
        let list_out = Command::new("unzip")
            .args(["-Z1", "--"])
            .arg(archive)
            .stdin(Stdio::null())
            .stderr(Stdio::piped())
            .output()
            .map_err(|e| format!("Failed to inspect zip archive: {e}"))?;
        if !list_out.status.success() {
            let msg = String::from_utf8_lossy(&list_out.stderr).trim().to_string();
            return Err(if msg.is_empty() {
                "Failed to list zip archive entries".to_string()
            } else {
                msg
            });
        }
        let text = String::from_utf8_lossy(&list_out.stdout);
        for line in text.lines() {
            let m = line.trim_end_matches('\r');
            validate_archive_member(m)?;
        }
        // Reject symlinks inside untrusted zip archives if zipinfo shows symlink mode.
        if let Ok(detail_out) = Command::new("unzip")
            .args(["-Z", "--"])
            .arg(archive)
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
        {
            if detail_out.status.success() {
                let dtxt = String::from_utf8_lossy(&detail_out.stdout);
                for line in dtxt.lines() {
                    let trimmed = line.trim_start();
                    if let Some(first_tok) = trimmed.split_whitespace().next() {
                        if first_tok.len() == 10 && first_tok.starts_with('l') {
                            return Err("Refusing to extract symlink from zip archive".to_string());
                        }
                    }
                }
            }
        }
        return Ok(());
    }

    let tf_out = Command::new("tar")
        .arg("-tf")
        .arg(archive)
        .stdin(Stdio::null())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| format!("Failed to inspect tar archive: {e}"))?;
    if !tf_out.status.success() {
        let msg = String::from_utf8_lossy(&tf_out.stderr).trim().to_string();
        return Err(if msg.is_empty() {
            "Failed to list tar archive entries".to_string()
        } else {
            msg
        });
    }
    let tf_text = String::from_utf8_lossy(&tf_out.stdout);
    let tf_lines: Vec<&str> = tf_text.lines().collect();
    for m in &tf_lines {
        validate_archive_member(m)?;
    }

    let tvf_out = Command::new("tar")
        .arg("-tvf")
        .arg(archive)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|e| format!("Failed to verify tar archive links: {e}"))?;
    if tvf_out.status.success() {
        let tvf_text = String::from_utf8_lossy(&tvf_out.stdout);
        let tvf_lines: Vec<&str> = tvf_text.lines().collect();
        for (idx, line) in tvf_lines.iter().enumerate() {
            if line.starts_with('l') {
                let member_opt = tf_lines.get(idx).copied();
                let target_opt = member_opt
                    .and_then(|m| {
                        let pat = format!(" {m} -> ");
                        line.find(&pat).map(|pos| &line[pos + pat.len()..])
                    })
                    .or_else(|| line.rsplit_once(" -> ").map(|(_, t)| t));
                if let Some(target) = target_opt {
                    if let Some(m) = member_opt {
                        check_relative_within_root(m, target)?;
                    } else {
                        validate_archive_member(target)?;
                    }
                }
            } else if line.starts_with('h') {
                if let Some((_, target)) = line.rsplit_once(" link to ") {
                    validate_archive_member(target)?;
                }
            }
        }
    }
    Ok(())
}

pub fn compress_paths(
    raw_sources: &[String],
    raw_dest_dir: &str,
    archive_name: &str,
    format: &str,
) -> Result<String, String> {
    if raw_sources.is_empty() {
        return Err("No items selected to compress".to_string());
    }
    let clean_name = archive_name.trim();
    if clean_name.is_empty()
        || clean_name == "."
        || clean_name == ".."
        || clean_name.starts_with('-')
        || clean_name.contains('/')
        || clean_name.contains('\0')
    {
        return Err("Invalid archive name".to_string());
    }
    let dest_dir = expand_path(raw_dest_dir);
    let fmt = format.trim().to_ascii_lowercase();
    let use_zip = fmt == "zip" || clean_name.ends_with(".zip");
    let final_name = if use_zip {
        if clean_name.ends_with(".zip") {
            clean_name.to_string()
        } else {
            format!("{clean_name}.zip")
        }
    } else if clean_name.ends_with(".tar.gz") || clean_name.ends_with(".tgz") {
        clean_name.to_string()
    } else {
        format!("{clean_name}.tar.gz")
    };
    let archive_path = unique_dest_path(&dest_dir.join(final_name));
    let first_src = expand_path(&raw_sources[0]);
    let base_dir = first_src.parent().unwrap_or(&dest_dir);

    let mut rel_items = Vec::with_capacity(raw_sources.len());
    for raw in raw_sources {
        let p = expand_path(raw);
        if fs::symlink_metadata(&p).is_err() {
            return Err(format!("Source not found: {}", p.display()));
        }
        let rel = p
            .strip_prefix(base_dir)
            .map(|r| r.to_string_lossy().into_owned())
            .unwrap_or_else(|_| p.to_string_lossy().into_owned());
        let safe_rel = if rel.starts_with('-') {
            format!("./{rel}")
        } else {
            rel
        };
        rel_items.push(safe_rel);
    }

    let status = if use_zip {
        Command::new("zip")
            .arg("-rq")
            .arg(&archive_path)
            .arg("--")
            .args(&rel_items)
            .current_dir(base_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
    } else {
        Command::new("tar")
            .arg("-czf")
            .arg(&archive_path)
            .arg("--")
            .args(&rel_items)
            .current_dir(base_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
    }
    .map_err(|e| format!("Failed to invoke archiver: {e}"))?;

    if !status.status.success() {
        let err_msg = String::from_utf8_lossy(&status.stderr).trim().to_string();
        return Err(if err_msg.is_empty() {
            "Archive creation failed".to_string()
        } else {
            err_msg
        });
    }

    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("path", &archive_path.to_string_lossy());
    out.obj_end();
    Ok(out.finish())
}

pub fn extract_archive(raw_archive: &str, raw_dest_dir: Option<&str>) -> Result<String, String> {
    let archive = expand_path(raw_archive);
    if !archive.is_file() {
        return Err(format!("Archive does not exist: {}", archive.display()));
    }
    let fname = archive
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("extracted");
    let lower = fname.to_ascii_lowercase();
    let is_zip = lower.ends_with(".zip");

    // Pre-validate against Zip Slip / Tar Slip path traversal and symlink escapes.
    validate_archive_before_extract(&archive, is_zip)?;

    let parent = match raw_dest_dir.map(str::trim).filter(|s| !s.is_empty()) {
        Some(d) => expand_path(d),
        None => archive
            .parent()
            .unwrap_or_else(|| Path::new("/"))
            .to_path_buf(),
    };
    let folder_stem = fname
        .strip_suffix(".tar.gz")
        .or_else(|| fname.strip_suffix(".tar.xz"))
        .or_else(|| fname.strip_suffix(".tar.bz2"))
        .or_else(|| fname.strip_suffix(".tar.zst"))
        .or_else(|| fname.strip_suffix(".tgz"))
        .or_else(|| fname.strip_suffix(".zip"))
        .or_else(|| fname.strip_suffix(".tar"))
        .unwrap_or("extracted");
    let safe_stem = if folder_stem.is_empty() || folder_stem == "." || folder_stem == ".." {
        "extracted"
    } else {
        folder_stem
    };
    let out_dir = unique_dest_path(&parent.join(safe_stem));
    fs::create_dir_all(&out_dir).map_err(|e| format!("Create extract dir: {e}"))?;

    let res = if is_zip {
        Command::new("unzip")
            .arg("-oq")
            .arg("--")
            .arg(&archive)
            .arg("-d")
            .arg(&out_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
    } else {
        Command::new("tar")
            .args(["--no-same-owner", "--no-same-permissions", "-xf"])
            .arg(&archive)
            .arg("-C")
            .arg(&out_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
    };

    let output = match res {
        Ok(o) => o,
        Err(e) => {
            let _ = fs::remove_dir(&out_dir);
            return Err(format!("Failed to invoke extractor: {e}"));
        }
    };

    if !output.status.success() {
        let _ = fs::remove_dir(&out_dir);
        let msg = String::from_utf8_lossy(&output.stderr).trim().to_string();
        return Err(if msg.is_empty() {
            "Extraction failed".to_string()
        } else {
            msg
        });
    }

    let mut out = JsonOut::new();
    out.obj_start();
    out.kv_str("path", &out_dir.to_string_lossy());
    out.obj_end();
    Ok(out.finish())
}

pub fn copy_uri(raw_paths: &[String]) -> Result<String, String> {
    if raw_paths.is_empty() {
        return Err("No paths specified".to_string());
    }
    let mut payload = String::new();
    for raw in raw_paths {
        let p = expand_path(raw);
        let abs = fs::canonicalize(&p).unwrap_or(p);
        let enc = percent_encode_path(&abs.to_string_lossy());
        payload.push_str("file://");
        payload.push_str(&enc);
        payload.push_str("\r\n");
    }
    let mut child = Command::new("wl-copy")
        .args(["-t", "text/uri-list"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("wl-copy unavailable: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(payload.as_bytes());
    }
    let _ = child.wait();
    Ok("{\"copied\":true}".to_string())
}

pub fn copy_text(text: &str) -> Result<String, String> {
    let mut child = Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("wl-copy unavailable: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(text.as_bytes());
    }
    let _ = child.wait();
    Ok("{\"copied\":true}".to_string())
}

pub fn open_path(raw_path: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    Command::new("xdg-open")
        .arg(&target)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("xdg-open failed: {e}"))?;
    Ok("{\"launched\":true}".to_string())
}

pub fn open_with(raw_path: &str, program: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let parts: Vec<&str> = program.split_whitespace().collect();
    let Some((exe, args)) = parts.split_first() else {
        return Err("No application configured".to_string());
    };
    if exe.starts_with('-') {
        return Err("Invalid application executable".to_string());
    }
    Command::new(exe)
        .args(args)
        .arg(&target)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Launch '{exe}' failed: {e}"))?;
    Ok("{\"launched\":true}".to_string())
}

pub fn open_terminal(raw_dir: &str, preferred: Option<&str>) -> Result<String, String> {
    let dir = expand_path(raw_dir);
    let mut candidates: Vec<&str> = Vec::new();
    if let Some(p) = preferred
        .map(str::trim)
        .filter(|s| !s.is_empty() && !s.starts_with('-') && !s.contains('/'))
    {
        candidates.push(p);
    }
    for fb in [
        "foot",
        "kitty",
        "alacritty",
        "wezterm",
        "ghostty",
        "konsole",
        "xterm",
    ] {
        if !candidates.contains(&fb) {
            candidates.push(fb);
        }
    }

    for term in candidates {
        let mut cmd = match term {
            "foot" => {
                let mut c = Command::new("foot");
                c.arg("-D").arg(&dir);
                c
            }
            "kitty" => {
                let mut c = Command::new("kitty");
                c.arg("--directory").arg(&dir);
                c
            }
            "alacritty" => {
                let mut c = Command::new("alacritty");
                c.arg("--working-directory").arg(&dir);
                c
            }
            "wezterm" => {
                let mut c = Command::new("wezterm");
                c.args(["start", "--cwd"]).arg(&dir);
                c
            }
            other => {
                let mut c = Command::new(other);
                c.current_dir(&dir);
                c
            }
        };
        if cmd
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .is_ok()
        {
            return Ok(format!("{{\"launched\":\"{term}\"}}"));
        }
    }
    Err("No terminal emulator found".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

    fn make_temp_dir(tag: &str) -> PathBuf {
        let seq = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
        let dir =
            std::env::temp_dir().join(format!("mango_fm_ops_{tag}_{}_{seq}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    #[test]
    fn archive_member_security_checks() {
        assert!(validate_archive_member("folder/file.txt").is_ok());
        assert!(validate_archive_member("a..b/c.txt").is_ok());
        assert!(validate_archive_member("/etc/passwd").is_err());
        assert!(validate_archive_member("\\Windows\\System32").is_err());
        assert!(validate_archive_member("C:evil.txt").is_err());
        assert!(validate_archive_member("../escape.txt").is_err());
        assert!(validate_archive_member("sub/../../escape.txt").is_err());
        assert!(validate_archive_member("bad\0name").is_err());

        assert!(check_relative_within_root("usr/bin/app", "../lib/libfoo.so").is_ok());
        assert!(check_relative_within_root("bin/app", "../../etc/passwd").is_err());
        assert!(check_relative_within_root("app", "/etc/passwd").is_err());
    }

    #[test]
    fn compress_rejects_flag_archive_name() {
        let res = compress_paths(&["/tmp/a".to_string()], "/tmp", "--checkpoint=1", "tar.gz");
        assert!(res.is_err());
    }

    #[test]
    fn cross_dir_copy_move_and_unique_dest() {
        let base = make_temp_dir("copy_move");
        let src_dir = base.join("src");
        let dst_dir = base.join("dst");
        fs::create_dir_all(src_dir.join("nested")).unwrap();
        fs::create_dir_all(&dst_dir).unwrap();
        fs::write(src_dir.join("hello.txt"), b"world").unwrap();
        fs::write(src_dir.join("nested/inner.txt"), b"42").unwrap();

        let srcs = vec![
            src_dir.join("hello.txt").to_string_lossy().into_owned(),
            src_dir.join("nested").to_string_lossy().into_owned(),
        ];
        copy_or_move(
            &srcs,
            &dst_dir.to_string_lossy(),
            false,
            false,
            |_, _, _| {},
        )
        .expect("copy succeeds");
        assert_eq!(fs::read(dst_dir.join("hello.txt")).unwrap(), b"world");
        assert_eq!(fs::read(dst_dir.join("nested/inner.txt")).unwrap(), b"42");

        // Second copy without overwrite gets unique "(copy)" suffix
        copy_or_move(
            &[src_dir.join("hello.txt").to_string_lossy().into_owned()],
            &dst_dir.to_string_lossy(),
            false,
            false,
            |_, _, _| {},
        )
        .expect("unique copy succeeds");
        assert!(dst_dir.join("hello (copy).txt").is_file());

        // Move removes original file
        copy_or_move(
            &[src_dir.join("hello.txt").to_string_lossy().into_owned()],
            &dst_dir.to_string_lossy(),
            true,
            true,
            |_, _, _| {},
        )
        .expect("move with overwrite succeeds");
        assert!(!src_dir.join("hello.txt").exists());
        assert_eq!(fs::read(dst_dir.join("hello.txt")).unwrap(), b"world");

        let _ = fs::remove_dir_all(&base);
    }
}
