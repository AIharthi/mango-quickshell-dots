use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::config::{PowerConfig, Profile};
use crate::json::JsonOut;

const CPUFREQ_BASE: &str = "/sys/devices/system/cpu/cpufreq";
const GLOBAL_BOOST_PATH: &str = "/sys/devices/system/cpu/cpufreq/boost";
const INTEL_NO_TURBO_PATH: &str = "/sys/devices/system/cpu/intel_pstate/no_turbo";
const PLATFORM_PROFILE_PATH: &str = "/sys/firmware/acpi/platform_profile";
const PLATFORM_CHOICES_PATH: &str = "/sys/firmware/acpi/platform_profile_choices";

pub fn read_trimmed(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
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

pub fn current_euid() -> Option<u32> {
    let txt = fs::read_to_string("/proc/self/status").ok()?;
    for line in txt.lines() {
        if let Some(rest) = line.strip_prefix("Uid:") {
            return rest.split_whitespace().nth(1)?.parse::<u32>().ok();
        }
    }
    None
}

pub fn detect_init_system() -> &'static str {
    if Path::new("/run/systemd/system").is_dir() {
        "systemd"
    } else if which("rc-service").is_some()
        || which("rc-status").is_some()
        || Path::new("/run/openrc").is_dir()
    {
        "openrc"
    } else {
        "unknown"
    }
}

pub fn is_daemon_installed() -> bool {
    Path::new("/etc/init.d/aurora-powerd").exists()
        || Path::new("/etc/systemd/system/aurora-powerd.service").exists()
}

pub fn query_powerprofilesctl() -> Option<String> {
    which("powerprofilesctl")?;
    let out = Command::new("powerprofilesctl").arg("get").output().ok()?;
    if !out.status.success() {
        return None;
    }
    let val = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if val.is_empty() {
        None
    } else {
        Some(val)
    }
}

fn list_cpufreq_policies() -> Vec<PathBuf> {
    let mut policies = Vec::new();
    let Ok(rd) = fs::read_dir(CPUFREQ_BASE) else {
        return policies;
    };
    for ent in rd.flatten() {
        let name = ent.file_name();
        let s = name.to_string_lossy();
        if s.starts_with("policy") && s["policy".len()..].chars().all(|c| c.is_ascii_digit()) {
            policies.push(ent.path());
        }
    }
    policies.sort();
    policies
}

fn list_gpu_dpm_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    let Ok(rd) = fs::read_dir("/sys/class/drm") else {
        return paths;
    };
    for ent in rd.flatten() {
        let name = ent.file_name();
        let s = name.to_string_lossy();
        if let Some(rest) = s.strip_prefix("card") {
            if !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()) {
                let dpm = ent.path().join("device/power_dpm_force_performance_level");
                if dpm.exists() {
                    paths.push(dpm);
                }
            }
        }
    }
    paths.sort();
    paths
}

pub fn detect_battery_and_ac() -> (bool, bool) {
    let mut has_battery = false;
    let mut mains_count = 0usize;
    let mut any_mains_online = false;

    if let Ok(rd) = fs::read_dir("/sys/class/power_supply") {
        for ent in rd.flatten() {
            let p = ent.path();
            match read_trimmed(&p.join("type")).as_deref() {
                Some("Battery") => {
                    if read_trimmed(&p.join("scope")).as_deref() != Some("Device") {
                        has_battery = true;
                    }
                }
                Some("Mains") => {
                    mains_count += 1;
                    if read_trimmed(&p.join("online")).as_deref() == Some("1") {
                        any_mains_online = true;
                    }
                }
                _ => {}
            }
        }
    }

    let on_ac = if mains_count == 0 {
        true
    } else {
        any_mains_online
    };
    (has_battery, on_ac)
}

#[derive(Debug, Clone)]
pub struct HardwareSnapshot {
    pub has_cpufreq: bool,
    pub driver: String,
    pub governor: String,
    pub epp: String,
    pub boost_supported: bool,
    pub boost_enabled: bool,
    pub has_platform_profile: bool,
    pub platform_profile: String,
    pub gpu_dpm_supported: bool,
    pub gpu_dpm_level: String,
    pub cpu_freq_mhz: u64,
    pub has_battery: bool,
    pub on_ac: bool,
}

