# MangoWC + Quickshell Dynamic Island Dotfiles

A reactive, hardware-aware Wayland desktop built around **MangoWC** (`mangowm` + `scenefx`) and **Quickshell**, designed to adapt automatically across **desktops and laptops** (including multi-monitor setups), with live **Matugen** wallpaper theming, **three instant visual modes**, and a **built-in Quickshell Settings app**.

---

## Features

- **Hardware-Aware Multi-Device Adaptation (`DeviceCaps`)**
  - Automatically probes your machine at startup (`detect-hardware.sh`) and adapts the shell UI to the hardware actually present:
    - **Desktop PCs** without Wi-Fi, Bluetooth, backlight, battery, or touchpad automatically hide those unused controls and tabs — replacing clutter with a clean **Audio Output & Settings** shortcut.
    - **Laptops** automatically surface live **Battery % / charging status** (in the Dynamic Island pill, Simple Bar, and System Monitor), **Backlight brightness**, **Wi-Fi**, **Bluetooth**, and **Touchpad** settings.
  - **Multi-Monitor Support**: Wraps `PanelWindow`s in Quickshell `Variants` over `Quickshell.screens`, syncing per-monitor MangoWC tags across all connected displays.
  - **Per-Device MangoWC Overrides (`~/.config/mango/local.conf`)**: Included via `source_optional=~/.config/mango/local.conf` (ignored by Git and preserved across `./install.sh` re-runs), so every machine can pull the same dotfiles while keeping its own monitor rules, keyboard layout, and touchpad settings.
- **Built-in Quickshell Settings App (`Super + S`)** *(with live sidebar search, smooth open/close, sliding indicator, toggle & page transitions)*
  - **Appearance**: Switch visual modes (`Default` / `Simple` / `Blur`), theme presets or dynamic Matugen mode, Dark/Light scheme, **Typography & System Font** selector & point size (synced across Quickshell, GTK 3/4, `gsettings`, Foot, and Kitty), **Cursor Theme & Size** (`20`–`48px` + auto-hide idle/typing, synced across MangoWC, GTK 3/4, `~/.icons/default`, and `gsettings`), MangoWC animation styles/speeds (`zoom`/`slide`/`fade`/`none`), shadows, border width, blur parameters, corner radius, and gaps.
  - **Windows**: Focus follows mouse (`sloppy_focus`), cursor warp (`warp_cursor`), focus on activate, new-as-master, master area ratio, smart gaps, drag-to-swap, scroller column proportion, and floating magnetic snapping (`~/.config/mango/local.conf`).
  - **Audio**: Output & microphone volume sliders, mute toggles, live default sink/source switching, **Application Volume Mixer** (per-stream volume & mute via `pactl --format=json list sink-inputs`), and quick launch for `pavucontrol`.
  - **Displays**: Inspect connected outputs (`wlr-randr`), switch resolution, refresh rate, fractional scaling, **Orientation / Rotation** (`0°`–`270°`), and **Adaptive Sync (VRR)** live or persist `monitor_rule` to `~/.config/mango/local.conf`, plus conditional **Night Light** *(when `hyprsunset`/`wlsunset`/`gammastep` is installed)*.
  - **Network & Bluetooth** *(shown only when hardware exists)*: Wi-Fi radio toggle, scanning, and network connect (with inline password prompt); Bluetooth power toggle, scanning, and device connect/disconnect.
  - **Input**: Per-device keyboard layouts (`xkb_rules_layout`), switch shortcut (`xkb_rules_options`), repeat rate/delay, NumLock on startup, mouse/trackpad acceleration profile (`Flat` / `Adaptive`) & pointer speed, natural scrolling, and touchpad controls *(touchpad section shown only when a touchpad is detected)*.
  - **Notifications**: **Do Not Disturb** toggle (`󰂛` active badge in bar & island), popup auto-hide duration (`2.5s`–`10s`), **Test Notification** trigger, and scrollable session **Notification History** with individual dismiss and Clear All.
  - **Apps & Startup**: Configure **Quick-Launch Keybind Apps** (`Super + Return` / `B` / `Z` via `launch-app.sh`), system **XDG Default Apps** (`xdg-mime` for Web, Files, Text, Images, Video), and **Startup Applications** (`exec_once` in `~/.config/mango/local.conf` alongside built-in `autostart.sh` services).
  - **Shortcuts**: Searchable, categorized **MangoWC Keybindings & Mouse Actions** viewer parsed directly from your live compositor config.
  - **System**: CPU, GPU, RAM, uptime, **Disk Storage** usage bars, **Date & Time** format (`24h`/`12h`, seconds, date pattern, timezone), **Keep Screen Awake** (`Wayland IdleInhibitor`), conditional **Power Profiles** (`powerprofilesctl`), detected hardware capability badges, embedded **Power Menu**, and MangoWC reload / `local.conf` reset.
