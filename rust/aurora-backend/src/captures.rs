use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, UNIX_EPOCH};

use crate::json::{self, JsonOut};
use crate::util::{
    atomic_write, config_dir, current_uid, data_dir, expand_user_path, format_age, human_size,
    now_unix_secs, percent_encode_path, proc_uid_and_comm, runtime_dir, unix_secs_to_iso,
    validate_basename, which, FileLock,
};

const MAX_COPY_IMAGE_BYTES: u64 = 64 * 1024 * 1024;
const MAX_PPM_STDIN_BYTES: usize = 65_536;

pub struct CapturePrefs {
    pub screenshot_dir: PathBuf,
    pub recording_dir: PathBuf,
    pub copy_clipboard: bool,
    pub notify: bool,
    pub delay_sec: u64,
    pub sel_border: String,
    pub sel_fill: String,
}

fn load_prefs() -> CapturePrefs {
    let qs_dir = config_dir().join("quickshell");
    let prefs_path = qs_dir.join("shell-prefs.json");
    let colors_path = qs_dir.join("colors.json");

    let mut screenshot_raw = "~/Pictures/Screenshots".to_string();
    let mut recording_raw = "~/Videos/Recordings".to_string();
    let mut copy_clipboard = true;
    let mut notify = true;
    let mut delay_sec = 0u64;

    if let Ok(raw) = fs::read_to_string(&prefs_path) {
        if let Ok(val) = json::parse(&raw) {
            if let Some(s) = val.get_str("screenshotDir") {
                if !s.trim().is_empty() {
                    screenshot_raw = s.to_string();
                }
            }
            if let Some(r) = val.get_str("recordingDir") {
                if !r.trim().is_empty() {
                    recording_raw = r.to_string();
                }
            }
            if let Some(b) = val.get_bool("screenshotCopyClipboard") {
                copy_clipboard = b;
            }
            if let Some(b) = val.get_bool("screenshotNotify") {
                notify = b;
            }
            if let Some(d) = val.get_u64("screenshotDelay") {
                delay_sec = d.min(10);
            }
        }
    }

    let screenshot_dir = expand_user_path(&screenshot_raw, "Pictures/Screenshots")
        .unwrap_or_else(|_| crate::util::home_dir().join("Pictures/Screenshots"));
    let recording_dir = expand_user_path(&recording_raw, "Videos/Recordings")
        .unwrap_or_else(|_| crate::util::home_dir().join("Videos/Recordings"));

    let mut primary_hex = "cba6f7".to_string();
    if let Ok(raw) = fs::read_to_string(&colors_path) {
        if let Ok(val) = json::parse(&raw) {
            if let Some(p) = val.get_str("primary") {
                let clean = p.trim().trim_start_matches('#');
                if clean.len() == 6 && clean.bytes().all(|b| b.is_ascii_hexdigit()) {
                    primary_hex = clean.to_ascii_lowercase();
                }
            }
        }
    }

    CapturePrefs {
        screenshot_dir,
        recording_dir,
        copy_clipboard,
        notify,
        delay_sec,
        sel_border: format!("#{primary_hex}ff"),
        sel_fill: format!("#{primary_hex}24"),
    }
}

pub fn parse_png_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    const SIG: &[u8; 8] = b"\x89PNG\r\n\x1a\n";
    if bytes.len() < 24 || &bytes[..8] != SIG {
        return None;
    }
    if &bytes[12..16] != b"IHDR" {
        return None;
    }
    let w = u32::from_be_bytes([bytes[16], bytes[17], bytes[18], bytes[19]]);
    let h = u32::from_be_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]);
    if w == 0 || h == 0 {
        return None;
    }
    Some((w, h))
}

fn read_png_dims_from_file(path: &Path) -> (u32, u32) {
    let Ok(mut f) = File::open(path) else {
        return (0, 0);
    };
    let mut buf = [0u8; 24];
    if f.read_exact(&mut buf).is_err() {
        return (0, 0);
    }
    parse_png_dimensions(&buf).unwrap_or((0, 0))
}

