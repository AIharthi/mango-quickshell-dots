use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const DEFAULT_CONFIG_PATH: &str = "/etc/aurora-powerd.conf";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Profile {
    PowerSaver,
    Balanced,
    Performance,
}

impl Profile {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "power-saver" | "powersaver" | "saver" => Some(Self::PowerSaver),
            "balanced" | "balance" => Some(Self::Balanced),
            "performance" | "perf" => Some(Self::Performance),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::PowerSaver => "power-saver",
            Self::Balanced => "balanced",
            Self::Performance => "performance",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PowerConfig {
    pub profile: Profile,
    pub auto_switch: bool,
    pub ac_profile: Profile,
    pub battery_profile: Profile,
    pub gpu_dpm: bool,
    pub boost_on_saver: bool,
}

impl Default for PowerConfig {
    fn default() -> Self {
        Self {
            profile: Profile::Balanced,
            auto_switch: false,
            ac_profile: Profile::Balanced,
            battery_profile: Profile::PowerSaver,
            gpu_dpm: true,
            boost_on_saver: false,
        }
    }
}

pub fn config_path() -> PathBuf {
    env::var_os("AURORA_POWERD_CONF")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_CONFIG_PATH))
}

pub fn parse_bool(raw: &str) -> Option<bool> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

impl PowerConfig {
    pub fn parse_str(txt: &str) -> Self {
        let mut cfg = Self::default();
        for line in txt.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let Some((k, v)) = trimmed.split_once('=') else {
                continue;
            };
            let key = k.trim();
            let val = v.trim();
            match key {
                "profile" => {
                    if let Some(p) = Profile::parse(val) {
                        cfg.profile = p;
                    }
                }
                "auto_switch" => {
                    if let Some(b) = parse_bool(val) {
                        cfg.auto_switch = b;
                    }
                }
                "ac_profile" => {
                    if let Some(p) = Profile::parse(val) {
                        cfg.ac_profile = p;
                    }
                }
                "battery_profile" => {
                    if let Some(p) = Profile::parse(val) {
                        cfg.battery_profile = p;
                    }
                }
                "gpu_dpm" => {
                    if let Some(b) = parse_bool(val) {
                        cfg.gpu_dpm = b;
                    }
                }
                "boost_on_saver" => {
                    if let Some(b) = parse_bool(val) {
                        cfg.boost_on_saver = b;
                    }
                }
                _ => {}
            }
        }
        cfg
    }

    pub fn serialize(&self) -> String {
        format!(
            "# Aurora Power Daemon configuration\n\
             profile={}\n\
             auto_switch={}\n\
             ac_profile={}\n\
             battery_profile={}\n\
             gpu_dpm={}\n\
             boost_on_saver={}\n",
            self.profile.as_str(),
            self.auto_switch,
            self.ac_profile.as_str(),
            self.battery_profile.as_str(),
            self.gpu_dpm,
            self.boost_on_saver,
        )
    }

    pub fn load_from(path: &Path) -> Self {
        match fs::read_to_string(path) {
            Ok(txt) => Self::parse_str(&txt),
            Err(_) => Self::default(),
        }
    }

    pub fn save_to(&self, path: &Path) -> Result<(), String> {
        let parent = path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("/etc"));
        fs::create_dir_all(parent).map_err(|e| format!("Failed creating config dir: {e}"))?;
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let tmp = parent.join(format!(
            ".aurora-powerd.conf.tmp.{}.{}",
            std::process::id(),
            nanos
        ));
        let data = self.serialize();
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o644)
            .open(&tmp)
            .map_err(|e| format!("Failed creating temp config: {e}"))?;
        if let Err(e) = f.write_all(data.as_bytes()).and_then(|_| f.flush()) {
            let _ = fs::remove_file(&tmp);
            return Err(format!("Failed writing config: {e}"));
        }
        drop(f);
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o644));
        if let Err(e) = fs::rename(&tmp, path) {
            let _ = fs::remove_file(&tmp);
            return Err(format!("Failed renaming config: {e}"));
        }
        Ok(())
    }

    pub fn set_field(&mut self, key: &str, raw_val: &str) -> Result<(), String> {
        match key.trim() {
            "auto_switch" => {
                self.auto_switch = parse_bool(raw_val)
                    .ok_or_else(|| format!("Invalid boolean for auto_switch: '{raw_val}'"))?;
            }
            "ac_profile" => {
                self.ac_profile = Profile::parse(raw_val)
                    .ok_or_else(|| format!("Invalid profile for ac_profile: '{raw_val}'"))?;
            }
            "battery_profile" => {
                self.battery_profile = Profile::parse(raw_val)
                    .ok_or_else(|| format!("Invalid profile for battery_profile: '{raw_val}'"))?;
            }
            "gpu_dpm" => {
                self.gpu_dpm = parse_bool(raw_val)
                    .ok_or_else(|| format!("Invalid boolean for gpu_dpm: '{raw_val}'"))?;
            }
            "boost_on_saver" => {
                self.boost_on_saver = parse_bool(raw_val)
                    .ok_or_else(|| format!("Invalid boolean for boost_on_saver: '{raw_val}'"))?;
            }
            other => {
                return Err(format!(
                    "Unknown config key '{other}'. Expected auto_switch, ac_profile, battery_profile, gpu_dpm, or boost_on_saver"
                ));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profile_and_config_roundtrip() {
        assert_eq!(Profile::parse("power-saver"), Some(Profile::PowerSaver));
        assert_eq!(Profile::parse("balanced"), Some(Profile::Balanced));
        assert_eq!(Profile::parse("performance"), Some(Profile::Performance));
        assert_eq!(Profile::parse("turbo"), None);

        let mut cfg = PowerConfig {
            profile: Profile::Performance,
            auto_switch: true,
            ac_profile: Profile::Performance,
            battery_profile: Profile::PowerSaver,
            gpu_dpm: false,
            boost_on_saver: true,
        };
        let raw = cfg.serialize();
        let parsed = PowerConfig::parse_str(&raw);
        assert_eq!(parsed, cfg);

        cfg.set_field("auto_switch", "false").unwrap();
        cfg.set_field("ac_profile", "balanced").unwrap();
        cfg.set_field("gpu_dpm", "true").unwrap();
        assert!(!cfg.auto_switch);
        assert_eq!(cfg.ac_profile, Profile::Balanced);
        assert!(cfg.gpu_dpm);
        assert!(cfg.set_field("unknown", "1").is_err());
        assert!(cfg.set_field("ac_profile", "invalid").is_err());

        let tmp = env::temp_dir().join(format!(
            "aurora_powerd_cfg_test_{}.conf",
            std::process::id()
        ));
        let _ = fs::remove_file(&tmp);
        cfg.save_to(&tmp).unwrap();
        let loaded = PowerConfig::load_from(&tmp);
        assert_eq!(loaded, cfg);
        let _ = fs::remove_file(&tmp);
    }
}
