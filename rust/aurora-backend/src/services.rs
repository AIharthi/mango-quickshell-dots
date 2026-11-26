use std::collections::HashSet;
use std::path::Path;
use std::process::{Command, Stdio};

use crate::json::JsonOut;
use crate::util::{current_uid, proc_uid_and_comm, run_stdout, sanitize_id, which};

pub struct ServiceEntry {
    pub name: String,
    pub status: String,
    pub scope: String,
}

pub fn parse_openrc_status_output(out: &str, force_scope: Option<&str>) -> Vec<ServiceEntry> {
    let mut svcs = Vec::new();
    let mut cur_runlevel = "default".to_string();
    for line in out.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed
            .strip_prefix("Runlevel:")
            .or_else(|| trimmed.strip_prefix("Dynamic Runlevel:"))
        {
            let rl = rest.trim();
            if !rl.is_empty() {
                cur_runlevel = rl.to_string();
            }
            continue;
        }
        if cur_runlevel == "shutdown" && force_scope.is_none() {
            continue;
        }
        if let (Some(lbrack), Some(rbrack)) = (line.find('['), line.rfind(']')) {
            if rbrack > lbrack {
                let name = line[..lbrack].trim();
                let raw_status = line[lbrack + 1..rbrack].trim();
                let status = raw_status.split_whitespace().next().unwrap_or("");
                if !name.is_empty() && !name.contains(' ') && !status.is_empty() {
                    svcs.push(ServiceEntry {
                        name: name.to_string(),
                        status: status.to_string(),
                        scope: force_scope.unwrap_or(&cur_runlevel).to_string(),
                    });
                }
            }
        }
    }
    svcs
}

pub fn parse_systemd_units_output(
    out: &str,
    scope: &str,
    allowlist: Option<&[&str]>,
) -> Vec<ServiceEntry> {
    let mut svcs = Vec::new();
    for line in out.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 4 {
            continue;
        }
        let raw_unit = parts[0].trim_start_matches('●').trim();
        let name = raw_unit.strip_suffix(".service").unwrap_or(raw_unit);
        if name.is_empty() {
            continue;
        }
        if let Some(allowed) = allowlist {
            if !allowed.iter().any(|a| a.eq_ignore_ascii_case(name)) {
                continue;
            }
        }
        svcs.push(ServiceEntry {
            name: name.to_string(),
            status: parts[3].to_string(),
            scope: scope.to_string(),
        });
    }
    svcs
}

pub fn is_protected_comm(comm: &str) -> bool {
    matches!(
        comm,
        "mango"
            | "qs"
            | "quickshell"
            | "aurora-backend"
            | "aurora-fm"
            | "dbus-daemon"
            | "pipewire"
            | "wireplumber"
            | "systemd"
            | "openrc-init"
            | "openrc-user"
            | "sddm"
            | "sddm-helper"
            | "elogind"
            | "init"
    )
}

fn gather_services() -> (&'static str, Vec<ServiceEntry>) {
    let has_systemd = Path::new("/run/systemd/system").is_dir();
    if which("rc-status").is_some() && !has_systemd {
        let mut svcs = Vec::new();
        let mut seen = HashSet::new();
        if let Some(user_out) = run_stdout("rc-status", &["--user", "-a"]) {
            for s in parse_openrc_status_output(&user_out, Some("user")) {
                if seen.insert((s.scope.clone(), s.name.clone())) {
                    svcs.push(s);
                }
            }
        }
        if let Some(sys_out) = run_stdout("rc-status", &["-a"]) {
            for s in parse_openrc_status_output(&sys_out, None) {
                if seen.insert((s.scope.clone(), s.name.clone())) {
                    svcs.push(s);
                }
            }
        }
        svcs.sort_by_key(|s| match s.scope.as_str() {
            "user" => 0,
            "default" => 1,
            "boot" => 2,
            "sysinit" => 4,
            _ => 3,
        });
        return ("openrc", svcs);
    }

    if which("systemctl").is_some() && has_systemd {
        let mut svcs = Vec::new();
        let mut seen = HashSet::new();
        if let Some(user_out) = run_stdout(
            "systemctl",
            &[
                "--user",
                "list-units",
                "--type=service",
                "--all",
                "--no-pager",
                "--no-legend",
            ],
        ) {
            for s in parse_systemd_units_output(&user_out, "user", None) {
                if seen.insert((s.scope.clone(), s.name.clone())) {
                    svcs.push(s);
                }
            }
        }
        const KEY_SYS: &[&str] = &[
            "NetworkManager",
            "bluetooth",
            "sddm",
            "power-profiles-daemon",
            "aurora-powerd",
            "restart-i2c",
            "upower",
            "iwd",
            "sshd",
            "docker",
            "libvirtd",
        ];
        if let Some(sys_out) = run_stdout(
            "systemctl",
            &[
                "list-units",
                "--type=service",
                "--all",
                "--no-pager",
                "--no-legend",
            ],
        ) {
            for s in parse_systemd_units_output(&sys_out, "system", Some(KEY_SYS)) {
                if seen.insert((s.scope.clone(), s.name.clone())) {
                    svcs.push(s);
                }
            }
        }
        return ("systemd", svcs);
    }

    ("unknown", Vec::new())
}

