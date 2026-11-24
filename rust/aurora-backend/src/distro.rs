use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::json::{self, JsonOut};
use crate::util::{
    atomic_write, cache_dir, data_dir, format_age, now_unix_secs, run_stdout, which,
};

const CACHE_TTL_SECS: u64 = 900;

pub fn parse_os_release(txt: &str) -> (&'static str, String) {
    let mut id = String::new();
    let mut id_like = String::new();
    let mut pretty = String::new();

    for line in txt.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("ID=") {
            id = rest
                .trim_matches(|c| c == '"' || c == '\'')
                .to_ascii_lowercase();
        } else if let Some(rest) = trimmed.strip_prefix("ID_LIKE=") {
            id_like = rest
                .trim_matches(|c| c == '"' || c == '\'')
                .to_ascii_lowercase();
        } else if let Some(rest) = trimmed.strip_prefix("PRETTY_NAME=") {
            pretty = rest.trim_matches(|c| c == '"' || c == '\'').to_string();
        }
    }

    let combined = format!("{id} {id_like}");
    let family = if combined.split_whitespace().any(|tok| {
        matches!(
            tok,
            "arch" | "cachyos" | "endeavouros" | "manjaro" | "artix"
        )
    }) {
        "arch"
    } else if combined
        .split_whitespace()
        .any(|tok| matches!(tok, "fedora" | "nobara" | "ultramarine" | "rhel" | "centos"))
    {
        "fedora"
    } else if combined
        .split_whitespace()
        .any(|tok| matches!(tok, "gentoo" | "funtoo"))
    {
        "gentoo"
    } else {
        "linux"
    };

    if pretty.is_empty() {
        pretty = "Linux".to_string();
    }
    (family, pretty)
}

pub fn detect_init_and_seat() -> (&'static str, &'static str, bool) {
    let has_systemd = Path::new("/run/systemd/system").is_dir();
    let has_rc = which("rc-status").is_some() || Path::new("/run/openrc").is_dir();
    let init_sys = if has_systemd {
        "systemd"
    } else if has_rc {
        "openrc"
    } else {
        "other"
    };

    let has_elogind = Path::new("/run/elogind.pid").exists()
        || Path::new("/sys/fs/cgroup/elogind").is_dir()
        || (!has_systemd && which("loginctl").is_some());
    let seat_mgr = if has_systemd {
        "systemd-logind"
    } else if has_elogind {
        "elogind"
    } else {
        "none"
    };

    let has_openrc_user = has_rc && run_stdout("rc-status", &["--user", "-a"]).is_some();
    (init_sys, seat_mgr, has_openrc_user)
}

fn count_flatpak_apps() -> u64 {
    let mut total = 0u64;
    for base in [
        Path::new("/var/lib/flatpak/app").to_path_buf(),
        data_dir().join("flatpak/app"),
    ] {
        if let Ok(rd) = fs::read_dir(&base) {
            for ent in rd.flatten() {
                let name = ent.file_name().to_string_lossy().into_owned();
                if !name.starts_with('.') && ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    total += 1;
                }
            }
        }
    }
    total
}

fn gentoo_pkg_db_stats(pkg_db: &Path) -> (u64, bool) {
    let Ok(cats) = fs::read_dir(pkg_db) else {
        return (0, false);
    };
    let mut count = 0u64;
    let mut merging = false;
    for cat in cats.flatten() {
        let cname = cat.file_name().to_string_lossy().into_owned();
        if cname.starts_with('.') || !cat.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            continue;
        }
        if let Ok(pkgs) = fs::read_dir(cat.path()) {
            for pkg in pkgs.flatten() {
                let pname = pkg.file_name().to_string_lossy().into_owned();
                if pname.starts_with('.') || !pkg.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                    continue;
                }
                if pname.contains("-MERGING-") {
                    merging = true;
                    continue;
                }
                count += 1;
            }
        }
    }
    (count, merging)
}

fn gentoo_world_count(world_file: &Path) -> u64 {
    let Ok(raw) = fs::read_to_string(world_file) else {
        return 0;
    };
    raw.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .count() as u64
}

fn gentoo_repos(repos_dir: &Path) -> Vec<String> {
    let mut repos = Vec::new();
    if let Ok(rd) = fs::read_dir(repos_dir) {
        for ent in rd.flatten() {
            let name = ent.file_name().to_string_lossy().into_owned();
            if !name.starts_with('.') && ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                repos.push(name);
            }
        }
    }
    repos.sort();
    repos
}

