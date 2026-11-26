use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::process::Command;

use crate::distro::parse_os_release;
use crate::json::{self, JsonOut, JsonVal};
use crate::store::{collect_installed_native_fast, detect_rpmfusion};
use crate::util::{
    atomic_write, cache_dir, data_dir, human_size, now_unix_secs, run_stdout, unix_secs_to_iso,
    which,
};

#[derive(Clone, Copy)]
struct BloatPkg {
    id: &'static str,
    pkg: &'static str,
    name: &'static str,
    category: &'static str,
    summary: &'static str,
    risk: &'static str,
}

#[derive(Clone, Copy)]
struct BloatService {
    unit: &'static str,
    name: &'static str,
    summary: &'static str,
    risk: &'static str,
}

#[derive(Clone, Copy)]
struct TweakItem {
    id: &'static str,
    title: &'static str,
    summary: &'static str,
    detail: &'static str,
    risk: &'static str,
    requires_root: bool,
}

struct HistoryEntry {
    ts: i64,
    time_label: String,
    target: String,
    action: String,
    packages: Vec<String>,
}

const PROTECTED_PACKAGES: &[&str] = &[
    "linux",
    "linux-cachyos",
    "linux-cachyos-headers",
    "linux-cachyos-lts",
    "linux-cachyos-lts-headers",
    "linux-lts",
    "linux-zen",
    "kernel",
    "kernel-core",
    "kernel-modules",
    "kernel-modules-core",
    "grub",
    "grub2",
    "grub2-common",
    "systemd-boot",
    "limine",
    "efibootmgr",
    "dracut",
    "mkinitcpio",
    "base",
    "base-devel",
    "glibc",
    "filesystem",
    "bash",
    "zsh",
    "fish",
    "coreutils",
    "systemd",
    "systemd-libs",
    "systemd-sysvcompat",
    "pacman",
    "pacman-contrib",
    "cachyos-keyring",
    "cachyos-mirrorlist",
    "cachyos-settings",
    "archlinux-keyring",
    "dnf",
    "dnf5",
    "rpm",
    "fedora-release",
    "fedora-repos",
    "sudo",
    "doas",
    "polkit",
    "dbus",
    "dbus-broker",
    "openssh",
    "openssh-server",
    "networkmanager",
    "iwd",
    "wpa_supplicant",
    "mango",
    "mangowm",
    "scenefx",
    "quickshell",
    "wayland",
    "xorg-xwayland",
    "xorg-x11-server-xwayland",
    "mesa",
    "vulkan-icd-loader",
    "pipewire",
    "wireplumber",
    "pipewire-pulse",
    "foot",
    "kitty",
    "matugen",
    "awww",
    "swww",
    "grim",
    "slurp",
    "wl-clipboard",
    "python",
    "python3",
    "git",
    "rust",
    "cargo",
    "paru",
    "yay",
];

const PROTECTED_SERVICES: &[&str] = &[
    "dbus.service",
    "dbus-broker.service",
    "systemd-logind.service",
    "systemd-journald.service",
    "systemd-udevd.service",
    "networkmanager.service",
    "iwd.service",
    "wpa_supplicant.service",
    "seatd.service",
    "elogind.service",
    "sddm.service",
    "gdm.service",
    "lightdm.service",
    "greetd.service",
    "pipewire.service",
    "wireplumber.service",
    "sshd.service",
    "aurora-powerd.service",
    "polkit.service",
];

const CACHYOS_CATALOG: &[BloatPkg] = &[
    BloatPkg {
        id: "cachyos-hello",
        pkg: "cachyos-hello",
        name: "CachyOS Hello",
        category: "CachyOS Extras",
        summary: "Post-install welcome greeter window synced at desktop login",
        risk: "safe",
    },
    BloatPkg {
        id: "cachyos-pkginst",
        pkg: "cachyos-packageinstaller",
        name: "CachyOS Package Installer",
        category: "CachyOS Extras",
        summary: "Extra GUI software installer (covered natively by Aurora Store)",
        risk: "safe",
    },
    BloatPkg {
        id: "octopi",
        pkg: "octopi",
        name: "Octopi GUI",
        category: "CachyOS Extras",
        summary: "Qt Pacman graphical frontend redundant with Aurora Store",
        risk: "safe",
    },
    BloatPkg {
        id: "cachyos-wallpapers",
        pkg: "cachyos-wallpapers",
        name: "CachyOS Wallpapers Pack",
        category: "CachyOS Extras",
        summary: "Bundled stock wallpaper archive taking extra root disk space",
        risk: "safe",
    },
    BloatPkg {
        id: "cachyos-micro",
        pkg: "cachyos-micro-settings",
        name: "CachyOS Micro Settings",
        category: "CachyOS Extras",
        summary: "Default CachyOS micro editor configuration overrides",
        risk: "safe",
    },
    BloatPkg {
        id: "cachyos-fish",
        pkg: "cachyos-fish-config",
        name: "CachyOS Fish Config",
        category: "CachyOS Extras",
        summary: "Pre-configured fish prompt and aliases from CachyOS",
        risk: "caution",
    },
    BloatPkg {
        id: "cachyos-zsh",
        pkg: "cachyos-zsh-config",
        name: "CachyOS Zsh Config",
        category: "CachyOS Extras",
        summary: "Pre-configured zsh plugins and powerline prompt package",
        risk: "caution",
    },
    BloatPkg {
        id: "cachyos-gaming",
        pkg: "cachyos-gaming-meta",
        name: "CachyOS Gaming Meta",
        category: "CachyOS Extras",
        summary: "Large meta-package bundling Wine, Lutris, Winetricks & runtimes",
        risk: "caution",
    },
    BloatPkg {
        id: "cachyos-snapper",
        pkg: "cachyos-snapper-support",
        name: "CachyOS Snapper Support",
        category: "CachyOS Extras",
        summary: "Automated Btrfs snapshot pacman hooks (keep if you roll back)",
        risk: "caution",
    },
    BloatPkg {
        id: "meld",
        pkg: "meld",
        name: "Meld Diff Viewer",
        category: "CachyOS Extras",
        summary: "GTK visual diff/merge tool often bundled in CachyOS ISO",
        risk: "safe",
    },
    BloatPkg {
        id: "micro",
        pkg: "micro",
        name: "Micro Editor",
        category: "CachyOS Extras",
        summary: "Terminal editor redundant if using Neovim, Helix, or Zed",
        risk: "safe",
    },
    BloatPkg {
        id: "alacritty",
        pkg: "alacritty",
        name: "Alacritty",
        category: "CachyOS Extras",
        summary: "Secondary terminal redundant with Foot/Kitty in Aurora Shell",
        risk: "safe",
    },
    BloatPkg {
        id: "discover",
        pkg: "discover",
        name: "KDE Discover",
        category: "Desktop Apps",
        summary: "Heavy Plasma software store pulling PackageKit background daemon",
        risk: "safe",
    },
    BloatPkg {
        id: "gnome-software",
        pkg: "gnome-software",
        name: "GNOME Software",
        category: "Desktop Apps",
        summary: "Background GNOME app store polling PackageKit metadata in RAM",
        risk: "safe",
    },
    BloatPkg {
        id: "gnome-tour",
        pkg: "gnome-tour",
        name: "GNOME Tour",
        category: "Desktop Apps",
        summary: "First-run onboarding tour app unused on tiling compositors",
        risk: "safe",
    },
    BloatPkg {
        id: "epiphany",
        pkg: "epiphany",
        name: "GNOME Web (Epiphany)",
        category: "Desktop Apps",
        summary: "Secondary WebKitGTK browser redundant with primary browser",
        risk: "safe",
    },
    BloatPkg {
        id: "thunderbird",
        pkg: "thunderbird",
        name: "Thunderbird Mail",
        category: "Desktop Apps",
        summary: "Heavy standalone email client if you use webmail",
        risk: "safe",
    },
    BloatPkg {
        id: "kate",
        pkg: "kate",
        name: "Kate Editor",
        category: "Desktop Apps",
        summary: "KDE Frameworks text editor dragging KDE runtime libraries",
        risk: "safe",
    },
    BloatPkg {
        id: "kwrite",
        pkg: "kwrite",
        name: "KWrite",
        category: "Desktop Apps",
        summary: "Minimal KDE text editor redundant on Wayland shells",
        risk: "safe",
    },
    BloatPkg {
        id: "dolphin",
        pkg: "dolphin",
        name: "Dolphin File Manager",
        category: "Desktop Apps",
        summary: "KDE file manager if relying on Aurora File Manager (aurora-fm)",
        risk: "safe",
    },
    BloatPkg {
        id: "konsole",
        pkg: "konsole",
        name: "Konsole Terminal",
        category: "Desktop Apps",
        summary: "KDE terminal emulator redundant with Foot or Kitty",
        risk: "safe",
    },
    BloatPkg {
        id: "ark",
        pkg: "ark",
        name: "Ark Archiver",
        category: "Desktop Apps",
        summary: "KDE GUI archiver (aurora-fm handles tar/zip natively)",
        risk: "safe",
    },
    BloatPkg {
        id: "gwenview",
        pkg: "gwenview",
        name: "Gwenview",
        category: "Desktop Apps",
        summary: "KDE image viewer replaceable with lightweight imv/swayimg",
        risk: "safe",
    },
    BloatPkg {
        id: "okular",
        pkg: "okular",
        name: "Okular",
        category: "Desktop Apps",
        summary: "KDE document viewer replaceable with lightweight zathura or browser",
        risk: "safe",
    },
    BloatPkg {
        id: "elisa",
        pkg: "elisa",
        name: "Elisa Music Player",
        category: "Desktop Apps",
        summary: "Pre-installed Qt music player",
        risk: "safe",
    },
    BloatPkg {
        id: "haruna",
        pkg: "haruna",
        name: "Haruna Video Player",
        category: "Desktop Apps",
        summary: "Qt frontend around mpv (keep plain mpv instead)",
        risk: "safe",
    },
    BloatPkg {
        id: "totem",
        pkg: "totem",
        name: "GNOME Videos (Totem)",
        category: "Desktop Apps",
        summary: "Stock GNOME media player replaceable by mpv/VLC",
        risk: "safe",
    },
    BloatPkg {
        id: "rhythmbox",
        pkg: "rhythmbox",
        name: "Rhythmbox",
        category: "Desktop Apps",
        summary: "Legacy GNOME music library player",
        risk: "safe",
    },
    BloatPkg {
        id: "cheese",
        pkg: "cheese",
        name: "Cheese Webcam",
        category: "Desktop Apps",
        summary: "Stock GNOME webcam booth app",
        risk: "safe",
    },
    BloatPkg {
        id: "simple-scan",
        pkg: "simple-scan",
        name: "Document Scanner",
        category: "Desktop Apps",
        summary: "GNOME flatbed scanner utility (remove if no scanner attached)",
        risk: "safe",
    },
    BloatPkg {
        id: "yelp",
        pkg: "yelp",
        name: "GNOME Help (Yelp)",
        category: "Desktop Apps",
        summary: "Offline GNOME documentation viewer",
        risk: "safe",
    },
    BloatPkg {
        id: "orca",
        pkg: "orca",
        name: "Orca Screen Reader",
        category: "Desktop Apps",
        summary: "Accessibility screen reader (keep if you rely on speech output)",
        risk: "caution",
    },
    BloatPkg {
        id: "libreoffice-fresh",
        pkg: "libreoffice-fresh",
        name: "LibreOffice Fresh",
        category: "Desktop Apps",
        summary: "Large office suite (~400 MB); safe to remove if using web docs",
        risk: "caution",
    },
    BloatPkg {
        id: "libreoffice-still",
        pkg: "libreoffice-still",
        name: "LibreOffice Still",
        category: "Desktop Apps",
        summary: "LTS office suite (~400 MB); safe to remove if using web docs",
        risk: "caution",
    },
    BloatPkg {
        id: "firefox",
        pkg: "firefox",
        name: "Mozilla Firefox",
        category: "Desktop Apps",
        summary: "Stock browser if you installed Helium, Brave, Zen, or Chromium",
        risk: "caution",
    },
];