pub fn cmd_services() {
    let (init_sys, svcs) = gather_services();
    let mut o = JsonOut::with_capacity(svcs.len() * 64 + 64);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("initSystem", init_sys);
    o.key("services");
    o.arr_start();
    for s in svcs {
        o.obj_start();
        o.kv_str("name", &s.name);
        o.kv_str("status", &s.status);
        o.kv_str("scope", &s.scope);
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
}

pub fn cmd_service_action(args: &[String]) -> Result<(), String> {
    let raw_name = args
        .first()
        .ok_or_else(|| "Usage: service-action <name> <start|stop|restart> [scope]".to_string())?;
    let act = args
        .get(1)
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| matches!(s.as_str(), "start" | "stop" | "restart"))
        .ok_or_else(|| "Action must be start, stop, or restart".to_string())?;
    let name = sanitize_id(raw_name, 80).ok_or_else(|| "Invalid service name".to_string())?;
    let scope_hint = args.get(2).map(|s| s.trim().to_ascii_lowercase());

    let has_systemd = Path::new("/run/systemd/system").is_dir();
    if has_systemd && which("systemctl").is_some() {
        let is_user = match scope_hint.as_deref() {
            Some("user") => true,
            Some("system") => false,
            _ => Command::new("systemctl")
                .args(["--user", "cat", "--", &name])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false),
        };
        if is_user {
            let _ = Command::new("systemctl")
                .args(["--user", &act, "--", &name])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        } else {
            let ok = Command::new("systemctl")
                .args([&act, "--", &name])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if !ok && which("pkexec").is_some() {
                let _ = Command::new("pkexec")
                    .args(["systemctl", &act, &name])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        }
    } else if which("rc-service").is_some() {
        let is_user = match scope_hint.as_deref() {
            Some("user") => true,
            Some(s) if s != "user" && !s.is_empty() => false,
            _ => Command::new("rc-service")
                .args(["--user", "-e", &name])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false),
        };
        if is_user {
            let _ = Command::new("rc-service")
                .args(["--user", &name, &act])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        } else {
            let mut ran = false;
            if which("sudo").is_some() {
                ran = Command::new("sudo")
                    .args(["-n", "rc-service", &name, &act])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status()
                    .map(|s| s.success())
                    .unwrap_or(false);
            }
            if !ran && which("pkexec").is_some() {
                let _ = Command::new("pkexec")
                    .args(["rc-service", &name, &act])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
            }
        }
    } else {
        return Err("No supported service manager found (systemd or OpenRC)".to_string());
    }

    cmd_services();
    Ok(())
}

pub fn cmd_kill_proc(args: &[String]) -> Result<(), String> {
    let pid: u64 = args
        .first()
        .and_then(|s| s.trim().parse().ok())
        .ok_or_else(|| "Usage: kill-proc <pid> [TERM|KILL]".to_string())?;
    if pid <= 1 || pid == std::process::id() as u64 {
        return Err("Refusing to signal protected PID".to_string());
    }

    let sig_name = args
        .get(1)
        .map(|s| s.trim().to_ascii_uppercase())
        .unwrap_or_else(|| "TERM".to_string());
    if sig_name != "TERM" && sig_name != "KILL" {
        return Err("Signal must be TERM or KILL".to_string());
    }

    let my_uid = current_uid().ok_or_else(|| "Unable to determine current UID".to_string())?;
    let (proc_uid, comm) = proc_uid_and_comm(pid)
        .ok_or_else(|| format!("Process {pid} does not exist or cannot be inspected"))?;
    if proc_uid != my_uid {
        return Err("Refusing to signal process owned by another user".to_string());
    }
    if is_protected_comm(&comm) {
        return Err(format!(
            "Refusing to terminate critical session process: {comm}"
        ));
    }

    let status = Command::new("kill")
        .args(["-s", &sig_name, "--", &pid.to_string()])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("Failed invoking kill: {e}"))?;
    if !status.success() {
        return Err(format!("kill -s {sig_name} failed for PID {pid}"));
    }

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_u64("signaled", pid);
    o.kv_str("signal", &sig_name);
    o.kv_str("comm", &comm);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

