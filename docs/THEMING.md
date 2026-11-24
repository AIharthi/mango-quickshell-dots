# Theming, Visual Modes & Matugen Pipeline

The shell synchronizes color palettes and surface styling across **Quickshell**, **MangoWC** (`theme.conf` / `mode.conf`), **GTK 3 & GTK 4**, **Foot**, and **Kitty** using serialized atomic updates (`flock` / `fcntl.flock`) so concurrent triggers never corrupt generated configs.

---

## 1. Three Visual Modes (`apply-mode.sh`)

Switch modes live from **Settings → Appearance**, the shell switcher, or CLI:

| Mode | Bar / Island | Window Geometry | Compositor Effects (`scenefx`) |
| --- | --- | --- | --- |
| `default` | Floating Dynamic Island (`pill` / `notch` / `bar`) | Rounded corners & gaps | Soft shadows, smooth animations, opaque windows |
| `simple` | Crisp `28px` edge-to-edge top bar (`SimpleBar`) | Square (`0px` radius, zero gaps) | Blur, shadows & animations disabled; crisp `2px` focus borders |
| `blur` | Frosted translucent Dynamic Island (`pill` / `notch` / `bar`) | Rounded corners & gaps | Blurred translucent windows, subtle border sheen & optional unfocused dim |

```bash
qs ipc call island setShellMode default
qs ipc call island setShellMode simple
qs ipc call island setShellMode blur
```

Or via script:

```bash
~/.config/quickshell/scripts/apply-mode.sh <default|simple|blur|--init> [--no-reload]
```

---

## 2. Eight One-Click Aesthetic Vibes

Vibes configure **Visual Mode**, **Surface Finish**, **Island Shape**, **Border Style**, **Opacity**, **Preset Palette**, and optional **Colored Window Shadows** in one step:

| Vibe ID | Mode | Preset | Scheme | Surface | Island |
| --- | --- | --- | --- | --- | --- |
| `aurora-glass` | `blur` | `catppuccin-mocha` | Dark | `glass` | `pill` |
| `minimal-square` | `simple` | `nord` | Dark | `flat` | `pill` |
| `oled-stealth` | `default` | `oled-black` | Dark | `oled` | `notch` |
| `neon-cyber` | `blur` | `cyberpunk` | Dark | `tinted` | `pill` (`glow` border + shadow tint) |
| `cozy-paper` | `default` | `rose-pine` | Light | `flat` | `pill` |
| `full-dock-bar` | `blur` | `tokyo-night` | Dark | `glass` | `bar` |
| `warm-gruvbox` | `default` | `gruvbox` | Dark | `default` | `pill` |
| `dracula-notch` | `blur` | `dracula` | Dark | `glass` | `notch` (`accent` border + shadow tint) |

Apply from CLI:

```bash
qs ipc call island applyVibe aurora-glass
~/.config/quickshell/scripts/manage-themes.sh apply-vibe neon-cyber
```

---

## 3. Sixteen Curated Dark & Light Presets

Available in **Themes & Colors**, the **Theme Switcher (`Super + Shift + T`)**, `qs ipc call island applyPreset <id>`, and `apply-theme.sh --preset <id>`:

- `catppuccin-mocha`
- `tokyo-night`
- `gruvbox`
- `nord`
- `rose-pine`
- `dracula`
- `everforest`
- `kanagawa`
- `solarized`
- `one-dark`
- `ayu`
- `oxocarbon`
- `synthwave`
- `oled-black`
- `sakura`
- `cyberpunk`

---

## 4. Dynamic Wallpaper Extraction (Matugen + `awww`/`swww`)

Place `.png`, `.jpg`, `.jpeg`, or `.webp` wallpapers inside `~/Pictures/Wallpapers/`.

- **`awww` / `swww` Auto-Resolution**: `apply-theme.sh`, `manage-themes.sh`, and `autostart.sh` automatically detect `awww` (preferred) or `swww` in `$PATH`, ensure the daemon (`awww-daemon` / `swww-daemon`) is ready by polling `query`, and smoothly transition the wallpaper.
- **First-Run Boot Safety**: If no wallpaper has been picked yet (or on systems without wallpapers / `matugen`), `--init` automatically falls back to your first available wallpaper or the built-in `catppuccin-mocha` preset so the bar always renders cleanly on boot.
- **Seed Accent Color Generator**: Generate a full Material You dark/light palette from any hex color without changing your wallpaper (`qs ipc call island applyAccent "#89b4fa"` or `apply-theme.sh --mode accent --accent "#89b4fa"`).

### `apply-theme.sh` CLI Reference

```bash
~/.config/quickshell/scripts/apply-theme.sh \
  --mode <dynamic|preset|accent|custom> \
  --scheme <dark|light> \
  [--preset <preset-id>] \
  [--accent <#RRGGBB>] \
  [--custom <slug>] \
  [--wallpaper <path>] \
  [--no-wallpaper] \
  [--init]
```

---

## 5. Custom Themes, Validation & Reset Controls

`manage-themes.sh` exposes custom palette management under `~/.config/quickshell/custom-themes/`:

- **Subcommands**: `list-presets`, `render-preset`, `apply-mango-overrides`, `tweak-colors`, `custom-list`, `custom-save`, `custom-apply`, `custom-delete`, `custom-export`, `custom-import`, `wallpaper-colors`, `wallpapers-list`, `solid-wallpaper`, `random-wallpaper`, `apply-vibe`.
- **Import Validation**: `custom-import` enforces a `256 KiB` size cap, validates JSON types, strictly verifies `#RRGGBB` hex colors against an allowlist of palette tokens, sanitizes theme names/slugs, and auto-completes missing derivative Material roles so malformed JSON files cannot break Quickshell or MangoWC.
- **Safe Resets**:
  - `qs ipc call aurora resetAppearance`: resets surface, font, blur & theme appearance settings.
  - `qs ipc call aurora resetBar`: resets bar widgets, layout & shell behavior.
  - `qs ipc call aurora resetAllSettings`: resets shell settings to factory defaults.