pub fn snapshot_hardware() -> HardwareSnapshot {
    let policies = list_cpufreq_policies();
    let has_cpufreq = !policies.is_empty();
    let first_policy = policies.first();

    let driver = first_policy
        .and_then(|p| read_trimmed(&p.join("scaling_driver")))
        .unwrap_or_default();
    let governor = first_policy
        .and_then(|p| read_trimmed(&p.join("scaling_governor")))
        .unwrap_or_default();
    let epp = first_policy
        .and_then(|p| read_trimmed(&p.join("energy_performance_preference")))
        .unwrap_or_default();

    let (boost_supported, boost_enabled) = if Path::new(GLOBAL_BOOST_PATH).exists() {
        let en = read_trimmed(Path::new(GLOBAL_BOOST_PATH)).as_deref() == Some("1");
        (true, en)
    } else if Path::new(INTEL_NO_TURBO_PATH).exists() {
        let disabled = read_trimmed(Path::new(INTEL_NO_TURBO_PATH)).as_deref() == Some("1");
        (true, !disabled)
    } else if let Some(p) = first_policy.filter(|p| p.join("boost").exists()) {
        let en = read_trimmed(&p.join("boost")).as_deref() == Some("1");
        (true, en)
    } else {
        (false, false)
    };

    let has_platform_profile = Path::new(PLATFORM_PROFILE_PATH).exists();
    let platform_profile = if has_platform_profile {
        read_trimmed(Path::new(PLATFORM_PROFILE_PATH)).unwrap_or_default()
    } else {
        String::new()
    };

    let gpu_paths = list_gpu_dpm_paths();
    let gpu_dpm_supported = !gpu_paths.is_empty();
    let gpu_dpm_level = gpu_paths
        .first()
        .and_then(|p| read_trimmed(p))
        .unwrap_or_default();

    let mut freq_sum_khz = 0u64;
    let mut freq_count = 0u64;
    for p in &policies {
        if let Some(khz) =
            read_trimmed(&p.join("scaling_cur_freq")).and_then(|s| s.parse::<u64>().ok())
        {
            freq_sum_khz = freq_sum_khz.saturating_add(khz);
            freq_count += 1;
        }
    }
    let cpu_freq_mhz = freq_sum_khz
        .checked_div(freq_count)
        .map(|khz| khz / 1000)
        .unwrap_or(0);

    let (has_battery, on_ac) = detect_battery_and_ac();

    HardwareSnapshot {
        has_cpufreq,
        driver,
        governor,
        epp,
        boost_supported,
        boost_enabled,
        has_platform_profile,
        platform_profile,
        gpu_dpm_supported,
        gpu_dpm_level,
        cpu_freq_mhz,
        has_battery,
        on_ac,
    }
}

pub fn choose_governor(profile: Profile, driver: &str, available: &[String]) -> Option<String> {
    let is_pstate = driver.contains("pstate");
    let candidates: &[&str] = match profile {
        Profile::PowerSaver => &["powersave", "conservative", "schedutil"],
        Profile::Balanced => {
            if is_pstate {
                &["powersave", "schedutil", "ondemand"]
            } else {
                &["schedutil", "ondemand", "conservative", "powersave"]
            }
        }
        Profile::Performance => &["performance", "schedutil"],
    };
    for cand in candidates {
        if available.iter().any(|a| a == cand) {
            return Some((*cand).to_string());
        }
    }
    None
}

pub fn choose_epp(profile: Profile, available: &[String]) -> Option<String> {
    let candidates: &[&str] = match profile {
        Profile::PowerSaver => &["power", "balance_power"],
        Profile::Balanced => &["balance_performance", "default", "balance_power"],
        Profile::Performance => &["performance"],
    };
    for cand in candidates {
        if available.iter().any(|a| a == cand) {
            return Some((*cand).to_string());
        }
    }
    None
}

pub fn choose_platform_profile(profile: Profile, available: &[String]) -> Option<String> {
    let candidates: &[&str] = match profile {
        Profile::PowerSaver => &["low-power", "quiet", "cool"],
        Profile::Balanced => &["balanced"],
        Profile::Performance => &["performance", "balanced-performance"],
    };
    for cand in candidates {
        if available.iter().any(|a| a == cand) {
            return Some((*cand).to_string());
        }
    }
    None
}

pub fn choose_boost_enabled(profile: Profile, boost_on_saver: bool) -> bool {
    match profile {
        Profile::PowerSaver => boost_on_saver,
        Profile::Balanced | Profile::Performance => true,
    }
}

pub fn choose_gpu_dpm_level(profile: Profile) -> &'static str {
    match profile {
        Profile::PowerSaver => "low",
        Profile::Balanced => "auto",
        Profile::Performance => "high",
    }
}

