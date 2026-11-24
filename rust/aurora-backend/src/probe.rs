use std::fs;
use std::path::Path;

use crate::json::JsonOut;
use crate::util::{battery_snapshot, config_dir, read_trimmed, run_stdout, which};

fn dir_has_any(dir: &Path, filter: impl Fn(&str) -> bool) -> bool {
    let Ok(rd) = fs::read_dir(dir) else {
        return false;
    };
    for ent in rd.flatten() {
        let name = ent.file_name();
        if filter(&name.to_string_lossy()) {
            return true;
        }
    }
    false
}

fn has_wifi_hardware() -> bool {
    if dir_has_any(Path::new("/sys/class/ieee80211"), |_| true) {
        return true;
    }
    let Ok(rd) = fs::read_dir("/sys/class/net") else {
        return false;
    };
    for ent in rd.flatten() {
        let p = ent.path();
        if p.join("wireless").exists() || p.join("phy80211").exists() {
            return true;
        }
    }
    false
}

fn is_touchpad_name(lower: &str) -> bool {
    lower.contains("touchpad")
        || lower.contains("trackpad")
        || lower.contains("synaptics")
        || lower.contains("elan")
        || lower.contains("syna")
        || (lower.contains("apple") && lower.contains("trackpad"))
}

fn detect_touchpad() -> bool {
    if let Ok(txt) = fs::read_to_string("/proc/bus/input/devices") {
        for line in txt.lines() {
            if line.starts_with("N: Name=") && is_touchpad_name(&line.to_ascii_lowercase()) {
                return true;
            }
        }
    }
    if which("mmsg").is_some() {
        if let Some(raw) = run_stdout("mmsg", &["get", "all-devices"]) {
            if let Ok(val) = crate::json::parse(&raw) {
                if let Some(arr) = val.get("devices").and_then(|v| v.as_arr()) {
                    for dev in arr {
                        if let Some(name) = dev.get_str("name") {
                            if is_touchpad_name(&name.to_ascii_lowercase()) {
                                return true;
                            }
                        }
                    }
                }
            }
        }
    }
    false
}

fn read_distro() -> String {
    let Ok(txt) = fs::read_to_string("/etc/os-release") else {
        return "Linux".to_string();
    };
    for line in txt.lines() {
        if let Some(rest) = line.strip_prefix("PRETTY_NAME=") {
            let cleaned = rest.trim().trim_matches(|c| c == '"' || c == '\'');
            if !cleaned.is_empty() {
                return cleaned.to_string();
            }
        }
    }
    "Linux".to_string()
}

