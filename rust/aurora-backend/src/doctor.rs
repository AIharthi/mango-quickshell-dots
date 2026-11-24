use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

use crate::json::{self, JsonOut};
use crate::util::{config_dir, run_stdout, which};

struct CheckItem {
    id: &'static str,
    label: &'static str,
    status: &'static str,
    detail: String,
}

fn check_mango() -> CheckItem {
    let Some(_) = which("mango") else {
        return CheckItem {
            id: "mango-config",
            label: "MangoWC & Config",
            status: "fail",
            detail: "'mango' binary not found in PATH".to_string(),
        };
    };
    let Ok(out) = Command::new("mango").arg("-p").output() else {
        return CheckItem {
            id: "mango-config",
            label: "MangoWC & Config",
            status: "warn",
            detail: "Failed executing 'mango -p'".to_string(),
        };
    };
    if out.status.success() {
        CheckItem {
            id: "mango-config",
            label: "MangoWC & Config",
            status: "ok",
            detail: "mango -p configuration syntax valid".to_string(),
        }
    } else {
        let msg = String::from_utf8_lossy(&out.stderr)
            .lines()
            .next()
            .unwrap_or("Validation failed")
            .trim()
            .to_string();
        CheckItem {
            id: "mango-config",
            label: "MangoWC & Config",
            status: "fail",
            detail: msg,
        }
    }
}

fn check_bins(qs_dir: &Path) -> CheckItem {
    let fm = qs_dir.join("bin/aurora-fm").exists();
    let be = qs_dir.join("bin/aurora-backend").exists();
    match (fm, be) {
        (true, true) => CheckItem {
            id: "aurora-bins",
            label: "Aurora Rust Backends",
            status: "ok",
            detail: "aurora-fm and aurora-backend installed".to_string(),
        },
        (true, false) | (false, true) => CheckItem {
            id: "aurora-bins",
            label: "Aurora Rust Backends",
            status: "warn",
            detail: "Partial Rust binaries installed; run ./install.sh".to_string(),
        },
        (false, false) => CheckItem {
            id: "aurora-bins",
            label: "Aurora Rust Backends",
            status: "warn",
            detail: "Missing compiled binaries in quickshell/bin; run ./install.sh".to_string(),
        },
    }
}

fn check_session_env() -> CheckItem {
    let w = env::var("WAYLAND_DISPLAY").unwrap_or_default();
    let d = env::var("DBUS_SESSION_BUS_ADDRESS").unwrap_or_default();
    if !w.is_empty() && !d.is_empty() {
        CheckItem {
            id: "session-env",
            label: "Wayland & D-Bus Session",
            status: "ok",
            detail: format!("Wayland ({w}) and D-Bus active"),
        }
    } else {
        CheckItem {
            id: "session-env",
            label: "Wayland & D-Bus Session",
            status: "warn",
            detail: "Missing WAYLAND_DISPLAY or DBUS_SESSION_BUS_ADDRESS".to_string(),
        }
    }
}

fn check_audio() -> CheckItem {
    if which("pactl").is_some() && run_stdout("pactl", &["info"]).is_some() {
        CheckItem {
            id: "audio",
            label: "Audio Stack (PipeWire)",
            status: "ok",
            detail: "PipeWire / PulseAudio server reachable".to_string(),
        }
    } else {
        CheckItem {
            id: "audio",
            label: "Audio Stack (PipeWire)",
            status: "warn",
            detail: "pactl not responding or PipeWire inactive".to_string(),
        }
    }
}

fn check_wallpaper() -> CheckItem {
    for (bin, args) in [("awww", ["query"]), ("swww", ["query"])] {
        if which(bin).is_some() {
            if run_stdout(bin, &args).is_some() {
                return CheckItem {
                    id: "wallpaper",
                    label: "Wallpaper Engine",
                    status: "ok",
                    detail: format!("{bin}-daemon active"),
                };
            }
            return CheckItem {
                id: "wallpaper",
                label: "Wallpaper Engine",
                status: "warn",
                detail: format!("{bin} installed but daemon is not running"),
            };
        }
    }
    CheckItem {
        id: "wallpaper",
        label: "Wallpaper Engine",
        status: "warn",
        detail: "Neither awww nor swww installed (solid colors only)".to_string(),
    }
}