const FEDORA_CATALOG: &[BloatPkg] = &[
    BloatPkg {
        id: "fed-abrt",
        pkg: "abrt",
        name: "ABRT Crash Reporter",
        category: "Telemetry & Reporting",
        summary: "Fedora automatic bug reporting daemon & crash catcher",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-abrt-desktop",
        pkg: "abrt-desktop",
        name: "ABRT Desktop Reporter",
        category: "Telemetry & Reporting",
        summary: "Graphical desktop crash popup notifications from ABRT",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-abrt-gui",
        pkg: "abrt-gui",
        name: "ABRT Problem Viewer",
        category: "Telemetry & Reporting",
        summary: "GTK frontend for inspecting ABRT crash reports",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-abrt-cli",
        pkg: "abrt-cli",
        name: "ABRT CLI Tools",
        category: "Telemetry & Reporting",
        summary: "Terminal ABRT reporting client",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-tour",
        pkg: "gnome-tour",
        name: "GNOME Tour",
        category: "GNOME Workstation Apps",
        summary: "First-login welcome slides irrelevant on MangoWC",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-gnome-software",
        pkg: "gnome-software",
        name: "GNOME Software",
        category: "GNOME Workstation Apps",
        summary: "Heavy background store daemon (~150 MB RSS + PackageKit)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-contacts",
        pkg: "gnome-contacts",
        name: "GNOME Contacts",
        category: "GNOME Workstation Apps",
        summary: "Unused GNOME address book application",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-maps",
        pkg: "gnome-maps",
        name: "GNOME Maps",
        category: "GNOME Workstation Apps",
        summary: "Desktop OpenStreetMap client",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-weather",
        pkg: "gnome-weather",
        name: "GNOME Weather",
        category: "GNOME Workstation Apps",
        summary: "Standalone weather app (built into Aurora Alerts hub)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-clocks",
        pkg: "gnome-clocks",
        name: "GNOME Clocks",
        category: "GNOME Workstation Apps",
        summary: "Stock timer/stopwatch app (built into Aurora hub bar)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-calendar",
        pkg: "gnome-calendar",
        name: "GNOME Calendar",
        category: "GNOME Workstation Apps",
        summary: "Evolution Data Server backed calendar app",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-connections",
        pkg: "gnome-connections",
        name: "GNOME Connections",
        category: "GNOME Workstation Apps",
        summary: "Pre-installed VNC/RDP remote desktop client",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-boxes",
        pkg: "gnome-boxes",
        name: "GNOME Boxes",
        category: "GNOME Workstation Apps",
        summary: "QEMU/libvirt VM wrapper (remove if not running desktop VMs)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-text-editor",
        pkg: "gnome-text-editor",
        name: "GNOME Text Editor",
        category: "GNOME Workstation Apps",
        summary: "GTK4 editor redundant alongside Zed, VS Code, or Neovim",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-rhythmbox",
        pkg: "rhythmbox",
        name: "Rhythmbox",
        category: "GNOME Workstation Apps",
        summary: "Legacy GNOME music player & podcast client",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-totem",
        pkg: "totem",
        name: "GNOME Videos (Totem)",
        category: "GNOME Workstation Apps",
        summary: "Stock media player replaceable with mpv or VLC",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-showtime",
        pkg: "showtime",
        name: "Showtime Video Player",
        category: "GNOME Workstation Apps",
        summary: "Fedora 42+ stock video player replaceable by mpv/VLC",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-decibels",
        pkg: "decibels",
        name: "Decibels Audio Player",
        category: "GNOME Workstation Apps",
        summary: "Minimal GNOME audio file player",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-cheese",
        pkg: "cheese",
        name: "Cheese Webcam",
        category: "GNOME Workstation Apps",
        summary: "Legacy GNOME webcam booth",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-snapshot",
        pkg: "snapshot",
        name: "GNOME Snapshot",
        category: "GNOME Workstation Apps",
        summary: "Modern GTK4 camera app unused on desktops",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-loupe",
        pkg: "loupe",
        name: "Loupe Image Viewer",
        category: "GNOME Workstation Apps",
        summary: "GNOME image viewer (keep if no other viewer is installed)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-evince",
        pkg: "evince",
        name: "Evince Document Viewer",
        category: "GNOME Workstation Apps",
        summary: "GNOME PDF reader (keep if you open local PDFs offline)",
        risk: "caution",
    },
    BloatPkg {
        id: "fed-simple-scan",
        pkg: "simple-scan",
        name: "Simple Scan",
        category: "GNOME Workstation Apps",
        summary: "Document scanning utility for physical scanners",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-yelp",
        pkg: "yelp",
        name: "GNOME Help (Yelp)",
        category: "GNOME Workstation Apps",
        summary: "GNOME documentation help browser",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-malcontent",
        pkg: "malcontent-control",
        name: "Malcontent Parental Controls",
        category: "GNOME Workstation Apps",
        summary: "GNOME parental controls UI panel",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-baobab",
        pkg: "baobab",
        name: "Disk Usage Analyzer",
        category: "GNOME Workstation Apps",
        summary: "GTK disk analyzer (aurora-fm Inspector calculates sizes natively)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-mediawriter",
        pkg: "mediawriter",
        name: "Fedora Media Writer",
        category: "GNOME Workstation Apps",
        summary: "Fedora USB ISO flasher tool no longer needed post-install",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-bookmarks",
        pkg: "fedora-bookmarks",
        name: "Fedora Bookmarks",
        category: "GNOME Workstation Apps",
        summary: "Pre-bundled default browser bookmarks package",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-chromium-cfg",
        pkg: "fedora-chromium-config",
        name: "Fedora Chromium Config",
        category: "GNOME Workstation Apps",
        summary: "Stock Fedora Chromium policy and default bookmarks",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-ptyxis",
        pkg: "ptyxis",
        name: "Ptyxis Terminal",
        category: "GNOME Workstation Apps",
        summary: "Fedora Workstation container terminal redundant with Foot/Kitty",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-gnome-terminal",
        pkg: "gnome-terminal",
        name: "GNOME Terminal",
        category: "GNOME Workstation Apps",
        summary: "Legacy GNOME terminal redundant with Foot/Kitty",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-lo-writer",
        pkg: "libreoffice-writer",
        name: "LibreOffice Writer",
        category: "GNOME Workstation Apps",
        summary: "Word processor component (~180 MB); keep if editing .docx locally",
        risk: "caution",
    },
    BloatPkg {
        id: "fed-lo-calc",
        pkg: "libreoffice-calc",
        name: "LibreOffice Calc",
        category: "GNOME Workstation Apps",
        summary: "Spreadsheet component (~110 MB); keep if editing .xlsx locally",
        risk: "caution",
    },
    BloatPkg {
        id: "fed-lo-impress",
        pkg: "libreoffice-impress",
        name: "LibreOffice Impress",
        category: "GNOME Workstation Apps",
        summary: "Presentation component (~80 MB)",
        risk: "caution",
    },
    BloatPkg {
        id: "fed-lo-core",
        pkg: "libreoffice-core",
        name: "LibreOffice Core",
        category: "GNOME Workstation Apps",
        summary: "Shared LibreOffice core runtime (removes full suite)",
        risk: "caution",
    },
    BloatPkg {
        id: "fed-firefox",
        pkg: "firefox",
        name: "Mozilla Firefox",
        category: "GNOME Workstation Apps",
        summary: "Default Fedora browser (keep unless you installed another browser)",
        risk: "caution",
    },
    BloatPkg {
        id: "fed-plasma-discover",
        pkg: "plasma-discover",
        name: "KDE Discover",
        category: "KDE Spin Apps",
        summary: "Heavy Plasma software store redundant with Aurora Store",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-dragon",
        pkg: "dragon",
        name: "Dragon Player",
        category: "KDE Spin Apps",
        summary: "KDE simple video player replaceable with mpv",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kmail",
        pkg: "kmail",
        name: "KMail",
        category: "KDE Spin Apps",
        summary: "KDE Akonadi-backed email client (frees heavy Akonadi DB processes)",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kontact",
        pkg: "kontact",
        name: "Kontact Suite",
        category: "KDE Spin Apps",
        summary: "KDE PIM umbrella suite",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-korganizer",
        pkg: "korganizer",
        name: "KOrganizer",
        category: "KDE Spin Apps",
        summary: "KDE PIM calendar application",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kaddressbook",
        pkg: "kaddressbook",
        name: "KAddressBook",
        category: "KDE Spin Apps",
        summary: "KDE PIM contacts application",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-akregator",
        pkg: "akregator",
        name: "Akregator RSS",
        category: "KDE Spin Apps",
        summary: "KDE RSS feed reader",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-elisa",
        pkg: "elisa-player",
        name: "Elisa Player",
        category: "KDE Spin Apps",
        summary: "KDE music library app",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-neochat",
        pkg: "neochat",
        name: "NeoChat Matrix",
        category: "KDE Spin Apps",
        summary: "KDE Matrix messaging client",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kmahjongg",
        pkg: "kmahjongg",
        name: "KMahjongg",
        category: "KDE Spin Apps",
        summary: "Bundled KDE board game",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kmines",
        pkg: "kmines",
        name: "KMines",
        category: "KDE Spin Apps",
        summary: "Bundled KDE minesweeper game",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kpat",
        pkg: "kpat",
        name: "KPatience",
        category: "KDE Spin Apps",
        summary: "Bundled KDE solitaire card games",
        risk: "safe",
    },
    BloatPkg {
        id: "fed-kolourpaint",
        pkg: "kolourpaint",
        name: "KolourPaint",
        category: "KDE Spin Apps",
        summary: "Basic KDE bitmap paint app",
        risk: "safe",
    },
];