pub fn cmd_probe() {
    let cfg = config_dir();
    let has_wifi_hw = has_wifi_hardware();
    let has_nmcli = which("nmcli").is_some();
    let has_wifi = has_wifi_hw && has_nmcli;
    let has_bt = dir_has_any(Path::new("/sys/class/bluetooth"), |n| n.starts_with("hci"))
        && which("bluetoothctl").is_some();
    let has_backlight = dir_has_any(Path::new("/sys/class/backlight"), |_| true)
        && which("brightnessctl").is_some();

    let bat = battery_snapshot();
    let battery_path = bat.paths.first().cloned().unwrap_or_default();
    let has_touchpad = detect_touchpad();
    let has_wlr_randr = which("wlr-randr").is_some();
    let has_audio = which("pactl").is_some();
    let has_pavucontrol = which("pavucontrol").is_some();
    let has_power_profiles = which("powerprofilesctl").is_some();
    let has_xdg_mime = which("xdg-mime").is_some();
    let has_network = dir_has_any(Path::new("/sys/class/net"), |n| n != "lo");
    let has_ddcutil = which("ddcutil").is_some();
    let has_openrc = which("rc-status").is_some();
    let has_systemd = which("systemctl").is_some() && Path::new("/run/systemd/system").is_dir();
    let has_clipboard = which("wl-copy").is_some();
    let has_speaker_test = which("speaker-test").is_some() || which("paplay").is_some();
    let has_foot = which("foot").is_some() || cfg.join("foot/foot.ini").exists();
    let has_kitty = which("kitty").is_some() || cfg.join("kitty/kitty.conf").exists();

    let night_light_cmd = ["hyprsunset", "wlsunset", "gammastep"]
        .into_iter()
        .find(|c| which(c).is_some())
        .unwrap_or("")
        .to_string();
    let has_night_light = !night_light_cmd.is_empty();

    let locker_cmd = ["hyprlock", "swaylock", "waylock"]
        .into_iter()
        .find(|c| which(c).is_some())
        .map(str::to_string)
        .unwrap_or_else(|| {
            if which("qs").is_some() || which("quickshell").is_some() {
                "quickshell".to_string()
            } else {
                String::new()
            }
        });
    let has_locker = !locker_cmd.is_empty();

    let device_type = if bat.has_battery || has_backlight || has_touchpad {
        "laptop"
    } else {
        "desktop"
    };
    let hostname = read_trimmed(Path::new("/proc/sys/kernel/hostname"))
        .or_else(|| std::env::var("HOSTNAME").ok())
        .unwrap_or_else(|| "localhost".to_string());
    let kernel = read_trimmed(Path::new("/proc/sys/kernel/osrelease")).unwrap_or_default();
    let distro = read_distro();

    let mut o = JsonOut::with_capacity(768);
    o.obj_start();
    o.kv_bool("probed", true);
    o.kv_bool("hasWifi", has_wifi);
    o.kv_bool("hasWifiHw", has_wifi_hw);
    o.kv_bool("hasBluetooth", has_bt);
    o.kv_bool("hasBacklight", has_backlight);
    o.kv_bool("hasBattery", bat.has_battery);
    o.kv_str("batteryPath", &battery_path);
    o.key("batteryPaths");
    o.arr_start();
    for p in &bat.paths {
        o.str(p);
    }
    o.arr_end();
    o.kv_bool("hasTouchpad", has_touchpad);
    o.kv_bool("hasWlrRandr", has_wlr_randr);
    o.kv_bool("hasAudio", has_audio);
    o.kv_bool("hasPavucontrol", has_pavucontrol);
    o.kv_str("nightLightCmd", &night_light_cmd);
    o.kv_bool("hasNightLight", has_night_light);
    o.kv_bool("hasPowerProfiles", has_power_profiles);
    o.kv_bool("hasXdgMime", has_xdg_mime);
    o.kv_bool("hasNetwork", has_network);
    o.kv_bool("hasNmcli", has_nmcli);
    o.kv_bool("hasDdcutil", has_ddcutil);
    o.kv_bool("hasOpenRc", has_openrc);
    o.kv_bool("hasSystemd", has_systemd);
    o.kv_bool("hasClipboard", has_clipboard);
    o.kv_bool("hasSpeakerTest", has_speaker_test);
    o.kv_bool("hasFoot", has_foot);
    o.kv_bool("hasKitty", has_kitty);
    o.kv_str("lockerCmd", &locker_cmd);
    o.kv_bool("hasLocker", has_locker);
    o.kv_str("deviceType", device_type);
    o.kv_str("hostname", &hostname);
    o.kv_str("kernel", &kernel);
    o.kv_str("distro", &distro);
    o.obj_end();
    println!("{}", o.finish());
}

pub fn cmd_battery() {
    let bat = battery_snapshot();
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_u64("percent", bat.percent);
    o.kv_str("status", &bat.status);
    o.kv_bool("charging", bat.charging);
    o.kv_u64("count", bat.count as u64);
    o.kv_f64("powerWatts", bat.power_watts, 1);
    o.kv_str("etaLabel", &bat.eta_label);
    o.kv_u64("healthPercent", bat.health_percent);
    o.obj_end();
    println!("{}", o.finish());
}
