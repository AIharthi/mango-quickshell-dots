use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::json::{self, JsonOut};
use crate::util::{
    atomic_write, config_dir, data_dir, expand_user_path, home_dir, now_unix_secs, run_stdout,
    unix_secs_to_iso, which,
};

const DEFAULT_REMOTE_URL: &str = "https://github.com/AIharthi/mango-quickshell-dots.git";

#[derive(Debug, Clone, Default)]
struct RepoMeta {
    repo_path: String,
    remote_url: String,
    branch: String,
    installed_commit: String,
    installed_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingCommit {
    pub hash: String,
    pub date: String,
    pub subject: String,
}

struct RepoStatus {
    repo_found: bool,
    repo_path: String,
    remote_url: String,
    branch: String,
    local_commit: String,
    local_subject: String,
    local_date: String,
    installed_commit: String,
    installed_at: String,
    dirty: bool,
    dirty_count: u64,
    behind_count: u64,
    ahead_count: u64,
    up_to_date: bool,
    needs_install: bool,
    has_git: bool,
    has_cargo: bool,
    pending_commits: Vec<PendingCommit>,
}

fn meta_file_path() -> PathBuf {
    config_dir().join("quickshell").join("repo-source.json")
}

fn load_meta() -> RepoMeta {
    let path = meta_file_path();
    let Ok(raw) = fs::read_to_string(&path) else {
        return RepoMeta::default();
    };
    let Ok(val) = json::parse(&raw) else {
        return RepoMeta::default();
    };
    RepoMeta {
        repo_path: val.get_str("repoPath").unwrap_or("").trim().to_string(),
        remote_url: val.get_str("remoteUrl").unwrap_or("").trim().to_string(),
        branch: val.get_str("branch").unwrap_or("").trim().to_string(),
        installed_commit: val
            .get_str("installedCommit")
            .unwrap_or("")
            .trim()
            .to_string(),
        installed_at: val.get_str("installedAt").unwrap_or("").trim().to_string(),
    }
}

fn save_meta(meta: &RepoMeta) -> Result<(), String> {
    let mut o = JsonOut::with_capacity(256);
    o.obj_start();
    o.kv_str("repoPath", &meta.repo_path);
    o.kv_str("remoteUrl", &meta.remote_url);
    o.kv_str("branch", &meta.branch);
    o.kv_str("installedCommit", &meta.installed_commit);
    o.kv_str("installedAt", &meta.installed_at);
    o.obj_end();
    let mut content = o.finish();
    content.push('\n');
    atomic_write(&meta_file_path(), content.as_bytes(), 0o644)
}

fn is_valid_repo_dir(dir: &Path) -> bool {
    dir.join(".git").exists() && dir.join("install.sh").is_file()
}

fn discover_repo(meta: &RepoMeta) -> Option<PathBuf> {
    if !meta.repo_path.is_empty() {
        let p = PathBuf::from(&meta.repo_path);
        if is_valid_repo_dir(&p) {
            return Some(p);
        }
    }
    let candidates = [
        home_dir().join("mango-quickshell-dots"),
        data_dir().join("mango-quickshell-dots"),
        home_dir().join("dotfiles").join("mango-quickshell-dots"),
    ];
    candidates.into_iter().find(|p| is_valid_repo_dir(p))
}

fn run_git(repo: &Path, args: &[&str]) -> Option<String> {
    let mut full = Vec::with_capacity(args.len() + 2);
    full.push("-C");
    let repo_str = repo.to_string_lossy();
    full.push(repo_str.as_ref());
    full.extend_from_slice(args);
    run_stdout("git", &full)
}

pub fn parse_ahead_behind(raw: &str) -> (u64, u64) {
    let mut parts = raw.split_whitespace();
    let ahead = parts
        .next()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0);
    let behind = parts
        .next()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0);
    (ahead, behind)
}

pub fn parse_pending_commits(raw: &str) -> Vec<PendingCommit> {
    let mut out = Vec::new();
    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let mut parts = trimmed.splitn(3, '\x1f');
        let hash = parts.next().unwrap_or("").trim().to_string();
        let date = parts.next().unwrap_or("").trim().to_string();
        let subject = parts.next().unwrap_or("").trim().to_string();
        if !hash.is_empty() {
            out.push(PendingCommit {
                hash,
                date,
                subject,
            });
        }
    }
    out
}

