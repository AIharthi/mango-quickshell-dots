#!/usr/bin/env bash
set -euo pipefail

# MangoWC + Quickshell Dynamic Island Dotfiles Uninstaller

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
FONT_DIR="$DATA_DIR/fonts"

WITH_SESSION=0
RESTORE_BACKUP=0
BACKUP_PATH=""
KEEP_FONTS=0
DRY_RUN=0
ASSUME_YES=0

DIRS=(mango quickshell matugen foot kitty xdg-desktop-portal)

usage() {
    cat <<'EOF'
Usage: ./uninstall.sh [OPTIONS]

Options:
  --dry-run             Print planned removals/restores without modifying files
  --with-session        Also remove /usr/local/bin/mango-session and
                        /usr/share/wayland-sessions/mango.desktop (requires sudo/root)
  --restore-backup      Restore the latest ~/.config-backup-mango-* backup after removal
  --backup <dir>        Restore a specific backup directory (implies --restore-backup)
  --keep-fonts          Do not remove JetBrainsMono / SymbolsNerdFont from ~/.local/share/fonts
  -y, --yes             Skip confirmation prompt
  -h, --help            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --with-session)
            WITH_SESSION=1
            shift
            ;;
        --restore-backup)
            RESTORE_BACKUP=1
            shift
            ;;
        --backup)
            RESTORE_BACKUP=1
            BACKUP_PATH="${2:?Missing directory path for --backup}"
            shift 2
            ;;
        --keep-fonts)
            KEEP_FONTS=1
            shift
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

run_cmd() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '  [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

find_latest_backup() {
    local latest=""
    local candidate
    shopt -s nullglob
    for candidate in "$HOME"/.config-backup-mango-*; do
        [[ -d "$candidate" ]] || continue
        if [[ -z "$latest" || "$candidate" > "$latest" ]]; then
            latest="$candidate"
        fi
    done
    shopt -u nullglob
    printf '%s\n' "$latest"
}

if [[ "$RESTORE_BACKUP" -eq 1 && -z "$BACKUP_PATH" ]]; then
    BACKUP_PATH="$(find_latest_backup)"
    if [[ -z "$BACKUP_PATH" ]]; then
        echo "ERROR: --restore-backup requested, but no $HOME/.config-backup-mango-* directory was found." >&2
        exit 1
    fi
fi

if [[ -n "$BACKUP_PATH" && ! -d "$BACKUP_PATH" ]]; then
    echo "ERROR: Backup directory does not exist: $BACKUP_PATH" >&2
    exit 1
fi

echo "==> Planned uninstall summary:"
for d in "${DIRS[@]}"; do
    if [[ -e "$CONFIG_DIR/$d" ]]; then
        echo "  Remove config: $CONFIG_DIR/$d"
    fi
done
if [[ -f "$CONFIG_DIR/mango/local.conf" ]]; then
    echo "  NOTE: Personal overrides exist at $CONFIG_DIR/mango/local.conf (will be removed with $CONFIG_DIR/mango)."
fi
if [[ "$KEEP_FONTS" -eq 0 ]]; then
    for fd in JetBrainsMono SymbolsNerdFont; do
        if [[ -e "$FONT_DIR/$fd" ]]; then
            echo "  Remove fonts:  $FONT_DIR/$fd"
        fi
    done
fi
if [[ "$WITH_SESSION" -eq 1 ]]; then
    echo "  Remove system: /usr/local/bin/mango-session, /usr/share/wayland-sessions/mango.desktop"
fi
if [[ "$RESTORE_BACKUP" -eq 1 ]]; then
    echo "  Restore from:  $BACKUP_PATH"
fi

if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
    if [[ -t 0 ]]; then
        printf 'Proceed with uninstall? [y/N] '
        IFS= read -r reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    else
        echo "ERROR: Non-interactive shell requires --yes (or use --dry-run to preview)." >&2
        exit 1
    fi
fi

echo "==> Removing dotfiles from $CONFIG_DIR"
for d in "${DIRS[@]}"; do
    if [[ -e "$CONFIG_DIR/$d" || -L "$CONFIG_DIR/$d" ]]; then
        run_cmd rm -rf "$CONFIG_DIR/$d"
    fi
done

if [[ "$KEEP_FONTS" -eq 0 ]]; then
    echo "==> Removing bundled fonts from $FONT_DIR"
    removed_fonts=0
    for fd in JetBrainsMono SymbolsNerdFont; do
        if [[ -e "$FONT_DIR/$fd" || -L "$FONT_DIR/$fd" ]]; then
            run_cmd rm -rf "$FONT_DIR/$fd"
            removed_fonts=1
        fi
    done
    if [[ "$removed_fonts" -eq 1 ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "  [dry-run] fc-cache -f $FONT_DIR"
        elif command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
        fi
    fi
fi

if [[ "$WITH_SESSION" -eq 1 ]]; then
    echo "==> Removing Wayland session files"
    priv=()
    if [[ "$EUID" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo "ERROR: 'sudo' is required to remove /usr files when not running as root." >&2
            exit 1
        fi
        priv=(sudo)
    fi
    for sys_file in /usr/local/bin/mango-session /usr/share/wayland-sessions/mango.desktop; do
        if [[ -e "$sys_file" || -L "$sys_file" ]]; then
            run_cmd "${priv[@]}" rm -f "$sys_file"
        fi
    done
fi

if [[ "$RESTORE_BACKUP" -eq 1 ]]; then
    echo "==> Restoring backup from $BACKUP_PATH"
    for d in "${DIRS[@]}"; do
        if [[ -e "$BACKUP_PATH/$d" ]]; then
            run_cmd mkdir -p "$CONFIG_DIR"
            run_cmd cp -a "$BACKUP_PATH/$d" "$CONFIG_DIR/$d"
        fi
    done
    if [[ "$WITH_SESSION" -eq 1 && -d "$BACKUP_PATH/system" ]]; then
        priv=()
        if [[ "$EUID" -ne 0 ]]; then
            priv=(sudo)
        fi
        if [[ -f "$BACKUP_PATH/system/mango-session" ]]; then
            run_cmd "${priv[@]}" install -Dm755 "$BACKUP_PATH/system/mango-session" /usr/local/bin/mango-session
        fi
        if [[ -f "$BACKUP_PATH/system/mango.desktop" ]]; then
            run_cmd "${priv[@]}" install -Dm644 "$BACKUP_PATH/system/mango.desktop" /usr/share/wayland-sessions/mango.desktop
        fi
    fi
fi

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run complete. No files were removed or restored."
else
    echo "Uninstall complete."
fi
