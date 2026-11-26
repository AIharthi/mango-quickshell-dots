use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;

use crate::distro::parse_os_release;
use crate::json::{self, JsonOut, JsonVal};
use crate::util::{data_dir, run_stdout, which};

#[derive(Clone, Copy)]
struct CatalogItem {
    id: &'static str,
    name: &'static str,
    summary: &'static str,
    category: &'static str,
    icon: &'static str,
    arch_source: &'static str,
    arch_pkg: &'static str,
    fedora_source: &'static str,
    fedora_pkg: &'static str,
    gentoo_pkg: &'static str,
    flatpak_id: &'static str,
}

const CATALOG: &[CatalogItem] = &[
    // Browsers
    CatalogItem {
        id: "firefox",
        name: "Firefox",
        summary: "Fast, privacy-focused open source web browser by Mozilla",
        category: "Browsers",
        icon: "󰈹",
        arch_source: "official",
        arch_pkg: "firefox",
        fedora_source: "official",
        fedora_pkg: "firefox",
        gentoo_pkg: "www-client/firefox",
        flatpak_id: "org.mozilla.firefox",
    },
    CatalogItem {
        id: "chromium",
        name: "Chromium",
        summary: "Open-source web browser project powering Chrome",
        category: "Browsers",
        icon: "󰊯",
        arch_source: "official",
        arch_pkg: "chromium",
        fedora_source: "official",
        fedora_pkg: "chromium",
        gentoo_pkg: "www-client/chromium",
        flatpak_id: "org.chromium.Chromium",
    },
    CatalogItem {
        id: "brave",
        name: "Brave Browser",
        summary: "Chromium browser with built-in ad and tracker blocking",
        category: "Browsers",
        icon: "󰖟",
        arch_source: "aur",
        arch_pkg: "brave-bin",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "com.brave.Browser",
    },
    CatalogItem {
        id: "zen-browser",
        name: "Zen Browser",
        summary: "Calm, customizable Firefox-based browser with vertical tabs",
        category: "Browsers",
        icon: "󰖟",
        arch_source: "aur",
        arch_pkg: "zen-browser-bin",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "app.zen_browser.zen",
    },
    // Development
    CatalogItem {
        id: "neovim",
        name: "Neovim",
        summary: "Hyperextensible Vim-based terminal text editor",
        category: "Development",
        icon: "",
        arch_source: "official",
        arch_pkg: "neovim",
        fedora_source: "official",
        fedora_pkg: "neovim",
        gentoo_pkg: "app-editors/neovim",
        flatpak_id: "io.neovim.nvim",
    },
    CatalogItem {
        id: "vscode",
        name: "Visual Studio Code",
        summary: "Extensible code editor with debugging and Git integration",
        category: "Development",
        icon: "󰨞",
        arch_source: "aur",
        arch_pkg: "visual-studio-code-bin",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "com.visualstudio.code",
    },
    CatalogItem {
        id: "zed",
        name: "Zed",
        summary: "High-performance GPU-accelerated multiplayer code editor",
        category: "Development",
        icon: "󰘦",
        arch_source: "official",
        arch_pkg: "zed",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "dev.zed.Zed",
    },
    CatalogItem {
        id: "helix",
        name: "Helix",
        summary: "Post-modern modal text editor with built-in LSP and tree-sitter",
        category: "Development",
        icon: "󰘦",
        arch_source: "official",
        arch_pkg: "helix",
        fedora_source: "official",
        fedora_pkg: "helix",
        gentoo_pkg: "app-editors/helix",
        flatpak_id: "",
    },
    CatalogItem {
        id: "git",
        name: "Git",
        summary: "Distributed version control system for modern workflows",
        category: "Development",
        icon: "󰊢",
        arch_source: "official",
        arch_pkg: "git",
        fedora_source: "official",
        fedora_pkg: "git",
        gentoo_pkg: "dev-vcs/git",
        flatpak_id: "",
    },
    CatalogItem {
        id: "lazygit",
        name: "Lazygit",
        summary: "Simple terminal UI for fast interactive Git staging and history",
        category: "Development",
        icon: "󰊢",
        arch_source: "official",
        arch_pkg: "lazygit",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "dev-vcs/lazygit",
        flatpak_id: "",
    },
    // Terminals & Shell
    CatalogItem {
        id: "foot",
        name: "Foot",
        summary: "Fast, lightweight, minimalistic Wayland terminal emulator",
        category: "Terminals & Shell",
        icon: "󰆍",
        arch_source: "official",
        arch_pkg: "foot",
        fedora_source: "official",
        fedora_pkg: "foot",
        gentoo_pkg: "gui-apps/foot",
        flatpak_id: "",
    },
    CatalogItem {
        id: "kitty",
        name: "Kitty",
        summary: "GPU-based terminal emulator supporting graphics and ligatures",
        category: "Terminals & Shell",
        icon: "󰆍",
        arch_source: "official",
        arch_pkg: "kitty",
        fedora_source: "official",
        fedora_pkg: "kitty",
        gentoo_pkg: "x11-terms/kitty",
        flatpak_id: "",
    },
    CatalogItem {
        id: "alacritty",
        name: "Alacritty",
        summary: "Cross-platform OpenGL terminal emulator focused on simplicity",
        category: "Terminals & Shell",
        icon: "󰆍",
        arch_source: "official",
        arch_pkg: "alacritty",
        fedora_source: "official",
        fedora_pkg: "alacritty",
        gentoo_pkg: "x11-terms/alacritty",
        flatpak_id: "",
    },
    CatalogItem {
        id: "wezterm",
        name: "WezTerm",
        summary: "GPU-accelerated terminal and multiplexer configured in Lua",
        category: "Terminals & Shell",
        icon: "󰆍",
        arch_source: "official",
        arch_pkg: "wezterm",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "org.wezfurlong.wezterm",
    },
    CatalogItem {
        id: "tmux",
        name: "tmux",
        summary: "Terminal multiplexer for detachable panes and sessions",
        category: "Terminals & Shell",
        icon: "󰆍",
        arch_source: "official",
        arch_pkg: "tmux",
        fedora_source: "official",
        fedora_pkg: "tmux",
        gentoo_pkg: "app-misc/tmux",
        flatpak_id: "",
    },
    CatalogItem {
        id: "starship",
        name: "Starship Prompt",
        summary: "Minimal, blazing-fast customizable prompt for any shell",
        category: "Terminals & Shell",
        icon: "󰘧",
        arch_source: "official",
        arch_pkg: "starship",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "app-shells/starship",
        flatpak_id: "",
    },
    // Media & Graphics
    CatalogItem {
        id: "obs-studio",
        name: "OBS Studio",
        summary: "Open-source studio for screen recording and live streaming",
        category: "Media & Graphics",
        icon: "󰑋",
        arch_source: "official",
        arch_pkg: "obs-studio",
        fedora_source: "rpmfusion",
        fedora_pkg: "obs-studio",
        gentoo_pkg: "media-video/obs-studio",
        flatpak_id: "com.obsproject.Studio",
    },
    CatalogItem {
        id: "vlc",
        name: "VLC Media Player",
        summary: "Portable multimedia player supporting virtually every codec",
        category: "Media & Graphics",
        icon: "󰕼",
        arch_source: "official",
        arch_pkg: "vlc",
        fedora_source: "rpmfusion",
        fedora_pkg: "vlc",
        gentoo_pkg: "media-video/vlc",
        flatpak_id: "org.videolan.VLC",
    },
    CatalogItem {
        id: "mpv",
        name: "mpv",
        summary: "Minimal hardware-accelerated video player with clean OSC",
        category: "Media & Graphics",
        icon: "󰐊",
        arch_source: "official",
        arch_pkg: "mpv",
        fedora_source: "rpmfusion",
        fedora_pkg: "mpv",
        gentoo_pkg: "media-video/mpv",
        flatpak_id: "io.mpv.Mpv",
    },
    CatalogItem {
        id: "spotify",
        name: "Spotify",
        summary: "Desktop music streaming client with native MPRIS controls",
        category: "Media & Graphics",
        icon: "󰓇",
        arch_source: "aur",
        arch_pkg: "spotify",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "com.spotify.Client",
    },
    CatalogItem {
        id: "gimp",
        name: "GIMP",
        summary: "GNU Image Manipulation Program for retouching and artwork",
        category: "Media & Graphics",
        icon: "󰏘",
        arch_source: "official",
        arch_pkg: "gimp",
        fedora_source: "official",
        fedora_pkg: "gimp",
        gentoo_pkg: "media-gfx/gimp",
        flatpak_id: "org.gimp.GIMP",
    },
    CatalogItem {
        id: "krita",
        name: "Krita",
        summary: "Professional digital painting and 2D illustration studio",
        category: "Media & Graphics",
        icon: "󰏘",
        arch_source: "official",
        arch_pkg: "krita",
        fedora_source: "official",
        fedora_pkg: "krita",
        gentoo_pkg: "media-gfx/krita",
        flatpak_id: "org.kde.krita",
    },
    CatalogItem {
        id: "blender",
        name: "Blender",
        summary: "Complete 3D modeling, sculpting, animation, and rendering suite",
        category: "Media & Graphics",
        icon: "󰂫",
        arch_source: "official",
        arch_pkg: "blender",
        fedora_source: "official",
        fedora_pkg: "blender",
        gentoo_pkg: "media-gfx/blender",
        flatpak_id: "org.blender.Blender",
    },
    CatalogItem {
        id: "kdenlive",
        name: "Kdenlive",
        summary: "Non-linear multi-track video editor built on MLT",
        category: "Media & Graphics",
        icon: "󰿎",
        arch_source: "official",
        arch_pkg: "kdenlive",
        fedora_source: "official",
        fedora_pkg: "kdenlive",
        gentoo_pkg: "kde-apps/kdenlive",
        flatpak_id: "org.kde.kdenlive",
    },
    CatalogItem {
        id: "inkscape",
        name: "Inkscape",
        summary: "Precision vector graphics and SVG illustration editor",
        category: "Media & Graphics",
        icon: "󰏘",
        arch_source: "official",
        arch_pkg: "inkscape",
        fedora_source: "official",
        fedora_pkg: "inkscape",
        gentoo_pkg: "media-gfx/inkscape",
        flatpak_id: "org.inkscape.Inkscape",
    },
    // Gaming
    CatalogItem {
        id: "steam",
        name: "Steam",
        summary: "Valve gaming client with Proton Linux compatibility layer",
        category: "Gaming",
        icon: "󰓓",
        arch_source: "official",
        arch_pkg: "steam",
        fedora_source: "rpmfusion",
        fedora_pkg: "steam",
        gentoo_pkg: "",
        flatpak_id: "com.valvesoftware.Steam",
    },
    CatalogItem {
        id: "lutris",
        name: "Lutris",
        summary: "Open gaming platform integrating Wine, GOG, and emulators",
        category: "Gaming",
        icon: "󰊗",
        arch_source: "official",
        arch_pkg: "lutris",
        fedora_source: "official",
        fedora_pkg: "lutris",
        gentoo_pkg: "",
        flatpak_id: "net.lutris.Lutris",
    },
    CatalogItem {
        id: "heroic",
        name: "Heroic Games Launcher",
        summary: "Open source Epic Games, GOG, and Amazon Prime game launcher",
        category: "Gaming",
        icon: "󰊗",
        arch_source: "aur",
        arch_pkg: "heroic-games-launcher-bin",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "com.heroicgameslauncher.hgl",
    },
    CatalogItem {
        id: "mangohud",
        name: "MangoHud",
        summary: "Vulkan and OpenGL performance HUD overlay for frametimes",
        category: "Gaming",
        icon: "󰍛",
        arch_source: "official",
        arch_pkg: "mangohud",
        fedora_source: "official",
        fedora_pkg: "mangohud",
        gentoo_pkg: "",
        flatpak_id: "",
    },
    CatalogItem {
        id: "prismlauncher",
        name: "Prism Launcher",
        summary: "Custom Minecraft launcher with isolated modpack management",
        category: "Gaming",
        icon: "󰍳",
        arch_source: "aur",
        arch_pkg: "prismlauncher",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "org.prismlauncher.PrismLauncher",
    },
    // Communication
    CatalogItem {
        id: "discord",
        name: "Discord",
        summary: "Voice, video, and community chat desktop application",
        category: "Communication",
        icon: "󰙯",
        arch_source: "official",
        arch_pkg: "discord",
        fedora_source: "rpmfusion",
        fedora_pkg: "discord",
        gentoo_pkg: "",
        flatpak_id: "com.discordapp.Discord",
    },
    CatalogItem {
        id: "vesktop",
        name: "Vesktop",
        summary: "Wayland-native Discord client with screen audio and Vencord",
        category: "Communication",
        icon: "󰙯",
        arch_source: "aur",
        arch_pkg: "vesktop-bin",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "dev.vencord.Vesktop",
    },
    CatalogItem {
        id: "telegram",
        name: "Telegram Desktop",
        summary: "Fast cloud messaging app with Wayland support",
        category: "Communication",
        icon: "󰔁",
        arch_source: "official",
        arch_pkg: "telegram-desktop",
        fedora_source: "rpmfusion",
        fedora_pkg: "telegram-desktop",
        gentoo_pkg: "",
        flatpak_id: "org.telegram.desktop",
    },
    CatalogItem {
        id: "thunderbird",
        name: "Thunderbird",
        summary: "Open-source email, calendar, and RSS client by Mozilla",
        category: "Communication",
        icon: "󰇮",
        arch_source: "official",
        arch_pkg: "thunderbird",
        fedora_source: "official",
        fedora_pkg: "thunderbird",
        gentoo_pkg: "mail-client/thunderbird",
        flatpak_id: "org.mozilla.Thunderbird",
    },
    CatalogItem {
        id: "signal",
        name: "Signal Desktop",
        summary: "End-to-end encrypted private messaging desktop client",
        category: "Communication",
        icon: "󰍡",
        arch_source: "official",
        arch_pkg: "signal-desktop",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "org.signal.Signal",
    },
    // Utilities
    CatalogItem {
        id: "bitwarden",
        name: "Bitwarden",
        summary: "Open-source password manager with encrypted cross-device vault",
        category: "Utilities",
        icon: "󰌾",
        arch_source: "official",
        arch_pkg: "bitwarden",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "com.bitwarden.desktop",
    },
    CatalogItem {
        id: "btop",
        name: "btop++",
        summary: "Resource monitor with CPU, GPU, memory, disk, and network graphs",
        category: "Utilities",
        icon: "󰍛",
        arch_source: "official",
        arch_pkg: "btop",
        fedora_source: "official",
        fedora_pkg: "btop",
        gentoo_pkg: "sys-process/btop",
        flatpak_id: "",
    },
    CatalogItem {
        id: "localsend",
        name: "LocalSend",
        summary: "Share files across LAN devices with zero internet required",
        category: "Utilities",
        icon: "󰄙",
        arch_source: "aur",
        arch_pkg: "localsend-bin",
        fedora_source: "",
        fedora_pkg: "",
        gentoo_pkg: "",
        flatpak_id: "org.localsend.localsend_app",
    },
    CatalogItem {
        id: "syncthing",
        name: "Syncthing",
        summary: "Continuous peer-to-peer decentralized file synchronization",
        category: "Utilities",
        icon: "󰓦",
        arch_source: "official",
        arch_pkg: "syncthing",
        fedora_source: "official",
        fedora_pkg: "syncthing",
        gentoo_pkg: "net-p2p/syncthing",
        flatpak_id: "",
    },
    CatalogItem {
        id: "flameshot",
        name: "Flameshot",
        summary: "Screenshot utility with inline annotations and blur tools",
        category: "Utilities",
        icon: "󰄀",
        arch_source: "official",
        arch_pkg: "flameshot",
        fedora_source: "official",
        fedora_pkg: "flameshot",
        gentoo_pkg: "media-gfx/flameshot",
        flatpak_id: "org.flameshot.Flameshot",
    },
    CatalogItem {
        id: "libreoffice",
        name: "LibreOffice",
        summary: "Full-featured open-source office suite for documents and sheets",
        category: "Utilities",
        icon: "󰈙",
        arch_source: "official",
        arch_pkg: "libreoffice-fresh",
        fedora_source: "official",
        fedora_pkg: "libreoffice",
        gentoo_pkg: "app-office/libreoffice",
        flatpak_id: "org.libreoffice.LibreOffice",
    },
];