fn arch_repos_from_conf(conf_txt: &str) -> Vec<String> {
    let mut repos = Vec::new();
    for line in conf_txt.lines() {
        let t = line.trim();
        if t.starts_with('[') && t.ends_with(']') && t.len() > 2 {
            let name = t[1..t.len() - 1].trim();
            if name != "options" && !name.is_empty() {
                repos.push(name.to_string());
            }
        }
    }
    repos
}

fn fedora_enabled_repos(repos_dir: &Path) -> Vec<String> {
    let mut repos = Vec::new();
    let Ok(rd) = fs::read_dir(repos_dir) else {
        return repos;
    };
    for ent in rd.flatten() {
        let path = ent.path();
        if path.extension().and_then(|e| e.to_str()) != Some("repo") {
            continue;
        }
        let Ok(txt) = fs::read_to_string(&path) else {
            continue;
        };
        let mut cur_id: Option<String> = None;
        let mut enabled = true;
        for line in txt.lines() {
            let t = line.trim();
            if t.is_empty() || t.starts_with('#') || t.starts_with(';') {
                continue;
            }
            if t.starts_with('[') && t.ends_with(']') && t.len() > 2 {
                if let Some(id) = cur_id.take() {
                    if enabled {
                        repos.push(id);
                    }
                }
                cur_id = Some(t[1..t.len() - 1].trim().to_string());
                enabled = true;
            } else if let Some((k, v)) = t.split_once('=') {
                if k.trim().eq_ignore_ascii_case("enabled") {
                    let val = v.trim();
                    enabled = val == "1" || val.eq_ignore_ascii_case("true");
                }
            }
        }
        if let Some(id) = cur_id {
            if enabled {
                repos.push(id);
            }
        }
    }
    repos.sort();
    repos.dedup();
    repos
}

struct DistroStatus {
    family: &'static str,
    pretty_name: String,
    init_system: &'static str,
    seat_manager: &'static str,
    has_openrc_user: bool,
    package_manager: &'static str,
    installed_count: u64,
    world_count: u64,
    repos: Vec<String>,
    sync_status: String,
    updates_checked: bool,
    pending_count: u64,
    db_locked: bool,
    preserved_rebuild: bool,
    aur_helper: String,
    flatpak_count: u64,
    update_cmd: String,
}