const CACHYOS_SERVICES: &[BloatService] = &[
    BloatService {
        unit: "packagekit.service",
        name: "PackageKit Daemon",
        summary: "Background repo updater pulled by Discover/GNOME Software (unneeded on pacman)",
        risk: "safe",
    },
    BloatService {
        unit: "NetworkManager-wait-online.service",
        name: "NM Wait Online",
        summary: "Stalls boot waiting for full link readiness; disabling speeds up boot time",
        risk: "safe",
    },
    BloatService {
        unit: "ModemManager.service",
        name: "ModemManager",
        summary: "Cellular WWAN 4G/5G modem service (unneeded on desktops/standard Wi-Fi laptops)",
        risk: "safe",
    },
    BloatService {
        unit: "man-db.timer",
        name: "man-db Periodic Reindex",
        summary: "Background timer regenerating manual page caches on idle",
        risk: "safe",
    },
    BloatService {
        unit: "plocate-updatedb.timer",
        name: "plocate File Indexer Timer",
        summary: "Daily full-filesystem indexing timer (disable if not using locate)",
        risk: "safe",
    },
    BloatService {
        unit: "avahi-daemon.service",
        name: "Avahi mDNS Discovery",
        summary: "Local .local multicast discovery (keep if using AirPrint or Chromecast)",
        risk: "caution",
    },
    BloatService {
        unit: "cups.service",
        name: "CUPS Printing Service",
        summary: "Printer spooler daemon (disable only if you never print from this machine)",
        risk: "caution",
    },
    BloatService {
        unit: "bluetooth.service",
        name: "Bluetooth Stack Daemon",
        summary: "BlueZ daemon (keep enabled if you use Bluetooth headphones/mice)",
        risk: "caution",
    },
];

const FEDORA_SERVICES: &[BloatService] = &[
    BloatService {
        unit: "abrtd.service",
        name: "ABRT Crash Daemon",
        summary: "Fedora automatic crash catcher consuming background RAM",
        risk: "safe",
    },
    BloatService {
        unit: "abrt-oops.service",
        name: "ABRT Kernel Oops Watcher",
        summary: "Watches dmesg for kernel oops telemetry events",
        risk: "safe",
    },
    BloatService {
        unit: "abrt-journal-core.service",
        name: "ABRT Core Dump Collector",
        summary: "Processes systemd coredumps for ABRT bug reporting",
        risk: "safe",
    },
    BloatService {
        unit: "packagekit.service",
        name: "PackageKit Daemon",
        summary: "Heavy D-Bus updater redundant when using DNF or Aurora Store",
        risk: "safe",
    },
    BloatService {
        unit: "NetworkManager-wait-online.service",
        name: "NM Wait Online",
        summary: "Delays systemd graphical target waiting for DHCP link confirmation",
        risk: "safe",
    },
    BloatService {
        unit: "ModemManager.service",
        name: "ModemManager",
        summary: "Mobile broadband WWAN daemon unneeded on most PCs and laptops",
        risk: "safe",
    },
    BloatService {
        unit: "geoclue.service",
        name: "GeoClue Location Daemon",
        summary: "Desktop geolocation service (Aurora weather/night-light work without it)",
        risk: "safe",
    },
    BloatService {
        unit: "pcscd.socket",
        name: "Smartcard Daemon (pcscd)",
        summary: "PC/SC smartcard socket activation (keep if using YubiKey/PIV)",
        risk: "caution",
    },
    BloatService {
        unit: "avahi-daemon.service",
        name: "Avahi mDNS Discovery",
        summary: "Local .local hostname/printer discovery (keep if using network printers)",
        risk: "caution",
    },
    BloatService {
        unit: "cups.service",
        name: "CUPS Printing Service",
        summary: "Printer queue daemon (disable only if you do not print locally)",
        risk: "caution",
    },
];

