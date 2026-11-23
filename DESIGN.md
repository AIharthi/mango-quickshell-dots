# MangoWC + Quickshell Design System

## Design Read
- **Product Surface**: Operate-mode Wayland desktop shell (Dynamic Island bar, expanded Control Hub, 16-page Settings app, Rust-backed File Manager, Spotlight Launcher, Alerts Center, Window Switcher, Keybind Sheet, Power Overlay, Polkit Prompt, Lock Screen, and SDDM Login Theme).
- **Antislop Dials**: `ENERGY 2 / RHYTHM 2 / MOTION 1`
  - **Energy 2 (Calm & Tactile)**: Restraint over ornament; quiet tonal elevation instead of heavy nested borders; clear focal hierarchy on every surface.
  - **Rhythm 2 (Structured Density)**: Grouped controls with deliberate vertical breathing room, aligned tabular telemetry, and clear primary vs secondary vs destructive separation.
  - **Motion 1 (Functional Motion)**: Crisp 110–170ms `OutCubic` transitions that respond immediately to input and collapse cleanly to `0ms` when `Theme.reducedMotion` or `Simple` mode is active.

## Identity Motif & Dual-Font Typography
- **Interface Sans (`Theme.fontFamily` -> `IBM Plex Sans`)**: Humanist proportions and crisp stroke contrast at 10–15px desktop sizes, chosen intentionally over generic SaaS sans defaults (`Inter`, `Geist`, `Space Grotesk`). Used for headings, body copy, navigation, button labels, notifications, filenames, and descriptions.
- **Technical Mono (`Theme.monoFont` -> `IBM Plex Mono`, matching x-height)**: Strictly reserved for time/clock readouts, tabular telemetry numbers (`%`, `GB`, `°C`, file sizes, timestamps, permissions), hex color codes, keycap badges, terminal configs, and raw path inputs.
- **Icon Font (`Theme.iconFont` -> `Symbols Nerd Font`)**: Single consistent vector glyph family across bar, hub, settings, files, and lock/login surfaces.
- All fonts remain dynamically configurable in **Settings -> Appearance -> Typography**, while keeping proportional UI and monospace terminal/numeric fonts cleanly separated (`JetBrains Mono` remains bundled for terminal/mono preference).

## Surface & Border Hierarchy (Maximum 2 Bordered Levels)
1. **Outer Shell / Modal (`Theme.notchBg` + `Theme.islandBorder`)**: Top-level windows, islands, and overlay dialogs.
2. **Primary Section Card (`Theme.cardBg` + `Theme.cardBorder`)**: Grouped logical modules inside Settings, Hub, and modals.
3. **Inner Items & Controls (`Theme.subCardBg` + `Theme.subBorderWidth`)**: Unselected rows, pills, inputs, and action buttons default to `0px` borders in Default/Blur/Minimal/OLED modes, relying on tonal contrast (`subCardBg` inside `cardBg`) and `1px` `Theme.hairlineBorder` dividers. Explicit borders appear only for selected/active/focused states, `highContrast`, `accent`/`glow` border modes, `Tactile (retro)`, or `Simple`.

## Radius Scale (Scaled by `Theme.r()`)
- **Shell / Modal**: `20px`
- **Section Card**: `14px`
- **Control / Input / Row**: `8–10px`
- **Capsule / Pill**: Strictly reserved for compact status chips, toggle switches, and segmented controls.

## Copy & State Discipline
- **Sentence-case headings**: Clear human section titles (`Visual Mode`, `Quick Controls`, `Workspaces`) replace ALL-CAPS tracked labels and parenthetical config paths.
- **No em-dashes or decorative button arrows**: Use concise middots (`·`) or direct phrasing instead of `—`, `→`, `↗`, or `↵` in button text.
- **No redundant status badges**: Hide idle placeholder badges (e.g. when no media player is active) and avoid repeating identical metadata (e.g. app name repeated as summary, or desktop app name repeated as comment).
- **Safe vs. Destructive Separation**: Session-ending and destructive actions (`Log Out`, `Reboot`, `Power Off`, `Empty Trash`, `Factory Reset`) are visually separated and require explicit confirmation.

## Dual-Theme Contrast Policy (WCAG AA)
- Every curated dark and light theme preset (`32` total entries across `16` themes) enforces mathematical WCAG AA contrast ratios before writing `colors.json`, GTK CSS, SDDM config, or terminal themes:
  - Normal text (`onSurface`, `onSurfaceVariant`, `error` on `surface` and `surfaceContainer`): `>= 4.5:1`
  - Primary ink (`onPrimary` on `primary`) and error ink (`onError` on `error`): `>= 4.5:1`
  - Primary accent readability (`primary` on `surface` and `surfaceContainer`): `>= 4.5:1` in light themes, `>= 3.2:1` in dark themes.