pub fn validate_remote_url(raw: &str) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("Remote URL cannot be empty".to_string());
    }
    if trimmed.starts_with('-')
        || trimmed.chars().any(char::is_whitespace)
        || trimmed.contains('\0')
    {
        return Err("Invalid characters in remote URL".to_string());
    }
    if !(trimmed.starts_with("https://") || trimmed.starts_with("git@")) {
        return Err("Remote URL must start with https:// or git@".to_string());
    }
    Ok(trimmed.to_string())
}

fn gather_status(meta: &RepoMeta) -> RepoStatus {
    let has_git = which("git").is_some();
    let has_cargo = which("cargo").is_some() && which("rustc").is_some();
    let repo_dir = discover_repo(meta);

    let Some(repo) = repo_dir else {
        return RepoStatus {
            repo_found: false,
            repo_path: meta.repo_path.clone(),
            remote_url: if meta.remote_url.is_empty() {
                DEFAULT_REMOTE_URL.to_string()
            } else {
                meta.remote_url.clone()
            },
            branch: if meta.branch.is_empty() {
                "main".to_string()
            } else {
                meta.branch.clone()
            },
            local_commit: String::new(),
            local_subject: String::new(),
            local_date: String::new(),
            installed_commit: meta.installed_commit.clone(),
            installed_at: meta.installed_at.clone(),
            dirty: false,
            dirty_count: 0,
            behind_count: 0,
            ahead_count: 0,
            up_to_date: false,
            needs_install: false,
            has_git,
            has_cargo,
            pending_commits: Vec::new(),
        };
    };

    let repo_path = repo.to_string_lossy().into_owned();
    let remote_url = if has_git {
        run_git(&repo, &["remote", "get-url", "origin"])
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| {
                if meta.remote_url.is_empty() {
                    DEFAULT_REMOTE_URL.to_string()
                } else {
                    meta.remote_url.clone()
                }
            })
    } else {
        DEFAULT_REMOTE_URL.to_string()
    };

    let branch = if has_git {
        let b = run_git(&repo, &["rev-parse", "--abbrev-ref", "HEAD"]).unwrap_or_default();
        if b.is_empty() || b == "HEAD" {
            if meta.branch.is_empty() {
                "main".to_string()
            } else {
                meta.branch.clone()
            }
        } else {
            b
        }
    } else {
        "main".to_string()
    };

    let local_commit = if has_git {
        run_git(&repo, &["rev-parse", "--short=7", "HEAD"]).unwrap_or_default()
    } else {
        String::new()
    };
    let local_full = if has_git {
        run_git(&repo, &["rev-parse", "HEAD"]).unwrap_or_default()
    } else {
        String::new()
    };
    let local_subject = if has_git {
        run_git(&repo, &["log", "-1", "--format=%s", "HEAD"]).unwrap_or_default()
    } else {
        String::new()
    };
    let local_date = if has_git {
        run_git(&repo, &["log", "-1", "--format=%cs", "HEAD"]).unwrap_or_default()
    } else {
        String::new()
    };

    let dirty_count = if has_git {
        run_git(&repo, &["status", "--porcelain"])
            .map(|s| s.lines().filter(|l| !l.trim().is_empty()).count() as u64)
            .unwrap_or(0)
    } else {
        0
    };
    let dirty = dirty_count > 0;

    let mut ahead_count = 0u64;
    let mut behind_count = 0u64;
    let mut pending_commits = Vec::new();
    if has_git {
        let origin_branch = format!("origin/{branch}");
        let upstream = run_git(&repo, &["rev-parse", "--abbrev-ref", "@{u}"])
            .filter(|s| !s.is_empty())
            .or_else(|| {
                run_git(&repo, &["rev-parse", "--verify", &origin_branch])
                    .map(|_| origin_branch.clone())
            });

        if let Some(up) = upstream {
            let range = format!("HEAD...{up}");
            if let Some(counts) = run_git(&repo, &["rev-list", "--left-right", "--count", &range]) {
                let (ahead, behind) = parse_ahead_behind(&counts);
                ahead_count = ahead;
                behind_count = behind;
            }
            if behind_count > 0 {
                let log_range = format!("HEAD..{up}");
                if let Some(log_raw) = run_git(
                    &repo,
                    &["log", "-n", "10", "--format=%h%x1f%cs%x1f%s", &log_range],
                ) {
                    pending_commits = parse_pending_commits(&log_raw);
                }
            }
        }
    }

    let needs_install = if local_commit.is_empty() {
        false
    } else if meta.installed_commit.is_empty() {
        true
    } else {
        meta.installed_commit != local_commit && !local_full.starts_with(&meta.installed_commit)
    };
    let up_to_date = behind_count == 0 && !needs_install;

    RepoStatus {
        repo_found: true,
        repo_path,
        remote_url,
        branch,
        local_commit,
        local_subject,
        local_date,
        installed_commit: meta.installed_commit.clone(),
        installed_at: meta.installed_at.clone(),
        dirty,
        dirty_count,
        behind_count,
        ahead_count,
        up_to_date,
        needs_install,
        has_git,
        has_cargo,
        pending_commits,
    }
}