const CACHYOS_TWEAKS: &[TweakItem] = &[
    TweakItem {
        id: "arch-orphans",
        title: "Remove Orphan Dependencies",
        summary: "Uninstall leftover libraries no longer required by any package (pacman -Qtdq)",
        detail: "Clears orphaned dependency trees left after removing apps without breaking explicit packages.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "arch-cache",
        title: "Prune Pacman Package Cache",
        summary: "Keep only latest 2 versions per package via paccache (fallback pacman -Sc)",
        detail: "Reclaims gigabytes of old package tarballs from /var/cache/pacman/pkg safely.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "arch-parallel",
        title: "Enable Pacman ParallelDownloads = 10 & Color",
        summary: "Uncomment Color and bump ParallelDownloads to 10 in /etc/pacman.conf",
        detail: "Significantly speeds up pacman and CachyOS repository syncs and downloads.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "arch-mirrors",
        title: "Refresh Fast CachyOS / Arch Mirrors",
        summary: "Rank fastest HTTPS mirrors using cachyos-rate-mirrors or reflector",
        detail: "Selects the lowest-latency mirrors automatically before system upgrades.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "journal-vacuum",
        title: "Vacuum Systemd Journal Logs (>100 MB)",
        summary: "Shrink /var/log/journal down to the most recent 100 MB",
        detail: "Keeps recent diagnostics intact while freeing bloated historical logs.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "flatpak-unused",
        title: "Remove Unused Flatpak Runtimes",
        summary: "Prune orphaned Flatpak SDKs and EOL platform runtimes",
        detail: "Runs flatpak uninstall --unused cleanly without root privileges.",
        risk: "safe",
        requires_root: false,
    },
];

const FEDORA_TWEAKS: &[TweakItem] = &[
    TweakItem {
        id: "fedora-dnf-fast",
        title: "Optimize DNF5 Speed (Parallel Downloads + Fastest Mirror)",
        summary: "Set max_parallel_downloads=10, fastestmirror=True & defaultyes=True in /etc/dnf/dnf.conf",
        detail: "Makes dnf5/dnf metadata syncs and package transfers dramatically faster on Fedora.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "fedora-autoremove",
        title: "Remove Unused DNF Leaf Packages",
        summary: "Uninstall orphaned Fedora dependencies via dnf autoremove",
        detail: "Clears old library packages left behind after removing preinstalled Workstation apps.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "fedora-clean",
        title: "Clean DNF Cache & Expired Metadata",
        summary: "Reclaim cached RPM packages and repodata from /var/cache/libdnf5",
        detail: "Safe cleanup of temporary package downloads and metadata snapshots.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "fedora-codecs",
        title: "Install Hardware Video & Multimedia Codecs (RPM Fusion)",
        summary: "Swap crippled stock ffmpeg-free/mesa stubs for full RPM Fusion codecs & VA-API",
        detail: "Recommended Fedora QOL setup for Firefox/mpv/OBS H.264, HEVC, and AV1 playback.",
        risk: "caution",
        requires_root: true,
    },
    TweakItem {
        id: "journal-vacuum",
        title: "Vacuum Systemd Journal Logs (>100 MB)",
        summary: "Shrink /var/log/journal down to the most recent 100 MB",
        detail: "Keeps recent system logs intact while trimming old rotated journals.",
        risk: "safe",
        requires_root: true,
    },
    TweakItem {
        id: "flatpak-unused",
        title: "Remove Unused Flatpak Runtimes",
        summary: "Prune orphaned Flatpak runtimes and extensions",
        detail: "Runs flatpak uninstall --unused without needing root permissions.",
        risk: "safe",
        requires_root: false,
    },
];

fn detect_host_target() -> (&'static str, &'static str, String) {
    let os_txt = fs::read_to_string("/etc/os-release").unwrap_or_default();
    let (family, pretty) = parse_os_release(&os_txt);
    let pacman_conf = fs::read_to_string("/etc/pacman.conf").unwrap_or_default();
    let lower_os = os_txt.to_ascii_lowercase();
    let is_cachyos = lower_os.contains("id=cachyos")
        || lower_os.contains("id=\"cachyos\"")
        || pacman_conf.contains("[cachyos");

    let host_target = if is_cachyos {
        "cachyos"
    } else if family == "arch" {
        "arch"
    } else if family == "fedora" {
        "fedora"
    } else {
        "other"
    };
    (family, host_target, pretty)
}

fn normalize_profile(raw: Option<&str>, host_target: &str) -> &'static str {
    match raw
        .map(str::trim)
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "cachyos" | "arch" => "cachyos",
        "fedora" => "fedora",
        _ => {
            if host_target == "fedora" {
                "fedora"
            } else {
                "cachyos"
            }
        }
    }
}

fn detect_dnf_bin() -> &'static str {
    if which("dnf5").is_some() {
        "dnf5"
    } else {
        "dnf"
    }
}

fn detect_priv_bin() -> &'static str {
    if which("sudo").is_some() {
        "sudo"
    } else if which("doas").is_some() {
        "doas"
    } else {
        "sudo"
    }
}

fn bounded_dir_bytes(path: &Path, depth: usize, budget: &mut usize) -> u64 {
    if depth > 4 || *budget == 0 {
        return 0;
    }
    let Ok(meta) = fs::symlink_metadata(path) else {
        return 0;
    };
    if meta.file_type().is_symlink() {
        return 0;
    }
    if meta.is_file() {
        return meta.len();
    }
    if !meta.is_dir() {
        return 0;
    }
    let Ok(rd) = fs::read_dir(path) else {
        return 0;
    };
    let mut sum = 0u64;
    for ent in rd.flatten() {
        if *budget == 0 {
            break;
        }
        *budget -= 1;
        sum = sum.saturating_add(bounded_dir_bytes(&ent.path(), depth + 1, budget));
    }
    sum
}

fn user_cache_bytes() -> u64 {
    let base = cache_dir();
    let targets = [
        base.join("thumbnails"),
        base.join("paru/clone"),
        base.join("yay"),
    ];
    let mut budget = 16_000usize;
    targets
        .iter()
        .map(|p| bounded_dir_bytes(p, 0, &mut budget))
        .fold(0u64, u64::saturating_add)
}

fn detect_pacman_optimized(conf_txt: &str) -> bool {
    conf_txt.lines().any(|l| {
        let t = l.trim();
        !t.starts_with('#') && t.starts_with("ParallelDownloads")
    })
}

fn detect_dnf_optimized(conf_txt: &str) -> bool {
    conf_txt.lines().any(|l| {
        let t = l.trim();
        !t.starts_with('#') && t.to_ascii_lowercase().starts_with("max_parallel_downloads")
    })
}

fn systemd_service_state(unit: &str, has_systemd: bool) -> &'static str {
    if has_systemd && which("systemctl").is_some() {
        if let Ok(out) = Command::new("systemctl")
            .args(["is-enabled", unit])
            .output()
        {
            let txt = String::from_utf8_lossy(&out.stdout)
                .trim()
                .to_ascii_lowercase();
            if txt.starts_with("enabled") {
                return "enabled";
            }
            if txt == "masked" {
                return "masked";
            }
            if txt == "disabled" || txt == "static" || txt == "indirect" {
                return "disabled";
            }
        }
    }
    for root in ["/usr/lib/systemd/system", "/etc/systemd/system"] {
        if Path::new(root).join(unit).exists() {
            return "disabled";
        }
    }
    "missing"
}