pub fn infer_active_profile(snap: &HardwareSnapshot) -> Profile {
    match snap.platform_profile.as_str() {
        "low-power" | "quiet" | "cool" => return Profile::PowerSaver,
        "performance" | "balanced-performance" => return Profile::Performance,
        "balanced" => {}
        _ => {}
    }

    match snap.epp.as_str() {
        "power" | "balance_power" => return Profile::PowerSaver,
        "performance" => return Profile::Performance,
        "balance_performance" | "default" => return Profile::Balanced,
        _ => {}
    }

    match snap.governor.as_str() {
        "performance" => Profile::Performance,
        "powersave" => {
            if snap.driver.contains("pstate") {
                Profile::Balanced
            } else {
                Profile::PowerSaver
            }
        }
        _ => Profile::Balanced,
    }
}

fn parse_space_list(path: &Path) -> Vec<String> {
    read_trimmed(path)
        .map(|s| s.split_whitespace().map(str::to_string).collect())
        .unwrap_or_default()
}

pub fn apply_profile(cfg: &PowerConfig) -> Result<(), String> {
    let profile = cfg.profile;
    let policies = list_cpufreq_policies();
    let mut applied_any = false;
    let mut errors: Vec<String> = Vec::new();

    if Path::new(PLATFORM_PROFILE_PATH).exists() {
        let choices = parse_space_list(Path::new(PLATFORM_CHOICES_PATH));
        if let Some(choice) = choose_platform_profile(profile, &choices) {
            match fs::write(PLATFORM_PROFILE_PATH, format!("{choice}\n")) {
                Ok(_) => applied_any = true,
                Err(e) => errors.push(format!("platform_profile: {e}")),
            }
        }
    }

    for policy in &policies {
        let driver = read_trimmed(&policy.join("scaling_driver")).unwrap_or_default();
        let avail_govs = parse_space_list(&policy.join("scaling_available_governors"));
        if let Some(gov) = choose_governor(profile, &driver, &avail_govs) {
            let gov_path = policy.join("scaling_governor");
            match fs::write(&gov_path, format!("{gov}\n")) {
                Ok(_) => applied_any = true,
                Err(e) => errors.push(format!("{}: {e}", gov_path.display())),
            }
        }

        let epp_avail_path = policy.join("energy_performance_available_preferences");
        if epp_avail_path.exists() {
            let avail_epp = parse_space_list(&epp_avail_path);
            if let Some(epp) = choose_epp(profile, &avail_epp) {
                let epp_path = policy.join("energy_performance_preference");
                match fs::write(&epp_path, format!("{epp}\n")) {
                    Ok(_) => applied_any = true,
                    Err(e) => errors.push(format!("{}: {e}", epp_path.display())),
                }
            }
        }
    }

    let want_boost = choose_boost_enabled(profile, cfg.boost_on_saver);
    if Path::new(GLOBAL_BOOST_PATH).exists() {
        let val = if want_boost { "1\n" } else { "0\n" };
        match fs::write(GLOBAL_BOOST_PATH, val) {
            Ok(_) => applied_any = true,
            Err(e) => errors.push(format!("boost: {e}")),
        }
    } else if Path::new(INTEL_NO_TURBO_PATH).exists() {
        let val = if want_boost { "0\n" } else { "1\n" };
        match fs::write(INTEL_NO_TURBO_PATH, val) {
            Ok(_) => applied_any = true,
            Err(e) => errors.push(format!("no_turbo: {e}")),
        }
    } else {
        let val = if want_boost { "1\n" } else { "0\n" };
        for policy in &policies {
            let boost_path = policy.join("boost");
            if boost_path.exists() {
                match fs::write(&boost_path, val) {
                    Ok(_) => applied_any = true,
                    Err(e) => errors.push(format!("{}: {e}", boost_path.display())),
                }
            }
        }
    }

    if cfg.gpu_dpm {
        let dpm_level = choose_gpu_dpm_level(profile);
        for dpm_path in list_gpu_dpm_paths() {
            if fs::write(&dpm_path, format!("{dpm_level}\n")).is_ok() {
                applied_any = true;
            } else if dpm_level != "auto" {
                let _ = fs::write(&dpm_path, "auto\n");
            }
        }
    }

    if !applied_any && !errors.is_empty() {
        return Err(errors.into_iter().next().unwrap_or_default());
    }
    Ok(())
}

