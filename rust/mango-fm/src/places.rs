use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::json::{self, JsonOut, JsonVal};
use crate::util::{config_dir, data_dir, expand_path, home_dir, human_size};

fn bookmarks_path() -> PathBuf {
    config_dir().join("quickshell").join("fm-bookmarks.json")
}

#[derive(Clone)]
pub struct BookmarkItem {
    pub name: String,
    pub path: String,
}

pub fn load_bookmarks() -> Vec<BookmarkItem> {
    let bp = bookmarks_path();
    let Ok(raw) = fs::read_to_string(&bp) else {
        return default_bookmarks();
    };
    let Ok(val) = json::parse(&raw) else {
        return default_bookmarks();
    };
    let arr = match val {
        JsonVal::Arr(a) => a,
        _ => return default_bookmarks(),
    };
    let mut items = Vec::with_capacity(arr.len());
    for entry in arr {
        if let (Some(n), Some(p)) = (entry.get_str("name"), entry.get_str("path")) {
            items.push(BookmarkItem {
                name: n.to_string(),
                path: p.to_string(),
            });
        }
    }
    items
}

fn default_bookmarks() -> Vec<BookmarkItem> {
    let mut out = Vec::new();
    let home = home_dir();
    let qs = config_dir().join("quickshell");
    if qs.is_dir() {
        out.push(BookmarkItem {
            name: "Quickshell Config".to_string(),
            path: qs.to_string_lossy().into_owned(),
        });
    }
    let wp = home.join("Pictures/Wallpapers");
    if wp.is_dir() {
        out.push(BookmarkItem {
            name: "Wallpapers".to_string(),
            path: wp.to_string_lossy().into_owned(),
        });
    }
    out
}

pub fn save_bookmarks(items: &[BookmarkItem]) -> Result<(), String> {
    let bp = bookmarks_path();
    let parent = bp.parent().ok_or("Invalid bookmarks path")?;
    fs::create_dir_all(parent).map_err(|e| format!("mkdir bookmarks dir: {e}"))?;

    let mut out = JsonOut::new();
    out.arr_start();
    for b in items {
        out.obj_start();
        out.kv_str("name", &b.name);
        out.kv_str("path", &b.path);
        out.obj_end();
    }
    out.arr_end();
    let mut text = out.finish();
    text.push('\n');

    let tmp = parent.join(format!(".tmp_bookmarks_{}", std::process::id()));
    {
        let mut f = fs::File::create(&tmp).map_err(|e| format!("create tmp bookmarks: {e}"))?;
        f.write_all(text.as_bytes())
            .map_err(|e| format!("write tmp bookmarks: {e}"))?;
    }
    fs::rename(&tmp, &bp).map_err(|e| format!("save bookmarks: {e}"))?;
    Ok(())
}