struct CaptureEntry {
    name: String,
    kind: &'static str,
    path: PathBuf,
    dir_path: PathBuf,
    size_bytes: u64,
    width: u32,
    height: u32,
    mtime_sec: i64,
}

fn file_ext_lower(name: &str) -> String {
    match name.rfind('.') {
        Some(idx) if idx + 1 < name.len() => name[idx + 1..].to_ascii_lowercase(),
        _ => String::new(),
    }
}

fn scan_capture_dir(
    dir: &Path,
    expected_kind: &'static str,
    seen: &mut HashSet<PathBuf>,
    out: &mut Vec<CaptureEntry>,
) {
    let Ok(rd) = fs::read_dir(dir) else {
        return;
    };
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') || validate_basename(&name).is_err() {
            continue;
        }
        let path = ent.path();
        if !seen.insert(path.clone()) {
            continue;
        }
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if meta.file_type().is_symlink() || !meta.is_file() {
            continue;
        }
        let ext = file_ext_lower(&name);
        let matches = match expected_kind {
            "screenshot" => matches!(ext.as_str(), "png" | "jpg" | "jpeg" | "webp"),
            "recording" => matches!(ext.as_str(), "mp4" | "mkv" | "webm"),
            _ => false,
        };
        if !matches {
            continue;
        }
        let (width, height) = if ext == "png" {
            read_png_dims_from_file(&path)
        } else {
            (0, 0)
        };
        let mtime_sec = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        out.push(CaptureEntry {
            name,
            kind: expected_kind,
            path,
            dir_path: dir.to_path_buf(),
            size_bytes: meta.len(),
            width,
            height,
            mtime_sec,
        });
    }
}

fn build_list_json(limit: usize) -> String {
    let prefs = load_prefs();
    let mut entries = Vec::new();
    let mut seen = HashSet::new();
    scan_capture_dir(&prefs.screenshot_dir, "screenshot", &mut seen, &mut entries);
    scan_capture_dir(&prefs.recording_dir, "recording", &mut seen, &mut entries);

    entries.sort_by(|a, b| {
        b.mtime_sec
            .cmp(&a.mtime_sec)
            .then_with(|| b.name.cmp(&a.name))
    });

    let mut screenshot_count = 0u64;
    let mut recording_count = 0u64;
    let mut total_bytes = 0u64;
    for e in &entries {
        if e.kind == "screenshot" {
            screenshot_count += 1;
        } else {
            recording_count += 1;
        }
        total_bytes = total_bytes.saturating_add(e.size_bytes);
    }

    let now = now_unix_secs();
    let shown = entries.into_iter().take(limit);

    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("screenshotDir", &prefs.screenshot_dir.to_string_lossy());
    o.kv_str("recordingDir", &prefs.recording_dir.to_string_lossy());
    o.kv_u64("screenshotCount", screenshot_count);
    o.kv_u64("recordingCount", recording_count);
    o.kv_u64("totalBytes", total_bytes);
    o.kv_str("totalSizeLabel", &human_size(total_bytes));
    o.key("items");
    o.arr_start();
    for e in shown {
        o.obj_start();
        o.kv_str("name", &e.name);
        o.kv_str("kind", e.kind);
        o.kv_str("path", &e.path.to_string_lossy());
        o.kv_str("dirPath", &e.dir_path.to_string_lossy());
        o.kv_u64("sizeBytes", e.size_bytes);
        o.kv_str("sizeLabel", &human_size(e.size_bytes));
        o.kv_u64("width", e.width as u64);
        o.kv_u64("height", e.height as u64);
        o.kv_i64("mtimeSec", e.mtime_sec);
        o.kv_str("ageLabel", &format_age(e.mtime_sec, now));
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    o.finish()
}

fn resolve_capture_target(kind: &str, filename: &str) -> Result<PathBuf, String> {
    if kind != "screenshot" && kind != "recording" {
        return Err("Capture kind must be 'screenshot' or 'recording'".to_string());
    }
    let clean_name = validate_basename(filename)?;
    let prefs = load_prefs();
    let base_dir = if kind == "screenshot" {
        prefs.screenshot_dir
    } else {
        prefs.recording_dir
    };
    let target = base_dir.join(clean_name);
    let meta =
        fs::symlink_metadata(&target).map_err(|_| format!("Capture '{clean_name}' not found"))?;
    if meta.file_type().is_symlink() || !meta.is_file() {
        return Err("Refusing symlink or non-regular file".to_string());
    }
    Ok(target)
}

fn cmd_prefs(tsv: bool) {
    let prefs = load_prefs();
    if tsv {
        println!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}",
            prefs.screenshot_dir.to_string_lossy(),
            if prefs.copy_clipboard { 1 } else { 0 },
            if prefs.notify { 1 } else { 0 },
            prefs.delay_sec,
            prefs.sel_border,
            prefs.sel_fill,
            prefs.recording_dir.to_string_lossy()
        );
        return;
    }
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("screenshotDir", &prefs.screenshot_dir.to_string_lossy());
    o.kv_str("recordingDir", &prefs.recording_dir.to_string_lossy());
    o.kv_bool("copyClipboard", prefs.copy_clipboard);
    o.kv_bool("notify", prefs.notify);
    o.kv_u64("delaySec", prefs.delay_sec);
    o.kv_str("selBorder", &prefs.sel_border);
    o.kv_str("selFill", &prefs.sel_fill);
    o.obj_end();
    println!("{}", o.finish());
}

