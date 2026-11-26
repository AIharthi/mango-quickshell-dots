#![forbid(unsafe_code)]

mod config;
mod daemon;
mod json;
mod sysfs;

use std::env;
use std::process::{Command, Stdio};

use crate::config::{config_path, PowerConfig, Profile};
use crate::daemon::{run_daemon, send_request, socket_path};
use crate::json::JsonOut;
use crate::sysfs::{apply_profile, build_status_json, current_euid, query_powerprofilesctl, which};

fn print_err_exit(msg: &str) -> ! {
    let mut o = JsonOut::with_capacity(128);
    o.obj_start();
    o.kv_bool("ok", false);
    o.kv_str("error", msg);
    o.obj_end();
    println!("{}", o.finish());
    std::process::exit(1);
}

fn cmd_status() {
    let sock = socket_path();
    if let Ok(resp) = send_request(&sock, "status") {
        println!("{resp}");
        return;
    }
    let cfg = PowerConfig::load_from(&config_path());
    println!("{}", build_status_json(false, &cfg));
}

fn apply_once_privileged(profile: Profile) -> Result<(), String> {
    if current_euid() != Some(0) {
        return Err("apply-once requires root privileges".to_string());
    }
    let cfg_file = config_path();
    let mut cfg = PowerConfig::load_from(&cfg_file);
    cfg.profile = profile;
    apply_profile(&cfg)?;
    let _ = cfg.save_to(&cfg_file);
    println!("{}", build_status_json(false, &cfg));
    Ok(())
}

fn escalate_apply_once(profile: Profile) -> Result<(), String> {
    let exe = env::current_exe().map_err(|e| format!("Unable to locate aurora-powerd: {e}"))?;
    let exe_str = exe.to_string_lossy().into_owned();
    let prof_str = profile.as_str();

    if which("sudo").is_some() {
        let out = Command::new("sudo")
            .args(["-n", &exe_str, "apply-once", prof_str])
            .output();
        if let Ok(o) = out {
            if o.status.success() {
                let txt = String::from_utf8_lossy(&o.stdout).trim().to_string();
                if !txt.is_empty() {
                    println!("{txt}");
                    return Ok(());
                }
            }
        }
    }

    if which("pkexec").is_some() {
        let out = Command::new("pkexec")
            .args([&exe_str, "apply-once", prof_str])
            .output()
            .map_err(|e| format!("Failed running pkexec: {e}"))?;
        if out.status.success() {
            let txt = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !txt.is_empty() {
                println!("{txt}");
                return Ok(());
            }
            let cfg = PowerConfig::load_from(&config_path());
            println!("{}", build_status_json(false, &cfg));
            return Ok(());
        }
        let err_txt = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(if err_txt.is_empty() {
            "Privilege escalation cancelled or failed".to_string()
        } else {
            err_txt
        });
    }

    Err("Daemon is not running and neither sudo nor pkexec succeeded".to_string())
}

fn cmd_set(args: &[String]) {
    let Some(raw) = args.first() else {
        print_err_exit("Usage: aurora-powerd set <power-saver|balanced|performance>");
    };
    let Some(profile) = Profile::parse(raw) else {
        print_err_exit(&format!("Invalid power profile '{raw}'"));
    };

    let sock = socket_path();
    if let Ok(resp) = send_request(&sock, &format!("set {}", profile.as_str())) {
        println!("{resp}");
        return;
    }

    if query_powerprofilesctl().is_some() {
        let ok = Command::new("powerprofilesctl")
            .args(["set", profile.as_str()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            let cfg = PowerConfig::load_from(&config_path());
            println!("{}", build_status_json(false, &cfg));
            return;
        }
    }

    if current_euid() == Some(0) {
        if let Err(e) = apply_once_privileged(profile) {
            print_err_exit(&e);
        }
        return;
    }

    if let Err(e) = escalate_apply_once(profile) {
        print_err_exit(&e);
    }
}

fn cmd_config(args: &[String]) {
    if args.len() < 2 {
        print_err_exit("Usage: aurora-powerd config <key> <value>");
    }
    let key = args[0].trim();
    let val = args[1].trim();
    let mut check_cfg = PowerConfig::default();
    if let Err(e) = check_cfg.set_field(key, val) {
        print_err_exit(&e);
    }

    let sock = socket_path();
    match send_request(&sock, &format!("config {key} {val}")) {
        Ok(resp) => println!("{resp}"),
        Err(_) => {
            print_err_exit("aurora-powerd daemon is not running; install & start the daemon first")
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let Some(cmd) = args.first().map(String::as_str) else {
        print_err_exit("Usage: aurora-powerd <version|daemon|status|set|config|apply-once>");
    };
    let rest = &args[1..];

    match cmd {
        "version" => {
            println!(
                "{{\"name\":\"aurora-powerd\",\"version\":\"{}\"}}",
                env!("CARGO_PKG_VERSION")
            );
        }
        "daemon" => {
            if let Err(e) = run_daemon() {
                print_err_exit(&e);
            }
        }
        "status" => cmd_status(),
        "set" => cmd_set(rest),
        "config" => cmd_config(rest),
        "apply-once" => {
            let Some(raw) = rest.first() else {
                print_err_exit(
                    "Usage: aurora-powerd apply-once <power-saver|balanced|performance>",
                );
            };
            let Some(profile) = Profile::parse(raw) else {
                print_err_exit(&format!("Invalid power profile '{raw}'"));
            };
            if let Err(e) = apply_once_privileged(profile) {
                print_err_exit(&e);
            }
        }
        other => print_err_exit(&format!("Unknown subcommand '{other}'")),
    }
}
