# Keybindings & Quickshell IPC Reference

Default compositor keybindings live in [`config/mango/config.conf`](../config/mango/config.conf). You can also search, filter, and append custom `bind=` rules interactively in **Settings → Shortcuts** (validated with `mango -p` before writing to `~/.config/mango/local.conf`).

---

## Shell, Launcher & Utilities

| Shortcut | Action |
| --- | --- |
| `Super + Return` | Open default terminal (`launch-app.sh terminal`) |
| `Super + B` | Open default browser (`launch-app.sh browser`) |
| `Super + Z` | Open default editor (`launch-app.sh editor`) |
| `Super + A` / `Super + Space` | Toggle Quickshell App Launcher |
| `Super + D` | Toggle Dynamic Island Hub |
| `Super + S` | Toggle Built-in Settings App (`16` hardware-aware pages) |
| `Super + Shift + T` | Toggle Theme & Wallpaper Switcher |
| `Super + Shift + E` | Toggle Dynamic File Manager (`mango-fm`) |
| `Super + Alt + E` | Toggle Dynamic Island Quick Files Tab |
| `Super + Shift + L` | Lock screen (`lock.sh`: `hyprlock` / `swaylock` / `waylock`) |
| `Super + =` | Area screenshot (`screenshot.sh --area`) |
| `Super + Shift + =` | Fullscreen screenshot (`screenshot.sh --full`) |
| `Super + R` | Reload MangoWC config (`reload_config`) |
| `Super + M` | Quit MangoWC (`quit`) |
| `XF86AudioRaiseVolume` / `LowerVolume` / `Mute` | Adjust volume (`pactl`) + show Dynamic Island OSD |
| `XF86MonBrightnessUp` / `Down` | Adjust backlight (`brightnessctl`) + show Dynamic Island OSD |

---

## Picture-in-Picture (PiP)

| Shortcut | Action |
| --- | --- |
| `Super + P` | Toggle focused window into PiP (floating + sticky + overlay) |
| `Super + Shift + P` | Cycle active PiP window across screen corners |
| `Super + Alt + P` | Re-snap active PiP window to configured size & corner |

*(Browser and chat popouts matching Picture-in-Picture titles in `config/mango/config.conf` also auto-float as global overlay PiP windows.)*

---

## Window & Layout Management

| Shortcut | Action |
| --- | --- |
| `Super + Q` | Close focused window (`killclient`) |
| `Super + Tab` | Focus next window in stack |
| `Super + Left / Right / Up / Down` | Focus window by direction |
| `Super + Shift + Left / Right / Up / Down` | Move window by direction |
| `Super + \` | Toggle floating |
| `Super + F` / `Super + Shift + F` | Toggle fullscreen / fake fullscreen |
| `Super + Shift + A` | Maximize window to screen |
| `Super + G` | Toggle global window |
| `Super + Shift + Tab` | Toggle window jump |
| `Super + I` / `Super + Shift + I` | Minimize window / restore minimized |
| `Super + O` | Toggle overlay state |
| `Super + Alt + Z` | Toggle scratchpad |
| `Super + N` | Switch MangoWC layout (`scroller`, `dwindle`, `tile`, `monocle`, etc.) |
| `Super + T` | Force current tag & window back to tiled mode (`force-tile.sh`) |
| `Super + E` | Reset scroller proportion (`1.0`) |
| `Super + X` | Cycle scroller proportion preset |
| `Super + Alt + Ctrl + Arrows` | Stack scroller windows left/right/up/down |
| `Super + Shift + Return` | Toggle dwindle split direction |

---

## Tags, Monitors, Gaps & Floating Geometry

| Shortcut | Action |
| --- | --- |
| `Super + 1..9` | Switch to tag `1`–`9` |
| `Super + Shift + 1..9` | Move focused window to tag `1`–`9` |
| `Super + Ctrl + Left / Right` | Switch to previous / next tag |
| `Super + Alt + Left / Right` | Switch to previous / next occupied tag |
| `Super + Ctrl + Shift + Left / Right` | Move focused window to previous / next tag |
| `Super + ,` / `Super + .` | Focus left / right monitor |
| `Super + Shift + ,` / `Super + Shift + .` | Move window to left / right monitor |
| `Super + Shift + X` / `Super + Shift + Z` | Increase / decrease gaps |
| `Super + Alt + R` | Toggle gaps |
| `Super + Ctrl + H / J / K / L` | Move floating window (`50px` steps) |
| `Super + Alt + H / J / K / L` | Resize floating window (`50px` steps) |

---

## Mouse, Wheel & Touchpad Gestures

| Input | Binding | Action |
| --- | --- | --- |
| `Super + Left Click` | `moveresize,curmove` | Drag to move window |
| `Super + Right Click` | `moveresize,curresize` | Drag to resize window |
| `Middle Click` | `togglemaximizescreen` | Maximize window |
| `Super + Scroll Up / Down` | `viewtoleft_have_client` / `viewtoright_have_client` | Switch occupied tags |
| `3-Finger Swipe (L/R/U/D)` | `focusdir` | Focus directional neighbor |
| `4-Finger Swipe Left / Right` | `viewnext_have_client` / `viewprev_have_client` | Cycle occupied tags |
| `4-Finger Swipe Up / Down` | `enteroverview` / `leaveoverview` | Toggle window overview |

---

## Quickshell IPC Commands (`qs ipc call island ...`)

```bash
# Drawers, Launcher, Settings & Files
qs ipc call island toggleLauncher
qs ipc call island toggleThemeTab
qs ipc call island toggleDashboard
qs ipc call island collapse
qs ipc call island showOsd <volume|mute|brightness>
qs ipc call island toggleSettings
qs ipc call island openSettings <appearance|themes|shell|windows|audio|displays|network|bluetooth|input|terminals|notifications|apps|shortcuts|privacy|monitor|system>
qs ipc call island closeSettings
qs ipc call island toggleFiles
qs ipc call island openFiles <path>
qs ipc call island closeFiles
qs ipc call island toggleFilesTab
qs ipc call island resetFiles

# Visual Modes & Live Theming
qs ipc call island setShellMode <default|simple|blur>
qs ipc call island toggleShellMode <default|simple|blur>
qs ipc call island applyVibe <aurora-glass|minimal-square|oled-stealth|neon-cyber|cozy-paper|full-dock-bar|warm-gruvbox|dracula-notch>
qs ipc call island applyPreset <preset-id>
qs ipc call island applyAccent "#cba6f7"
qs ipc call island randomWallpaper
qs ipc call island toggleDarkLight

# System Toggles, Resets & PiP
qs ipc call island toggleDnd
qs ipc call island toggleKeepAwake
qs ipc call island clearClipboard
qs ipc call island resetAppearance
qs ipc call island resetBar
qs ipc call island resetAllSettings
qs ipc call island togglePip
qs ipc call island cyclePipCorner
qs ipc call island snapPip
```