pub fn build_status_json(daemon_running: bool, cfg: &PowerConfig) -> String {
    let snap = snapshot_hardware();
    let daemon_installed = is_daemon_installed();
    let init_system = detect_init_system();
    let ppd_active = if daemon_running {
        None
    } else {
        query_powerprofilesctl()
    };

    let backend = if daemon_running {
        "aurora-powerd"
    } else if ppd_active.is_some() {
        "power-profiles-daemon"
    } else {
        "direct"
    };

    let active_str = if daemon_running {
        cfg.profile.as_str().to_string()
    } else if let Some(ref p) = ppd_active {
        p.clone()
    } else {
        infer_active_profile(&snap).as_str().to_string()
    };

    let has_power_profiles = snap.has_cpufreq || daemon_running || ppd_active.is_some();

    let mut o = JsonOut::with_capacity(640);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_bool("hasPowerProfiles", has_power_profiles);
    o.kv_str("backend", backend);
    o.kv_bool("daemonRunning", daemon_running);
    o.kv_bool("daemonInstalled", daemon_installed);
    o.kv_str("initSystem", init_system);
    o.kv_str("active", &active_str);
    o.key("available");
    o.arr_start();
    if has_power_profiles {
        o.str("power-saver");
        o.str("balanced");
        o.str("performance");
    }
    o.arr_end();
    o.kv_str("governor", &snap.governor);
    o.kv_str("epp", &snap.epp);
    o.kv_str("driver", &snap.driver);
    o.kv_bool("boostSupported", snap.boost_supported);
    o.kv_bool("boostEnabled", snap.boost_enabled);
    o.kv_str("platformProfile", &snap.platform_profile);
    o.kv_bool("hasPlatformProfile", snap.has_platform_profile);
    o.kv_bool("gpuDpmSupported", snap.gpu_dpm_supported);
    o.kv_str("gpuDpmLevel", &snap.gpu_dpm_level);
    o.kv_u64("cpuFreqMhz", snap.cpu_freq_mhz);
    o.kv_bool("hasBattery", snap.has_battery);
    o.kv_bool("onAc", snap.on_ac);
    o.kv_bool("autoSwitch", cfg.auto_switch);
    o.kv_str("acProfile", cfg.ac_profile.as_str());
    o.kv_str("batteryProfile", cfg.battery_profile.as_str());
    o.kv_bool("gpuDpmControl", cfg.gpu_dpm);
    o.kv_bool("boostOnSaver", cfg.boost_on_saver);
    o.obj_end();
    o.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selects_governor_and_epp_for_pstate_and_acpi() {
        let pstate_govs = vec!["performance".to_string(), "powersave".to_string()];
        let pstate_epps = vec![
            "default".to_string(),
            "performance".to_string(),
            "balance_performance".to_string(),
            "balance_power".to_string(),
            "power".to_string(),
        ];

        assert_eq!(
            choose_governor(Profile::PowerSaver, "amd-pstate-epp", &pstate_govs).as_deref(),
            Some("powersave")
        );
        assert_eq!(
            choose_governor(Profile::Balanced, "amd-pstate-epp", &pstate_govs).as_deref(),
            Some("powersave")
        );
        assert_eq!(
            choose_governor(Profile::Performance, "amd-pstate-epp", &pstate_govs).as_deref(),
            Some("performance")
        );

        assert_eq!(
            choose_epp(Profile::PowerSaver, &pstate_epps).as_deref(),
            Some("power")
        );
        assert_eq!(
            choose_epp(Profile::Balanced, &pstate_epps).as_deref(),
            Some("balance_performance")
        );
        assert_eq!(
            choose_epp(Profile::Performance, &pstate_epps).as_deref(),
            Some("performance")
        );

        let acpi_govs = vec![
            "conservative".to_string(),
            "ondemand".to_string(),
            "powersave".to_string(),
            "performance".to_string(),
            "schedutil".to_string(),
        ];
        assert_eq!(
            choose_governor(Profile::PowerSaver, "acpi-cpufreq", &acpi_govs).as_deref(),
            Some("powersave")
        );
        assert_eq!(
            choose_governor(Profile::Balanced, "acpi-cpufreq", &acpi_govs).as_deref(),
            Some("schedutil")
        );
        assert_eq!(
            choose_governor(Profile::Performance, "acpi-cpufreq", &acpi_govs).as_deref(),
            Some("performance")
        );

        assert!(!choose_boost_enabled(Profile::PowerSaver, false));
        assert!(choose_boost_enabled(Profile::PowerSaver, true));
        assert!(choose_boost_enabled(Profile::Balanced, false));
        assert_eq!(choose_gpu_dpm_level(Profile::PowerSaver), "low");
        assert_eq!(choose_gpu_dpm_level(Profile::Balanced), "auto");
        assert_eq!(choose_gpu_dpm_level(Profile::Performance), "high");
    }
}