- **Morphing Dynamic Island (`Quickshell`)**
  - Compact top pill showing time, optional battery indicator, and collapsible Spotify/MPRIS mini-player with spinning album art and equalizer bars.
  - Hover or press `Super + D` to open the **Hub**: MPRIS Media Card, live CPU/RAM (+ optional Battery) System Monitor, interactive MangoWC Tags (`1`–`9`) + layout switcher, hardware-aware Quick Controls, **System Tray** (`StatusNotifierItem`), and collapsible **Power Menu** (Lock, Suspend, Logout, Reboot, Poweroff with confirmation).
  - Built-in **Fuzzy App Launcher** (`Super + Space` / `Super + A`) with desktop entry filtering (`hidden-apps.json`).
  - Built-in **Theme & Wallpaper Switcher** (`Super + Shift + T`): live **Matugen** Material You extraction from `~/Pictures/Wallpapers`, 4 built-in presets (*Catppuccin Mocha*, *Tokyo Night*, *Gruvbox*, *Nord*), and instant Dark/Light switching synced across Quickshell, MangoWC, GTK 3/4, Foot, and Kitty.
  - Integrated **OSD** (volume, mute, brightness) and **Notification Server** with action buttons and critical urgency accents.
- **3 Live Visual Modes (MangoWC + Quickshell synced)**
  - **Default**: Floating rounded Dynamic Island, soft shadows, smooth animations, opaque windows.
  - **Simple Mode** (*everything square*): Flat, 28px full-width square top bar (`SimpleBar`), `0px` border radius everywhere, zero gaps, no blur/shadows/animations, and crisp `2px` square focus borders.
  - **Blur Mode** (*frosted glass*): Keeps the Dynamic Island with translucent glass surfaces, subtle borders, and top sheen while enabling rich `scenefx` window blur, translucent windows, and unfocused dimming.
- **Wayland Screenshots & Screen Lock**: Area (`Super + =`) and fullscreen (`Super + Shift + =`) capture via `grim` + `slurp` + `wl-copy`, plus lock screen (`Super + Shift + L`) using `hyprlock` / `swaylock` / `waylock`.

---

## Repository Layout

```text
.
├── install.sh                    # Backup-safe installer script (configs + bundled fonts; preserves local.conf)
├── fonts/                        # Bundled JetBrains Mono & Symbols Nerd Font
├── config/
│   ├── mango/                    # MangoWC config, mode.conf, theme.conf, autostart.sh
│   ├── quickshell/               # ShellRoot, Theme, DeviceCaps & ShellState singletons, JSON state
│   │   ├── components/           # DynamicIsland, SimpleBar, QuickControls, SystemTrayStrip, PowerMenu, etc.
│   │   ├── settings/             # Modular Settings app (11 pages: Appearance .. Shortcuts, System)
│   │   └── scripts/              # apply-mode.sh, apply-theme.sh, manage-settings.sh, launch-app.sh, detect-hardware.sh, etc.
│   ├── matugen/                  # Matugen config & templates (QS, GTK3/4, Mango, Foot, Kitty)
│   ├── foot/                     # Foot terminal config + synced colors
│   ├── kitty/                    # Kitty terminal config + synced colors
│   └── xdg-desktop-portal/       # Wayland screencast/screenshot portal config
└── system/
    ├── mango-session             # Optional /usr/local/bin/mango-session wrapper
    └── mango.desktop             # Optional /usr/share/wayland-sessions/mango.desktop
```

---

## Installation Guide

### 1. Install Dependencies

Choose your distribution below to install **MangoWC**, **Quickshell**, **Matugen**, **awww** (or `swww`), `wlr-randr`, and desktop utilities.

---

#### Arch Linux

Requires an AUR helper such as `paru` or `yay`.

```bash
# Official repositories
sudo pacman -S --needed \
  mangowm matugen foot kitty \
  wlr-randr grim slurp wl-clipboard brightnessctl libnotify \
  pipewire wireplumber pipewire-pulse \
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  polkit-gnome python adw-gtk-theme \
  ttf-jetbrains-mono ttf-nerd-fonts-symbols \
  qt6-svg qt6-imageformats qt6-multimedia qt6-5compat

# AUR packages (Quickshell + awww wallpaper daemon)
yay -S --needed quickshell awww-git
# Optional: swaylock (or hyprlock), pavucontrol, catppuccin-cursors-mocha
```

> **Note:** If `mangowm` is not yet in your mirror's official repos, install `mangowm-git` from the AUR (`yay -S mangowm-git`).

---

#### Fedora

```bash
# Enable required COPR repositories
sudo dnf copr enable -y dennemann/MangoWC
sudo dnf copr enable -y errornointernet/quickshell
sudo dnf copr enable -y scottames/awww

# Install compositor, shell, and desktop utilities
sudo dnf install -y \
  mangowc quickshell awww \
  foot kitty wlr-randr grim slurp wl-clipboard brightnessctl libnotify \
  pipewire pipewire-pulseaudio wireplumber \
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  polkit-gnome python3 adw-gtk3-theme \
  jetbrains-mono-fonts \
  qt6-qtsvg qt6-qtimageformats qt6-qtmultimedia qt6-qt5compat
# Optional: swaylock, pavucontrol

# Install Matugen (via Cargo if not available in DNF/COPR)
sudo dnf install -y cargo
cargo install matugen
# Make sure ~/.cargo/bin is in your PATH
```

