use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

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

pub fn cache_dir() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".cache"))
}

pub fn data_dir() -> PathBuf {
    env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".local/share"))
}

pub fn runtime_dir() -> PathBuf {
    env::var_os("XDG_RUNTIME_DIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| cache_dir().join("quickshell"))
}

pub struct FileLock(PathBuf);

impl FileLock {
    pub fn acquire(target_path: &Path) -> Result<Self, String> {
        let mut lock_os = target_path.as_os_str().to_os_string();
        lock_os.push(".lock");
        let lock_path = PathBuf::from(lock_os);
        if let Some(parent) = lock_path.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("Failed creating lock dir: {e}"))?;
        }
        for attempt in 0..40 {
            if OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&lock_path)
                .is_ok()
            {
                return Ok(Self(lock_path));
            }
            if attempt == 25 {
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
        Err(format!("Timed out acquiring lock {}", lock_path.display()))
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
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

pub fn expand_user_path(raw: &str, fallback_rel: &str) -> Result<PathBuf, String> {
    if raw.contains('\0') {
        return Err("Path contains NUL byte".to_string());
    }
    let home = home_dir();
    let trimmed = raw.trim();
    let candidate = if trimmed.is_empty() {
        home.join(fallback_rel)
    } else if trimmed == "~" || trimmed == "$HOME" {
        home.clone()
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        home.join(rest)
    } else if let Some(rest) = trimmed.strip_prefix("$HOME/") {
        home.join(rest)
    } else {
        PathBuf::from(trimmed)
    };

    for comp in candidate.components() {
        if matches!(comp, Component::ParentDir) {
            return Err("Parent traversal '..' is not allowed".to_string());
        }
    }
    if !candidate.is_absolute() {
        return Err("Path must be absolute or begin with ~/".to_string());
    }

    let norm = normalize_lexical(&candidate);
    let home_norm = normalize_lexical(&home);
    let tmp_norm = normalize_lexical(&env::temp_dir());
    let tmp_root = Path::new("/tmp");
    if !(norm.starts_with(&home_norm) || norm.starts_with(tmp_root) || norm.starts_with(&tmp_norm))
    {
        return Err("Path must stay inside home or /tmp".to_string());
    }

    if let Ok(canon) = fs::canonicalize(&norm) {
        let home_canon = fs::canonicalize(&home_norm).unwrap_or(home_norm);
        let tmp_canon = fs::canonicalize(tmp_root).unwrap_or_else(|_| PathBuf::from("/tmp"));
        let env_tmp_canon = fs::canonicalize(&tmp_norm).unwrap_or(tmp_norm);
        if !(canon.starts_with(&home_canon)
            || canon.starts_with(&tmp_canon)
            || canon.starts_with(&env_tmp_canon))
        {
            return Err("Symlink target resolves outside allowed directory".to_string());
        }
    }
    Ok(norm)
}

pub fn validate_basename(name: &str) -> Result<&str, String> {
    if name.is_empty() || name.len() > 240 {
        return Err("Invalid filename length".to_string());
    }
    if name == "." || name == ".." {
        return Err("Invalid relative filename".to_string());
    }
    if name.starts_with('-') || name.starts_with('.') {
        return Err("Filename cannot start with '-' or '.'".to_string());
    }
    if name.contains('/') || name.contains('\\') || name.contains('\0') {
        return Err("Filename contains illegal path characters".to_string());
    }
    Ok(name)
}

pub fn sanitize_id(s: &str, max_len: usize) -> Option<String> {
    let t = s.trim();
    if t.is_empty() || t.len() > max_len || t.starts_with('-') || t.contains("..") {
        return None;
    }
    if t.bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b'@' | b'-'))
    {
        Some(t.to_string())
    } else {
        None
    }
}

pub fn current_uid() -> Option<u32> {
    let txt = fs::read_to_string("/proc/self/status").ok()?;
    parse_proc_uid(&txt)
}

pub fn parse_proc_uid(status_txt: &str) -> Option<u32> {
    for line in status_txt.lines() {
        if let Some(rest) = line.strip_prefix("Uid:") {
            return rest.split_whitespace().next()?.parse::<u32>().ok();
        }
    }
    None
}

pub fn proc_uid_and_comm(pid: u64) -> Option<(u32, String)> {
    let status = fs::read_to_string(format!("/proc/{pid}/status")).ok()?;
    let uid = parse_proc_uid(&status)?;
    let comm = fs::read_to_string(format!("/proc/{pid}/comm"))
        .ok()?
        .trim()
        .to_string();
    Some((uid, comm))
}

pub fn now_unix_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

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

pub fn format_age(mtime_secs: i64, now_secs: i64) -> String {
    let diff = now_secs.saturating_sub(mtime_secs);
    if diff < 60 {
        "just now".to_string()
    } else if diff < 3600 {
        format!("{}m ago", diff / 60)
    } else if diff < 86400 {
        format!("{}h ago", diff / 3600)
    } else {
        format!("{}d ago", diff / 86400)
    }
}