fn serialize_status(st: &RepoStatus, extra: Option<(bool, bool, &str)>) -> String {
    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_bool("repoFound", st.repo_found);
    o.kv_str("repoPath", &st.repo_path);
    o.kv_str("remoteUrl", &st.remote_url);
    o.kv_str("branch", &st.branch);
    o.kv_str("localCommit", &st.local_commit);
    o.kv_str("localSubject", &st.local_subject);
    o.kv_str("localDate", &st.local_date);
    o.kv_str("installedCommit", &st.installed_commit);
    o.kv_str("installedAt", &st.installed_at);
    o.kv_bool("dirty", st.dirty);
    o.kv_u64("dirtyCount", st.dirty_count);
    o.kv_u64("behindCount", st.behind_count);
    o.kv_u64("aheadCount", st.ahead_count);
    o.kv_bool("upToDate", st.up_to_date);
    o.kv_bool("needsInstall", st.needs_install);
    o.kv_bool("hasGit", st.has_git);
    o.kv_bool("hasCargo", st.has_cargo);
    o.key("pendingCommits");
    o.arr_start();
    for c in &st.pending_commits {
        o.obj_start();
        o.kv_str("hash", &c.hash);
        o.kv_str("date", &c.date);
        o.kv_str("subject", &c.subject);
        o.obj_end();
    }
    o.arr_end();
    if let Some((updated, restart_rec, msg)) = extra {
        o.kv_bool("updated", updated);
        o.kv_bool("restartShellRecommended", restart_rec);
        o.kv_str("message", msg);
    }
    o.obj_end();
    o.finish()
}

fn cmd_status() -> Result<(), String> {
    let meta = load_meta();
    let st = gather_status(&meta);
    println!("{}", serialize_status(&st, None));
    Ok(())
}

fn cmd_check() -> Result<(), String> {
    if which("git").is_none() {
        return Err("'git' is not installed".to_string());
    }
    let meta = load_meta();
    let repo = discover_repo(&meta)
        .ok_or_else(|| "Repository not found; set repo path or clone first".to_string())?;
    let repo_str = repo.to_string_lossy().into_owned();

    let out = if which("timeout").is_some() {
        Command::new("timeout")
            .args(["15", "git", "-C", &repo_str, "fetch", "--prune", "origin"])
            .output()
    } else {
        Command::new("git")
            .args(["-C", &repo_str, "fetch", "--prune", "origin"])
            .output()
    }
    .map_err(|e| format!("Failed executing git fetch: {e}"))?;

    if !out.status.success() {
        let err_msg = String::from_utf8_lossy(&out.stderr)
            .lines()
            .next()
            .unwrap_or("git fetch failed")
            .trim()
            .to_string();
        return Err(if err_msg.is_empty() {
            "git fetch origin failed".to_string()
        } else {
            err_msg
        });
    }

    let st = gather_status(&meta);
    println!("{}", serialize_status(&st, None));
    Ok(())
}