struct StoreEnv {
    family: &'static str,
    pretty_name: String,
    native_manager: &'static str,
    aur_helper: String,
    has_flatpak: bool,
    has_flathub: bool,
    has_rpmfusion: bool,
    privilege_tool: &'static str,
}

#[derive(Clone)]
struct SearchHit {
    name: String,
    pkg: String,
    source: String,
    version: String,
    summary: String,
    installed: bool,
}

#[derive(Clone)]
struct UpdateHit {
    name: String,
    pkg: String,
    source: String,
    old_version: String,
    new_version: String,
    summary: String,
}

fn detect_store_env() -> StoreEnv {
    let os_txt = fs::read_to_string("/etc/os-release").unwrap_or_default();
    let (family, pretty_name) = parse_os_release(&os_txt);
    let native_manager = match family {
        "arch" => "pacman",
        "fedora" => {
            if which("dnf5").is_some() {
                "dnf5"
            } else {
                "dnf"
            }
        }
        "gentoo" => "emerge",
        _ => "unknown",
    };
    let aur_helper = if family == "arch" {
        ["paru", "yay"]
            .into_iter()
            .find(|h| which(h).is_some())
            .unwrap_or("")
            .to_string()
    } else {
        String::new()
    };

    let has_flatpak = which("flatpak").is_some();
    let has_flathub = if has_flatpak {
        detect_flathub(
            Path::new("/var/lib/flatpak/repo/config"),
            &data_dir().join("flatpak/repo/config"),
            true,
        )
    } else {
        false
    };
    let has_rpmfusion = if family == "fedora" {
        detect_rpmfusion(Path::new("/etc/yum.repos.d"))
    } else {
        false
    };
    let privilege_tool = if which("pkexec").is_some() {
        "pkexec"
    } else if which("sudo").is_some() {
        "sudo"
    } else {
        ""
    };

    StoreEnv {
        family,
        pretty_name,
        native_manager,
        aur_helper,
        has_flatpak,
        has_flathub,
        has_rpmfusion,
        privilege_tool,
    }
}

