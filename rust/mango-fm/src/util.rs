use std::cmp::Ordering;
use std::env;
use std::fs::File;
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn home_dir() -> PathBuf {
    env::var_os("HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

pub fn config_dir() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".config"))
}

pub fn data_dir() -> PathBuf {
    env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".local/share"))
}

pub fn normalize_lexical(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::Prefix(p) => out.push(p.as_os_str()),
            Component::RootDir => out.push(Component::RootDir.as_os_str()),
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() && !path.is_absolute() {
                    out.push("..");
                }
            }
            Component::Normal(seg) => out.push(seg),
        }
    }
    if out.as_os_str().is_empty() {
        if path.is_absolute() {
            PathBuf::from("/")
        } else {
            PathBuf::from(".")
        }
    } else {
        out
    }
}

pub fn expand_path(raw: &str) -> PathBuf {
    let trimmed = raw.trim();
    let home = home_dir();
    let expanded = if trimmed.is_empty() || trimmed == "~" {
        home
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        home.join(rest)
    } else if trimmed == "$HOME" {
        home
    } else if let Some(rest) = trimmed.strip_prefix("$HOME/") {
        home.join(rest)
    } else {
        let p = PathBuf::from(trimmed);
        if p.is_relative() {
            env::current_dir().unwrap_or(home).join(p)
        } else {
            p
        }
    };
    normalize_lexical(&expanded)
}

pub fn display_path(path: &Path) -> String {
    let home = home_dir();
    if let Ok(rel) = path.strip_prefix(&home) {
        if rel.as_os_str().is_empty() {
            "~".to_string()
        } else {
            format!("~/{}", rel.to_string_lossy())
        }
    } else {
        path.to_string_lossy().into_owned()
    }
}

pub fn human_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    if bytes < 1024 {
        return format!("{bytes} B");
    }
    let mut val = bytes as f64;
    let mut idx = 0usize;
    while val >= 1024.0 && idx + 1 < UNITS.len() {
        val /= 1024.0;
        idx += 1;
    }
    if val >= 100.0 {
        format!("{val:.0} {}", UNITS[idx])
    } else if val >= 10.0 {
        format!("{val:.1} {}", UNITS[idx])
    } else {
        format!("{val:.2} {}", UNITS[idx])
    }
}

pub fn format_mode(mode: u32, is_dir: bool, is_symlink: bool) -> String {
    let mut s = String::with_capacity(10);
    s.push(if is_symlink {
        'l'
    } else if is_dir {
        'd'
    } else {
        '-'
    });
    let bits = [
        (0o400, 'r'),
        (0o200, 'w'),
        (0o100, 'x'),
        (0o040, 'r'),
        (0o020, 'w'),
        (0o010, 'x'),
        (0o004, 'r'),
        (0o002, 'w'),
        (0o001, 'x'),
    ];
    for (mask, ch) in bits {
        s.push(if (mode & mask) != 0 { ch } else { '-' });
    }
    s
}

pub fn extract_ext(name: &str) -> String {
    let base = match name.rfind('/') {
        Some(idx) => &name[idx + 1..],
        None => name,
    };
    let clean = base.strip_prefix('.').unwrap_or(base);
    match clean.rfind('.') {
        Some(idx) if idx + 1 < clean.len() => clean[idx + 1..].to_ascii_lowercase(),
        _ => String::new(),
    }
}

pub fn classify_file(name: &str, is_dir: bool, is_exec: bool) -> (&'static str, String) {
    if is_dir {
        return ("dir", String::new());
    }
    let ext = extract_ext(name);
    let lower_name = name.to_ascii_lowercase();
    let cat = match ext.as_str() {
        "png" | "jpg" | "jpeg" | "webp" | "gif" | "bmp" | "svg" | "ico" | "avif" | "jxl"
        | "tiff" | "tif" => "image",
        "mp4" | "mkv" | "webm" | "mov" | "avi" | "flv" | "m4v" | "wmv" => "video",
        "mp3" | "flac" | "ogg" | "opus" | "wav" | "aac" | "m4a" | "wma" => "audio",
        "zip" | "tar" | "gz" | "tgz" | "bz2" | "tbz2" | "xz" | "txz" | "zst" | "7z" | "rar" => {
            "archive"
        }
        "pdf" => "pdf",
        "ttf" | "otf" | "woff" | "woff2" => "font",
        "rs" | "qml" | "js" | "mjs" | "ts" | "tsx" | "jsx" | "py" | "sh" | "bash" | "zsh"
        | "fish" | "c" | "h" | "cpp" | "hpp" | "go" | "java" | "kt" | "lua" | "rb" | "php"
        | "css" | "scss" | "html" | "htm" | "xml" | "json" | "jsonc" | "toml" | "yaml" | "yml"
        | "ini" | "conf" | "cfg" | "nix" | "sql" | "vim" | "glsl" | "frag" | "vert" => "code",
        "md" | "txt" | "rst" | "org" | "log" | "csv" | "tsv" | "rtf" | "doc" | "docx"
        | "odt" => "doc",
        _ if lower_name == "makefile"
            || lower_name == "dockerfile"
            || lower_name == "cmakelists.txt"
            || lower_name == "cargo.lock" =>
        {
            "code"
        }
        _ if lower_name == "readme" || lower_name == "license" => "doc",
        _ if is_exec => "exec",
        _ => "file",
    };
    (cat, ext)
}