pub fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

pub fn read_u64(path: &Path) -> Option<u64> {
    read_trimmed(path).and_then(|s| s.parse::<u64>().ok())
}

pub fn read_i64(path: &Path) -> Option<i64> {
    read_trimmed(path).and_then(|s| s.parse::<i64>().ok())
}

pub fn which(bin: &str) -> Option<PathBuf> {
    if bin.contains('/') {
        let p = PathBuf::from(bin);
        return is_executable(&p).then_some(p);
    }
    let path_var = env::var_os("PATH")?;
    for dir in env::split_paths(&path_var) {
        let candidate = dir.join(bin);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

pub fn is_executable(path: &Path) -> bool {
    let Ok(meta) = fs::metadata(path) else {
        return false;
    };
    meta.is_file() && (meta.permissions().mode() & 0o111 != 0)
}

pub fn run_stdout(bin: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(bin).args(args).output().ok()?;
    if out.status.success() {
        Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        None
    }
}

pub fn atomic_write(path: &Path, data: &[u8], mode: u32) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "Invalid destination path".to_string())?;
    fs::create_dir_all(parent).map_err(|e| format!("Failed creating directory: {e}"))?;
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let tmp = parent.join(format!(".tmp_{}_{nanos}", std::process::id()));
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(mode)
        .open(&tmp)
        .map_err(|e| format!("Failed creating temp file: {e}"))?;
    if let Err(e) = f.write_all(data).and_then(|_| f.flush()) {
        let _ = fs::remove_file(&tmp);
        return Err(format!("Write failed: {e}"));
    }
    drop(f);
    let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(mode));
    if let Err(e) = fs::rename(&tmp, path) {
        let _ = fs::remove_file(&tmp);
        return Err(format!("Rename failed: {e}"));
    }
    Ok(())
}

pub fn format_rate(bps: u64) -> String {
    if bps < 1024 {
        format!("{bps}B/s")
    } else if bps < 1024 * 1024 {
        let kb = (bps as f64) / 1024.0;
        if kb >= 100.0 {
            format!("{kb:.0}K/s")
        } else {
            format!("{kb:.1}K/s")
        }
    } else if bps < 1024 * 1024 * 1024 {
        let mb = (bps as f64) / (1024.0 * 1024.0);
        format!("{mb:.1}M/s")
    } else {
        let gb = (bps as f64) / (1024.0 * 1024.0 * 1024.0);
        format!("{gb:.1}G/s")
    }
}

pub fn format_uptime(secs: u64) -> String {
    let days = secs / 86400;
    let hours = (secs % 86400) / 3600;
    let mins = (secs % 3600) / 60;
    if days > 0 {
        format!("{days}d {hours}h")
    } else if hours > 0 {
        format!("{hours}h {mins}m")
    } else {
        format!("{}m", mins.max(1))
    }
}

#[derive(Debug, Clone)]
pub struct BatterySnapshot {
    pub has_battery: bool,
    pub count: usize,
    pub percent: u64,
    pub status: String,
    pub charging: bool,
    pub power_watts: f64,
    pub eta_label: String,
    pub health_percent: u64,
    pub paths: Vec<String>,
}

pub fn find_system_batteries() -> Vec<PathBuf> {
    let mut found = Vec::new();
    let Ok(rd) = fs::read_dir("/sys/class/power_supply") else {
        return found;
    };
    for ent in rd.flatten() {
        let p = ent.path();
        if read_trimmed(&p.join("type")).as_deref() == Some("Battery")
            && read_trimmed(&p.join("scope")).as_deref() != Some("Device")
        {
            found.push(p);
        }
    }
    found.sort();
    found
}

