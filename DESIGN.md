# Aurora Shell Design System

## Design Read
- **Product Surface**: Operate-mode Wayland desktop shell (Dynamic Island top bar + expanded Hub, dedicated Sequoia Menu Bar + top-right Control Center Hub, Aurora App Store for Arch/AUR/Fedora/Flatpak, 19-page Aurora Settings app with System Doctor, `aurora-fm` File Manager, Spotlight Launcher with unit/color/math evaluation, Alerts Center, Window Switcher, Keybind Sheet, Power Overlay, Polkit Prompt, Lock Screen, and Aurora Island SDDM Theme).
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
3. **Inner Items & Interactive Controls (`Theme.subCardBg` + `Theme.activeControlBorderWidth`)**: Buttons, toggle tiles, option chips, selection cards, list rows, and bar badges default to `0px` borders (`Theme.activeControlBorderWidth`) in Default/Blur/Minimal/OLED/Simple modes, relying on elevated tonal fills (`Theme.tileActiveBg`, `Theme.rowSelectedBg`), crisp solid ink flips (`Theme.primary` + `Theme.fgPrimary`), filled icon medallions, and 3px left accent bars rather than colored wireframe outlines. Reserve `1px` focus rings for text inputs and subtle `Theme.hairlineBorder` dividers (`1px`) for section separators and swatch hairlines; explicit control borders appear only when the user enables `highContrast`, `accent`/`glow` borders, or `Tactile (retro)`.

## Monochrome-First Bar & Adaptive Hub Sizing
- **Monochrome-First Top Bar**: Idle metrics, workspace numbers, layout badges, Focus/Keep Awake icons, and utility buttons stay calm monochrome (`Theme.fgSurface` / `Theme.fgSurfaceVariant`) on transparent or subtle neutral surfaces without idle green dots or multi-color borders. Reserve semantic accent colors strictly for active recording (`Theme.error`), critical thresholds (`>85%` CPU/RAM or low battery), and live charging states.
- **Content-Fitted Adaptive Hub Layouts**: The expanded Hub adapts its height dynamically per `hubUiStyle` and hardware capabilities (`DeviceCaps`) instead of forcing tall fixed voids; avoid `Layout.fillHeight: true` spacer gaps inside dashboard cards.
- **Dedicated Sequoia vs. Dynamic Island Surfaces**: Keep `barUiStyle === "menubar"` strictly separated into `SequoiaBar.qml` (stationary top bar) and `SequoiaHub.qml` (on-demand top-right Control Center popover, Notification Center, centered Spotlight, and passive top-right Toast / center OSD) so opening popups never shrinks or distorts the top menu bar. Load heavy modal windows and inactive hubs via URL `LazyLoader`s with garbage collection on unload to maintain minimal idle memory.

## Radius Scale (Scaled by `Theme.r()`)
- **Shell / Modal**: `20px`
- **Section Card**: `14px`
- **Control / Input / Row**: `8–10px`
- **Capsule / Pill**: Strictly reserved for compact status chips, toggle switches, and segmented controls.

## Copy & State Discipline
- **Sentence-case headings**: Clear human section titles (`Visual Mode`, `Quick Controls`, `Workspaces`) replace ALL-CAPS tracked labels and parenthetical config paths.
- **No em-dashes or decorative button arrows**: Use concise middots (`·`), hyphens, or colons instead of unicode em-dashes or directional symbols in button text.
- **No redundant status badges**: Hide idle placeholder badges (e.g. when no media player is active) and avoid repeating identical metadata (e.g. app name repeated as summary, or desktop app name repeated as comment).
- **Safe vs. Destructive Separation**: Session-ending and destructive actions (`Log Out`, `Reboot`, `Power Off`, `Empty Trash`, `Factory Reset`) are visually separated and require explicit confirmation.

## Dual-Theme Contrast Policy (WCAG AA)
- Every curated dark and light theme preset (`32` total entries across `16` themes) enforces mathematical WCAG AA contrast ratios before writing `colors.json`, GTK CSS, SDDM config, or terminal themes:
  - Normal text (`onSurface`, `onSurfaceVariant`, `error` on `surface` and `surfaceContainer`): `>= 4.5:1`
  - Primary ink (`onPrimary` on `primary`) and error ink (`onError` on `error`): `>= 4.5:1`
  - Primary accent readability (`primary` on `surface` and `surfaceContainer`): `>= 4.5:1` in light themes, `>= 3.2:1` in dark themes.