fn cmd_set_repo(args: &[String]) -> Result<(), String> {
    let raw_path = args
        .first()
        .ok_or_else(|| "Usage: config-update set-repo <path>".to_string())?;
    let target = expand_user_path(raw_path, "mango-quickshell-dots")?;
    if !is_valid_repo_dir(&target) {
        return Err(format!(
            "'{}' is not a valid mango-quickshell-dots git repository (missing .git or install.sh)",
            target.display()
        ));
    }

    let mut meta = load_meta();
    let new_path = target.to_string_lossy().into_owned();
    if meta.repo_path != new_path {
        meta.repo_path = new_path;
    }
    meta.remote_url = run_git(&target, &["remote", "get-url", "origin"])
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_REMOTE_URL.to_string());
    meta.branch = run_git(&target, &["rev-parse", "--abbrev-ref", "HEAD"])
        .filter(|s| !s.is_empty() && s != "HEAD")
        .unwrap_or_else(|| "main".to_string());
    save_meta(&meta)?;

    let st = gather_status(&meta);
    println!("{}", serialize_status(&st, None));
    Ok(())
}

fn cmd_clone(args: &[String]) -> Result<(), String> {
    if which("git").is_none() {
        return Err("'git' is not installed".to_string());
    }
    let raw_path = args
        .first()
        .map(String::as_str)
        .unwrap_or("~/mango-quickshell-dots");
    let target = expand_user_path(raw_path, "mango-quickshell-dots")?;
    let url = validate_remote_url(
        args.get(1)
            .map(String::as_str)
            .unwrap_or(DEFAULT_REMOTE_URL),
    )?;

    if target.exists() {
        let non_empty = fs::read_dir(&target)
            .map(|mut rd| rd.next().is_some())
            .unwrap_or(true);
        if non_empty {
            return Err(format!(
                "Target directory '{}' already exists and is not empty",
                target.display()
            ));
        }
    }

    let target_str = target.to_string_lossy().into_owned();
    let out = Command::new("git")
        .args(["clone", "--", &url, &target_str])
        .output()
        .map_err(|e| format!("Failed executing git clone: {e}"))?;
    if !out.status.success() {
        let err_msg = String::from_utf8_lossy(&out.stderr)
            .lines()
            .next()
            .unwrap_or("git clone failed")
            .trim()
            .to_string();
        return Err(if err_msg.is_empty() {
            "git clone failed".to_string()
        } else {
            err_msg
        });
    }

    if !is_valid_repo_dir(&target) {
        return Err("Cloned repository does not contain install.sh".to_string());
    }

    let mut meta = load_meta();
    meta.repo_path = target_str;
    meta.remote_url = url;
    meta.branch = run_git(&target, &["rev-parse", "--abbrev-ref", "HEAD"])
        .filter(|s| !s.is_empty() && s != "HEAD")
        .unwrap_or_else(|| "main".to_string());
    save_meta(&meta)?;

    let st = gather_status(&meta);
    println!("{}", serialize_status(&st, None));
    Ok(())
}