pub fn battery_snapshot() -> BatterySnapshot {
    let bats = find_system_batteries();
    if bats.is_empty() {
        return BatterySnapshot {
            has_battery: false,
            count: 0,
            percent: 100,
            status: "Full".to_string(),
            charging: false,
            power_watts: 0.0,
            eta_label: String::new(),
            health_percent: 100,
            paths: Vec::new(),
        };
    }

    let mut total_now: u64 = 0;
    let mut total_full: u64 = 0;
    let mut total_design: u64 = 0;
    let mut total_power_uw: f64 = 0.0;
    let mut cap_fallbacks: Vec<u64> = Vec::new();
    let mut statuses: Vec<String> = Vec::new();
    let mut paths: Vec<String> = Vec::new();

    for ps in &bats {
        paths.push(ps.to_string_lossy().into_owned());
        let st = read_trimmed(&ps.join("status"))
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "Unknown".to_string());
        statuses.push(st);

        if let Some(pw) = read_u64(&ps.join("power_now")) {
            total_power_uw += pw as f64;
        } else if let (Some(curr), Some(volt)) = (
            read_u64(&ps.join("current_now")),
            read_u64(&ps.join("voltage_now")),
        ) {
            total_power_uw += (curr as f64) * (volt as f64) / 1_000_000.0;
        }

        if let (Some(en), Some(ef)) = (
            read_u64(&ps.join("energy_now")),
            read_u64(&ps.join("energy_full")),
        ) {
            if ef > 0 {
                total_now = total_now.saturating_add(en);
                total_full = total_full.saturating_add(ef);
                if let Some(ed) = read_u64(&ps.join("energy_full_design")) {
                    total_design = total_design.saturating_add(ed);
                }
                continue;
            }
        }

        if let (Some(cn), Some(cf)) = (
            read_u64(&ps.join("charge_now")),
            read_u64(&ps.join("charge_full")),
        ) {
            if cf > 0 {
                let volt = read_u64(&ps.join("voltage_now")).unwrap_or(3_700_000);
                // Convert uAh * uV to approximate uWh for multi-battery aggregation
                total_now = total_now.saturating_add((cn.saturating_mul(volt)) / 1_000_000);
                total_full = total_full.saturating_add((cf.saturating_mul(volt)) / 1_000_000);
                if let Some(cd) = read_u64(&ps.join("charge_full_design")) {
                    total_design =
                        total_design.saturating_add((cd.saturating_mul(volt)) / 1_000_000);
                }
                continue;
            }
        }

        if let Some(cap) = read_u64(&ps.join("capacity")) {
            cap_fallbacks.push(cap.min(100));
        }
    }

    let pct = if total_full > 0 {
        (((total_now as f64) * 100.0) / (total_full as f64))
            .round()
            .clamp(0.0, 100.0) as u64
    } else if !cap_fallbacks.is_empty() {
        let sum: u64 = cap_fallbacks.iter().sum();
        ((sum as f64) / (cap_fallbacks.len() as f64))
            .round()
            .clamp(0.0, 100.0) as u64
    } else {
        100
    };

    let agg_status = if statuses.iter().any(|s| s == "Charging") {
        "Charging".to_string()
    } else if statuses.iter().any(|s| s == "Discharging") {
        "Discharging".to_string()
    } else if statuses.iter().any(|s| s == "Full") {
        "Full".to_string()
    } else {
        statuses
            .into_iter()
            .next()
            .unwrap_or_else(|| "Unknown".to_string())
    };
    let charging = agg_status == "Charging" || agg_status == "Full";
    let power_watts = total_power_uw / 1_000_000.0;

    let eta_label = if total_power_uw > 250_000.0 && total_full > 0 {
        let hours = if agg_status == "Discharging" {
            (total_now as f64) / total_power_uw
        } else if agg_status == "Charging" && total_full > total_now {
            ((total_full - total_now) as f64) / total_power_uw
        } else {
            0.0
        };
        if hours > 0.02 && hours < 48.0 {
            let mins = (hours * 60.0).round() as u64;
            let h = mins / 60;
            let m = mins % 60;
            if h > 0 {
                format!("{h}h {m}m")
            } else {
                format!("{m}m")
            }
        } else {
            String::new()
        }
    } else {
        String::new()
    };

    let health_percent = if total_design > 0 && total_full > 0 {
        (((total_full as f64) * 100.0) / (total_design as f64))
            .round()
            .clamp(1.0, 100.0) as u64
    } else {
        100
    };

    BatterySnapshot {
        has_battery: true,
        count: bats.len(),
        percent: pct,
        status: agg_status,
        charging,
        power_watts,
        eta_label,
        health_percent,
        paths,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basename_and_path_hardening() {
        assert!(validate_basename("shot_01.png").is_ok());
        assert!(validate_basename("").is_err());
        assert!(validate_basename("..").is_err());
        assert!(validate_basename("../evil.png").is_err());
        assert!(validate_basename("a/b.png").is_err());
        assert!(validate_basename("-rf").is_err());
        assert!(validate_basename(".hidden").is_err());
        assert!(validate_basename("a\0b.png").is_err());

        assert!(expand_user_path("~/Pictures/../.ssh", "Pictures").is_err());
        assert!(expand_user_path("/etc/passwd", "Pictures").is_err());
        assert!(expand_user_path("relative/path", "Pictures").is_err());
        assert!(expand_user_path("bad\0path", "Pictures").is_err());
        let ok_p = expand_user_path("~/Pictures/Screenshots", "Pictures/Screenshots")
            .expect("home path allowed");
        assert!(ok_p.ends_with("Pictures/Screenshots"));
    }

    #[test]
    fn sanitize_and_proc_uid_parsing() {
        assert_eq!(
            sanitize_id("NetworkManager", 80),
            Some("NetworkManager".to_string())
        );
        assert_eq!(
            sanitize_id("foo@1.service", 80),
            Some("foo@1.service".to_string())
        );
        assert_eq!(sanitize_id("-flag", 80), None);
        assert_eq!(sanitize_id("../bad", 80), None);
        assert_eq!(sanitize_id("a;rm", 80), None);

        let sample_status = "Name:\tqs\nUid:\t1000\t1000\t1000\t1000\nGid:\t1000\t1000\n";
        assert_eq!(parse_proc_uid(sample_status), Some(1000));
        assert!(current_uid().is_some());
    }
}