fn cmd_copy(kind: &str, filename: &str) -> Result<(), String> {
    let target = resolve_capture_target(kind, filename)?;
    if which("wl-copy").is_none() {
        return Err("wl-copy is required".to_string());
    }
    let ext = file_ext_lower(filename);
    let meta = fs::symlink_metadata(&target).map_err(|e| format!("Stat failed: {e}"))?;
    let mut child = if kind == "screenshot" && ext == "png" && meta.len() <= MAX_COPY_IMAGE_BYTES {
        Command::new("wl-copy")
            .args(["--type", "image/png"])
            .stdin(Stdio::piped())
            .spawn()
            .map_err(|e| format!("wl-copy spawn failed: {e}"))?
    } else {
        Command::new("wl-copy")
            .args(["--type", "text/plain"])
            .stdin(Stdio::piped())
            .spawn()
            .map_err(|e| format!("wl-copy spawn failed: {e}"))?
    };

    if let Some(mut sin) = child.stdin.take() {
        if kind == "screenshot" && ext == "png" && meta.len() <= MAX_COPY_IMAGE_BYTES {
            let bytes = fs::read(&target).map_err(|e| format!("Read failed: {e}"))?;
            let _ = sin.write_all(&bytes);
        } else {
            let _ = sin.write_all(target.to_string_lossy().as_bytes());
        }
    }
    let status = child
        .wait()
        .map_err(|e| format!("wl-copy wait failed: {e}"))?;
    if !status.success() {
        return Err("wl-copy exited with non-zero status".to_string());
    }

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("copied", &target.to_string_lossy());
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn unique_trash_name(files_dir: &Path, info_dir: &Path, base_name: &str) -> String {
    let stem_ext = match base_name.rfind('.') {
        Some(idx) if idx > 0 => (&base_name[..idx], Some(&base_name[idx..])),
        _ => (base_name, None),
    };
    let mut n = 0u32;
    loop {
        let cand = if n == 0 {
            base_name.to_string()
        } else if let Some(ext) = stem_ext.1 {
            format!("{}.{n}{ext}", stem_ext.0)
        } else {
            format!("{base_name}.{n}")
        };
        let fp = files_dir.join(&cand);
        let ip = info_dir.join(format!("{cand}.trashinfo"));
        if fs::symlink_metadata(&fp).is_err() && fs::symlink_metadata(&ip).is_err() {
            return cand;
        }
        n += 1;
    }
}

fn move_file_to_trash(src: &Path, trash_base: &Path, filename: &str) -> Result<(), String> {
    let files_dir = trash_base.join("files");
    let info_dir = trash_base.join("info");
    fs::create_dir_all(&files_dir).map_err(|e| format!("Trash files dir failed: {e}"))?;
    fs::create_dir_all(&info_dir).map_err(|e| format!("Trash info dir failed: {e}"))?;

    let trash_name = unique_trash_name(&files_dir, &info_dir, filename);
    let info_path = info_dir.join(format!("{trash_name}.trashinfo"));
    let dest_path = files_dir.join(&trash_name);

    let orig_abs = fs::canonicalize(src).unwrap_or_else(|_| src.to_path_buf());
    let encoded = percent_encode_path(&orig_abs.to_string_lossy());
    let del_date = unix_secs_to_iso(now_unix_secs());
    let info_body = format!("[Trash Info]\nPath={encoded}\nDeletionDate={del_date}\n");

    atomic_write(&info_path, info_body.as_bytes(), 0o600)?;
    if fs::rename(src, &dest_path).is_err() {
        if let Err(e) = fs::copy(src, &dest_path).and_then(|_| fs::remove_file(src)) {
            let _ = fs::remove_file(&dest_path);
            let _ = fs::remove_file(&info_path);
            return Err(format!("Failed moving capture to Trash: {e}"));
        }
    }
    Ok(())
}

fn cmd_trash(kind: &str, filename: &str) -> Result<(), String> {
    let target = resolve_capture_target(kind, filename)?;
    let trash_base = data_dir().join("Trash");
    move_file_to_trash(&target, &trash_base, filename)?;
    println!("{}", build_list_json(60));
    Ok(())
}

pub fn parse_ppm_p6_rgb(data: &[u8]) -> Result<(u8, u8, u8), String> {
    let mut i = 0usize;
    let n = data.len();
    let mut tokens: Vec<String> = Vec::with_capacity(4);
    while i < n && tokens.len() < 4 {
        while i < n && matches!(data[i], b' ' | b'\t' | b'\r' | b'\n') {
            i += 1;
        }
        if i < n && data[i] == b'#' {
            while i < n && data[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        let start = i;
        while i < n && !matches!(data[i], b' ' | b'\t' | b'\r' | b'\n' | b'#') {
            i += 1;
        }
        if i > start {
            tokens.push(String::from_utf8_lossy(&data[start..i]).into_owned());
        } else {
            break;
        }
    }
    if tokens.len() < 4 || tokens[0] != "P6" {
        return Err("Input is not binary P6 PPM".to_string());
    }
    let maxval: u32 = tokens[3].parse().map_err(|_| "Invalid PPM maxval")?;
    if maxval != 255 {
        return Err("Unsupported PPM maxval (expected 255)".to_string());
    }
    if i < n && matches!(data[i], b' ' | b'\t' | b'\r' | b'\n') {
        i += 1;
    }
    if i + 3 > n {
        return Err("PPM pixel data truncated".to_string());
    }
    Ok((data[i], data[i + 1], data[i + 2]))
}

fn cmd_ppm_hex(raw_hex: bool) -> Result<(), String> {
    let mut buf = Vec::new();
    io::stdin()
        .take(MAX_PPM_STDIN_BYTES as u64)
        .read_to_end(&mut buf)
        .map_err(|e| format!("Failed reading stdin: {e}"))?;
    let (r, g, b) = parse_ppm_p6_rgb(&buf)?;
    let hex = format!("#{r:02x}{g:02x}{b:02x}");
    if raw_hex {
        println!("{hex}");
        return Ok(());
    }
    let rgb = format!("rgb({r}, {g}, {b})");
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("hex", &hex);
    o.kv_str("rgb", &rgb);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_window_geom() -> Result<(), String> {
    if which("mmsg").is_none() {
        return Err("mmsg is not available".to_string());
    }
    let out = crate::util::run_stdout("mmsg", &["get", "focusing-client"])
        .ok_or_else(|| "No focused window".to_string())?;
    let val = json::parse(&out)?;
    if val.get("error").is_some_and(|v| match v {
        json::JsonVal::Bool(b) => *b,
        json::JsonVal::Str(s) => !s.is_empty(),
        json::JsonVal::Null => false,
        _ => true,
    }) {
        return Err("Focused window error".to_string());
    }
    let x = val.get_i64("x").unwrap_or(0);
    let y = val.get_i64("y").unwrap_or(0);
    let w = val.get_i64("width").unwrap_or(0);
    let h = val.get_i64("height").unwrap_or(0);
    if w <= 0 || h <= 0 {
        return Err("Invalid window geometry".to_string());
    }
    println!("{x},{y} {w}x{h}");
    Ok(())
}

fn rec_state_path() -> PathBuf {
    let rdir = runtime_dir();
    let _ = fs::create_dir_all(&rdir);
    if rdir.ends_with("quickshell") {
        let _ = fs::set_permissions(&rdir, fs::Permissions::from_mode(0o700));
    }
    rdir.join("aurora-recording.json")
}

fn is_valid_recorder_pid(pid: u64) -> bool {
    if pid <= 1 {
        return false;
    }
    let Some(my_uid) = current_uid() else {
        return false;
    };
    let Some((uid, comm)) = proc_uid_and_comm(pid) else {
        return false;
    };
    uid == my_uid && (comm == "wf-recorder" || comm == "gpu-screen-recorder")
}

fn read_verified_rec_state(state_path: &Path) -> Option<(u64, i64, String)> {
    let raw = fs::read_to_string(state_path).ok()?;
    let val = json::parse(&raw).ok()?;
    let pid = val.get_u64("pid")?;
    let started_at = val.get_i64("startedAt").unwrap_or(0);
    let file = val.get_str("file").unwrap_or("").to_string();
    if is_valid_recorder_pid(pid) {
        Some((pid, started_at, file))
    } else {
        let _ = fs::remove_file(state_path);
        None
    }
}

fn cmd_rec_state(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("status");
    let state_path = rec_state_path();

    match op {
        "status" => {
            let _lock = FileLock::acquire(&state_path)?;
            if let Some((pid, started_at, file)) = read_verified_rec_state(&state_path) {
                let elapsed = now_unix_secs().saturating_sub(started_at).max(0) as u64;
                let mut o = JsonOut::new();
                o.obj_start();
                o.kv_bool("active", true);
                o.kv_u64("pid", pid);
                o.kv_i64("startedAt", started_at);
                o.kv_u64("elapsed", elapsed);
                o.kv_str("file", &file);
                o.obj_end();
                println!("{}", o.finish());
            } else {
                println!("{{\"active\":false,\"elapsed\":0,\"file\":\"\"}}");
            }
            Ok(())
        }
        "write" => {
            let pid: u64 = args
                .get(1)
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| "Usage: captures rec-state write <pid> <filepath>".to_string())?;
            let raw_file = args
                .get(2)
                .ok_or_else(|| "Missing recording file path".to_string())?;
            if !is_valid_recorder_pid(pid) {
                return Err("Target PID is not an owned active recorder process".to_string());
            }
            let valid_file = expand_user_path(raw_file, "Videos/Recordings")?;
            let started_at = now_unix_secs();

            let mut o = JsonOut::new();
            o.obj_start();
            o.kv_bool("active", true);
            o.kv_u64("pid", pid);
            o.kv_i64("startedAt", started_at);
            o.kv_str("file", &valid_file.to_string_lossy());
            o.obj_end();
            let mut payload = o.finish();
            payload.push('\n');

            let _lock = FileLock::acquire(&state_path)?;
            let mut f = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .mode(0o600)
                .open(&state_path)
                .map_err(|e| format!("Failed opening rec state: {e}"))?;
            f.write_all(payload.as_bytes())
                .map_err(|e| format!("Failed writing rec state: {e}"))?;
            println!("{}", payload.trim());
            Ok(())
        }
        "stop" => {
            let print_path = args.get(1).map(String::as_str) == Some("--print-path");
            let _lock = FileLock::acquire(&state_path)?;
            let Some((pid, _, file)) = read_verified_rec_state(&state_path) else {
                let _ = fs::remove_file(&state_path);
                if print_path {
                    println!();
                } else {
                    println!("{{\"ok\":true,\"stopped\":false,\"file\":\"\"}}");
                }
                return Ok(());
            };

            let pid_s = pid.to_string();
            let _ = Command::new("kill")
                .args(["-s", "INT", "--", &pid_s])
                .status();
            for _ in 0..30 {
                if !is_valid_recorder_pid(pid) {
                    break;
                }
                thread::sleep(Duration::from_millis(100));
            }
            if is_valid_recorder_pid(pid) {
                let _ = Command::new("kill")
                    .args(["-s", "TERM", "--", &pid_s])
                    .status();
            }
            let _ = fs::remove_file(&state_path);

            if print_path {
                println!("{file}");
            } else {
                let mut o = JsonOut::new();
                o.obj_start();
                o.kv_bool("ok", true);
                o.kv_bool("stopped", true);
                o.kv_str("file", &file);
                o.obj_end();
                println!("{}", o.finish());
            }
            Ok(())
        }
        other => Err(format!("Unknown rec-state action '{other}'")),
    }
}

pub fn cmd_captures(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("list");
    let rest = args.get(1..).unwrap_or(&[]);

    match op {
        "prefs" => {
            let tsv = rest.first().map(String::as_str) == Some("--tsv");
            cmd_prefs(tsv);
            Ok(())
        }
        "list" => {
            let mut limit = 60usize;
            if rest.first().map(String::as_str) == Some("--limit") {
                if let Some(n) = rest.get(1).and_then(|s| s.parse::<usize>().ok()) {
                    limit = n.clamp(1, 200);
                }
            }
            println!("{}", build_list_json(limit));
            Ok(())
        }
        "copy" => {
            let kind = rest.first().map(String::as_str).unwrap_or("");
            let filename = rest.get(1).map(String::as_str).unwrap_or("");
            cmd_copy(kind, filename)
        }
        "trash" => {
            let kind = rest.first().map(String::as_str).unwrap_or("");
            let filename = rest.get(1).map(String::as_str).unwrap_or("");
            cmd_trash(kind, filename)
        }
        "ppm-hex" => {
            let raw_hex = rest.first().map(String::as_str) == Some("--raw");
            cmd_ppm_hex(raw_hex)
        }
        "window-geom" => cmd_window_geom(),
        "rec-state" => cmd_rec_state(rest),
        other => Err(format!("Unknown captures command '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_png_ihdr_dimensions() {
        let mut buf = vec![0u8; 24];
        buf[..8].copy_from_slice(b"\x89PNG\r\n\x1a\n");
        buf[12..16].copy_from_slice(b"IHDR");
        buf[16..20].copy_from_slice(&1920u32.to_be_bytes());
        buf[20..24].copy_from_slice(&1080u32.to_be_bytes());
        assert_eq!(parse_png_dimensions(&buf), Some((1920, 1080)));
        assert_eq!(parse_png_dimensions(b"not a png"), None);
    }

    #[test]
    fn parses_ppm_p6_with_comments() {
        let mut ppm = b"P6\n# grim pixel capture\n1 1\n255\n".to_vec();
        ppm.extend_from_slice(&[0xCB, 0xA6, 0xF7]);
        let (r, g, b) = parse_ppm_p6_rgb(&ppm).expect("ppm parses");
        assert_eq!((r, g, b), (0xCB, 0xA6, 0xF7));
    }

    #[test]
    fn moves_regular_file_to_trash_safely() {
        let base = std::env::temp_dir().join(format!("aurora_cap_trash_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let src_dir = base.join("shots");
        let trash_dir = base.join("Trash");
        fs::create_dir_all(&src_dir).unwrap();
        let shot = src_dir.join("test_shot.png");
        fs::write(&shot, b"pngbytes").unwrap();

        move_file_to_trash(&shot, &trash_dir, "test_shot.png").expect("trash ok");
        assert!(!shot.exists());
        assert!(trash_dir.join("files/test_shot.png").is_file());
        let info = fs::read_to_string(trash_dir.join("info/test_shot.png.trashinfo")).unwrap();
        assert!(info.starts_with("[Trash Info]\nPath=/"));
        let _ = fs::remove_dir_all(&base);
    }
}
