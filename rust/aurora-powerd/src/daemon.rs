use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

use crate::config::{config_path, PowerConfig, Profile};
use crate::json::JsonOut;
use crate::sysfs::{apply_profile, build_status_json, detect_battery_and_ac};

pub const DEFAULT_SOCKET_PATH: &str = "/run/aurora-powerd.sock";
const MAX_LINE_BYTES: usize = 256;

pub fn socket_path() -> PathBuf {
    env::var_os("AURORA_POWERD_SOCK")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_SOCKET_PATH))
}

struct DaemonState {
    config: PowerConfig,
    config_file: PathBuf,
}

fn error_json(msg: &str) -> String {
    let mut o = JsonOut::with_capacity(128);
    o.obj_start();
    o.kv_bool("ok", false);
    o.kv_str("error", msg);
    o.obj_end();
    o.finish()
}

fn handle_command(raw_line: &str, shared: &Arc<Mutex<DaemonState>>) -> String {
    let trimmed = raw_line.trim();
    if trimmed.is_empty() {
        return error_json("Empty command");
    }
    let mut parts = trimmed.split_whitespace();
    let Some(cmd) = parts.next() else {
        return error_json("Empty command");
    };

    match cmd {
        "status" => {
            let Ok(guard) = shared.lock() else {
                return error_json("Daemon state poisoned");
            };
            build_status_json(true, &guard.config)
        }
        "set" => {
            let Some(prof_raw) = parts.next() else {
                return error_json("Usage: set <power-saver|balanced|performance>");
            };
            if parts.next().is_some() {
                return error_json("Too many arguments for set");
            }
            let Some(prof) = Profile::parse(prof_raw) else {
                return error_json(&format!("Unknown profile '{prof_raw}'"));
            };
            let Ok(mut guard) = shared.lock() else {
                return error_json("Daemon state poisoned");
            };
            let mut next_cfg = guard.config.clone();
            next_cfg.profile = prof;
            if let Err(e) = apply_profile(&next_cfg) {
                return error_json(&e);
            }
            let _ = next_cfg.save_to(&guard.config_file);
            guard.config = next_cfg;
            build_status_json(true, &guard.config)
        }
        "config" => {
            let Some(key) = parts.next() else {
                return error_json("Usage: config <key> <value>");
            };
            let Some(val) = parts.next() else {
                return error_json("Usage: config <key> <value>");
            };
            if parts.next().is_some() {
                return error_json("Too many arguments for config");
            }
            let Ok(mut guard) = shared.lock() else {
                return error_json("Daemon state poisoned");
            };
            let mut next_cfg = guard.config.clone();
            if let Err(e) = next_cfg.set_field(key, val) {
                return error_json(&e);
            }
            if next_cfg.auto_switch {
                let (has_bat, on_ac) = detect_battery_and_ac();
                if has_bat {
                    next_cfg.profile = if on_ac {
                        next_cfg.ac_profile
                    } else {
                        next_cfg.battery_profile
                    };
                }
            }
            if let Err(e) = apply_profile(&next_cfg) {
                return error_json(&e);
            }
            let _ = next_cfg.save_to(&guard.config_file);
            guard.config = next_cfg;
            build_status_json(true, &guard.config)
        }
        other => error_json(&format!("Unsupported daemon command '{other}'")),
    }
}

fn handle_client(stream: UnixStream, shared: &Arc<Mutex<DaemonState>>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));

    let Ok(writer_stream) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(stream.take((MAX_LINE_BYTES + 1) as u64));
    let mut line = String::new();
    let resp = match reader.read_line(&mut line) {
        Ok(0) => return,
        Ok(n) if n > MAX_LINE_BYTES && !line.ends_with('\n') => {
            error_json("Command exceeds 256 byte limit")
        }
        Ok(_) => handle_command(&line, shared),
        Err(e) => error_json(&format!("Read error: {e}")),
    };

    let mut writer = writer_stream;
    let _ = writer.write_all(resp.as_bytes());
    let _ = writer.write_all(b"\n");
    let _ = writer.flush();
}

pub fn send_request(sock: &Path, req: &str) -> Result<String, String> {
    let mut stream = UnixStream::connect(sock)
        .map_err(|e| format!("Failed connecting to {}: {e}", sock.display()))?;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(2)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(2)));
    stream
        .write_all(req.as_bytes())
        .and_then(|_| stream.write_all(b"\n"))
        .and_then(|_| stream.flush())
        .map_err(|e| format!("Failed writing to daemon socket: {e}"))?;

    let mut reader = BufReader::new(stream);
    let mut resp = String::new();
    reader
        .read_line(&mut resp)
        .map_err(|e| format!("Failed reading daemon response: {e}"))?;
    let trimmed = resp.trim().to_string();
    if trimmed.is_empty() {
        return Err("Empty response from aurora-powerd".to_string());
    }
    Ok(trimmed)
}