fn detect_flathub(system_cfg: &Path, user_cfg: &Path, allow_cli: bool) -> bool {
    for p in [system_cfg, user_cfg] {
        if let Ok(txt) = fs::read_to_string(p) {
            if txt.contains("[remote \"flathub\"]") || txt.contains("flathub.org") {
                return true;
            }
        }
    }
    if allow_cli {
        if let Some(out) = run_stdout("flatpak", &["remotes", "--columns=name"]) {
            return out.lines().any(|l| l.trim() == "flathub");
        }
    }
    false
}

pub(crate) fn detect_rpmfusion(repo_dir: &Path) -> bool {
    let Ok(rd) = fs::read_dir(repo_dir) else {
        return false;
    };
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().to_ascii_lowercase();
        if !name.ends_with(".repo") {
            continue;
        }
        if name.starts_with("rpmfusion-free") || name.starts_with("rpmfusion-nonfree") {
            if let Ok(txt) = fs::read_to_string(ent.path()) {
                if txt.lines().any(|l| l.trim() == "enabled=1") {
                    return true;
                }
            }
        }
    }
    false
}

/// Strip version and release suffix from a `/var/lib/pacman/local` folder name (`pkg-1.2.3-4`).
fn parse_pacman_local_dir(dirname: &str) -> Option<(String, String)> {
    let idx_rel = dirname.rfind('-')?;
    let without_rel = &dirname[..idx_rel];
    let idx_ver = without_rel.rfind('-')?;
    let name = &without_rel[..idx_ver];
    let version = &dirname[idx_ver + 1..];
    if name.is_empty() || version.is_empty() {
        return None;
    }
    Some((name.to_string(), version.to_string()))
}

/// Strip `-<version>` suffix from a `/var/db/pkg/<category>/<name>-<ver>` directory name.
fn parse_gentoo_pkg_dir(cat: &str, dirname: &str) -> Option<(String, String)> {
    let bytes = dirname.as_bytes();
    for (idx, w) in bytes.windows(2).enumerate() {
        if w[0] == b'-' && w[1].is_ascii_digit() {
            let pkg = &dirname[..idx];
            let ver = &dirname[idx + 1..];
            if !pkg.is_empty() && !ver.is_empty() {
                return Some((format!("{cat}/{pkg}"), ver.to_string()));
            }
        }
    }
    None
}

fn collect_installed_flatpaks() -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    let user_apps = data_dir().join("flatpak/app");
    for base in [Path::new("/var/lib/flatpak/app"), user_apps.as_path()] {
        let Ok(rd) = fs::read_dir(base) else {
            continue;
        };
        for ent in rd.flatten() {
            if !ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                continue;
            }
            let app_id = ent.file_name().to_string_lossy().into_owned();
            if app_id.starts_with('.') || !app_id.contains('.') {
                continue;
            }
            map.entry(app_id).or_insert_with(|| "installed".to_string());
        }
    }
    map
}

pub(crate) fn collect_installed_native_fast(family: &str) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    match family {
        "arch" => {
            if let Ok(rd) = fs::read_dir("/var/lib/pacman/local") {
                for ent in rd.flatten() {
                    if !ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                        continue;
                    }
                    let dname = ent.file_name().to_string_lossy().into_owned();
                    if dname.starts_with('.') || dname == "ALPM_DB_VERSION" {
                        continue;
                    }
                    if let Some((pkg, ver)) = parse_pacman_local_dir(&dname) {
                        map.insert(pkg, ver);
                    }
                }
            }
        }
        "fedora" => {
            if let Some(out) =
                run_stdout("rpm", &["-qa", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\n"])
            {
                for line in out.lines() {
                    if let Some((name, ver)) = line.split_once('\t') {
                        let name = name.trim();
                        if !name.is_empty() {
                            map.insert(name.to_string(), ver.trim().to_string());
                        }
                    }
                }
            }
        }
        "gentoo" => {
            if let Ok(cats) = fs::read_dir("/var/db/pkg") {
                for cat_ent in cats.flatten() {
                    if !cat_ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                        continue;
                    }
                    let cat = cat_ent.file_name().to_string_lossy().into_owned();
                    if cat.starts_with('.') {
                        continue;
                    }
                    if let Ok(pkgs) = fs::read_dir(cat_ent.path()) {
                        for pkg_ent in pkgs.flatten() {
                            if !pkg_ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                                continue;
                            }
                            let dname = pkg_ent.file_name().to_string_lossy().into_owned();
                            if let Some((atom, ver)) = parse_gentoo_pkg_dir(&cat, &dname) {
                                map.insert(atom, ver);
                            }
                        }
                    }
                }
            }
        }
        _ => {}
    }
    map
}

