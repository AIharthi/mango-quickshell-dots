#!/usr/bin/env bash
set -euo pipefail

# MangoWC + Quickshell Dynamic Island Dotfiles Installer
# Supports Arch Linux, Fedora, and Gentoo (systemd and OpenRC + elogind).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
FONT_DIR="$DATA_DIR/fonts"
BACKUP_DIR="$HOME/.config-backup-mango-$(date +%Y%m%d_%H%M%S)"

INSTALL_SESSION=0
NO_SYSTEM=0
SKIP_BACKUP=0
SKIP_BUILD=0
SKIP_FONTS=0
DRY_RUN=0

DIRS=(mango quickshell matugen foot kitty xdg-desktop-portal)

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  --dry-run        Print planned actions without modifying files, building, or running sudo
  --no-system      Skip root/system installation even if --with-session is passed
  --skip-build     Skip compiling rust/mango-fm
  --skip-fonts     Skip installing bundled fonts into ~/.local/share/fonts
  --with-session   Also install /usr/local/bin/mango-session and
                   /usr/share/wayland-sessions/mango.desktop (requires sudo/root)
  --no-backup      Overwrite existing updated files without creating a timestamped backup
  -h, --help       Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --no-system)
            NO_SYSTEM=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --skip-fonts)
            SKIP_FONTS=1
            shift
            ;;
        --with-session)
            INSTALL_SESSION=1
            shift
            ;;
        --no-backup)
            SKIP_BACKUP=1
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

is_preserved_seed() {
    case "$1" in
        mango/mode.conf|mango/theme.conf|\
        quickshell/colors.json|quickshell/theme-state.json|quickshell/shell-mode.json|\
        quickshell/mode-prefs.json|quickshell/hidden-apps.json|\
        foot/colors.ini|foot/foot.ini|kitty/colors.conf|kitty/kitty.conf)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