pub fn bookmark_add(raw_path: &str, label: Option<&str>) -> Result<String, String> {
    let target = expand_path(raw_path);
    let canonical = fs::canonicalize(&target).unwrap_or(target);
    let p_str = canonical.to_string_lossy().into_owned();
    let name = match label.map(str::trim).filter(|s| !s.is_empty()) {
        Some(s) => s.to_string(),
        None => canonical
            .file_name()
            .and_then(|n| n.to_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("Bookmark")
            .to_string(),
    };
    let mut items = load_bookmarks();
    if let Some(existing) = items.iter_mut().find(|b| b.path == p_str) {
        existing.name = name;
    } else {
        items.push(BookmarkItem { name, path: p_str });
    }
    save_bookmarks(&items)?;
    get_places()
}

pub fn bookmark_remove(raw_path: &str) -> Result<String, String> {
    let target = expand_path(raw_path);
    let canonical = fs::canonicalize(&target).unwrap_or_else(|_| target.clone());
    let cand1 = target.to_string_lossy().into_owned();
    let cand2 = canonical.to_string_lossy().into_owned();
    let mut items = load_bookmarks();
    items.retain(|b| b.path != cand1 && b.path != cand2 && b.path != raw_path);
    save_bookmarks(&items)?;
    get_places()
}

fn unescape_mount_field(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 3 < bytes.len() {
            if let Ok(code) = u8::from_str_radix(std::str::from_utf8(&bytes[i + 1..i + 4]).unwrap_or(""), 8) {
                out.push(code as char);
                i += 4;
                continue;
            }
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

fn df_usage_map() -> HashMap<String, (u64, u64, u64, u64)> {
    let mut map = HashMap::new();
    let Ok(output) = Command::new("df")
        .args(["-k", "-P"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    else {
        return map;
    };
    if !output.status.success() {
        return map;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines().skip(1) {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 6 {
            continue;
        }
        let Ok(total_kb) = cols[1].parse::<u64>() else { continue };
        let Ok(used_kb) = cols[2].parse::<u64>() else { continue };
        let Ok(avail_kb) = cols[3].parse::<u64>() else { continue };
        let pct_str = cols[4].trim_end_matches('%');
        let pct = pct_str.parse::<u64>().unwrap_or(0);
        let mnt = cols[5..].join(" ");
        map.insert(
            mnt,
            (
                total_kb.saturating_mul(1024),
                used_kb.saturating_mul(1024),
                avail_kb.saturating_mul(1024),
                pct,
            ),
        );
    }
    map
}

struct DriveEntry {
    label: String,
    mount_point: String,
    device: String,
    fs_type: String,
    total_bytes: u64,
    used_bytes: u64,
    avail_bytes: u64,
    used_pct: u64,
    removable: bool,
}

fn list_drives() -> Vec<DriveEntry> {
    let df_map = df_usage_map();
    let Ok(mounts_raw) = fs::read_to_string("/proc/mounts") else {
        return Vec::new();
    };
    let mut seen_mounts = HashSet::new();
    let mut drives = Vec::new();
    let ignored_fs = [
        "proc", "sysfs", "tmpfs", "devtmpfs", "devpts", "cgroup", "cgroup2", "pstore", "bpf",
        "tracefs", "debugfs", "securityfs", "configfs", "fusectl", "mqueue", "hugetlbfs",
        "ramfs", "autofs", "efivarfs", "binfmt_misc", "squashfs", "overlay", "rpc_pipefs",
        "nfsd", "fuse.portal", "fuse.gvfsd-fuse", "nsfs",
    ];

    for line in mounts_raw.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 3 {
            continue;
        }
        let dev = unescape_mount_field(parts[0]);
        let mnt = unescape_mount_field(parts[1]);
        let fstype = parts[2].to_string();

        if ignored_fs.contains(&fstype.as_str()) {
            continue;
        }
        if mnt.starts_with("/sys") || mnt.starts_with("/proc") || mnt.starts_with("/dev") {
            continue;
        }
        if mnt.starts_with("/boot") || mnt == "/efi" {
            continue;
        }
        let is_real_block = dev.starts_with("/dev/");
        let is_user_media =
            mnt.starts_with("/run/media") || mnt.starts_with("/media") || mnt.starts_with("/mnt");
        if !is_real_block && !is_user_media && mnt != "/" && mnt != "/home" {
            continue;
        }
        if !seen_mounts.insert(mnt.clone()) {
            continue;
        }
        let Some(&(total_b, used_b, avail_b, pct)) = df_map.get(&mnt) else {
            continue;
        };
        if total_b == 0 {
            continue;
        }
        let removable = is_user_media
            || dev.contains("usb")
            || dev.contains("mmcblk")
            || fstype == "vfat"
            || fstype == "exfat"
            || fstype == "ntfs"
            || fstype == "ntfs3";

        let label = if mnt == "/" {
            "System Root".to_string()
        } else if mnt == "/home" {
            "Home Volume".to_string()
        } else {
            Path::new(&mnt)
                .file_name()
                .and_then(|n| n.to_str())
                .filter(|s| !s.is_empty())
                .unwrap_or(&mnt)
                .to_string()
        };

        drives.push(DriveEntry {
            label,
            mount_point: mnt,
            device: dev,
            fs_type: fstype,
            total_bytes: total_b,
            used_bytes: used_b,
            avail_bytes: avail_b,
            used_pct: pct,
            removable,
        });
    }
    drives
}

fn trash_item_count() -> u64 {
    let trash_info = data_dir().join("Trash").join("info");
    if let Ok(rd) = fs::read_dir(&trash_info) {
        return rd
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().ends_with(".trashinfo"))
            .count() as u64;
    }
    let trash_files = data_dir().join("Trash").join("files");
    if let Ok(rd) = fs::read_dir(&trash_files) {
        return rd.count() as u64;
    }
    0
}

pub fn get_places() -> Result<String, String> {
    let home = home_dir();
    let mut places: Vec<(&str, &str, PathBuf)> = vec![("Home", "󰋜", home.clone())];

    let candidates = [
        ("Desktop", "󰇄", home.join("Desktop")),
        ("Documents", "󰈙", home.join("Documents")),
        ("Downloads", "󰉍", home.join("Downloads")),
        ("Pictures", "󰉏", home.join("Pictures")),
        ("Wallpapers", "󰸉", home.join("Pictures/Wallpapers")),
        ("Music", "󰝚", home.join("Music")),
        ("Videos", "󰕧", home.join("Videos")),
    ];
    for (name, icon, path) in candidates {
        if path.is_dir() {
            places.push((name, icon, path));
        }
    }

    let bookmarks = load_bookmarks();
    let drives = list_drives();
    let trash_count = trash_item_count();
    let trash_path = data_dir().join("Trash");

    let mut out = JsonOut::with_capacity(2048);
    out.obj_start();

    out.kv_str("home", &home.to_string_lossy());
    out.kv_str("trashPath", &trash_path.to_string_lossy());
    out.kv_u64("trashCount", trash_count);

    out.key("places");
    out.arr_start();
    for (name, icon, p) in places {
        out.obj_start();
        out.kv_str("name", name);
        out.kv_str("icon", icon);
        out.kv_str("path", &p.to_string_lossy());
        out.obj_end();
    }
    out.arr_end();

    out.key("bookmarks");
    out.arr_start();
    for b in &bookmarks {
        out.obj_start();
        out.kv_str("name", &b.name);
        out.kv_str("path", &b.path);
        out.kv_bool("exists", Path::new(&b.path).exists());
        out.obj_end();
    }
    out.arr_end();

    out.key("drives");
    out.arr_start();
    for d in &drives {
        out.obj_start();
        out.kv_str("label", &d.label);
        out.kv_str("mountPoint", &d.mount_point);
        out.kv_str("device", &d.device);
        out.kv_str("fsType", &d.fs_type);
        out.kv_u64("totalBytes", d.total_bytes);
        out.kv_u64("usedBytes", d.used_bytes);
        out.kv_u64("availBytes", d.avail_bytes);
        out.kv_str("totalHuman", &human_size(d.total_bytes));
        out.kv_str("availHuman", &human_size(d.avail_bytes));
        out.kv_u64("usedPct", d.used_pct);
        out.kv_bool("removable", d.removable);
        out.obj_end();
    }
    out.arr_end();

    out.obj_end();
    Ok(out.finish())
}