fn sanitize_debloat_pkg(raw: &str) -> Result<String, String> {
    let t = raw.trim();
    if t.is_empty() || t.len() > 128 {
        return Err("Package name must be 1 to 128 characters".to_string());
    }
    if t.starts_with('-') || t.contains("..") {
        return Err(format!("Invalid package token '{t}'"));
    }
    if !t
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'@' | b'.' | b'_' | b'+' | b'-'))
    {
        return Err(format!("Unsafe character in package token '{t}'"));
    }
    let lower = t.to_ascii_lowercase();
    if PROTECTED_PACKAGES.contains(&lower.as_str()) {
        return Err(format!(
            "Refusing to remove protected core package '{t}' (essential for OS, boot, or Aurora Shell)"
        ));
    }
    Ok(t.to_string())
}

fn sanitize_reinstall_pkg(raw: &str) -> Result<String, String> {
    let t = raw.trim();
    if t.is_empty() || t.len() > 128 || t.starts_with('-') || t.contains("..") {
        return Err(format!("Invalid package token '{t}'"));
    }
    if !t
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'@' | b'.' | b'_' | b'+' | b'-'))
    {
        return Err(format!("Unsafe character in package token '{t}'"));
    }
    Ok(t.to_string())
}

fn sanitize_service_unit(raw: &str, action: &str) -> Result<String, String> {
    let t = raw.trim();
    if t.is_empty() || t.len() > 128 || t.starts_with('-') || t.contains("..") {
        return Err(format!("Invalid systemd unit '{t}'"));
    }
    if !(t.ends_with(".service") || t.ends_with(".socket") || t.ends_with(".timer")) {
        return Err(format!(
            "Unit '{t}' must end with .service, .socket, or .timer"
        ));
    }
    if !t
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'@' | b'.' | b'_' | b'-'))
    {
        return Err(format!("Unsafe character in unit '{t}'"));
    }
    let lower = t.to_ascii_lowercase();
    if action == "disable" && PROTECTED_SERVICES.contains(&lower.as_str()) {
        return Err(format!(
            "Refusing to disable protected essential service '{t}'"
        ));
    }
    Ok(t.to_string())
}

fn build_remove_command(profile: &str, dnf_bin: &str, priv_bin: &str, pkgs: &[String]) -> String {
    let joined = pkgs.join(" ");
    if profile == "fedora" {
        format!("{priv_bin} {dnf_bin} remove -- {joined}")
    } else {
        format!("{priv_bin} pacman -Rns -- {joined}")
    }
}

fn build_reinstall_command(
    profile: &str,
    dnf_bin: &str,
    priv_bin: &str,
    pkgs: &[String],
) -> String {
    let joined = pkgs.join(" ");
    if profile == "fedora" {
        format!("{priv_bin} {dnf_bin} install -- {joined}")
    } else {
        format!("{priv_bin} pacman -S --needed -- {joined}")
    }
}

fn build_service_command(action: &str, priv_bin: &str, units: &[String]) -> String {
    let joined = units.join(" ");
    let verb = if action == "enable" {
        "enable --now"
    } else {
        "disable --now"
    };
    format!("{priv_bin} systemctl {verb} -- {joined}")
}

fn build_tweak_command(
    profile: &str,
    tweak_id: &str,
    dnf_bin: &str,
    priv_bin: &str,
) -> Result<(String, String, String, bool), String> {
    match tweak_id {
        "arch-orphans" => {
            if profile != "cachyos" {
                return Err("arch-orphans applies to CachyOS / Arch systems".to_string());
            }
            let cmd = format!(
                "orphans=$(pacman -Qtdq 2>/dev/null || true); if [ -n \"$orphans\" ]; then printf '%s\\n' \"$orphans\" | {priv_bin} pacman -Rns -; else echo 'No orphan packages found.'; fi"
            );
            Ok((
                "Remove Orphan Dependencies".to_string(),
                "Uninstalls unneeded dependency packages reported by pacman -Qtdq.".to_string(),
                cmd,
                true,
            ))
        }
        "arch-cache" => {
            if profile != "cachyos" {
                return Err("arch-cache applies to CachyOS / Arch systems".to_string());
            }
            let cmd = format!(
                "if command -v paccache >/dev/null 2>&1; then {priv_bin} paccache -rk2 && {priv_bin} paccache -ruk0; else {priv_bin} pacman -Sc --noconfirm; fi"
            );
            Ok((
                "Prune Pacman Cache".to_string(),
                "Keeps at most 2 cached versions of installed packages and removes uninstalled tarballs.".to_string(),
                cmd,
                true,
            ))
        }
        "arch-parallel" => {
            if profile != "cachyos" {
                return Err("arch-parallel applies to CachyOS / Arch systems".to_string());
            }
            let cmd = format!(
                "{priv_bin} python3 -c \"from pathlib import Path; p=Path('/etc/pacman.conf'); t=p.read_text(); t=t.replace('#Color','Color').replace('#ParallelDownloads = 5','ParallelDownloads = 10'); t=t.replace('ParallelDownloads = 5','ParallelDownloads = 10'); p.write_text(t); print('Updated /etc/pacman.conf')\""
            );
            Ok((
                "Optimize /etc/pacman.conf".to_string(),
                "Enables colored output and sets ParallelDownloads = 10 in /etc/pacman.conf."
                    .to_string(),
                cmd,
                true,
            ))
        }
        "arch-mirrors" => {
            if profile != "cachyos" {
                return Err("arch-mirrors applies to CachyOS / Arch systems".to_string());
            }
            let cmd = format!(
                "if command -v cachyos-rate-mirrors >/dev/null 2>&1; then {priv_bin} cachyos-rate-mirrors; elif command -v reflector >/dev/null 2>&1; then {priv_bin} reflector --latest 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist; else echo 'Install cachyos-rate-mirrors or reflector first.'; fi"
            );
            Ok((
                "Rate Fastest Mirrors".to_string(),
                "Ranks fast HTTPS mirrors using cachyos-rate-mirrors or reflector.".to_string(),
                cmd,
                true,
            ))
        }
        "fedora-dnf-fast" => {
            if profile != "fedora" {
                return Err("fedora-dnf-fast applies to Fedora systems".to_string());
            }
            let cmd = format!(
                "{priv_bin} python3 -c \"from pathlib import Path; p=Path('/etc/dnf/dnf.conf'); txt=p.read_text() if p.exists() else '[main]\\n'; u={{'max_parallel_downloads':'10','fastestmirror':'True','defaultyes':'True'}}; rows=[l.split('=',1) for l in txt.splitlines()]; out=[f'{{r[0].strip().lower()}}={{u[r[0].strip().lower()]}}' if len(r)==2 and not r[0].lstrip().startswith('#') and r[0].strip().lower() in u else (r[0] if len(r)==1 else r[0]+'='+r[1]) for r in rows]; present={{l.split('=',1)[0].strip().lower() for l in out if '=' in l and not l.lstrip().startswith('#')}}; out.extend(f'{{k}}={{v}}' for k,v in u.items() if k not in present); p.write_text('\\n'.join(out)+'\\n'); print('Updated /etc/dnf/dnf.conf')\""
            );
            Ok((
                "Optimize DNF5 (/etc/dnf/dnf.conf)".to_string(),
                "Configures max_parallel_downloads=10, fastestmirror=True, and defaultyes=True."
                    .to_string(),
                cmd,
                true,
            ))
        }
        "fedora-autoremove" => {
            if profile != "fedora" {
                return Err("fedora-autoremove applies to Fedora systems".to_string());
            }
            let cmd = format!("{priv_bin} {dnf_bin} autoremove");
            Ok((
                "Remove Unused Fedora Leaf Packages".to_string(),
                "Cleans up dependencies left behind after removing preinstalled apps.".to_string(),
                cmd,
                true,
            ))
        }
        "fedora-clean" => {
            if profile != "fedora" {
                return Err("fedora-clean applies to Fedora systems".to_string());
            }
            let cmd = format!("{priv_bin} {dnf_bin} clean all");
            Ok((
                "Clean DNF Package Cache".to_string(),
                "Removes cached RPM metadata and downloaded package files from /var/cache."
                    .to_string(),
                cmd,
                true,
            ))
        }
        "fedora-codecs" => {
            if profile != "fedora" {
                return Err("fedora-codecs applies to Fedora systems".to_string());
            }
            let cmd = format!(
                "{priv_bin} {dnf_bin} swap -y ffmpeg-free ffmpeg --allowerasing || true; {priv_bin} {dnf_bin} install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin || true"
            );
            Ok((
                "Install Full Fedora Codecs".to_string(),
                "Switches ffmpeg-free to full RPM Fusion ffmpeg and multimedia codecs.".to_string(),
                cmd,
                true,
            ))
        }
        "journal-vacuum" => {
            let cmd = format!("{priv_bin} journalctl --vacuum-size=100M");
            Ok((
                "Vacuum Systemd Journal".to_string(),
                "Trims old binary systemd journal archives while keeping the last 100 MB."
                    .to_string(),
                cmd,
                true,
            ))
        }
        "flatpak-unused" => Ok((
            "Remove Unused Flatpak Runtimes".to_string(),
            "Uninstalls unused Flatpak runtimes and EOL SDKs cleanly.".to_string(),
            "flatpak uninstall --unused -y".to_string(),
            false,
        )),
        other => Err(format!("Unknown debloat tweak '{other}'")),
    }
}

