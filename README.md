# MangoWC + Quickshell Dynamic Island Dotfiles

A complete, reactive Wayland desktop built around **MangoWC** (`mangowm` + `scenefx`) and **Quickshell**, featuring a morphing **Dynamic Island**, live **Matugen** wallpaper theming (synced across Quickshell, MangoWC, GTK 3/4, Foot, and Kitty), and **three instant visual modes** toggleable directly from Quick Controls.

---

## Features

- **Morphing Dynamic Island (`Quickshell`)**
  - Compact top pill showing time + collapsible Spotify/MPRIS mini-player with spinning album art and equalizer bars.
  - Hover or press `Super + D` to open the **Hub**: MPRIS Media Card, live CPU/RAM System Monitor, interactive MangoWC Tags (`1`–`9`) + layout switcher, and Quick Controls (volume, brightness, visual modes).
  - Built-in **Fuzzy App Launcher** (`Super + Space` / `Super + A`) with desktop entry filtering (`hidden-apps.json`).
  - Built-in **Theme & Wallpaper Switcher** (`Super + Shift + T`): live **Matugen** Material You extraction from `~/Pictures/Wallpapers`, 4 built-in presets (*Catppuccin Mocha*, *Tokyo Night*, *Gruvbox*, *Nord*), and instant Dark/Light switching synced across Quickshell, MangoWC, GTK 3/4, Foot, and Kitty.
  - Integrated **OSD** (volume, mute, brightness) and **Notification Server** with action buttons and critical urgency accents.
- **3 Live Visual Modes (MangoWC + Quickshell synced)**
  - **Default**: Floating rounded Dynamic Island (`border_radius=20`), soft shadows, smooth animations, opaque windows.
  - **Simple Mode** (*everything square*): Flat, 28px full-width square top bar (`SimpleBar`), `0px` border radius everywhere, zero gaps, no blur/shadows/animations, and crisp `2px` square focus borders.
  - **Blur Mode** (*frosted glass*): Keeps the Dynamic Island with translucent glass surfaces, subtle borders, and top sheen while enabling rich 4-pass `scenefx` window blur, translucent windows (`focused_opacity=0.86`, `unfocused_opacity=0.76`), and unfocused dimming.
- **Wayland Screenshots**: Area (`Super + =`) and fullscreen (`Super + Shift + =`) capture via `grim` + `slurp` + `wl-copy` with theme-matched selection colors and notifications.

---

## Repository Layout

```text
.
├── install.sh                    # Backup-safe installer script (configs + bundled fonts)
├── fonts/                        # Bundled JetBrains Mono & Symbols Nerd Font
├── config/
│   ├── mango/                    # MangoWC config, mode.conf, theme.conf, autostart.sh
│   ├── quickshell/               # Dynamic Island, SimpleBar, Theme engine & scripts
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

Choose your distribution below to install **MangoWC**, **Quickshell**, **Matugen**, **awww** (or `swww`), fonts, and utilities.

---

#### Arch Linux

Requires an AUR helper such as `paru` or `yay`.

```bash
# Official repositories
sudo pacman -S --needed \
  mangowm matugen foot kitty \
  grim slurp wl-clipboard brightnessctl libnotify \
  pipewire wireplumber pipewire-pulse \
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  polkit-gnome python adw-gtk-theme \
  ttf-jetbrains-mono ttf-nerd-fonts-symbols \
  qt6-svg qt6-imageformats qt6-multimedia qt6-5compat

# AUR packages (Quickshell + awww wallpaper daemon)
yay -S --needed quickshell awww-git
# Optional: catppuccin-cursors-mocha
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
  foot kitty grim slurp wl-clipboard brightnessctl libnotify \
  pipewire pipewire-pulseaudio wireplumber \
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  polkit-gnome python3 adw-gtk3-theme \
  jetbrains-mono-fonts \
  qt6-qtsvg qt6-qtimageformats qt6-qtmultimedia qt6-qt5compat

# Install Matugen (via Cargo if not available in DNF/COPR)
sudo dnf install -y cargo
cargo install matugen
# Make sure ~/.cargo/bin is in your PATH
```

> **Bundled Fonts:** Both **JetBrains Mono** and **Symbols Nerd Font** are included in `fonts/` and automatically installed to `~/.local/share/fonts/` by `./install.sh` (with `fc-cache`), so you don't need to download Nerd Fonts manually on Fedora, Arch, or Gentoo.

---

#### Gentoo

Enable the **GURU** community overlay first (provides `mangowm`, `scenefx`, `quickshell`, `matugen`, and `awww`):

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
```

Install all packages:

```bash
sudo emerge --ask --verbose \
  gui-wm/mangowm \
  gui-apps/quickshell \
  x11-misc/matugen \
  gui-apps/awww \
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
```

> Ensure `dev-qt/qtsvg`, `dev-qt/qtimageformats`, and `dev-qt/qt5compat` are installed (usually pulled in by `gui-apps/quickshell`), and `pactl` is available (`media-sound/pulseaudio-daemon` or `media-libs/libpulse`).

---

### 2. Clone & Install the Dotfiles

```bash
git clone https://github.com/AIharthi/mango-quickshell-dots.git
cd mango-quickshell-dots

# Install user configs into ~/.config (automatically backs up existing configs)
./install.sh

# Or also install /usr/local/bin/mango-session and the display manager entry:
./install.sh --with-session
```

### 3. Add Wallpapers & Customize

1. Place your wallpapers in `~/Pictures/Wallpapers/` (`.png`, `.jpg`, `.jpeg`, `.webp`).
2. Open the Theme Switcher (`Super + Shift + T`), select **Dynamic (Matugen)** or **Presets**, and click any wallpaper to apply it live.
3. Optional: edit `~/.config/mango/config.conf` to customize:
   - Keyboard layouts (`xkb_rules_layout=us,ara`)
   - Default browser (`SUPER+B` → `helium`) and editor (`SUPER+Z` → `zedit`)
   - Cursor theme (`cursor_theme=catppuccin-mocha-dark-cursors`)

---

## Keybindings

| Shortcut | Action |
| --- | --- |
| `Super + Return` | Open terminal (`foot`) |
| `Super + Space` / `Super + A` | Toggle Quickshell App Launcher |
| `Super + D` | Toggle Dynamic Island Hub |
| `Super + Shift + T` | Toggle Theme & Wallpaper Switcher |
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

### CLI / IPC Mode Switching

You can also switch visual modes from a terminal or custom keybinding:

```bash
qs ipc call island setShellMode default
qs ipc call island setShellMode simple
qs ipc call island setShellMode blur
```

---

## License

[MIT](LICENSE)