pub fn cmd_power(args: &[String]) -> Result<(), String> {
    let act = args
        .first()
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| {
            matches!(
                s.as_str(),
                "suspend" | "hibernate" | "reboot" | "poweroff" | "logout"
            )
        })
        .ok_or_else(|| "Usage: power <suspend|hibernate|reboot|poweroff|logout>".to_string())?;

    if act == "logout" {
        let mut ok = false;
        if which("mmsg").is_some() {
            ok = Command::new("mmsg")
                .args(["dispatch", "quit"])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
        }
        if !ok && which("loginctl").is_some() {
            if let Some(uid) = current_uid() {
                ok = Command::new("loginctl")
                    .args(["terminate-user", &uid.to_string()])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status()
                    .map(|s| s.success())
                    .unwrap_or(false);
            }
        }
        if !ok {
            return Err("Failed logging out of Wayland session".to_string());
        }
        println!("{{\"ok\":true,\"action\":\"logout\"}}");
        return Ok(());
    }

    let mut dispatched = false;
    if which("loginctl").is_some() {
        dispatched = Command::new("loginctl")
            .arg(&act)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
    }

    if !dispatched && Path::new("/run/systemd/system").is_dir() && which("systemctl").is_some() {
        dispatched = Command::new("systemctl")
            .arg(&act)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
    }

    if !dispatched && which("dbus-send").is_some() {
        let method = match act.as_str() {
            "suspend" => "org.freedesktop.login1.Manager.Suspend",
            "hibernate" => "org.freedesktop.login1.Manager.Hibernate",
            "reboot" => "org.freedesktop.login1.Manager.Reboot",
            "poweroff" => "org.freedesktop.login1.Manager.PowerOff",
            _ => "",
        };
        if !method.is_empty() {
            dispatched = Command::new("dbus-send")
                .args([
                    "--system",
                    "--print-reply",
                    "--dest=org.freedesktop.login1",
                    "/org/freedesktop/login1",
                    method,
                    "boolean:true",
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
        }
    }

    if !dispatched && act == "suspend" && which("zzz").is_some() {
        dispatched = Command::new("zzz")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .is_ok();
    }

    if !dispatched {
        return Err(format!("No supported power backend succeeded for '{act}'"));
    }

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("action", &act);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_openrc_and_systemd_services() {
        let rc = "Runlevel: shutdown\n killprocs [ stopped ]\nRunlevel: default\n dbus [ started ]\n waydroid [ started 01:13:26 (0) ]\n elogind [ started ]\nRunlevel: sysinit\n udev [ started ]\n";
        let svcs = parse_openrc_status_output(rc, None);
        assert_eq!(svcs.len(), 4);
        assert_eq!(svcs[0].name, "dbus");
        assert_eq!(svcs[0].status, "started");
        assert_eq!(svcs[0].scope, "default");
        assert_eq!(svcs[1].name, "waydroid");
        assert_eq!(svcs[1].status, "started");
        assert_eq!(svcs[3].scope, "sysinit");

        let sd = "  pipewire.service loaded active running PipeWire Multimedia Service\n  NetworkManager.service loaded active running Network Manager\n  bluetooth.service loaded inactive dead Bluetooth service\n";
        let allowed = &["NetworkManager", "bluetooth"];
        let sd_svcs = parse_systemd_units_output(sd, "system", Some(allowed));
        assert_eq!(sd_svcs.len(), 2);
        assert_eq!(sd_svcs[0].name, "NetworkManager");
        assert_eq!(sd_svcs[1].status, "dead");
        assert!(is_protected_comm("mango"));
        assert!(!is_protected_comm("firefox"));
    }
}