fn cmd_apply(args: &[String]) -> Result<(), String> {
    let mut skip_build = false;
    let mut no_pull = false;
    for arg in args {
        match arg.as_str() {
            "--skip-build" => skip_build = true,
            "--no-pull" => no_pull = true,
            other => {
                return Err(format!("Unknown option '{other}' for config-update apply"));
            }
        }
    }

    let mut meta = load_meta();
    let repo = discover_repo(&meta)
        .ok_or_else(|| "Repository not found; set repo path or clone first".to_string())?;
    let pre = gather_status(&meta);

    if !no_pull && pre.behind_count > 0 {
        if pre.dirty {
            return Err(
                "Local repository has uncommitted changes; commit/stash them or sync local files without pulling"
                    .to_string(),
            );
        }
        let repo_str = repo.to_string_lossy().into_owned();
        let out = Command::new("git")
            .args(["-C", &repo_str, "pull", "--ff-only", "origin", &pre.branch])
            .output()
            .map_err(|e| format!("Failed executing git pull: {e}"))?;
        if !out.status.success() {
            let err_msg = String::from_utf8_lossy(&out.stderr)
                .lines()
                .next()
                .unwrap_or("git pull --ff-only failed")
                .trim()
                .to_string();
            return Err(if err_msg.is_empty() {
                "git pull --ff-only failed".to_string()
            } else {
                err_msg
            });
        }
    }

    let install_sh = repo.join("install.sh");
    if !install_sh.is_file() {
        return Err(format!(
            "Missing installer script at {}",
            install_sh.display()
        ));
    }

    let install_str = install_sh.to_string_lossy().into_owned();
    let mut install_args = vec![install_str.as_str(), "--no-system"];
    if skip_build {
        install_args.push("--skip-build");
    }

    let inst_out = Command::new("bash")
        .args(&install_args)
        .current_dir(&repo)
        .output()
        .map_err(|e| format!("Failed running install.sh: {e}"))?;
    if !inst_out.status.success() {
        let err_msg = String::from_utf8_lossy(&inst_out.stderr)
            .lines()
            .last()
            .unwrap_or("install.sh exited with error")
            .trim()
            .to_string();
        return Err(if err_msg.is_empty() {
            "install.sh failed during config update".to_string()
        } else {
            err_msg
        });
    }

    let head_short = run_git(&repo, &["rev-parse", "--short=7", "HEAD"]).unwrap_or_default();
    let remote_url = run_git(&repo, &["remote", "get-url", "origin"])
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| pre.remote_url.clone());
    let branch = run_git(&repo, &["rev-parse", "--abbrev-ref", "HEAD"])
        .filter(|s| !s.is_empty() && s != "HEAD")
        .unwrap_or_else(|| pre.branch.clone());

    meta.repo_path = repo.to_string_lossy().into_owned();
    meta.remote_url = remote_url;
    meta.branch = branch;
    meta.installed_commit = head_short.clone();
    meta.installed_at = unix_secs_to_iso(now_unix_secs());
    save_meta(&meta)?;

    if which("mmsg").is_some() {
        let _ = Command::new("mmsg")
            .args(["dispatch", "reload_config"])
            .output();
    }

    let post = gather_status(&meta);
    let msg = if head_short.is_empty() {
        "Configuration updated and applied".to_string()
    } else {
        format!("Applied Aurora Shell config at commit {head_short}")
    };
    println!("{}", serialize_status(&post, Some((true, true, &msg))));
    Ok(())
}

pub fn cmd_config_update(args: &[String]) -> Result<(), String> {
    let sub = args.first().map(String::as_str).unwrap_or("status");
    let rest = if args.is_empty() { &[][..] } else { &args[1..] };
    match sub {
        "status" => cmd_status(),
        "check" => cmd_check(),
        "set-repo" => cmd_set_repo(rest),
        "clone" => cmd_clone(rest),
        "apply" => cmd_apply(rest),
        other => Err(format!("Unknown config-update action '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_ahead_behind_and_pending_commits() {
        assert_eq!(parse_ahead_behind("0\t3\n"), (0, 3));
        assert_eq!(parse_ahead_behind("2 5"), (2, 5));
        assert_eq!(parse_ahead_behind(""), (0, 0));

        let raw = "abc1234\x1f2026-11-26\x1fAdd power daemon\ndef5678\x1f2026-11-25\x1fFix MSI touchpad\n";
        let commits = parse_pending_commits(raw);
        assert_eq!(commits.len(), 2);
        assert_eq!(commits[0].hash, "abc1234");
        assert_eq!(commits[0].date, "2026-11-26");
        assert_eq!(commits[0].subject, "Add power daemon");
        assert_eq!(commits[1].hash, "def5678");
    }

    #[test]
    fn validates_remote_urls_and_paths() {
        assert!(
            validate_remote_url("https://github.com/AIharthi/mango-quickshell-dots.git").is_ok()
        );
        assert!(validate_remote_url("git@github.com:AIharthi/mango-quickshell-dots.git").is_ok());
        assert!(validate_remote_url("").is_err());
        assert!(validate_remote_url("--upload-pack=evil").is_err());
        assert!(validate_remote_url("http://example.com/repo.git").is_err());
        assert!(validate_remote_url("https://example.com/repo.git extra").is_err());
        assert!(expand_user_path("~/../etc", "mango-quickshell-dots").is_err());
        assert!(expand_user_path("~/mango-quickshell-dots", "mango-quickshell-dots").is_ok());
    }
}
