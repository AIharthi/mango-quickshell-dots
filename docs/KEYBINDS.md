# Keybindings & Quickshell IPC Reference

Default compositor keybindings live in [`config/mango/config.conf`](../config/mango/config.conf). You can also search, filter, and append custom `bind=` rules interactively in **Settings → Shortcuts** (validated with `mango -p` before writing to `~/.config/mango/local.conf`).

---

## Shell, Launcher & Utilities

| Shortcut | Action |
| --- | --- |
| `Super + Return` | Open default terminal (`launch-app.sh terminal`) |
| `Super + B` | Open default browser (`launch-app.sh browser`) |
| `Super + Z` | Open default editor (`launch-app.sh editor`) |
| `Super + A` / `Super + Space` | Toggle Multi-Mode Launcher (`Apps`, `=` Calc, `>` Commands, `:` Emoji, `cb ` Clipboard) |
| `Super + W` | Toggle Open Window Switcher (`WindowSwitcher.qml` via `mmsg get all-clients`) |
| `Super + Escape` | Toggle Full-Screen Power Overlay (`Lock`, `Suspend`, `Hibernate`, `Logout`, `Reboot`, `Poweroff`) |
| `Super + Shift + G` | Toggle Game Mode (switches bar to Minimal Pill + pauses slideshow & idle auto-lock) |
| `Super + V` | Toggle Clipboard History Manager (`manage-clipboard.sh`) |
| `Super + Shift + N` | Toggle Alerts & Agenda Hub (Notifications, Calendar, Timer/Stopwatch, Weather, Scratchpad) |
| `Super + /` | Toggle Interactive Keybind Cheat Sheet Modal |
| `Super + D` | Toggle Dynamic Island Hub |
| `Super + S` | Toggle Built-in Settings App (`16` hardware-aware pages) |
| `Super + Shift + T` | Toggle Theme & Wallpaper Switcher |
| `Super + Shift + E` | Toggle Dynamic File Manager (`aurora-fm`) |
| `Super + Alt + E` | Toggle Dynamic Island Quick Files Tab |
| `Super + Shift + L` | Lock screen (`lock.sh`: native `WlSessionLock` PAM screen, or `hyprlock`/`swaylock`/`waylock` fallback) |
| `Super + =` | Area screenshot (`screenshot.sh --area`) |
| `Super + Shift + =` | Fullscreen screenshot (`screenshot.sh --full`) |
| `Super + Ctrl + =` | Focused window screenshot (`screenshot.sh --window`) |
| `Super + Alt + C` | Eyedropper color picker (`screenshot.sh --color`, copies `#RRGGBB`) |
| `Super + Shift + R` | Toggle area screen recording (`record-screen.sh toggle --area`) |
| `Super + R` | Reload MangoWC config (`reload_config`) |
| `Super + M` | Quit MangoWC (`quit`) |
| `XF86AudioRaiseVolume` / `LowerVolume` / `Mute` | Adjust volume (`pactl`) + show Dynamic Island OSD |
| `XF86AudioMicMute` | Toggle microphone mute (`pactl`) + show Dynamic Island Mic OSD |
| `XF86AudioPlay` / `Next` / `Prev` | Media transport (`playerctl`) + show Dynamic Island Media OSD |
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

## Quickshell IPC Commands (`qs ipc call aurora ...` or legacy `qs ipc call island ...`)

```bash
# Drawers, Launcher, Lock, Power, Switcher, Settings & Files
qs ipc call aurora lockSession
qs ipc call aurora toggleLauncher
qs ipc call aurora toggleWindowSwitcher
qs ipc call aurora togglePowerOverlay
qs ipc call aurora toggleGameMode
qs ipc call aurora toggleClipboard
qs ipc call aurora toggleNotifications
qs ipc call aurora toggleKeybindSheet
qs ipc call aurora toggleThemeTab
qs ipc call aurora toggleDashboard
qs ipc call aurora refreshWeather
qs ipc call aurora syncSddmTheme
qs ipc call aurora collapse
qs ipc call aurora showOsd <volume|mute|brightness|mic|kb|media-play|media-next|media-prev>
qs ipc call aurora syncRecordingState
qs ipc call aurora toggleSettings
qs ipc call aurora openSettings <appearance|themes|shell|windows|audio|displays|network|bluetooth|input|terminals|notifications|apps|shortcuts|privacy|monitor|system>
qs ipc call aurora openDoctor
qs ipc call aurora closeSettings
qs ipc call aurora toggleFiles
qs ipc call aurora openFiles <path>
qs ipc call aurora closeFiles
qs ipc call aurora toggleFilesTab
qs ipc call aurora resetFiles

# Bar UI Styles, Hub Layouts & Visual Modes
qs ipc call aurora setBarUiStyle <apple|split|menubar|classic>
qs ipc call aurora cycleBarUiStyle
qs ipc call aurora setHubUiStyle <cupertino|stage|cockpit|bento>
qs ipc call aurora cycleHubUiStyle
qs ipc call aurora setShellMode <default|blur|neon|minimal|retro|oled|simple>
qs ipc call aurora toggleShellMode <blur|neon|minimal|retro|oled|simple>
qs ipc call aurora cycleShellMode
qs ipc call aurora applyVibe <aurora-glass|minimal-square|oled-stealth|neon-cyber|cozy-paper|full-dock-bar|warm-gruvbox|dracula-notch>
qs ipc call aurora applyPreset <preset-id>
qs ipc call aurora applyAccent "#cba6f7"
qs ipc call aurora randomWallpaper
qs ipc call aurora toggleDarkLight

# System Toggles, Resets & PiP
qs ipc call aurora toggleDnd
qs ipc call aurora toggleKeepAwake
qs ipc call aurora clearClipboard
qs ipc call aurora resetAppearance
qs ipc call aurora resetBar
qs ipc call aurora resetAllSettings
qs ipc call aurora togglePip
qs ipc call aurora cyclePipCorner
qs ipc call aurora snapPip
```