pub fn natural_cmp(a: &str, b: &str) -> Ordering {
    let ab = a.as_bytes();
    let bb = b.as_bytes();
    let mut i = 0usize;
    let mut j = 0usize;
    while i < ab.len() && j < bb.len() {
        let ac = ab[i];
        let bc = bb[j];
        if ac.is_ascii_digit() && bc.is_ascii_digit() {
            let mut ai = i;
            let mut bi = j;
            while ai < ab.len() && ab[ai].is_ascii_digit() {
                ai += 1;
            }
            while bi < bb.len() && bb[bi].is_ascii_digit() {
                bi += 1;
            }
            let a_trimmed = &ab[i..ai];
            let b_trimmed = &bb[j..bi];
            let a_nz = a_trimmed
                .iter()
                .position(|&c| c != b'0')
                .unwrap_or(a_trimmed.len());
            let b_nz = b_trimmed
                .iter()
                .position(|&c| c != b'0')
                .unwrap_or(b_trimmed.len());
            let a_num = &a_trimmed[a_nz..];
            let b_num = &b_trimmed[b_nz..];
            match a_num.len().cmp(&b_num.len()) {
                Ordering::Equal => match a_num.cmp(b_num) {
                    Ordering::Equal => {
                        if a_trimmed.len() != b_trimmed.len() {
                            return a_trimmed.len().cmp(&b_trimmed.len());
                        }
                    }
                    ord => return ord,
                },
                ord => return ord,
            }
            i = ai;
            j = bi;
        } else {
            let al = ac.to_ascii_lowercase();
            let bl = bc.to_ascii_lowercase();
            match al.cmp(&bl) {
                Ordering::Equal => {
                    i += 1;
                    j += 1;
                }
                ord => return ord,
            }
        }
    }
    match ab.len().cmp(&bb.len()) {
        Ordering::Equal => a.cmp(b),
        ord => ord,
    }
}

pub fn percent_encode_path(s: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut out = String::with_capacity(s.len());
    for &b in s.as_bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~' | b'/') {
            out.push(b as char);
        } else {
            out.push('%');
            out.push(HEX[(b >> 4) as usize] as char);
            out.push(HEX[(b & 0x0F) as usize] as char);
        }
    }
    out
}

pub fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(hi), Some(lo)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                out.push((hi << 4) | lo);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

pub fn now_unix_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Howard Hinnant civil-from-days algorithm in pure Rust (UTC ISO-8601 without Z, per XDG Trash spec)
pub fn unix_secs_to_iso(secs: i64) -> String {
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    let hour = rem / 3600;
    let min = (rem % 3600) / 60;
    let sec = rem % 60;

    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = y + if m <= 2 { 1 } else { 0 };
    format!("{year:04}-{m:02}-{d:02}T{hour:02}:{min:02}:{sec:02}")
}