fn sanitize_pkg_token(raw: &str) -> Result<String, String> {
    let t = raw.trim();
    if t.is_empty() || t.len() > 128 {
        return Err("Package name must be 1 to 128 characters".to_string());
    }
    if t.starts_with('-') || t.contains("..") {
        return Err(format!("Invalid package token '{t}'"));
    }
    if !t
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'@' | b'.' | b'_' | b'+' | b'-' | b'/'))
    {
        return Err(format!("Unsafe character in package token '{t}'"));
    }
    Ok(t.to_string())
}

fn sanitize_search_query(raw: &str) -> Result<String, String> {
    let t = raw.trim();
    if t.len() < 2 || t.len() > 64 {
        return Err("Search query must be 2 to 64 characters".to_string());
    }
    if !t
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b' ' | b'_' | b'.' | b'-' | b'+'))
    {
        return Err("Search query contains unsupported characters".to_string());
    }
    Ok(t.to_string())
}

fn percent_encode_query(q: &str) -> String {
    let mut out = String::with_capacity(q.len() * 2);
    for b in q.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.') {
            out.push(b as char);
        } else if b == b' ' {
            out.push_str("%20");
        } else {
            out.push('%');
            let _ = std::fmt::Write::write_fmt(&mut out, format_args!("{b:02X}"));
        }
    }
    out
}

fn native_spec_for<'a>(item: &'a CatalogItem, family: &str) -> (&'a str, &'a str) {
    match family {
        "arch" => (item.arch_source, item.arch_pkg),
        "fedora" => (item.fedora_source, item.fedora_pkg),
        "gentoo" if !item.gentoo_pkg.is_empty() => ("official", item.gentoo_pkg),
        _ => ("", ""),
    }
}

fn emit_env_fields(o: &mut JsonOut, env: &StoreEnv, native_count: u64, flatpak_count: u64) {
    o.kv_str("family", env.family);
    o.kv_str("prettyName", &env.pretty_name);
    o.kv_str("nativeManager", env.native_manager);
    o.kv_str("aurHelper", &env.aur_helper);
    o.kv_bool("hasFlatpak", env.has_flatpak);
    o.kv_bool("hasFlathub", env.has_flathub);
    o.kv_bool("hasRpmFusion", env.has_rpmfusion);
    o.kv_str("privilegeTool", env.privilege_tool);
    o.kv_bool(
        "supportsOfficial",
        matches!(env.family, "arch" | "fedora" | "gentoo"),
    );
    o.kv_bool("supportsAur", env.family == "arch");
    o.kv_bool("supportsFlatpak", env.has_flatpak);
    o.kv_u64("nativeCount", native_count);
    o.kv_u64("flatpakCount", flatpak_count);
    o.kv_bool(
        "needsAurSetup",
        env.family == "arch" && env.aur_helper.is_empty(),
    );
    o.kv_bool(
        "needsRpmFusionSetup",
        env.family == "fedora" && !env.has_rpmfusion,
    );
    o.kv_bool("needsFlathubSetup", env.has_flatpak && !env.has_flathub);
}