check_dependencies() {
    local missing_required=()
    local missing_optional=()
    local cmd

    if ! command -v python3 >/dev/null 2>&1; then
        missing_required+=("python3")
    fi

    for cmd in mango qs matugen wlr-randr grim slurp wl-copy pactl fc-cache; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_optional+=("$cmd")
        fi
    done

    if ! command -v awww >/dev/null 2>&1 && ! command -v swww >/dev/null 2>&1; then
        missing_optional+=("awww (or swww)")
    fi

    if [[ "$SKIP_BUILD" -eq 0 && -f "$SCRIPT_DIR/rust/mango-fm/Cargo.toml" ]]; then
        if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
            echo "NOTE: Rust toolchain ('cargo'/'rustc') not found; mango-fm build will be skipped." >&2
            echo "      Arch: 'sudo pacman -S rust' | Fedora: 'sudo dnf install cargo rust' | Gentoo: 'sudo emerge dev-lang/rust'" >&2
        fi
    fi

    if [[ "${#missing_optional[@]}" -gt 0 ]]; then
        echo "NOTE: Missing optional/runtime tools: ${missing_optional[*]}" >&2
        echo "      See README.md for Arch, Fedora, and Gentoo package instructions." >&2
    fi

    if [[ "$INSTALL_SESSION" -eq 1 && "$NO_SYSTEM" -eq 0 && "$EUID" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            missing_required+=("sudo (required for --with-session when not root; pass --no-system to skip)")
        fi
    fi

    if [[ "${#missing_required[@]}" -gt 0 ]]; then
        echo "ERROR: Missing required tools: ${missing_required[*]}" >&2
        if [[ "$DRY_RUN" -eq 0 ]]; then
            exit 1
        fi
    fi
}

create_backups() {
    if [[ "$SKIP_BACKUP" -eq 1 ]]; then
        return 0
    fi

    local backed_up=0
    local d sys_file
    for d in "${DIRS[@]}"; do
        if [[ -e "$CONFIG_DIR/$d" ]]; then
            if [[ "$backed_up" -eq 0 ]]; then
                echo "==> Backing up existing configs to $BACKUP_DIR"
                run_cmd mkdir -p "$BACKUP_DIR"
                backed_up=1
            fi
            run_cmd cp -a "$CONFIG_DIR/$d" "$BACKUP_DIR/$d"
        fi
    done

    if [[ "$INSTALL_SESSION" -eq 1 && "$NO_SYSTEM" -eq 0 ]]; then
        for sys_file in /usr/local/bin/mango-session /usr/share/wayland-sessions/mango.desktop; do
            if [[ -e "$sys_file" ]]; then
                if [[ "$backed_up" -eq 0 ]]; then
                    echo "==> Backing up existing configs to $BACKUP_DIR"
                    run_cmd mkdir -p "$BACKUP_DIR"
                    backed_up=1
                fi
                run_cmd mkdir -p "$BACKUP_DIR/system"
                run_cmd cp -a "$sys_file" "$BACKUP_DIR/system/"
            fi
        done
    fi
}

install_configs() {
    echo "==> Installing dotfiles to $CONFIG_DIR (preserving user state & local.conf)"
    run_cmd mkdir -p "$CONFIG_DIR" "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots" "$HOME/Videos/Recordings"

    local d rel src dst dst_dir
    for d in "${DIRS[@]}"; do
        run_cmd mkdir -p "$CONFIG_DIR/$d"
        while IFS= read -r -d '' rel; do
            src="$SCRIPT_DIR/config/$rel"
            dst="$CONFIG_DIR/$rel"
            if is_preserved_seed "$rel" && [[ -e "$dst" ]]; then
                echo "  [keep] $dst"
                continue
            fi
            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "  [dry-run] copy $rel -> $dst"
            else
                dst_dir="$(dirname "$dst")"
                mkdir -p "$dst_dir"
                cp -a "$src" "$dst"
            fi
        done < <(cd "$SCRIPT_DIR/config" && find "$d" \( -type f -o -type l \) -print0)
    done

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] chmod +x $CONFIG_DIR/mango/autostart.sh and $CONFIG_DIR/quickshell/scripts/*.sh"
    else
        chmod +x "$CONFIG_DIR/mango/autostart.sh"
        chmod +x "$CONFIG_DIR/quickshell/scripts/"*.sh
    fi

    if [[ -f "$CONFIG_DIR/mango/local.conf" ]]; then
        echo "==> Preserved per-device overrides: $CONFIG_DIR/mango/local.conf"
    fi
}

build_mango_fm() {
    if [[ "$SKIP_BUILD" -eq 1 ]]; then
        echo "==> Skipping rust/mango-fm build (--skip-build)"
        return 0
    fi
    if [[ ! -f "$SCRIPT_DIR/rust/mango-fm/Cargo.toml" ]]; then
        return 0
    fi
    if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
        echo "==> Skipping mango-fm build ('cargo'/'rustc' unavailable)"
        return 0
    fi

    echo "==> Building zero-dependency Rust file manager backend (mango-fm)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] cargo build --release --manifest-path $SCRIPT_DIR/rust/mango-fm/Cargo.toml"
        echo "  [dry-run] install -Dm755 $SCRIPT_DIR/rust/mango-fm/target/release/mango-fm $CONFIG_DIR/quickshell/bin/mango-fm"
        return 0
    fi

    if cargo build --release --manifest-path "$SCRIPT_DIR/rust/mango-fm/Cargo.toml"; then
        mkdir -p "$CONFIG_DIR/quickshell/bin"
        install -Dm755 "$SCRIPT_DIR/rust/mango-fm/target/release/mango-fm" "$CONFIG_DIR/quickshell/bin/mango-fm"
        echo "==> Installed $CONFIG_DIR/quickshell/bin/mango-fm"
    else
        echo "WARNING: Failed to compile rust/mango-fm; file manager backend unavailable until rebuilt." >&2
    fi
}

install_fonts() {
    if [[ "$SKIP_FONTS" -eq 1 ]]; then
        echo "==> Skipping bundled font installation (--skip-fonts)"
        return 0
    fi

    echo "==> Installing bundled fonts (JetBrains Mono & Symbols Nerd Font) to $FONT_DIR"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] install fonts to $FONT_DIR/{JetBrainsMono,SymbolsNerdFont} and refresh fc-cache"
        return 0
    fi

    mkdir -p "$FONT_DIR/JetBrainsMono" "$FONT_DIR/SymbolsNerdFont"
    cp -a "$SCRIPT_DIR/fonts/JetBrainsMono/." "$FONT_DIR/JetBrainsMono/"
    cp -a "$SCRIPT_DIR/fonts/SymbolsNerdFont/." "$FONT_DIR/SymbolsNerdFont/"
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
}

init_state() {
    echo "==> Initializing visual mode, settings prefs, and default theme (idempotent)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/apply-mode.sh --init --no-reload"
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/manage-settings.sh prefs-get"
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/apply-theme.sh --init --no-wallpaper"
        return 0
    fi

    "$CONFIG_DIR/quickshell/scripts/apply-mode.sh" --init --no-reload || true
    "$CONFIG_DIR/quickshell/scripts/manage-settings.sh" prefs-get >/dev/null || true
    "$CONFIG_DIR/quickshell/scripts/apply-theme.sh" --init --no-wallpaper || true
}

install_system_session() {
    if [[ "$INSTALL_SESSION" -eq 0 ]]; then
        return 0
    fi
    if [[ "$NO_SYSTEM" -eq 1 ]]; then
        echo "==> Skipping Wayland session installation (--no-system)"
        return 0
    fi

    echo "==> Installing Wayland session entry"
    local priv=()
    if [[ "$EUID" -ne 0 ]]; then
        priv=(sudo)
    fi

    run_cmd "${priv[@]}" install -Dm755 "$SCRIPT_DIR/system/mango-session" /usr/local/bin/mango-session
    run_cmd "${priv[@]}" install -Dm644 "$SCRIPT_DIR/system/mango.desktop" /usr/share/wayland-sessions/mango.desktop
}

check_dependencies
create_backups
install_configs
build_mango_fm
install_fonts
init_state
install_system_session

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run complete. No files were modified."
else
    echo "Done! Next steps:"
    echo "  1. Drop wallpapers into $HOME/Pictures/Wallpapers/ for the Theme Switcher & Matugen."
    echo "  2. Press Super+S anytime to open Settings (16 categories)."
    echo "  3. Press Super+Shift+E to open the Rust-backed Dynamic File Manager (or Super+Alt+E for Quick Files)."
    echo "  4. Per-device overrides are stored in $CONFIG_DIR/mango/local.conf and preferences in $CONFIG_DIR/quickshell/shell-prefs.json."
    echo "  5. Log in to MangoWC (or press Super+R / run 'mmsg dispatch reload_config' if already running)."
fi
