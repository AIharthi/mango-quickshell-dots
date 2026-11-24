use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
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

pub fn cache_dir() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".cache"))
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
