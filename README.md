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
- **Built-in Quickshell Settings App (`Super + S`)**
  - **Appearance**: Switch visual modes (`Default` / `Simple` / `Blur`), theme presets or dynamic Matugen mode, Dark/Light scheme, and tune blur opacity/radius/passes, corner radius, window gaps, and animations (`mode-prefs.json`).
  - **Audio**: Output & microphone volume sliders, mute toggles, live default sink/source switching via `pactl`, and quick launch for `pavucontrol`.
  - **Displays**: Inspect connected outputs (`wlr-randr`), switch resolution, refresh rate, and fractional scaling live, or persist `monitor_rule` directly to `~/.config/mango/local.conf`.
  - **Network & Bluetooth** *(shown only when hardware exists)*: Wi-Fi radio toggle, scanning, and network connect (with inline password prompt); Bluetooth power toggle, scanning, and device connect/disconnect.
  - **Input**: Per-device keyboard layouts (`xkb_rules_layout`), repeat rate/delay, cursor size, mouse natural scrolling, and touchpad controls *(touchpad section shown only when a touchpad is detected)*.
  - **System**: Host & distro summary, detected hardware capability matrix, embedded **Power Menu**, and `local.conf` override counter/reset.
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
│   ├── quickshell/               # ShellRoot, Theme & DeviceCaps singletons, JSON state
│   │   ├── components/           # DynamicIsland, SimpleBar, QuickControls, SystemTrayStrip, PowerMenu, etc.
│   │   ├── settings/             # Modular Settings app (Appearance, Audio, Display, Network, BT, Input, System)
│   │   └── scripts/              # apply-mode.sh, apply-theme.sh, detect-hardware.sh, apply-local-setting.sh, lock.sh, etc.
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
3. Press `Super + S` to open **Settings** and configure per-device display resolution/scaling, keyboard layouts, touchpad/mouse options, audio defaults, or blur/gap tuning — per-device hardware rules are written cleanly to `~/.config/mango/local.conf`.
4. Optional: edit `~/.config/mango/config.conf` if you want different default app binds (`SUPER+B` → `helium`, `SUPER+Z` → `zedit`) or cursor theme (`catppuccin-mocha-dark-cursors`).

---

## Keybindings

| Shortcut | Action |
| --- | --- |
| `Super + Return` | Open terminal (`foot`) |
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

# Settings Window
qs ipc call island toggleSettings
qs ipc call island openSettings audio   # appearance | audio | displays | network | bluetooth | input | system
qs ipc call island closeSettings
```

---

## License

[MIT](LICENSE)