fn gather_status() -> DistroStatus {
    let os_txt = fs::read_to_string("/etc/os-release").unwrap_or_default();
    let (family, pretty_name) = parse_os_release(&os_txt);
    let (init_system, seat_manager, has_openrc_user) = detect_init_and_seat();
    let flatpak_count = count_flatpak_apps();

    match family {
        "gentoo" => {
            let (installed_count, db_locked) = gentoo_pkg_db_stats(Path::new("/var/db/pkg"));
            let world_count = gentoo_world_count(Path::new("/var/lib/portage/world"));
            let repos = gentoo_repos(Path::new("/var/db/repos"));
            let sync_probe = [
                Path::new("/var/db/repos/gentoo/metadata/timestamp.chk"),
                Path::new("/var/db/repos/gentoo"),
            ]
            .into_iter()
            .find_map(|p| fs::metadata(p).ok()?.modified().ok())
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64);
            let sync_status = match sync_probe {
                Some(ts) => format!("Synced {}", format_age(ts, now_unix_secs())),
                None => "Repository timestamp unavailable".to_string(),
            };
            let reg_path = Path::new("/var/lib/portage/preserved_libs_registry");
            let preserved_rebuild = if let Ok(raw) = fs::read_to_string(reg_path) {
                let t = raw.trim();
                !t.is_empty() && t != "{}" && t != "(dp0\n." && t != "(dp1\n."
            } else {
                fs::metadata(reg_path)
                    .map(|m| m.len() > 16)
                    .unwrap_or(false)
            };
            DistroStatus {
                family,
                pretty_name,
                init_system,
                seat_manager,
                has_openrc_user,
                package_manager: "Portage (emerge)",
                installed_count,
                world_count,
                repos,
                sync_status,
                updates_checked: false,
                pending_count: 0,
                db_locked,
                preserved_rebuild,
                aur_helper: String::new(),
                flatpak_count,
                update_cmd: "sudo emaint sync -a && sudo emerge -avuDN @world".to_string(),
            }
        }
        "arch" => {
            let mut installed_count = 0u64;
            if let Ok(rd) = fs::read_dir("/var/lib/pacman/local") {
                for ent in rd.flatten() {
                    let name = ent.file_name().to_string_lossy().into_owned();
                    if !name.starts_with('.')
                        && name != "ALPM_DB_VERSION"
                        && ent.file_type().map(|t| t.is_dir()).unwrap_or(false)
                    {
                        installed_count += 1;
                    }
                }
            }
            let conf_txt = fs::read_to_string("/etc/pacman.conf").unwrap_or_default();
            let repos = arch_repos_from_conf(&conf_txt);
            let aur_helper = ["paru", "yay"]
                .into_iter()
                .find(|h| which(h).is_some())
                .unwrap_or("")
                .to_string();
            let db_locked = Path::new("/var/lib/pacman/db.lck").exists();

            let mut updates_checked = false;
            let mut pending_count = 0u64;
            if which("checkupdates").is_some() {
                if let Ok(out) = Command::new("checkupdates").output() {
                    if out.status.code() == Some(0) || out.status.code() == Some(2) {
                        updates_checked = true;
                        let s = String::from_utf8_lossy(&out.stdout);
                        pending_count = s.lines().filter(|l| !l.trim().is_empty()).count() as u64;
                    }
                }
            } else if which("pacman").is_some() {
                if let Ok(out) = Command::new("pacman").arg("-Qu").output() {
                    if out.status.code() == Some(0) || out.status.code() == Some(1) {
                        updates_checked = true;
                        let s = String::from_utf8_lossy(&out.stdout);
                        pending_count = s.lines().filter(|l| !l.trim().is_empty()).count() as u64;
                    }
                }
            }

            let sync_status = if updates_checked {
                if pending_count == 0 {
                    "Up to date".to_string()
                } else {
                    format!("{pending_count} updates pending")
                }
            } else {
                "Run pacman -Sy or checkupdates".to_string()
            };

            let update_cmd = match aur_helper.as_str() {
                "paru" => "paru -Syu".to_string(),
                "yay" => "yay -Syu".to_string(),
                _ => "sudo pacman -Syu".to_string(),
            };

            DistroStatus {
                family,
                pretty_name,
                init_system,
                seat_manager,
                has_openrc_user,
                package_manager: "pacman",
                installed_count,
                world_count: 0,
                repos,
                sync_status,
                updates_checked,
                pending_count,
                db_locked,
                preserved_rebuild: false,
                aur_helper,
                flatpak_count,
                update_cmd,
            }
        }
        "fedora" => {
            let installed_count = if which("rpm").is_some() {
                run_stdout("rpm", &["-qa", "--qf", "%{NAME}\n"])
                    .map(|s| s.lines().filter(|l| !l.trim().is_empty()).count() as u64)
                    .unwrap_or(0)
            } else {
                0
            };
            let repos = fedora_enabled_repos(Path::new("/etc/yum.repos.d"));
            let mut updates_checked = false;
            let mut pending_count = 0u64;
            if which("dnf").is_some() {
                if let Ok(out) = Command::new("dnf")
                    .args(["check-update", "-q", "--cacheonly"])
                    .output()
                {
                    match out.status.code() {
                        Some(0) => {
                            updates_checked = true;
                            pending_count = 0;
                        }
                        Some(100) => {
                            updates_checked = true;
                            let s = String::from_utf8_lossy(&out.stdout);
                            pending_count = s
                                .lines()
                                .map(str::trim)
                                .filter(|l| {
                                    !l.is_empty()
                                        && !l.starts_with("Obsoleting")
                                        && !l.starts_with("Security:")
                                        && l.split_whitespace().count() >= 2
                                })
                                .count() as u64;
                        }
                        _ => {}
                    }
                }
            }
            let sync_status = if updates_checked {
                if pending_count == 0 {
                    "Cache up to date".to_string()
                } else {
                    format!("{pending_count} updates cached")
                }
            } else {
                "Cached check unavailable".to_string()
            };
            DistroStatus {
                family,
                pretty_name,
                init_system,
                seat_manager,
                has_openrc_user,
                package_manager: "dnf (rpm)",
                installed_count,
                world_count: 0,
                repos,
                sync_status,
                updates_checked,
                pending_count,
                db_locked: false,
                preserved_rebuild: false,
                aur_helper: String::new(),
                flatpak_count,
                update_cmd: "sudo dnf upgrade --refresh".to_string(),
            }
        }
        _ => DistroStatus {
            family,
            pretty_name,
            init_system,
            seat_manager,
            has_openrc_user,
            package_manager: "System",
            installed_count: 0,
            world_count: 0,
            repos: Vec::new(),
            sync_status: "Unsupported package query".to_string(),
            updates_checked: false,
            pending_count: 0,
            db_locked: false,
            preserved_rebuild: false,
            aur_helper: String::new(),
            flatpak_count,
            update_cmd: String::new(),
        },
    }
}