fn cmd_status() -> Result<(), String> {
    let env = detect_store_env();
    let native_count = collect_installed_native_fast(env.family).len() as u64;
    let flatpak_count = collect_installed_flatpaks().len() as u64;

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    emit_env_fields(&mut o, &env, native_count, flatpak_count);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_catalog() -> Result<(), String> {
    let env = detect_store_env();
    let native_installed = collect_installed_native_fast(env.family);
    let flatpak_installed = collect_installed_flatpaks();

    let mut o = JsonOut::with_capacity(8192);
    o.obj_start();
    o.kv_bool("ok", true);
    emit_env_fields(
        &mut o,
        &env,
        native_installed.len() as u64,
        flatpak_installed.len() as u64,
    );
    o.key("items");
    o.arr_start();
    for item in CATALOG {
        let (native_src, native_pkg) = native_spec_for(item, env.family);
        let is_native_inst = !native_pkg.is_empty() && native_installed.contains_key(native_pkg);
        let is_fp_inst =
            !item.flatpak_id.is_empty() && flatpak_installed.contains_key(item.flatpak_id);
        let installed = is_native_inst || is_fp_inst;
        let installed_via = if is_native_inst {
            native_src
        } else if is_fp_inst {
            "flatpak"
        } else {
            ""
        };
        let (rec_source, rec_pkg) = if !native_pkg.is_empty() {
            (native_src, native_pkg)
        } else if env.has_flatpak && !item.flatpak_id.is_empty() {
            ("flatpak", item.flatpak_id)
        } else {
            ("", "")
        };

        o.obj_start();
        o.kv_str("id", item.id);
        o.kv_str("name", item.name);
        o.kv_str("summary", item.summary);
        o.kv_str("category", item.category);
        o.kv_str("icon", item.icon);
        o.kv_str("nativeSource", native_src);
        o.kv_str("nativePkg", native_pkg);
        o.kv_bool("nativeInstalled", is_native_inst);
        o.kv_str("flatpakId", item.flatpak_id);
        o.kv_bool("flatpakInstalled", is_fp_inst);
        o.kv_str("recommendedSource", rec_source);
        o.kv_str("recommendedPkg", rec_pkg);
        o.kv_bool("installed", installed);
        o.kv_str("installedVia", installed_via);
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn parse_pacman_ss(output: &str, limit: usize) -> Vec<SearchHit> {
    let mut hits = Vec::new();
    let lines: Vec<&str> = output.lines().collect();
    let mut i = 0;
    while i < lines.len() && hits.len() < limit {
        let header = lines[i];
        if !header.is_empty() && !header.starts_with(' ') && !header.starts_with('\t') {
            if let Some((repo_pkg, rest)) = header.split_once(' ') {
                let Some((repo, pkg)) = repo_pkg.split_once('/') else {
                    i += 1;
                    continue;
                };
                let version = rest.split_whitespace().next().unwrap_or("").to_string();
                let installed = rest.contains("[installed");
                let summary = lines
                    .get(i + 1)
                    .map(|s| s.trim())
                    .filter(|_| i + 1 < lines.len())
                    .unwrap_or("")
                    .to_string();
                let source = if repo.eq_ignore_ascii_case("aur") {
                    "aur"
                } else {
                    "official"
                };
                hits.push(SearchHit {
                    name: pkg.to_string(),
                    pkg: pkg.to_string(),
                    source: source.to_string(),
                    version,
                    summary,
                    installed,
                });
                i += 2;
                continue;
            }
        }
        i += 1;
    }
    hits
}

fn parse_aur_rpc_json(
    raw: &str,
    installed_map: &BTreeMap<String, String>,
    limit: usize,
) -> Vec<SearchHit> {
    let Ok(val) = json::parse(raw) else {
        return Vec::new();
    };
    let Some(results) = val.get("results").and_then(JsonVal::as_arr) else {
        return Vec::new();
    };
    let mut hits = Vec::new();
    for item in results.iter().take(limit) {
        let Some(pkg) = item.get_str("Name") else {
            continue;
        };
        let ver = item.get_str("Version").unwrap_or("").to_string();
        let desc = item.get_str("Description").unwrap_or("").to_string();
        hits.push(SearchHit {
            name: pkg.to_string(),
            pkg: pkg.to_string(),
            source: "aur".to_string(),
            version: ver,
            summary: desc,
            installed: installed_map.contains_key(pkg),
        });
    }
    hits
}

fn parse_dnf_search(
    output: &str,
    installed_map: &BTreeMap<String, String>,
    limit: usize,
) -> Vec<SearchHit> {
    let mut hits = Vec::new();
    let mut seen = BTreeSet::new();
    for line in output.lines() {
        if hits.len() >= limit {
            break;
        }
        let trimmed = line.trim();
        if trimmed.is_empty()
            || trimmed.starts_with('=')
            || trimmed.starts_with("Updating")
            || trimmed.starts_with("Matched")
        {
            continue;
        }
        let Some((lhs, rhs)) = trimmed.split_once(" : ") else {
            continue;
        };
        let pkg_token = lhs.trim();
        let pkg = pkg_token
            .rsplit_once('.')
            .map(|(base, arch)| {
                if matches!(arch, "x86_64" | "aarch64" | "noarch" | "i686") {
                    base
                } else {
                    pkg_token
                }
            })
            .unwrap_or(pkg_token);
        if pkg.is_empty() || !seen.insert(pkg.to_string()) {
            continue;
        }
        hits.push(SearchHit {
            name: pkg.to_string(),
            pkg: pkg.to_string(),
            source: "official".to_string(),
            version: installed_map.get(pkg).cloned().unwrap_or_default(),
            summary: rhs.trim().to_string(),
            installed: installed_map.contains_key(pkg),
        });
    }
    hits
}

fn parse_flatpak_search(
    output: &str,
    installed_flatpaks: &BTreeMap<String, String>,
    limit: usize,
) -> Vec<SearchHit> {
    let mut hits = Vec::new();
    let mut seen = BTreeSet::new();
    for line in output.lines() {
        if hits.len() >= limit {
            break;
        }
        let cols: Vec<&str> = line.split('\t').collect();
        if cols.len() < 2 {
            continue;
        }
        let app_id = cols[0].trim();
        if app_id.is_empty() || !app_id.contains('.') || !seen.insert(app_id.to_string()) {
            continue;
        }
        let name = cols.get(1).map(|s| s.trim()).unwrap_or(app_id);
        let desc = cols.get(2).map(|s| s.trim()).unwrap_or("");
        let ver = cols.get(3).map(|s| s.trim()).unwrap_or("");
        hits.push(SearchHit {
            name: if name.is_empty() {
                app_id.to_string()
            } else {
                name.to_string()
            },
            pkg: app_id.to_string(),
            source: "flatpak".to_string(),
            version: ver.to_string(),
            summary: desc.to_string(),
            installed: installed_flatpaks.contains_key(app_id),
        });
    }
    hits
}

fn gentoo_search_repos(
    query_lc: &str,
    installed_map: &BTreeMap<String, String>,
    limit: usize,
) -> Vec<SearchHit> {
    let mut hits = Vec::new();
    let Ok(repos) = fs::read_dir("/var/db/repos") else {
        return hits;
    };
    for repo in repos.flatten() {
        if hits.len() >= limit {
            break;
        }
        if !repo.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            continue;
        }
        let Ok(cats) = fs::read_dir(repo.path()) else {
            continue;
        };
        for cat_ent in cats.flatten() {
            if hits.len() >= limit {
                break;
            }
            if !cat_ent.file_type().map(|t| t.is_dir()).unwrap_or(false) {
                continue;
            }
            let cat = cat_ent.file_name().to_string_lossy().into_owned();
            if cat.starts_with('.')
                || matches!(
                    cat.as_str(),
                    "metadata" | "profiles" | "eclass" | "licenses" | "scripts"
                )
            {
                continue;
            }
            let Ok(pkgs) = fs::read_dir(cat_ent.path()) else {
                continue;
            };
            for pkg_ent in pkgs.flatten() {
                if hits.len() >= limit {
                    break;
                }
                let pkg = pkg_ent.file_name().to_string_lossy().into_owned();
                let atom = format!("{cat}/{pkg}");
                if !atom.to_ascii_lowercase().contains(query_lc) {
                    continue;
                }
                let desc = read_gentoo_description(&pkg_ent.path()).unwrap_or_default();
                let ver = installed_map.get(&atom).cloned().unwrap_or_default();
                hits.push(SearchHit {
                    name: pkg,
                    pkg: atom.clone(),
                    source: "official".to_string(),
                    version: ver,
                    summary: desc,
                    installed: installed_map.contains_key(&atom),
                });
            }
        }
    }
    hits
}

fn read_gentoo_description(pkg_dir: &Path) -> Option<String> {
    let rd = fs::read_dir(pkg_dir).ok()?;
    for ent in rd.flatten() {
        let name = ent.file_name().to_string_lossy().into_owned();
        if !name.ends_with(".ebuild") {
            continue;
        }
        if let Ok(txt) = fs::read_to_string(ent.path()) {
            for line in txt.lines().take(30) {
                let t = line.trim();
                if let Some(rest) = t.strip_prefix("DESCRIPTION=") {
                    let cleaned = rest.trim().trim_matches('"').trim_matches('\'');
                    if !cleaned.is_empty() {
                        return Some(cleaned.to_string());
                    }
                }
            }
        }
        break;
    }
    None
}

fn cmd_search(args: &[String]) -> Result<(), String> {
    let raw_query = args.first().map(String::as_str).unwrap_or("");
    let query = sanitize_search_query(raw_query)?;
    let source_filter = args
        .get(1)
        .map(String::as_str)
        .unwrap_or("all")
        .to_ascii_lowercase();

    let env = detect_store_env();
    let native_installed = collect_installed_native_fast(env.family);
    let flatpak_installed = collect_installed_flatpaks();
    let mut hits: Vec<SearchHit> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();

    let want_official = matches!(source_filter.as_str(), "all" | "native" | "official");
    let want_aur = env.family == "arch" && matches!(source_filter.as_str(), "all" | "aur");
    let want_flatpak = env.has_flatpak && matches!(source_filter.as_str(), "all" | "flatpak");

    if want_official {
        match env.family {
            "arch" => {
                if let Some(out) = run_stdout("pacman", &["-Ss", "--", &query]) {
                    hits.extend(parse_pacman_ss(&out, 36));
                }
            }
            "fedora" => {
                if let Some(out) = run_stdout(env.native_manager, &["search", "-q", &query]) {
                    hits.extend(parse_dnf_search(&out, &native_installed, 36));
                }
            }
            "gentoo" => {
                hits.extend(gentoo_search_repos(
                    &query.to_ascii_lowercase(),
                    &native_installed,
                    36,
                ));
            }
            _ => {}
        }
    }

    if want_aur {
        if !env.aur_helper.is_empty() {
            if let Some(out) = run_stdout(&env.aur_helper, &["-Ssa", "--", &query]) {
                hits.extend(parse_pacman_ss(&out, 28));
            }
        } else if which("curl").is_some() {
            let url = format!(
                "https://aur.archlinux.org/rpc/v5/search/{}?by=name-desc",
                percent_encode_query(&query)
            );
            if let Some(raw) = run_stdout("curl", &["-fsSL", "--max-time", "5", &url]) {
                hits.extend(parse_aur_rpc_json(&raw, &native_installed, 28));
            } else {
                warnings.push("AUR search unreachable or timed out".to_string());
            }
        }
    }

    if want_flatpak {
        if let Some(out) = run_stdout(
            "flatpak",
            &[
                "search",
                "--columns=application,name,description,version,remotes",
                &query,
            ],
        ) {
            hits.extend(parse_flatpak_search(&out, &flatpak_installed, 28));
        }
    }

    let mut o = JsonOut::with_capacity(4096);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("query", &query);
    o.kv_str("source", &source_filter);
    o.key("items");
    o.arr_start();
    for h in hits.into_iter().take(80) {
        o.obj_start();
        o.kv_str("name", &h.name);
        o.kv_str("pkg", &h.pkg);
        o.kv_str("source", &h.source);
        o.kv_str("version", &h.version);
        o.kv_str("summary", &h.summary);
        o.kv_bool("installed", h.installed);
        o.obj_end();
    }
    o.arr_end();
    o.key("warnings");
    o.arr_start();
    for w in &warnings {
        o.str(w);
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_installed(args: &[String]) -> Result<(), String> {
    let filter = args
        .first()
        .map(String::as_str)
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    let env = detect_store_env();
    let mut rows: Vec<(String, String, String, String, String)> = Vec::new();

    match env.family {
        "arch" => {
            let mut foreign = BTreeSet::new();
            if let Some(out) = run_stdout("pacman", &["-Qmq"]) {
                for l in out.lines() {
                    let t = l.trim();
                    if !t.is_empty() {
                        foreign.insert(t.to_string());
                    }
                }
            }
            if let Some(out) = run_stdout("pacman", &["-Qe"]) {
                for line in out.lines() {
                    let mut parts = line.split_whitespace();
                    let Some(pkg) = parts.next() else {
                        continue;
                    };
                    let ver = parts.next().unwrap_or("");
                    let src = if foreign.contains(pkg) {
                        "aur"
                    } else {
                        "official"
                    };
                    rows.push((
                        pkg.to_string(),
                        pkg.to_string(),
                        src.to_string(),
                        ver.to_string(),
                        "Explicitly installed package".to_string(),
                    ));
                }
            }
        }
        "fedora" => {
            let mut seen = BTreeSet::new();
            if let Some(out) = run_stdout(
                "rpm",
                &[
                    "-qa",
                    "--qf",
                    "%{NAME}\t%{VERSION}-%{RELEASE}\t%{SUMMARY}\n",
                ],
            ) {
                for line in out.lines() {
                    let cols: Vec<&str> = line.splitn(3, '\t').collect();
                    let pkg = cols.first().map(|s| s.trim()).unwrap_or("");
                    if pkg.is_empty() || !seen.insert(pkg.to_string()) {
                        continue;
                    }
                    let ver = cols.get(1).map(|s| s.trim()).unwrap_or("");
                    let summary = cols.get(2).map(|s| s.trim()).unwrap_or("");
                    rows.push((
                        pkg.to_string(),
                        pkg.to_string(),
                        "official".to_string(),
                        ver.to_string(),
                        summary.to_string(),
                    ));
                }
            }
        }
        "gentoo" => {
            let installed = collect_installed_native_fast("gentoo");
            let world_txt = fs::read_to_string("/var/lib/portage/world").unwrap_or_default();
            for line in world_txt.lines() {
                let atom = line.trim();
                if atom.is_empty() || atom.starts_with('#') {
                    continue;
                }
                let name = atom.rsplit_once('/').map(|(_, n)| n).unwrap_or(atom);
                let ver = installed.get(atom).cloned().unwrap_or_default();
                rows.push((
                    name.to_string(),
                    atom.to_string(),
                    "official".to_string(),
                    ver,
                    "Selected @world Portage package".to_string(),
                ));
            }
        }
        _ => {}
    }

    if env.has_flatpak {
        if let Some(out) = run_stdout(
            "flatpak",
            &["list", "--app", "--columns=application,name,version,origin"],
        ) {
            for line in out.lines() {
                let cols: Vec<&str> = line.split('\t').collect();
                let app_id = cols.first().map(|s| s.trim()).unwrap_or("");
                if app_id.is_empty() {
                    continue;
                }
                let name = cols
                    .get(1)
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .unwrap_or(app_id);
                let ver = cols.get(2).map(|s| s.trim()).unwrap_or("");
                let origin = cols.get(3).map(|s| s.trim()).unwrap_or("flathub");
                rows.push((
                    name.to_string(),
                    app_id.to_string(),
                    "flatpak".to_string(),
                    ver.to_string(),
                    format!("Flatpak ({origin})"),
                ));
            }
        }
    }

    let mut o = JsonOut::with_capacity(8192);
    o.obj_start();
    o.kv_bool("ok", true);
    o.key("items");
    o.arr_start();
    for (name, pkg, source, version, summary) in rows
        .into_iter()
        .filter(|(n, p, s, _, _)| {
            filter.is_empty()
                || n.to_ascii_lowercase().contains(&filter)
                || p.to_ascii_lowercase().contains(&filter)
                || s.to_ascii_lowercase().contains(&filter)
        })
        .take(200)
    {
        o.obj_start();
        o.kv_str("name", &name);
        o.kv_str("pkg", &pkg);
        o.kv_str("source", &source);
        o.kv_str("version", &version);
        o.kv_str("summary", &summary);
        o.kv_bool("installed", true);
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn parse_pacman_updates(output: &str, source: &str) -> Vec<UpdateHit> {
    let mut items = Vec::new();
    for line in output.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 4 && parts[2] == "->" {
            items.push(UpdateHit {
                name: parts[0].to_string(),
                pkg: parts[0].to_string(),
                source: source.to_string(),
                old_version: parts[1].to_string(),
                new_version: parts[3].to_string(),
                summary: format!("{} -> {}", parts[1], parts[3]),
            });
        }
    }
    items
}

fn cmd_updates() -> Result<(), String> {
    let env = detect_store_env();
    let mut items: Vec<UpdateHit> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();

    match env.family {
        "arch" => {
            if which("checkupdates").is_some() {
                if let Ok(out) = Command::new("checkupdates").output() {
                    if matches!(out.status.code(), Some(0) | Some(2)) {
                        let txt = String::from_utf8_lossy(&out.stdout);
                        items.extend(parse_pacman_updates(&txt, "official"));
                    }
                }
            } else if let Some(txt) = run_stdout("pacman", &["-Qu"]) {
                items.extend(parse_pacman_updates(&txt, "official"));
            } else {
                warnings.push("Install pacman-contrib (checkupdates) for safe non-root official update checks".to_string());
            }

            if !env.aur_helper.is_empty() {
                if let Some(txt) = run_stdout(&env.aur_helper, &["-Qua"]) {
                    items.extend(parse_pacman_updates(&txt, "aur"));
                }
            }
        }
        "fedora" => {
            if which(env.native_manager).is_some() {
                if let Ok(out) = Command::new(env.native_manager)
                    .args(["check-update", "-q"])
                    .output()
                {
                    if matches!(out.status.code(), Some(0) | Some(100)) {
                        let txt = String::from_utf8_lossy(&out.stdout);
                        for line in txt.lines() {
                            let parts: Vec<&str> = line.split_whitespace().collect();
                            if parts.len() >= 2 && !parts[0].starts_with("Obsoleting") {
                                let pkg = parts[0]
                                    .rsplit_once('.')
                                    .map(|(b, _)| b)
                                    .unwrap_or(parts[0]);
                                items.push(UpdateHit {
                                    name: pkg.to_string(),
                                    pkg: pkg.to_string(),
                                    source: "official".to_string(),
                                    old_version: String::new(),
                                    new_version: parts[1].to_string(),
                                    summary: format!("Available {}", parts[1]),
                                });
                            }
                        }
                    }
                }
            }
        }
        "gentoo" => {
            warnings.push(
                "Portage updates use interactive dependency resolution via Update All".to_string(),
            );
        }
        _ => {}
    }

    if env.has_flatpak {
        if let Some(out) = run_stdout(
            "flatpak",
            &[
                "remote-ls",
                "--updates",
                "--columns=application,name,version,origin",
            ],
        ) {
            for line in out.lines() {
                let cols: Vec<&str> = line.split('\t').collect();
                let app_id = cols.first().map(|s| s.trim()).unwrap_or("");
                if app_id.is_empty() {
                    continue;
                }
                let name = cols
                    .get(1)
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .unwrap_or(app_id);
                let ver = cols.get(2).map(|s| s.trim()).unwrap_or("update");
                let origin = cols.get(3).map(|s| s.trim()).unwrap_or("flathub");
                items.push(UpdateHit {
                    name: name.to_string(),
                    pkg: app_id.to_string(),
                    source: "flatpak".to_string(),
                    old_version: String::new(),
                    new_version: ver.to_string(),
                    summary: format!("Flatpak ({origin})"),
                });
            }
        }
    }

    let update_cmd = build_update_all_cmd(&env);
    let mut o = JsonOut::with_capacity(4096);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_u64("count", items.len() as u64);
    o.kv_str("updateCmd", &update_cmd);
    o.key("items");
    o.arr_start();
    for it in &items {
        o.obj_start();
        o.kv_str("name", &it.name);
        o.kv_str("pkg", &it.pkg);
        o.kv_str("source", &it.source);
        o.kv_str("oldVersion", &it.old_version);
        o.kv_str("newVersion", &it.new_version);
        o.kv_str("summary", &it.summary);
        o.obj_end();
    }
    o.arr_end();
    o.key("warnings");
    o.arr_start();
    for w in &warnings {
        o.str(w);
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn build_update_all_cmd(env: &StoreEnv) -> String {
    let mut parts: Vec<String> = Vec::new();
    match env.family {
        "arch" => {
            if !env.aur_helper.is_empty() {
                parts.push(format!("{} -Syu", env.aur_helper));
            } else {
                parts.push("sudo pacman -Syu".to_string());
            }
        }
        "fedora" => parts.push(format!("sudo {} upgrade --refresh", env.native_manager)),
        "gentoo" => parts.push("sudo emaint sync -a && sudo emerge -avuDN @world".to_string()),
        _ => {}
    }
    if env.has_flatpak {
        parts.push("flatpak update -y".to_string());
    }
    parts.join(" && ")
}

fn build_plan_for_env(
    family: &str,
    native_manager: &str,
    aur_helper: &str,
    has_flatpak: bool,
    action: &str,
    source: &str,
    raw_pkgs: &[String],
) -> Result<(String, String, String, bool, bool), String> {
    let src = source.trim().to_ascii_lowercase();
    match action {
        "setup-aur" => {
            if family != "arch" {
                return Err("AUR setup applies only to Arch-based systems".to_string());
            }
            let cmd = "sudo pacman -S --needed base-devel git && tmp_aur=$(mktemp -d) && git clone https://aur.archlinux.org/paru-bin.git \"$tmp_aur/paru-bin\" && (cd \"$tmp_aur/paru-bin\" && makepkg -si) && rm -rf \"$tmp_aur\"".to_string();
            return Ok((
                "Install paru AUR Helper".to_string(),
                "Installs base-devel & git, builds paru-bin from AUR cleanly".to_string(),
                cmd,
                true,
                false,
            ));
        }
        "setup-rpmfusion" => {
            if family != "fedora" {
                return Err("RPM Fusion setup applies only to Fedora".to_string());
            }
            let cmd = format!(
                "sudo {native_manager} install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            );
            return Ok((
                "Enable RPM Fusion Free & Nonfree".to_string(),
                "Enables Steam, VLC, OBS codecs, and Discord packages on Fedora".to_string(),
                cmd,
                true,
                false,
            ));
        }
        "setup-flathub" => {
            let cmd =
                "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
                    .to_string();
            return Ok((
                "Add Flathub Repository".to_string(),
                "Registers the Flathub catalog for Flatpak apps".to_string(),
                cmd,
                false,
                true,
            ));
        }
        "update-all" => {
            let mut parts = Vec::new();
            match family {
                "arch" => {
                    if !aur_helper.is_empty() {
                        parts.push(format!("{aur_helper} -Syu"));
                    } else {
                        parts.push("sudo pacman -Syu".to_string());
                    }
                }
                "fedora" => parts.push(format!("sudo {native_manager} upgrade --refresh")),
                "gentoo" => {
                    parts.push("sudo emaint sync -a && sudo emerge -avuDN @world".to_string())
                }
                _ => {}
            }
            if has_flatpak {
                parts.push("flatpak update -y".to_string());
            }
            if parts.is_empty() {
                return Err("No supported update manager found on host".to_string());
            }
            return Ok((
                "System & Apps Update".to_string(),
                "Updates native packages and installed Flatpak apps".to_string(),
                parts.join(" && "),
                family != "other",
                false,
            ));
        }
        _ => {}
    }

    if raw_pkgs.is_empty() {
        return Err("At least one package name is required".to_string());
    }
    let mut pkgs = Vec::with_capacity(raw_pkgs.len());
    for p in raw_pkgs {
        pkgs.push(sanitize_pkg_token(p)?);
    }
    let joined = pkgs.join(" ");

    match (action, src.as_str()) {
        ("install", "flatpak") => Ok((
            format!("Install {} via Flatpak", pkgs.len()),
            joined.clone(),
            format!("flatpak install -y flathub {joined}"),
            false,
            true,
        )),
        ("remove", "flatpak") => Ok((
            format!("Remove {} via Flatpak", pkgs.len()),
            joined.clone(),
            format!("flatpak uninstall -y {joined}"),
            false,
            true,
        )),
        ("update", "flatpak") => Ok((
            format!("Update {} via Flatpak", pkgs.len()),
            joined.clone(),
            format!("flatpak update -y {joined}"),
            false,
            true,
        )),
        ("install", "aur") => {
            if family != "arch" {
                return Err("AUR packages require Arch Linux".to_string());
            }
            if aur_helper.is_empty() {
                return Err("Install an AUR helper (paru or yay) first".to_string());
            }
            Ok((
                format!("Install {} from AUR", pkgs.len()),
                joined.clone(),
                format!("{aur_helper} -S --needed {joined}"),
                true,
                false,
            ))
        }
        ("remove", "aur") => {
            if family != "arch" {
                return Err("AUR packages require Arch Linux".to_string());
            }
            let cmd = if !aur_helper.is_empty() {
                format!("{aur_helper} -Rns {joined}")
            } else {
                format!("sudo pacman -Rns {joined}")
            };
            Ok((
                format!("Remove {}", joined),
                String::new(),
                cmd,
                true,
                false,
            ))
        }
        ("install", "official" | "rpmfusion") => {
            let cmd = match family {
                "arch" => format!("sudo pacman -S --needed {joined}"),
                "fedora" => format!("sudo {native_manager} install {joined}"),
                "gentoo" => format!("sudo emerge -av {joined}"),
                _ => return Err("Unsupported native package manager".to_string()),
            };
            Ok((
                format!("Install {} via {native_manager}", pkgs.len()),
                joined,
                cmd,
                true,
                false,
            ))
        }
        ("remove", "official" | "rpmfusion") => {
            let cmd = match family {
                "arch" => format!("sudo pacman -Rns {joined}"),
                "fedora" => format!("sudo {native_manager} remove {joined}"),
                "gentoo" => format!("sudo emerge -av --depclean {joined}"),
                _ => return Err("Unsupported native package manager".to_string()),
            };
            Ok((
                format!("Remove {} via {native_manager}", pkgs.len()),
                joined,
                cmd,
                true,
                false,
            ))
        }
        ("update", "official" | "aur" | "rpmfusion") => {
            let cmd = match family {
                "arch" if src == "aur" && !aur_helper.is_empty() => {
                    format!("{aur_helper} -S {joined}")
                }
                "arch" => format!("sudo pacman -S {joined}"),
                "fedora" => format!("sudo {native_manager} upgrade {joined}"),
                "gentoo" => format!("sudo emerge -avu1 {joined}"),
                _ => return Err("Unsupported native package manager".to_string()),
            };
            Ok((format!("Update {joined}"), String::new(), cmd, true, false))
        }
        _ => Err(format!(
            "Unsupported store plan action '{action}' / source '{src}'"
        )),
    }
}

fn cmd_plan(args: &[String]) -> Result<(), String> {
    let Some(action) = args.first().map(String::as_str) else {
        return Err(
            "Usage: store plan <install|remove|update|update-all|setup-aur|setup-rpmfusion|setup-flathub> <source> [pkg...]".to_string(),
        );
    };
    let source = args.get(1).map(String::as_str).unwrap_or("official");
    let rest = if args.len() > 2 { &args[2..] } else { &[] };
    let env = detect_store_env();
    let (title, summary, shell_cmd, requires_root, can_run_direct) = build_plan_for_env(
        env.family,
        env.native_manager,
        &env.aur_helper,
        env.has_flatpak,
        action,
        source,
        rest,
    )?;

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("action", action);
    o.kv_str("source", source);
    o.kv_str("title", &title);
    o.kv_str("summary", &summary);
    o.kv_str("shellCmd", &shell_cmd);
    o.kv_bool("requiresRoot", requires_root);
    o.kv_bool("canRunDirect", can_run_direct);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

pub fn cmd_store(args: &[String]) -> Result<(), String> {
    let Some(sub) = args.first().map(String::as_str) else {
        return cmd_status();
    };
    let rest = &args[1..];
    match sub {
        "status" => cmd_status(),
        "catalog" => cmd_catalog(),
        "search" => cmd_search(rest),
        "installed" => cmd_installed(rest),
        "updates" => cmd_updates(),
        "plan" => cmd_plan(rest),
        other => Err(format!(
            "Unknown store subcommand '{other}'. Expected status|catalog|search|installed|updates|plan"
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_pkg_tokens_and_search_queries() {
        assert_eq!(sanitize_pkg_token("firefox").unwrap(), "firefox");
        assert_eq!(
            sanitize_pkg_token("org.mozilla.firefox").unwrap(),
            "org.mozilla.firefox"
        );
        assert_eq!(
            sanitize_pkg_token("www-client/firefox").unwrap(),
            "www-client/firefox"
        );
        assert!(sanitize_pkg_token("-rf").is_err());
        assert!(sanitize_pkg_token("foo;rm -rf /").is_err());
        assert!(sanitize_pkg_token("../etc/passwd").is_err());
        assert!(sanitize_pkg_token("").is_err());

        assert_eq!(sanitize_search_query("obs studio").unwrap(), "obs studio");
        assert!(sanitize_search_query("a").is_err());
        assert!(sanitize_search_query("vim;whoami").is_err());
    }

    #[test]
    fn parses_pacman_and_gentoo_local_dirs() {
        assert_eq!(
            parse_pacman_local_dir("firefox-133.0.1-1"),
            Some(("firefox".to_string(), "133.0.1-1".to_string()))
        );
        assert_eq!(
            parse_pacman_local_dir("visual-studio-code-bin-1.95.0-1"),
            Some(("visual-studio-code-bin".to_string(), "1.95.0-1".to_string()))
        );
        assert_eq!(
            parse_gentoo_pkg_dir("gui-apps", "quickshell-0.3.2"),
            Some(("gui-apps/quickshell".to_string(), "0.3.2".to_string()))
        );
    }

    #[test]
    fn parses_search_outputs_across_backends() {
        let pac = "extra/firefox 133.0-1 [installed]\n    Fast web browser\naur/brave-bin 1.72-1\n    Privacy browser\n";
        let hits = parse_pacman_ss(pac, 10);
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].pkg, "firefox");
        assert_eq!(hits[0].source, "official");
        assert!(hits[0].installed);
        assert_eq!(hits[1].source, "aur");
        assert!(!hits[1].installed);

        let aur_json = r#"{"results":[{"Name":"zen-browser-bin","Version":"1.0-1","Description":"Calm browser"}]}"#;
        let inst = BTreeMap::new();
        let aur_hits = parse_aur_rpc_json(aur_json, &inst, 10);
        assert_eq!(aur_hits.len(), 1);
        assert_eq!(aur_hits[0].pkg, "zen-browser-bin");

        let dnf_out =
            "firefox.x86_64 : Mozilla Firefox Web browser\nobs-studio.x86_64 : Recording studio\n";
        let mut dnf_inst = BTreeMap::new();
        dnf_inst.insert("firefox".to_string(), "133.0".to_string());
        let dnf_hits = parse_dnf_search(dnf_out, &dnf_inst, 10);
        assert_eq!(dnf_hits.len(), 2);
        assert!(dnf_hits[0].installed);
        assert!(!dnf_hits[1].installed);

        let fp_out = "org.mozilla.firefox\tFirefox\tFast browser\t133.0\tflathub\n";
        let fp_hits = parse_flatpak_search(fp_out, &inst, 10);
        assert_eq!(fp_hits.len(), 1);
        assert_eq!(fp_hits[0].source, "flatpak");
    }

    #[test]
    fn builds_safe_install_and_setup_plans() {
        let pkgs = vec!["firefox".to_string(), "neovim".to_string()];
        let (_, _, cmd_arch, req_root, direct) =
            build_plan_for_env("arch", "pacman", "paru", true, "install", "official", &pkgs)
                .unwrap();
        assert_eq!(cmd_arch, "sudo pacman -S --needed firefox neovim");
        assert!(req_root);
        assert!(!direct);

        let (_, _, cmd_fedora, _, _) =
            build_plan_for_env("fedora", "dnf5", "", true, "install", "official", &pkgs).unwrap();
        assert_eq!(cmd_fedora, "sudo dnf5 install firefox neovim");

        let fp = vec!["org.mozilla.firefox".to_string()];
        let (_, _, cmd_fp, req_fp, direct_fp) =
            build_plan_for_env("fedora", "dnf5", "", true, "install", "flatpak", &fp).unwrap();
        assert_eq!(cmd_fp, "flatpak install -y flathub org.mozilla.firefox");
        assert!(!req_fp);
        assert!(direct_fp);

        assert!(build_plan_for_env("arch", "pacman", "", true, "install", "aur", &pkgs).is_err());

        let (_, _, setup_aur, _, _) =
            build_plan_for_env("arch", "pacman", "", false, "setup-aur", "aur", &[]).unwrap();
        assert!(setup_aur.contains("paru-bin.git"));
    }
}