fn check_theme(qs_dir: &Path) -> CheckItem {
    let colors_path = qs_dir.join("colors.json");
    let Ok(raw) = fs::read_to_string(&colors_path) else {
        return CheckItem {
            id: "theme",
            label: "Theme & Matugen Palette",
            status: "warn",
            detail: "colors.json missing; run apply-theme.sh --init".to_string(),
        };
    };
    let Ok(val) = json::parse(&raw) else {
        return CheckItem {
            id: "theme",
            label: "Theme & Matugen Palette",
            status: "fail",
            detail: "colors.json is invalid JSON".to_string(),
        };
    };
    let has_keys = val.get_str("primary").is_some() && val.get_str("surface").is_some();
    if !has_keys {
        return CheckItem {
            id: "theme",
            label: "Theme & Matugen Palette",
            status: "warn",
            detail: "colors.json missing primary/surface tokens".to_string(),
        };
    }
    let matugen_note = if which("matugen").is_some() {
        "Palette valid + matugen available"
    } else {
        "Palette valid (presets ready; matugen not installed)"
    };
    CheckItem {
        id: "theme",
        label: "Theme & Matugen Palette",
        status: "ok",
        detail: matugen_note.to_string(),
    }
}

fn check_portal(cfg_dir: &Path) -> CheckItem {
    let has_bin = which("xdg-desktop-portal").is_some()
        || Path::new("/usr/libexec/xdg-desktop-portal-wlr").exists()
        || Path::new("/usr/lib/xdg-desktop-portal-wlr").exists();
    let has_conf = cfg_dir
        .join("xdg-desktop-portal/mango-portals.conf")
        .exists();
    if has_bin && has_conf {
        CheckItem {
            id: "portal",
            label: "XDG Desktop Portals",
            status: "ok",
            detail: "Portal binary and mango-portals.conf ready".to_string(),
        }
    } else {
        CheckItem {
            id: "portal",
            label: "XDG Desktop Portals",
            status: "warn",
            detail: "Portal binary or mango-portals.conf missing".to_string(),
        }
    }
}

fn check_pam(qs_dir: &Path) -> CheckItem {
    if qs_dir.join("pam/lock").is_file() {
        CheckItem {
            id: "lock-pam",
            label: "Session Lock PAM",
            status: "ok",
            detail: "quickshell/pam/lock present".to_string(),
        }
    } else {
        CheckItem {
            id: "lock-pam",
            label: "Session Lock PAM",
            status: "warn",
            detail: "quickshell/pam/lock missing".to_string(),
        }
    }
}

fn check_sddm() -> CheckItem {
    for (name, path) in [
        ("aurora-island", "/usr/share/sddm/themes/aurora-island"),
        ("mango-island", "/usr/share/sddm/themes/mango-island"),
    ] {
        let p = Path::new(path);
        if p.join("Main.qml").is_file() {
            return CheckItem {
                id: "sddm",
                label: "SDDM Login Theme",
                status: "ok",
                detail: format!("{name} installed in /usr/share/sddm/themes"),
            };
        }
    }
    CheckItem {
        id: "sddm",
        label: "SDDM Login Theme",
        status: "ok",
        detail: "Not installed (optional: ./install.sh --with-sddm)".to_string(),
    }
}

pub fn cmd_doctor() {
    let cfg = config_dir();
    let qs_dir = cfg.join("quickshell");
    let checks = vec![
        check_mango(),
        check_bins(&qs_dir),
        check_session_env(),
        check_audio(),
        check_wallpaper(),
        check_theme(&qs_dir),
        check_portal(&cfg),
        check_pam(&qs_dir),
        check_sddm(),
    ];

    let mut pass_count = 0u64;
    let mut warn_count = 0u64;
    let mut fail_count = 0u64;
    for c in &checks {
        match c.status {
            "ok" => pass_count += 1,
            "warn" => warn_count += 1,
            _ => fail_count += 1,
        }
    }
    let ok = fail_count == 0;
    let summary = format!("{pass_count} passed, {warn_count} warnings, {fail_count} failed");

    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", ok);
    o.kv_str("summary", &summary);
    o.kv_u64("passCount", pass_count);
    o.kv_u64("warnCount", warn_count);
    o.kv_u64("failCount", fail_count);
    o.key("checks");
    o.arr_start();
    for c in checks {
        o.obj_start();
        o.kv_str("id", c.id);
        o.kv_str("label", c.label);
        o.kv_str("status", c.status);
        o.kv_str("detail", &c.detail);
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
}