> **Bundled Fonts:** Both **JetBrains Mono** and **Symbols Nerd Font** are included in `fonts/` and automatically installed to `~/.local/share/fonts/` by `./install.sh` (with `fc-cache`), so you don't need to download Nerd Fonts manually on Fedora, Arch, or Gentoo.

---

#### Gentoo

Enable the **GURU** community overlay first (provides `mangowm`, `scenefx`, `quickshell`, `matugen`, `awww`, and `wlr-randr`):

```bash
sudo emerge --ask --verbose app-eselect/eselect-repository
sudo eselect repository enable guru
sudo emaint sync -r guru
```

Unmask testing keywords (e.g., `/etc/portage/package.accept_keywords/mango-desktop`):

```text
gui-libs/scenefx ~amd64
gui-wm/mangowm ~amd64
gui-apps/quickshell ~amd64
x11-misc/matugen ~amd64
gui-apps/awww ~amd64
gui-apps/wlr-randr ~amd64
```

Install all packages:

```bash
sudo emerge --ask --verbose \
  gui-wm/mangowm \
  gui-apps/quickshell \
  x11-misc/matugen \
  gui-apps/awww \
  gui-apps/wlr-randr \
  gui-apps/foot \
  gui-apps/grim \
  gui-apps/slurp \
  gui-apps/wl-clipboard \
  app-misc/brightnessctl \
  x11-libs/libnotify \
  media-fonts/jetbrains-mono \
  media-fonts/symbols-nerd-font \
  x11-themes/adw-gtk3 \
  sys-apps/xdg-desktop-portal \
  gui-libs/xdg-desktop-portal-wlr \
  sys-apps/xdg-desktop-portal-gtk \
  gnome-extra/polkit-gnome \
  media-video/pipewire
# Optional: gui-apps/swaylock, media-sound/pavucontrol
```

> Ensure `dev-qt/qtsvg`, `dev-qt/qtimageformats`, and `dev-qt/qt5compat` are installed (usually pulled in by `gui-apps/quickshell`), and `pactl` is available (`media-sound/pulseaudio-daemon` or `media-libs/libpulse`).

---

### 2. Clone & Install the Dotfiles

```bash
git clone https://github.com/AIharthi/mango-quickshell-dots.git
cd mango-quickshell-dots

# Install user configs & fonts into ~/.config and ~/.local/share/fonts
# (automatically backs up existing configs and preserves any existing ~/.config/mango/local.conf)
./install.sh

# Or also install /usr/local/bin/mango-session and the display manager entry:
./install.sh --with-session
```

### 3. Add Wallpapers & Per-Device Setup

1. Place your wallpapers in `~/Pictures/Wallpapers/` (`.png`, `.jpg`, `.jpeg`, `.webp`).
2. Open the Theme Switcher (`Super + Shift + T`), select **Dynamic (Matugen)** or **Presets**, and click any wallpaper to apply it live.
3. Press `Super + S` to open **Settings** and configure fonts, displays, audio mixer, notifications, default apps/startup entries, or per-device hardware rules — hardware overrides are written cleanly to `~/.config/mango/local.conf` and UI/default-app preferences to `~/.config/quickshell/shell-prefs.json`.
4. Optional: customize `Super + Return / B / Z` default terminal/browser/editor directly inside **Settings → Apps & Startup** (powered by `launch-app.sh`).

---

## Keybindings

| Shortcut | Action |
| --- | --- |
| `Super + Return` | Open default terminal (`launch-app.sh terminal`) |
| `Super + B` / `Super + Z` | Open default browser / editor (`launch-app.sh browser` / `editor`) |
| `Super + Space` / `Super + A` | Toggle Quickshell App Launcher |
| `Super + D` | Toggle Dynamic Island Hub |
| `Super + S` | Toggle Built-in Settings App |
| `Super + Shift + T` | Toggle Theme & Wallpaper Switcher |
| `Super + Shift + L` | Lock screen (`hyprlock` / `swaylock` / `waylock`) |
| `Super + =` / `Super + Shift + =` | Area / Fullscreen Screenshot |
| `Super + Q` | Close focused window |
| `Super + 1..9` | Switch to tag `1`–`9` |
| `Super + Shift + 1..9` | Move window to tag `1`–`9` |
| `Super + N` | Cycle MangoWC layout |
| `Super + T` | Force current tag & window back to tiled mode |
| `Super + \` | Toggle floating |
| `Super + F` | Toggle fullscreen |
| `Super + R` | Reload MangoWC config |
| `Super + M` | Quit MangoWC |

### CLI / IPC Controls

```bash
# Visual Modes
qs ipc call island setShellMode default
qs ipc call island setShellMode simple
qs ipc call island setShellMode blur

# Settings Window & Toggles
qs ipc call island toggleSettings
qs ipc call island openSettings audio   # appearance | windows | audio | displays | network | bluetooth | input | notifications | apps | shortcuts | system
qs ipc call island closeSettings
qs ipc call island toggleDnd
qs ipc call island toggleKeepAwake
```

---

## License

[MIT](LICENSE)
