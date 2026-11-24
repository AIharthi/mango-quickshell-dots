# Aurora Dynamic File Manager & Pure-Rust Backend (`rust/aurora-fm`)

Aurora Shell 2.1 includes a native Quickshell file manager (**`Super + Shift + E`** standalone window or **`Super + Alt + E`** inside the Dynamic Island **Files** tab) backed by a zero-dependency pure-Rust binary (`aurora-fm`, with a `mango-fm` compatibility symlink).

---

## Architecture & Efficiency

- **Pure Standard Library (`std` only)**: `rust/aurora-fm/Cargo.toml` has zero external crate dependencies (`#![forbid(unsafe_code)]`, tracked `Cargo.lock`), compiling offline into `~/.config/quickshell/bin/aurora-fm`.
- **On-Demand Lifecycle**: Both the standalone File Manager window (`FileManagerWindow.qml`) and its backend process spawn only when opened and unload completely (`Loader` + clean `BrokenPipe` / `quit` shutdown) when closed.
- **Worker-Capped Concurrency & Cryptography**: Streaming FIPS 180-4 SHA-256 checksums (up to 2 GiB) and symlink-loop-guarded iterative folder sizing (`50,000`-entry cap) run off-thread with a hard limit of 8 concurrent background workers and clamped search limits (`1..=2000`).
- **Bounded Image Memory**: Grid thumbnails and previews specify explicit `sourceSize` and `asynchronous: true` so large photos or wallpapers do not spike Qt memory usage.

---

## Workflow Views & Customization Drawer

Switch views on the fly inside the File Manager toolbar or Customize Drawer:

- **List View**: Detailed rows with size, permissions, modified time, and optional zebra striping.
- **Grid View**: Scaled icon & async image thumbnail cards.
- **3-Column Miller View**: Classic `Parent | Current | Child` column navigation with optional inspector preview pane.
- **Dual-Pane Split (`F3`) & Multi-Tab (`Ctrl+T` / `Ctrl+W`)**: Copy/move across panes seamlessly.

### Four One-Click Workflow Presets

| Preset ID | Title | Description |
| --- | --- | --- |
| `finder` | **Finder Columns** | 3-pane Miller columns with preview inspector |
| `minimal` | **Minimal Zen** | Compact OLED monochrome styling |
| `gallery` | **Media Gallery** | Large image thumbnails with frosted glass background |
| `commander` | **Commander** | Dual-pane split view with permissions visibility |

Plus live per-panel customization for **Surface Finish** (`Inherit`, `Glass`, `Solid`, `OLED`, `Tinted`), opacity, accent hex swatch, row density (`compact` / default / `spacious`), header style, and one-click reset (`qs ipc call aurora resetFiles`).

### Desktop & Shell Integrations

- **Direct Shell Actions**: 1-click **Set Wallpaper / Extract Matugen Theme** on images and 1-click **Import as Shell Theme** on `.json` theme files.
- **Inspector Utilities**: 1-click **Compute SHA-256** checksums on files (click digest to copy) and **Calculate Folder Size** on directories directly in the preview pane.
- **Mounted Storage & Bookmarks**: Reads `/proc/mounts` + `df` usage bars and saves custom sidebar bookmarks atomically to `~/.config/quickshell/fm-bookmarks.json`.
- **Async Progress Pill**: Long copy, move, compress, and extract operations stream live progress into the Dynamic Island pill.

---

## Security & Filesystem Hardening

- **Flag-Injection Guards**: CLI invocations of `zip`, `tar`, and `unzip` pass `--` option terminators and reject archive names beginning with `-`, `..`, or control characters.
- **Zip Slip / Tar Slip Protection**: Archive extraction validates every member path against path traversal (`..`, root paths, NUL bytes) and rejects unsafe symlinks/hardlinks; `tar` extraction applies `--no-same-owner --no-same-permissions`.
- **Symlink Loop Protection**: Threaded recursive search tracks canonical `(dev, ino)` pairs to avoid infinite loops and cancels stale searches cleanly when query/directory changes or when the client disconnects (`BrokenPipe`).
- **XDG Trash & Wayland Clipboard**: Implements `.trashinfo` (`DeletionDate`, RFC 3986 path percent-encoding, atomic file creation), cross-filesystem (`EXDEV`) copy+remove move fallback, and percent-encoded `text/uri-list` copying via `wl-copy`.

---

## `aurora-fm` CLI & NDJSON `serve` Reference

### Standalone CLI Subcommands

```text
aurora-fm [serve]
aurora-fm version
aurora-fm list [--hidden] [--desc] [--no-dirs-first] [--sort <name|size|mtime|ext>] [path]
aurora-fm places
aurora-fm preview <path>
aurora-fm checksum <path>
aurora-fm dir-size <path>
aurora-fm search <path> <query> [--hidden] [--max <N>]
aurora-fm trash <path...>
aurora-fm trash-list
aurora-fm trash-restore <trash-name>
aurora-fm trash-empty
aurora-fm open <path>
aurora-fm terminal <path> [terminal-cmd]
aurora-fm copy-text <text...>
```

### Persistent Daemon (`serve` NDJSON Operations)

`ping`, `list`, `dir_stamp`, `places`, `bookmark_add`, `bookmark_remove`, `preview`, `checksum`, `dir_size`, `search`, `mkdir`, `touch`, `rename`, `copy`, `move`, `trash`, `trash_list`, `trash_restore`, `trash_empty`, `delete`, `chmod`, `compress`, `extract`, `copy_uri`, `copy_text`, `open`, `open_with`, `terminal`, `quit`.