fn history_file_path() -> std::path::PathBuf {
    data_dir().join("aurora/debloat-history.json")
}

fn load_history() -> Vec<HistoryEntry> {
    let Ok(raw) = fs::read_to_string(history_file_path()) else {
        return Vec::new();
    };
    let Ok(val) = json::parse(&raw) else {
        return Vec::new();
    };
    let Some(arr) = val.get("entries").and_then(|v| v.as_arr()) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for item in arr.iter().take(50) {
        let ts = item.get_i64("ts").unwrap_or(0);
        let time_label = item.get_str("timeLabel").unwrap_or("").to_string();
        let target = item.get_str("target").unwrap_or("cachyos").to_string();
        let action = item.get_str("action").unwrap_or("remove").to_string();
        let mut pkgs = Vec::new();
        if let Some(pa) = item.get("packages").and_then(|v| v.as_arr()) {
            for p in pa {
                if let JsonVal::Str(s) = p {
                    pkgs.push(s.clone());
                }
            }
        }
        if !pkgs.is_empty() {
            out.push(HistoryEntry {
                ts,
                time_label,
                target,
                action,
                packages: pkgs,
            });
        }
    }
    out
}

fn save_history(entries: &[HistoryEntry]) -> Result<(), String> {
    let mut o = JsonOut::with_capacity(2048);
    o.obj_start();
    o.key("entries");
    o.arr_start();
    for ent in entries.iter().take(50) {
        o.obj_start();
        o.kv_i64("ts", ent.ts);
        o.kv_str("timeLabel", &ent.time_label);
        o.kv_str("target", &ent.target);
        o.kv_str("action", &ent.action);
        o.key("packages");
        o.arr_start();
        for p in &ent.packages {
            o.str(p);
        }
        o.arr_end();
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    let payload = format!("{}\n", o.finish());
    atomic_write(&history_file_path(), payload.as_bytes(), 0o600)
}

fn cmd_scan(args: &[String]) -> Result<(), String> {
    let (family, host_target, pretty_name) = detect_host_target();
    let profile = normalize_profile(args.first().map(String::as_str), host_target);
    let matches_host = (profile == "cachyos" && matches!(host_target, "cachyos" | "arch"))
        || (profile == "fedora" && host_target == "fedora");

    let catalog = if profile == "fedora" {
        FEDORA_CATALOG
    } else {
        CACHYOS_CATALOG
    };
    let services = if profile == "fedora" {
        FEDORA_SERVICES
    } else {
        CACHYOS_SERVICES
    };
    let tweaks = if profile == "fedora" {
        FEDORA_TWEAKS
    } else {
        CACHYOS_TWEAKS
    };

    let installed_map = if matches_host {
        collect_installed_native_fast(family)
    } else {
        Default::default()
    };
    let installed_lower: BTreeSet<String> = installed_map
        .keys()
        .map(|k| k.to_ascii_lowercase())
        .collect();

    let has_systemd = Path::new("/run/systemd/system").is_dir();
    let dnf_bin = detect_dnf_bin();
    let aur_helper = if family == "arch" {
        ["paru", "yay"]
            .into_iter()
            .find(|h| which(h).is_some())
            .unwrap_or("")
            .to_string()
    } else {
        String::new()
    };

    let mut pkg_budget = 8_000usize;
    let pkg_cache_bytes = if matches_host {
        if profile == "fedora" {
            bounded_dir_bytes(Path::new("/var/cache/libdnf5"), 0, &mut pkg_budget).saturating_add(
                bounded_dir_bytes(Path::new("/var/cache/dnf"), 0, &mut pkg_budget),
            )
        } else {
            bounded_dir_bytes(Path::new("/var/cache/pacman/pkg"), 0, &mut pkg_budget)
        }
    } else {
        0
    };
    let mut j_budget = 8_000usize;
    let journal_bytes = bounded_dir_bytes(Path::new("/var/log/journal"), 0, &mut j_budget);
    let u_cache_bytes = user_cache_bytes();

    let orphan_count = if matches_host && profile == "cachyos" && which("pacman").is_some() {
        run_stdout("pacman", &["-Qtdq"])
            .map(|s| s.lines().filter(|l| !l.trim().is_empty()).count() as u64)
            .unwrap_or(0)
    } else {
        0
    };

    let pacman_conf = fs::read_to_string("/etc/pacman.conf").unwrap_or_default();
    let dnf_conf = fs::read_to_string("/etc/dnf/dnf.conf").unwrap_or_default();
    let pacman_optimized = detect_pacman_optimized(&pacman_conf);
    let dnf_optimized = detect_dnf_optimized(&dnf_conf);
    let has_rpmfusion = family == "fedora" && detect_rpmfusion(Path::new("/etc/yum.repos.d"));
    let flatpak_available = which("flatpak").is_some();

    let mut installed_bloat_count = 0u64;
    let mut safe_installed_count = 0u64;

    let mut o = JsonOut::with_capacity(16384);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("hostTarget", host_target);
    o.kv_str("family", family);
    o.kv_str("prettyName", &pretty_name);
    o.kv_str("profile", profile);
    o.kv_bool("matchesHost", matches_host);
    o.kv_str(
        "packageManager",
        if profile == "fedora" {
            dnf_bin
        } else {
            "pacman"
        },
    );
    o.kv_str("aurHelper", &aur_helper);
    o.kv_bool("hasSystemd", has_systemd);
    o.kv_bool("flatpakAvailable", flatpak_available);
    o.kv_bool("pacmanOptimized", pacman_optimized);
    o.kv_bool("dnfOptimized", dnf_optimized);
    o.kv_bool("hasRpmFusion", has_rpmfusion);
    o.kv_u64("orphanCount", orphan_count);
    o.kv_u64("pkgCacheBytes", pkg_cache_bytes);
    o.kv_str("pkgCacheHuman", &human_size(pkg_cache_bytes));
    o.kv_u64("journalBytes", journal_bytes);
    o.kv_str("journalHuman", &human_size(journal_bytes));
    o.kv_u64("userCacheBytes", u_cache_bytes);
    o.kv_str("userCacheHuman", &human_size(u_cache_bytes));

    o.key("packages");
    o.arr_start();
    for item in catalog {
        let is_inst = matches_host && installed_lower.contains(&item.pkg.to_ascii_lowercase());
        if is_inst {
            installed_bloat_count += 1;
            if item.risk == "safe" {
                safe_installed_count += 1;
            }
        }
        o.obj_start();
        o.kv_str("id", item.id);
        o.kv_str("pkg", item.pkg);
        o.kv_str("name", item.name);
        o.kv_str("category", item.category);
        o.kv_str("summary", item.summary);
        o.kv_str("risk", item.risk);
        o.kv_bool("installed", is_inst);
        o.obj_end();
    }
    o.arr_end();

    let mut enabled_service_count = 0u64;
    o.key("services");
    o.arr_start();
    for svc in services {
        let state = if matches_host {
            systemd_service_state(svc.unit, has_systemd)
        } else {
            "missing"
        };
        if state == "enabled" {
            enabled_service_count += 1;
        }
        o.obj_start();
        o.kv_str("unit", svc.unit);
        o.kv_str("name", svc.name);
        o.kv_str("summary", svc.summary);
        o.kv_str("risk", svc.risk);
        o.kv_str("state", state);
        o.obj_end();
    }
    o.arr_end();

    o.key("tweaks");
    o.arr_start();
    for tw in tweaks {
        let applied = match tw.id {
            "arch-parallel" => pacman_optimized,
            "fedora-dnf-fast" => dnf_optimized,
            "arch-orphans" => matches_host && orphan_count == 0,
            "fedora-codecs" => has_rpmfusion,
            _ => false,
        };
        o.obj_start();
        o.kv_str("id", tw.id);
        o.kv_str("title", tw.title);
        o.kv_str("summary", tw.summary);
        o.kv_str("detail", tw.detail);
        o.kv_str("risk", tw.risk);
        o.kv_bool("requiresRoot", tw.requires_root);
        o.kv_bool("applied", applied);
        o.obj_end();
    }
    o.arr_end();

    o.kv_u64("installedBloatCount", installed_bloat_count);
    o.kv_u64("safeInstalledCount", safe_installed_count);
    o.kv_u64("enabledServiceCount", enabled_service_count);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_plan_remove(args: &[String]) -> Result<(), String> {
    let profile = match args.first().map(String::as_str) {
        Some("cachyos" | "arch") => "cachyos",
        Some("fedora") => "fedora",
        _ => return Err("Usage: debloat plan-remove <cachyos|fedora> <pkg...>".to_string()),
    };
    let raw_pkgs = args.get(1..).unwrap_or(&[]);
    if raw_pkgs.is_empty() {
        return Err("Select at least one package to remove".to_string());
    }
    let mut pkgs = Vec::with_capacity(raw_pkgs.len());
    for raw in raw_pkgs {
        let clean = sanitize_debloat_pkg(raw)?;
        if !pkgs.contains(&clean) {
            pkgs.push(clean);
        }
    }
    let command = build_remove_command(profile, detect_dnf_bin(), detect_priv_bin(), &pkgs);
    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("action", "remove");
    o.kv_str("target", profile);
    o.kv_str("title", &format!("Remove {} Package(s)", pkgs.len()));
    o.kv_str(
        "warning",
        "Review dependency output carefully inside your terminal before typing 'y' to confirm removal.",
    );
    o.kv_str("command", &command);
    o.kv_bool("requiresRoot", true);
    o.key("packages");
    o.arr_start();
    for p in &pkgs {
        o.str(p);
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_plan_reinstall(args: &[String]) -> Result<(), String> {
    let profile = match args.first().map(String::as_str) {
        Some("cachyos" | "arch") => "cachyos",
        Some("fedora") => "fedora",
        _ => return Err("Usage: debloat plan-reinstall <cachyos|fedora> <pkg...>".to_string()),
    };
    let raw_pkgs = args.get(1..).unwrap_or(&[]);
    if raw_pkgs.is_empty() {
        return Err("Specify at least one package to reinstall".to_string());
    }
    let mut pkgs = Vec::with_capacity(raw_pkgs.len());
    for raw in raw_pkgs {
        let clean = sanitize_reinstall_pkg(raw)?;
        if !pkgs.contains(&clean) {
            pkgs.push(clean);
        }
    }
    let command = build_reinstall_command(profile, detect_dnf_bin(), detect_priv_bin(), &pkgs);
    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("action", "reinstall");
    o.kv_str("target", profile);
    o.kv_str("title", &format!("Reinstall {} Package(s)", pkgs.len()));
    o.kv_str(
        "warning",
        "Restores previously removed package(s) from configured repositories.",
    );
    o.kv_str("command", &command);
    o.kv_bool("requiresRoot", true);
    o.key("packages");
    o.arr_start();
    for p in &pkgs {
        o.str(p);
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_plan_services(args: &[String]) -> Result<(), String> {
    let action = match args.first().map(String::as_str) {
        Some("disable") => "disable",
        Some("enable") => "enable",
        _ => return Err("Usage: debloat plan-services <disable|enable> <unit...>".to_string()),
    };
    let raw_units = args.get(1..).unwrap_or(&[]);
    if raw_units.is_empty() {
        return Err("Select at least one systemd unit".to_string());
    }
    let mut units = Vec::with_capacity(raw_units.len());
    for raw in raw_units {
        let clean = sanitize_service_unit(raw, action)?;
        if !units.contains(&clean) {
            units.push(clean);
        }
    }
    let command = build_service_command(action, detect_priv_bin(), &units);
    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("action", action);
    o.kv_str(
        "title",
        &format!(
            "{} {} Service(s)",
            if action == "enable" {
                "Enable"
            } else {
                "Disable"
            },
            units.len()
        ),
    );
    o.kv_str(
        "warning",
        "You can re-enable any unit immediately from the Services tab.",
    );
    o.kv_str("command", &command);
    o.kv_bool("requiresRoot", true);
    o.key("units");
    o.arr_start();
    for u in &units {
        o.str(u);
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_plan_tweak(args: &[String]) -> Result<(), String> {
    let profile = match args.first().map(String::as_str) {
        Some("cachyos" | "arch") => "cachyos",
        Some("fedora") => "fedora",
        _ => return Err("Usage: debloat plan-tweak <cachyos|fedora> <tweak_id>".to_string()),
    };
    let tweak_id = args
        .get(1)
        .map(String::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "Missing tweak id".to_string())?;
    let (title, warning, command, requires_root) =
        build_tweak_command(profile, tweak_id, detect_dnf_bin(), detect_priv_bin())?;

    let mut o = JsonOut::with_capacity(1024);
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("action", "tweak");
    o.kv_str("target", profile);
    o.kv_str("tweakId", tweak_id);
    o.kv_str("title", &title);
    o.kv_str("warning", &warning);
    o.kv_str("command", &command);
    o.kv_bool("requiresRoot", requires_root);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn remove_dir_contents_safe(dir: &Path, expected_parent: &Path) -> (u64, u64) {
    let Ok(parent_canon) = fs::canonicalize(expected_parent) else {
        return (0, 0);
    };
    let Ok(dir_canon) = fs::canonicalize(dir) else {
        return (0, 0);
    };
    if !dir_canon.starts_with(&parent_canon) {
        return (0, 0);
    }
    let Ok(rd) = fs::read_dir(&dir_canon) else {
        return (0, 0);
    };
    let mut freed = 0u64;
    let mut removed = 0u64;
    for ent in rd.flatten() {
        let p = ent.path();
        let Ok(meta) = fs::symlink_metadata(&p) else {
            continue;
        };
        if meta.file_type().is_symlink() {
            if fs::remove_file(&p).is_ok() {
                removed += 1;
            }
            continue;
        }
        if meta.is_file() {
            if fs::remove_file(&p).is_ok() {
                freed = freed.saturating_add(meta.len());
                removed += 1;
            }
        } else if meta.is_dir() {
            let mut b = 8_000usize;
            let sz = bounded_dir_bytes(&p, 0, &mut b);
            if fs::remove_dir_all(&p).is_ok() {
                freed = freed.saturating_add(sz);
                removed += 1;
            }
        }
    }
    (freed, removed)
}

fn cmd_clean_user() -> Result<(), String> {
    let base = cache_dir();
    let targets = [
        base.join("thumbnails"),
        base.join("paru/clone"),
        base.join("yay"),
    ];
    let mut freed_total = 0u64;
    let mut removed_total = 0u64;
    for t in &targets {
        if t.exists() {
            let (f, r) = remove_dir_contents_safe(t, &base);
            freed_total = freed_total.saturating_add(f);
            removed_total = removed_total.saturating_add(r);
        }
    }
    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_u64("freedBytes", freed_total);
    o.kv_str("freedHuman", &human_size(freed_total));
    o.kv_u64("removedCount", removed_total);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_snapshot() -> Result<(), String> {
    let (family, host_target, pretty_name) = detect_host_target();
    let mut lines: Vec<String> = Vec::new();
    lines.push(format!(
        "# Aurora Shell Package Snapshot ({pretty_name} / {host_target})"
    ));
    lines.push(format!("# Created: {}", unix_secs_to_iso(now_unix_secs())));
    lines.push(String::new());

    let mut count = 0u64;
    match family {
        "arch" => {
            lines.push("# Explicit Pacman Packages".to_string());
            if let Some(out) = run_stdout("pacman", &["-Qqe"]) {
                for l in out.lines().map(str::trim).filter(|l| !l.is_empty()) {
                    lines.push(l.to_string());
                    count += 1;
                }
            } else {
                let map = collect_installed_native_fast("arch");
                for k in map.keys() {
                    lines.push(k.clone());
                    count += 1;
                }
            }
        }
        "fedora" => {
            lines.push("# Installed RPM Packages".to_string());
            let map = collect_installed_native_fast("fedora");
            for k in map.keys() {
                lines.push(k.clone());
                count += 1;
            }
        }
        "gentoo" => {
            lines.push("# Portage @world Set".to_string());
            if let Ok(world) = fs::read_to_string("/var/lib/portage/world") {
                for l in world.lines().map(str::trim).filter(|l| !l.is_empty()) {
                    lines.push(l.to_string());
                    count += 1;
                }
            }
        }
        _ => {}
    }

    if let Some(fp) = run_stdout("flatpak", &["list", "--app", "--columns=application"]) {
        let apps: Vec<&str> = fp
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .collect();
        if !apps.is_empty() {
            lines.push(String::new());
            lines.push("# Flatpak Apps".to_string());
            for a in apps {
                lines.push(a.to_string());
                count += 1;
            }
        }
    }

    let ts = now_unix_secs();
    let out_path = data_dir().join(format!("aurora/pkg-snapshot-{ts}.txt"));
    let body = format!("{}\n", lines.join("\n"));
    atomic_write(&out_path, body.as_bytes(), 0o644)?;

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_str("path", &out_path.to_string_lossy());
    o.kv_u64("count", count);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_history() -> Result<(), String> {
    let entries = load_history();
    let mut o = JsonOut::with_capacity(2048);
    o.obj_start();
    o.kv_bool("ok", true);
    o.key("entries");
    o.arr_start();
    for ent in &entries {
        o.obj_start();
        o.kv_i64("ts", ent.ts);
        o.kv_str("timeLabel", &ent.time_label);
        o.kv_str("target", &ent.target);
        o.kv_str("action", &ent.action);
        o.key("packages");
        o.arr_start();
        for p in &ent.packages {
            o.str(p);
        }
        o.arr_end();
        o.obj_end();
    }
    o.arr_end();
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

fn cmd_record(args: &[String]) -> Result<(), String> {
    let target = match args.first().map(String::as_str) {
        Some("cachyos" | "arch") => "cachyos",
        Some("fedora") => "fedora",
        _ => return Err("Usage: debloat record <cachyos|fedora> <pkg...>".to_string()),
    };
    let raw_pkgs = args.get(1..).unwrap_or(&[]);
    if raw_pkgs.is_empty() {
        return Err("Missing packages to record".to_string());
    }
    let mut pkgs = Vec::with_capacity(raw_pkgs.len());
    for raw in raw_pkgs {
        let clean = sanitize_reinstall_pkg(raw)?;
        if !pkgs.contains(&clean) {
            pkgs.push(clean);
        }
    }
    let ts = now_unix_secs();
    let mut entries = load_history();
    entries.insert(
        0,
        HistoryEntry {
            ts,
            time_label: unix_secs_to_iso(ts),
            target: target.to_string(),
            action: "remove".to_string(),
            packages: pkgs,
        },
    );
    if entries.len() > 50 {
        entries.truncate(50);
    }
    save_history(&entries)?;

    let mut o = JsonOut::new();
    o.obj_start();
    o.kv_bool("ok", true);
    o.kv_u64("count", entries.len() as u64);
    o.obj_end();
    println!("{}", o.finish());
    Ok(())
}

pub fn cmd_debloat(args: &[String]) -> Result<(), String> {
    let sub = args.first().map(String::as_str).unwrap_or("scan");
    let rest = args.get(1..).unwrap_or(&[]);
    match sub {
        "scan" => cmd_scan(rest),
        "plan-remove" => cmd_plan_remove(rest),
        "plan-reinstall" => cmd_plan_reinstall(rest),
        "plan-services" => cmd_plan_services(rest),
        "plan-tweak" => cmd_plan_tweak(rest),
        "clean-user" => cmd_clean_user(),
        "snapshot" => cmd_snapshot(),
        "history" => cmd_history(),
        "record" => cmd_record(rest),
        other => Err(format!("Unknown debloat subcommand '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_protected_packages() {
        for pkg in [
            "linux",
            "linux-cachyos",
            "linux-cachyos-headers",
            "systemd",
            "pacman",
            "cachyos-keyring",
            "dnf5",
            "NetworkManager",
            "mango",
            "mangowm",
            "quickshell",
            "pipewire",
        ] {
            assert!(
                sanitize_debloat_pkg(pkg).is_err(),
                "expected protected rejection for {pkg}"
            );
        }
    }

    #[test]
    fn validates_pkg_and_unit_tokens() {
        assert_eq!(
            sanitize_debloat_pkg("cachyos-hello").as_deref(),
            Ok("cachyos-hello")
        );
        assert_eq!(
            sanitize_debloat_pkg("libreoffice-writer").as_deref(),
            Ok("libreoffice-writer")
        );
        assert!(sanitize_debloat_pkg("--noconfirm").is_err());
        assert!(sanitize_debloat_pkg("abrt;rm -rf /").is_err());
        assert!(sanitize_debloat_pkg("../etc/passwd").is_err());

        assert_eq!(
            sanitize_service_unit("abrtd.service", "disable").as_deref(),
            Ok("abrtd.service")
        );
        assert!(sanitize_service_unit("systemd-logind.service", "disable").is_err());
        assert!(sanitize_service_unit("aurora-powerd.service", "disable").is_err());
        assert!(sanitize_service_unit("bogus", "disable").is_err());
        assert!(sanitize_service_unit("bad;id.service", "disable").is_err());
    }

    #[test]
    fn builds_safe_cachyos_and_fedora_commands() {
        let pkgs = vec!["cachyos-hello".to_string(), "octopi".to_string()];
        let rm_cachy = build_remove_command("cachyos", "dnf5", "sudo", &pkgs);
        assert_eq!(rm_cachy, "sudo pacman -Rns -- cachyos-hello octopi");

        let fed_pkgs = vec!["abrt".to_string(), "gnome-tour".to_string()];
        let rm_fed = build_remove_command("fedora", "dnf5", "sudo", &fed_pkgs);
        assert_eq!(rm_fed, "sudo dnf5 remove -- abrt gnome-tour");

        let re_fed = build_reinstall_command("fedora", "dnf5", "sudo", &fed_pkgs);
        assert_eq!(re_fed, "sudo dnf5 install -- abrt gnome-tour");

        let re_cachy = build_reinstall_command("cachyos", "dnf5", "sudo", &pkgs);
        assert_eq!(re_cachy, "sudo pacman -S --needed -- cachyos-hello octopi");

        let svc_cmd = build_service_command("disable", "sudo", &["abrtd.service".to_string()]);
        assert_eq!(svc_cmd, "sudo systemctl disable --now -- abrtd.service");
    }

    #[test]
    fn builds_tweak_plans_and_conf_detectors() {
        let (title, _, cmd, root_req) =
            build_tweak_command("fedora", "fedora-dnf-fast", "dnf5", "sudo").expect("fedora tweak");
        assert!(title.contains("DNF5"));
        assert!(cmd.contains("max_parallel_downloads"));
        assert!(root_req);

        let (_, _, fp_cmd, fp_root) =
            build_tweak_command("cachyos", "flatpak-unused", "dnf5", "sudo").expect("flatpak");
        assert_eq!(fp_cmd, "flatpak uninstall --unused -y");
        assert!(!fp_root);

        assert!(build_tweak_command("fedora", "arch-parallel", "dnf5", "sudo").is_err());
        assert!(detect_pacman_optimized(
            "[options]\nParallelDownloads = 10\n"
        ));
        assert!(!detect_pacman_optimized(
            "[options]\n#ParallelDownloads = 5\n"
        ));
        assert!(detect_dnf_optimized("[main]\nmax_parallel_downloads=10\n"));
        assert!(!detect_dnf_optimized("[main]\n#max_parallel_downloads=5\n"));
    }
}