pub fn image_dimensions(path: &Path) -> Option<(u32, u32)> {
    let mut f = File::open(path).ok()?;
    let mut buf = vec![0u8; 65536];
    let n = f.read(&mut buf).ok()?;
    buf.truncate(n);
    if buf.len() >= 24 && &buf[0..8] == b"\x89PNG\r\n\x1a\n" {
        let w = u32::from_be_bytes([buf[16], buf[17], buf[18], buf[19]]);
        let h = u32::from_be_bytes([buf[20], buf[21], buf[22], buf[23]]);
        return Some((w, h));
    }
    if buf.len() >= 10 && (&buf[0..6] == b"GIF87a" || &buf[0..6] == b"GIF89a") {
        let w = u16::from_le_bytes([buf[6], buf[7]]) as u32;
        let h = u16::from_le_bytes([buf[8], buf[9]]) as u32;
        return Some((w, h));
    }
    if buf.len() >= 26 && &buf[0..2] == b"BM" {
        let w = i32::from_le_bytes([buf[18], buf[19], buf[20], buf[21]]).unsigned_abs();
        let h = i32::from_le_bytes([buf[22], buf[23], buf[24], buf[25]]).unsigned_abs();
        return Some((w, h));
    }
    if buf.len() >= 30 && &buf[0..4] == b"RIFF" && &buf[8..12] == b"WEBP" {
        let chunk = &buf[12..16];
        if chunk == b"VP8X" {
            let w = 1 + (buf[24] as u32 | ((buf[25] as u32) << 8) | ((buf[26] as u32) << 16));
            let h = 1 + (buf[27] as u32 | ((buf[28] as u32) << 8) | ((buf[29] as u32) << 16));
            return Some((w, h));
        } else if chunk == b"VP8 " && buf.len() >= 30 {
            let w = (u16::from_le_bytes([buf[26], buf[27]]) & 0x3FFF) as u32;
            let h = (u16::from_le_bytes([buf[28], buf[29]]) & 0x3FFF) as u32;
            return Some((w, h));
        } else if chunk == b"VP8L" && buf.len() >= 25 {
            let bits = u32::from_le_bytes([buf[21], buf[22], buf[23], buf[24]]);
            let w = (bits & 0x3FFF) + 1;
            let h = ((bits >> 14) & 0x3FFF) + 1;
            return Some((w, h));
        }
    }
    if buf.len() >= 4 && buf[0] == 0xFF && buf[1] == 0xD8 {
        let mut i = 2usize;
        while i + 9 < buf.len() {
            if buf[i] != 0xFF {
                i += 1;
                continue;
            }
            while i < buf.len() && buf[i] == 0xFF {
                i += 1;
            }
            if i >= buf.len() {
                break;
            }
            let marker = buf[i];
            i += 1;
            if marker == 0xD9 || marker == 0xDA {
                break;
            }
            if marker == 0x01 || (0xD0..=0xD8).contains(&marker) {
                continue;
            }
            if i + 1 >= buf.len() {
                break;
            }
            let seg_len = u16::from_be_bytes([buf[i], buf[i + 1]]) as usize;
            if seg_len < 2 || i + seg_len > buf.len() {
                break;
            }
            if matches!(marker, 0xC0 | 0xC1 | 0xC2 | 0xC3 | 0xC5 | 0xC6 | 0xC7 | 0xC9 | 0xCA | 0xCB)
                && seg_len >= 7
            {
                let h = u16::from_be_bytes([buf[i + 3], buf[i + 4]]) as u32;
                let w = u16::from_be_bytes([buf[i + 5], buf[i + 6]]) as u32;
                return Some((w, h));
            }
            i += seg_len;
        }
    }
    None
}

pub fn mtime_secs(meta: &std::fs::Metadata) -> i64 {
    meta.mtime()
}

pub fn is_same_or_subpath(candidate_dest: &Path, src: &Path) -> bool {
    let d = normalize_lexical(candidate_dest);
    let s = normalize_lexical(src);
    d == s || d.starts_with(&s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn natural_sorting() {
        let mut items = ["img10.png", "img2.png", "img1.png", "Alpha.txt", "beta.txt"];
        items.sort_by(|a, b| natural_cmp(a, b));
        assert_eq!(items, ["Alpha.txt", "beta.txt", "img1.png", "img2.png", "img10.png"]);
    }

    #[test]
    fn percent_roundtrip() {
        let orig = "/home/test/My Folder/hello world #1 (test)%.png";
        let enc = percent_encode_path(orig);
        assert_eq!(percent_decode(&enc), orig);
    }

    #[test]
    fn size_formatting() {
        assert_eq!(human_size(512), "512 B");
        assert_eq!(human_size(2048), "2.00 KB");
        assert_eq!(human_size(15 * 1024 * 1024), "15.0 MB");
    }

    #[test]
    fn mode_formatting() {
        assert_eq!(format_mode(0o755, true, false), "drwxr-xr-x");
        assert_eq!(format_mode(0o644, false, false), "-rw-r--r--");
        assert_eq!(format_mode(0o777, false, true), "lrwxrwxrwx");
    }

    #[test]
    fn unix_epoch_iso() {
        assert_eq!(unix_secs_to_iso(0), "1970-01-01T00:00:00");
        assert_eq!(unix_secs_to_iso(1_700_000_000), "2023-11-14T22:13:20");
    }
}