fn serialize_status(st: &DistroStatus) -> String {
    let mut o = JsonOut::with_capacity(512);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("family", st.family);
    o.kv_str("prettyName", &st.pretty_name);
    o.kv_str("initSystem", st.init_system);
    o.kv_str("seatManager", st.seat_manager);
    o.kv_bool("hasOpenRcUser", st.has_openrc_user);
    o.kv_str("packageManager", st.package_manager);
    o.kv_u64("installedCount", st.installed_count);
    o.kv_u64("worldCount", st.world_count);
    o.key("repos");
    o.arr_start();
    for r in &st.repos {
        o.str(r);
    }
    o.arr_end();
    o.kv_str("syncStatus", &st.sync_status);
    o.kv_bool("updatesChecked", st.updates_checked);
    o.kv_u64("pendingCount", st.pending_count);
    o.kv_bool("dbLocked", st.db_locked);
    o.kv_bool("preservedRebuild", st.preserved_rebuild);
    o.kv_str("aurHelper", &st.aur_helper);
    o.kv_u64("flatpakCount", st.flatpak_count);
    o.kv_str("updateCmd", &st.update_cmd);
    o.obj_end();
    o.finish()
}

pub fn cmd_distro(args: &[String]) -> Result<(), String> {
    let op = args.first().map(String::as_str).unwrap_or("status");
    if op != "status" && op != "refresh" {
        return Err(format!("Unknown distro command '{op}'"));
    }

    let cache_path = cache_dir().join("quickshell").join("distro-status.json");
    if op == "status" {
        if let Ok(meta) = fs::metadata(&cache_path) {
            if let Ok(modified) = meta.modified() {
                let age = SystemTime::now()
                    .duration_since(modified)
                    .unwrap_or(Duration::from_secs(CACHE_TTL_SECS + 1));
                if age < Duration::from_secs(CACHE_TTL_SECS) {
                    if let Ok(cached) = fs::read_to_string(&cache_path) {
                        if let Ok(val) = json::parse(&cached) {
                            if val.get_bool("ok") == Some(true) {
                                println!("{}", cached.trim());
                                return Ok(());
                            }
                        }
                    }
                }
            }
        }
    }

    let st = gather_status();
    let payload = serialize_status(&st);
    let mut to_disk = payload.clone();
    to_disk.push('\n');
    let _ = atomic_write(&cache_path, to_disk.as_bytes(), 0o600);
    println!("{payload}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_arch_fedora_gentoo_os_release() {
        let (f1, p1) =
            parse_os_release("NAME=\"Arch Linux\"\nID=arch\nPRETTY_NAME=\"Arch Linux\"\n");
        assert_eq!(f1, "arch");
        assert_eq!(p1, "Arch Linux");

        let (f2, p2) = parse_os_release(
            "NAME=\"Fedora Linux\"\nID=fedora\nPRETTY_NAME=\"Fedora Linux 42 (Workstation Edition)\"\n",
        );
        assert_eq!(f2, "fedora");
        assert!(p2.contains("Fedora"));

        let (f3, p3) = parse_os_release("NAME='Gentoo'\nID='gentoo'\nPRETTY_NAME='Gentoo Linux'\n");
        assert_eq!(f3, "gentoo");
        assert_eq!(p3, "Gentoo Linux");

        let (f4, _) = parse_os_release("ID=cachyos\nID_LIKE=arch\n");
        assert_eq!(f4, "arch");
    }

    #[test]
    fn parses_pacman_and_fedora_repo_files() {
        let repos =
            arch_repos_from_conf("[options]\nHoldPkg = pacman\n[core]\n[extra]\n[multilib]\n");
        assert_eq!(repos, vec!["core", "extra", "multilib"]);

        let base = std::env::temp_dir().join(format!("aurora_fedora_repos_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        fs::write(
            base.join("fedora.repo"),
            "[fedora]\nname=Fedora\nenabled=1\n[fedora-debuginfo]\nenabled=0\n",
        )
        .unwrap();
        let fed = fedora_enabled_repos(&base);
        assert_eq!(fed, vec!["fedora"]);
        let _ = fs::remove_dir_all(&base);
    }
}