fn spawn_watcher(shared: Arc<Mutex<DaemonState>>) {
    thread::spawn(move || {
        let mut last_on_ac: Option<bool> = None;
        let mut prev_mono = Instant::now();
        let mut prev_wall = SystemTime::now();

        loop {
            thread::sleep(Duration::from_secs(3));

            let now_mono = Instant::now();
            let now_wall = SystemTime::now();
            let mono_elapsed = now_mono.duration_since(prev_mono).as_secs_f64();
            let wall_elapsed = now_wall
                .duration_since(prev_wall)
                .map(|d| d.as_secs_f64())
                .unwrap_or(mono_elapsed);
            prev_mono = now_mono;
            prev_wall = now_wall;

            let resumed = (wall_elapsed - mono_elapsed) > 15.0;
            let (has_bat, on_ac) = detect_battery_and_ac();

            let Ok(mut guard) = shared.lock() else {
                continue;
            };

            let mut need_apply = resumed;
            let mut changed_profile = false;
            if guard.config.auto_switch && has_bat && (last_on_ac != Some(on_ac) || resumed) {
                let target = if on_ac {
                    guard.config.ac_profile
                } else {
                    guard.config.battery_profile
                };
                if guard.config.profile != target {
                    guard.config.profile = target;
                    changed_profile = true;
                }
                need_apply = true;
            }
            last_on_ac = Some(on_ac);

            if need_apply {
                let _ = apply_profile(&guard.config);
                if changed_profile {
                    let _ = guard.config.save_to(&guard.config_file);
                }
            }
        }
    });
}

fn bind_listener(sock: &Path) -> Result<UnixListener, String> {
    if sock.exists() {
        if UnixStream::connect(sock).is_ok() {
            return Err(format!(
                "Another aurora-powerd instance is already listening on {}",
                sock.display()
            ));
        }
        fs::remove_file(sock)
            .map_err(|e| format!("Failed removing stale socket {}: {e}", sock.display()))?;
    }
    if let Some(parent) = sock.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Failed creating socket dir {}: {e}", parent.display()))?;
    }
    let listener = UnixListener::bind(sock)
        .map_err(|e| format!("Failed binding socket {}: {e}", sock.display()))?;
    fs::set_permissions(sock, fs::Permissions::from_mode(0o666))
        .map_err(|e| format!("Failed setting permissions on {}: {e}", sock.display()))?;
    Ok(listener)
}

pub fn run_daemon() -> Result<(), String> {
    let sock = socket_path();
    let cfg_file = config_path();
    let cfg = PowerConfig::load_from(&cfg_file);
    let _ = apply_profile(&cfg);

    let listener = bind_listener(&sock)?;
    let shared = Arc::new(Mutex::new(DaemonState {
        config: cfg,
        config_file: cfg_file,
    }));

    spawn_watcher(Arc::clone(&shared));

    for incoming in listener.incoming() {
        match incoming {
            Ok(stream) => handle_client(stream, &shared),
            Err(_) => thread::sleep(Duration::from_millis(50)),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unix_socket_roundtrip() {
        let base = env::temp_dir().join(format!("aurora_powerd_sock_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        let sock = base.join("powerd.sock");
        let cfg_file = base.join("powerd.conf");

        let listener = bind_listener(&sock).unwrap();
        let mode = fs::metadata(&sock).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o666);

        let shared = Arc::new(Mutex::new(DaemonState {
            config: PowerConfig::default(),
            config_file: cfg_file.clone(),
        }));
        let shared_srv = Arc::clone(&shared);
        thread::spawn(move || {
            for stream in listener.incoming().take(2).flatten() {
                handle_client(stream, &shared_srv);
            }
        });

        let status_raw = send_request(&sock, "status").unwrap();
        assert!(status_raw.contains("\"ok\":true"));
        assert!(status_raw.contains("\"daemonRunning\":true"));
        assert!(status_raw.contains("\"backend\":\"aurora-powerd\""));

        let bad_raw = send_request(&sock, "bogus").unwrap();
        assert!(bad_raw.contains("\"ok\":false"));

        let _ = fs::remove_dir_all(&base);
    }
}
