#!/usr/bin/env bash
set -euo pipefail

# Aurora Shell 2.1 (MangoWC + Quickshell) Dotfiles Installer
# Supports Arch Linux, Fedora, and Gentoo (systemd and OpenRC + elogind).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
FONT_DIR="$DATA_DIR/fonts"
BACKUP_DIR="$HOME/.config-backup-aurora-$(date +%Y%m%d_%H%M%S)"

INSTALL_SESSION=0
INSTALL_SDDM=0
INSTALL_POWERD=0
INSTALL_DEPS=0
CHECK_ONLY=0
INTERACTIVE=0
RELOAD_LIVE=0
PROFILE_BAR=""
PROFILE_SURFACE=""
NO_SYSTEM=0
SKIP_BACKUP=0
SKIP_BUILD=0
SKIP_FONTS=0
DRY_RUN=0

DIRS=(mango quickshell matugen foot kitty fastfetch xdg-desktop-portal)

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  --check            Run read-only preflight check (distro, init, Rust & tools) and exit
  --install-deps     Install missing core/optional packages (Arch/CachyOS/Fedora; respects --dry-run/--no-system)
  --profile <style>  Pre-configure bar profile: sequoia | split | island | simple
  --interactive, -i  Run guided setup wizard to choose bar style, visual surface & system hooks
  --reload           Reload live MangoWC config and restart qs -d after installing
  --dry-run          Print planned actions without modifying files, building, or running sudo
  --no-system        Skip root/system installation even if --with-session/--with-sddm/--install-deps is passed
  --skip-build       Skip compiling rust/aurora-fm, rust/aurora-backend, and rust/aurora-powerd
  --skip-fonts       Skip installing bundled fonts into ~/.local/share/fonts
  --with-session     Also install /usr/local/bin/mango-session and
                     /usr/share/wayland-sessions/mango.desktop (requires sudo/root)
  --with-sddm        Also install matching animated SDDM theme (/usr/share/sddm/themes/aurora-island)
                     and configure /etc/sddm.conf.d/99-aurora-shell.conf (requires sudo/root)
  --with-powerd      Also install and start the aurora-powerd system service (requires sudo/root)
  --no-backup        Overwrite existing updated files without creating a timestamped backup
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=1
            shift
            ;;
        --install-deps)
            INSTALL_DEPS=1
            shift
            ;;
        --profile)
            if [[ $# -lt 2 ]]; then
                echo "Missing value for --profile (sequoia|split|island|simple)" >&2
                exit 1
            fi
            PROFILE_BAR="$2"
            shift 2
            ;;
        --interactive|-i)
            INTERACTIVE=1
            shift
            ;;
        --reload)
            RELOAD_LIVE=1
            shift
            ;;
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
        --with-sddm)
            INSTALL_SDDM=1
            shift
            ;;
        --with-powerd)
            INSTALL_POWERD=1
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

detect_distro_family() {
    local os_id="" os_like=""
    if [[ -r /etc/os-release ]]; then
        os_id="$(grep -E '^ID=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d "\"'" | tr '[:upper:]' '[:lower:]')"
        os_like="$(grep -E '^ID_LIKE=' /etc/os-release 2>/dev/null | head -n1 | cut -d= -f2- | tr -d "\"'" | tr '[:upper:]' '[:lower:]')"
    fi
    if [[ "$os_id" == "cachyos" ]] || grep -qs '\[cachyos' /etc/pacman.conf 2>/dev/null; then
        echo "cachyos"
        return 0
    fi
    case " $os_id $os_like " in
        *" gentoo "*|*" funtoo "*)
            echo "gentoo"
            ;;
        *" fedora "*|*" nobara "*|*" ultramarine "*|*" rhel "*|*" centos "*)
            echo "fedora"
            ;;
        *" arch "*|*" endeavouros "*|*" manjaro "*|*" artix "*)
            echo "arch"
            ;;
        *)
            echo "linux"
            ;;
    esac
}

run_interactive_wizard() {
    if [[ ! -t 0 || "$DRY_RUN" -eq 1 || "$CHECK_ONLY" -eq 1 ]]; then
        return 0
    fi
    echo "==> Interactive Aurora Shell Setup Wizard"
    echo "  Select Top Bar Architecture:"
    echo "    1) Dynamic Island (capsule)"
    echo "    2) Split Islands  (3 floating pods + per-pod hubs)"
    echo "    3) Sequoia Bar    (macOS top menu bar + Control Center)"
    echo "    4) Simple Bar     (flat square edge bar)"
    local bar_choice=""
    read -r -p "  Choice [1-4, Enter=keep current]: " bar_choice || true
    case "$bar_choice" in
        1) PROFILE_BAR="island" ;;
        2) PROFILE_BAR="split" ;;
        3) PROFILE_BAR="sequoia" ;;
        4) PROFILE_BAR="simple" ;;
    esac

    if [[ "$PROFILE_BAR" != "simple" ]]; then
        echo "  Select Visual Surface:"
        echo "    1) Default (balanced opacity)"
        echo "    2) Blur    (frosted glass + glow)"
        echo "    3) OLED    (deep pitch black)"
        local surf_choice=""
        read -r -p "  Choice [1-3, Enter=keep current]: " surf_choice || true
        case "$surf_choice" in
            1) PROFILE_SURFACE="default" ;;
            2) PROFILE_SURFACE="blur" ;;
            3) PROFILE_SURFACE="oled" ;;
        esac
    fi

    if [[ "$NO_SYSTEM" -eq 0 ]]; then
        local ans=""
        read -r -p "  Install Wayland session entry (/usr/share/wayland-sessions)? [y/N]: " ans || true
        [[ "$ans" =~ ^[Yy]$ ]] && INSTALL_SESSION=1
        read -r -p "  Install matching aurora-island SDDM login theme? [y/N]: " ans || true
        [[ "$ans" =~ ^[Yy]$ ]] && INSTALL_SDDM=1
        read -r -p "  Install aurora-powerd hardware power daemon? [y/N]: " ans || true
        [[ "$ans" =~ ^[Yy]$ ]] && INSTALL_POWERD=1
    fi
}

install_system_deps() {
    if [[ "$INSTALL_DEPS" -eq 0 ]]; then
        return 0
    fi
    if [[ "$NO_SYSTEM" -eq 1 ]]; then
        echo "==> Skipping system package installation (--no-system)"
        return 0
    fi

    local distro priv=()
    distro="$(detect_distro_family)"
    if [[ "$EUID" -ne 0 ]]; then
        priv=(sudo)
    fi

    case "$distro" in
        cachyos|arch)
            echo "==> Installing Aurora dependencies for $distro (pacman)"
            local arch_pkgs=(
                python foot kitty curl wlr-randr grim slurp wl-clipboard
                brightnessctl libnotify pipewire wireplumber pipewire-pulse
                playerctl xdg-desktop-portal xdg-desktop-portal-wlr
                xdg-desktop-portal-gtk gnome-keyring rust
                qt6-svg qt6-imageformats qt6-5compat matugen
            )
            run_cmd "${priv[@]}" pacman -S --needed --noconfirm "${arch_pkgs[@]}" || true
            local aur_helper=""
            if command -v paru >/dev/null 2>&1; then
                aur_helper="paru"
            elif command -v yay >/dev/null 2>&1; then
                aur_helper="yay"
            fi
            if [[ -n "$aur_helper" ]]; then
                run_cmd "$aur_helper" -S --needed --noconfirm mangowm quickshell awww-git || true
            else
                echo "NOTE: Install AUR packages manually or setup paru in Aurora Store: mangowm quickshell awww-git"
            fi
            ;;
        fedora)
            local dnf_bin="dnf"
            if command -v dnf5 >/dev/null 2>&1; then
                dnf_bin="dnf5"
            fi
            echo "==> Installing Aurora dependencies for Fedora ($dnf_bin)"
            local fed_pkgs=(
                python3 foot kitty curl wlr-randr grim slurp wl-clipboard
                brightnessctl libnotify pipewire wireplumber pipewire-utils
                playerctl xdg-desktop-portal xdg-desktop-portal-wlr
                xdg-desktop-portal-gtk gnome-keyring cargo rust
                qt6-qtsvg qt6-qtimageformats qt6-qt5compat
            )
            run_cmd "${priv[@]}" "$dnf_bin" install -y "${fed_pkgs[@]}" || true
            ;;
        gentoo)
            echo "==> Gentoo detected: review README.md for Portage emerge atoms."
            ;;
        *)
            echo "==> Automatic dependency install is not supported for this distro ($distro)."
            ;;
    esac
}

check_dependencies() {
    local missing_required=()
    local missing_optional=()
    local present_tools=()
    local cmd

    if ! command -v python3 >/dev/null 2>&1; then
        missing_required+=("python3")
    else
        present_tools+=("python3")
    fi

    for cmd in mango qs matugen wlr-randr grim slurp wl-copy pactl fc-cache; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_optional+=("$cmd")
        else
            present_tools+=("$cmd")
        fi
    done

    if ! command -v awww >/dev/null 2>&1 && ! command -v swww >/dev/null 2>&1; then
        missing_optional+=("awww (or swww)")
    else
        present_tools+=("wallpaper-daemon")
    fi

    local distro
    distro="$(detect_distro_family)"
    if [[ "$CHECK_ONLY" -eq 1 ]]; then
        echo "==> Aurora Shell Setup Preflight Check"
        echo "  Distro family : $distro"
        if [[ -d /run/systemd/system ]]; then
            echo "  Init system   : systemd"
        elif command -v rc-status >/dev/null 2>&1 || [[ -d /run/openrc ]]; then
            echo "  Init system   : OpenRC"
        else
            echo "  Init system   : other"
        fi
        if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
            echo "  Rust toolchain: $(rustc --version 2>/dev/null || echo present)"
        else
            echo "  Rust toolchain: missing (install cargo/rustc to build backends)"
        fi
        echo "  Found tools   : ${present_tools[*]:-none}"
        echo "  Missing opt   : ${missing_optional[*]:-none}"
        if [[ "${#missing_required[@]}" -gt 0 ]]; then
            echo "  Missing req   : ${missing_required[*]}" >&2
            return 1
        fi
        echo "  Preflight OK."
        return 0
    fi

    if [[ "$SKIP_BUILD" -eq 0 && ( -f "$SCRIPT_DIR/rust/aurora-fm/Cargo.toml" || -f "$SCRIPT_DIR/rust/aurora-backend/Cargo.toml" || -f "$SCRIPT_DIR/rust/aurora-powerd/Cargo.toml" ) ]]; then
        if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
            echo "NOTE: Rust toolchain ('cargo'/'rustc') not found; aurora-fm/aurora-backend/aurora-powerd build will be skipped." >&2
            echo "      Arch/CachyOS: 'sudo pacman -S rust' | Fedora: 'sudo dnf install cargo rust' | Gentoo: 'sudo emerge dev-lang/rust'" >&2
        fi
    fi

    if [[ "${#missing_optional[@]}" -gt 0 ]]; then
        echo "NOTE: Missing optional/runtime tools: ${missing_optional[*]}" >&2
        echo "      Run './install.sh --install-deps' or see README.md for package instructions." >&2
    fi

    if [[ ( "$INSTALL_SESSION" -eq 1 || "$INSTALL_SDDM" -eq 1 || "$INSTALL_POWERD" -eq 1 || "$INSTALL_DEPS" -eq 1 ) && "$NO_SYSTEM" -eq 0 && "$EUID" -ne 0 ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            missing_required+=("sudo (required for system actions when not root; pass --no-system to skip)")
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

atomic_copy_file() {
    local src="$1"
    local dst="$2"
    local dst_dir
    dst_dir="$(dirname "$dst")"
    mkdir -p "$dst_dir"
    if [[ -f "$dst" && ! -L "$dst" ]] && command -v cmp >/dev/null 2>&1 && cmp -s "$src" "$dst"; then
        return 1
    fi
    local tmp="${dst}.tmp.$$"
    cp -a "$src" "$tmp"
    mv -f "$tmp" "$dst"
    return 0
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
            elif [[ -L "$src" ]]; then
                dst_dir="$(dirname "$dst")"
                mkdir -p "$dst_dir"
                cp -a "$src" "$dst"
            else
                atomic_copy_file "$src" "$dst" || true
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

    local ff_variant="config-arch.jsonc"
    case "$(detect_distro_family)" in
        cachyos)
            ff_variant="config-cachyos.jsonc"
            ;;
        gentoo)
            ff_variant="config-gentoo.jsonc"
            ;;
        fedora)
            ff_variant="config-fedora.jsonc"
            ;;
        arch|*)
            ff_variant="config-arch.jsonc"
            ;;
    esac
    if [[ -e "$CONFIG_DIR/fastfetch/config.jsonc" ]]; then
        echo "  [keep] $CONFIG_DIR/fastfetch/config.jsonc"
    elif [[ -f "$SCRIPT_DIR/config/fastfetch/$ff_variant" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "  [dry-run] select fastfetch/$ff_variant -> $CONFIG_DIR/fastfetch/config.jsonc"
        else
            atomic_copy_file "$SCRIPT_DIR/config/fastfetch/$ff_variant" "$CONFIG_DIR/fastfetch/config.jsonc" || true
            echo "==> Selected fastfetch preset: $ff_variant -> $CONFIG_DIR/fastfetch/config.jsonc"
        fi
    fi

    if [[ "$DRY_RUN" -eq 0 ]] && [[ -d "$SCRIPT_DIR/.git" || -f "$SCRIPT_DIR/install.sh" ]]; then
        python3 - "$SCRIPT_DIR" "$CONFIG_DIR/quickshell/repo-source.json" <<'PY' || true
import datetime, json, os, subprocess, sys, tempfile

repo_dir, out_path = os.path.abspath(sys.argv[1]), sys.argv[2]

def git_out(args):
    try:
        return subprocess.check_output(["git", "-C", repo_dir, *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

remote_url = git_out(["remote", "get-url", "origin"]) or "https://github.com/AIharthi/mango-quickshell-dots.git"
branch = git_out(["rev-parse", "--abbrev-ref", "HEAD"])
if not branch or branch == "HEAD":
    branch = "main"
commit = git_out(["rev-parse", "--short=7", "HEAD"])
installed_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

payload = {
    "repoPath": repo_dir,
    "remoteUrl": remote_url,
    "branch": branch,
    "installedCommit": commit,
    "installedAt": installed_at,
}
parent = os.path.dirname(out_path)
os.makedirs(parent, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=parent, prefix=".tmp_repo_", text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, out_path)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
    fi
}

build_rust_backends() {
    if [[ "$SKIP_BUILD" -eq 1 ]]; then
        echo "==> Skipping Rust backend builds (--skip-build)"
        return 0
    fi
    if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
        echo "==> Skipping Rust backend builds ('cargo'/'rustc' unavailable)"
        return 0
    fi

    echo "==> Building zero-dependency Rust backends (aurora-fm, aurora-backend, aurora-powerd)"
    local crate
    for crate in aurora-fm aurora-backend aurora-powerd; do
        if [[ ! -f "$SCRIPT_DIR/rust/$crate/Cargo.toml" ]]; then
            continue
        fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "  [dry-run] cargo build --release --manifest-path $SCRIPT_DIR/rust/$crate/Cargo.toml"
            echo "  [dry-run] install -Dm755 $SCRIPT_DIR/rust/$crate/target/release/$crate $CONFIG_DIR/quickshell/bin/$crate"
        elif cargo build --release --manifest-path "$SCRIPT_DIR/rust/$crate/Cargo.toml"; then
            mkdir -p "$CONFIG_DIR/quickshell/bin"
            install -Dm755 "$SCRIPT_DIR/rust/$crate/target/release/$crate" "$CONFIG_DIR/quickshell/bin/$crate"
            echo "==> Installed $CONFIG_DIR/quickshell/bin/$crate"
        else
            echo "WARNING: Failed to compile rust/$crate; backend unavailable until rebuilt." >&2
        fi
    done

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] ln -sfn aurora-fm $CONFIG_DIR/quickshell/bin/mango-fm"
    elif [[ -x "$CONFIG_DIR/quickshell/bin/aurora-fm" ]]; then
        ln -sfn aurora-fm "$CONFIG_DIR/quickshell/bin/mango-fm"
    fi
}

install_fonts() {
    if [[ "$SKIP_FONTS" -eq 1 ]]; then
        echo "==> Skipping bundled font installation (--skip-fonts)"
        return 0
    fi

    echo "==> Installing bundled fonts (IBM Plex Sans, IBM Plex Mono, JetBrains Mono & Symbols Nerd Font) to $FONT_DIR"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] install fonts atomically to $FONT_DIR/{IBMPlexSans,IBMPlexMono,JetBrainsMono,SymbolsNerdFont} and refresh fc-cache if changed"
        return 0
    fi

    mkdir -p "$FONT_DIR/IBMPlexSans" "$FONT_DIR/IBMPlexMono" "$FONT_DIR/JetBrainsMono" "$FONT_DIR/SymbolsNerdFont"
    local changed=0
    local fam f dst
    for fam in IBMPlexSans IBMPlexMono JetBrainsMono SymbolsNerdFont; do
        while IFS= read -r -d '' f; do
            dst="$FONT_DIR/$fam/$(basename "$f")"
            if atomic_copy_file "$f" "$dst"; then
                changed=1
            fi
        done < <(find "$SCRIPT_DIR/fonts/$fam" -maxdepth 1 \( -type f -o -type l \) -print0)
    done
    if [[ "$changed" -eq 1 ]] && command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
    fi
}

init_state() {
    echo "==> Initializing visual mode, settings prefs, and default theme (idempotent)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/apply-mode.sh --init --no-reload"
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/manage-settings.sh prefs-get"
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/apply-theme.sh --init --no-wallpaper"
        if [[ -n "$PROFILE_BAR" ]]; then
            echo "  [dry-run] apply bar profile '$PROFILE_BAR' via manage-settings.sh / apply-mode.sh"
        fi
        if [[ -n "$PROFILE_SURFACE" ]]; then
            echo "  [dry-run] apply visual surface '$PROFILE_SURFACE' via apply-mode.sh"
        fi
        return 0
    fi

    "$CONFIG_DIR/quickshell/scripts/apply-mode.sh" --init --no-reload || true
    "$CONFIG_DIR/quickshell/scripts/manage-settings.sh" prefs-get >/dev/null || true
    "$CONFIG_DIR/quickshell/scripts/apply-theme.sh" --init --no-wallpaper || true

    case "$PROFILE_BAR" in
        "")
            ;;
        sequoia)
            "$CONFIG_DIR/quickshell/scripts/manage-settings.sh" prefs-set barUiStyle menubar >/dev/null || true
            ;;
        split)
            "$CONFIG_DIR/quickshell/scripts/manage-settings.sh" prefs-set barUiStyle split >/dev/null || true
            ;;
        island)
            "$CONFIG_DIR/quickshell/scripts/manage-settings.sh" prefs-set barUiStyle apple >/dev/null || true
            ;;
        simple)
            "$CONFIG_DIR/quickshell/scripts/apply-mode.sh" simple --no-reload || true
            ;;
        *)
            echo "WARNING: Unknown --profile '$PROFILE_BAR' (expected sequoia|split|island|simple)" >&2
            ;;
    esac

    if [[ -n "$PROFILE_SURFACE" && "$PROFILE_BAR" != "simple" ]]; then
        "$CONFIG_DIR/quickshell/scripts/apply-mode.sh" "$PROFILE_SURFACE" --no-reload || true
    fi
}

reload_live_session() {
    if [[ "$RELOAD_LIVE" -eq 0 ]]; then
        return 0
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] reload MangoWC (mmsg dispatch reload_config) and restart qs -d"
        return 0
    fi
    if ! command -v mmsg >/dev/null 2>&1 || [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        echo "==> Live session reload skipped (no active Wayland/MangoWC display)"
        return 0
    fi

    echo "==> Reloading live MangoWC & Quickshell session"
    mmsg dispatch reload_config >/dev/null 2>&1 || true
    if command -v qs >/dev/null 2>&1; then
        pkill -x qs >/dev/null 2>&1 || true
        pkill -x quickshell >/dev/null 2>&1 || true
        sleep 0.3
        mmsg dispatch spawn,"qs -d" >/dev/null 2>&1 || true
    fi
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

install_system_sddm() {
    if [[ "$INSTALL_SDDM" -eq 0 ]]; then
        return 0
    fi
    if [[ "$NO_SYSTEM" -eq 1 ]]; then
        echo "==> Skipping SDDM theme installation (--no-system)"
        return 0
    fi

    echo "==> Installing animated SDDM theme (/usr/share/sddm/themes/aurora-island)"
    local priv=()
    if [[ "$EUID" -ne 0 ]]; then
        priv=(sudo)
    fi

    local sddm_dst="/usr/share/sddm/themes/aurora-island"
    local sddm_src="$SCRIPT_DIR/system/sddm-theme/aurora-island"
    local target_user="${SUDO_USER:-$USER}"
    local font_pairs=(
        "fonts/IBMPlexSans/IBMPlexSans-Regular.ttf:$sddm_dst/fonts/IBMPlexSans-Regular.ttf"
        "fonts/IBMPlexSans/IBMPlexSans-Medium.ttf:$sddm_dst/fonts/IBMPlexSans-Medium.ttf"
        "fonts/IBMPlexSans/IBMPlexSans-SemiBold.ttf:$sddm_dst/fonts/IBMPlexSans-SemiBold.ttf"
        "fonts/IBMPlexSans/IBMPlexSans-Bold.ttf:$sddm_dst/fonts/IBMPlexSans-Bold.ttf"
        "fonts/IBMPlexMono/IBMPlexMono-Bold.ttf:$sddm_dst/fonts/IBMPlexMono-Bold.ttf"
        "fonts/JetBrainsMono/JetBrainsMono-Regular.ttf:$sddm_dst/fonts/JetBrainsMono-Regular.ttf"
        "fonts/JetBrainsMono/JetBrainsMono-Bold.ttf:$sddm_dst/fonts/JetBrainsMono-Bold.ttf"
        "fonts/SymbolsNerdFont/SymbolsNerdFont-Regular.ttf:$sddm_dst/fonts/SymbolsNerdFont-Regular.ttf"
    )
    local pair src_rel dst_font

    run_cmd "${priv[@]}" mkdir -p "$sddm_dst/fonts" /etc/sddm.conf.d
    run_cmd "${priv[@]}" install -Dm644 "$sddm_src/metadata.desktop" "$sddm_dst/metadata.desktop"
    run_cmd "${priv[@]}" install -Dm644 "$sddm_src/Main.qml" "$sddm_dst/Main.qml"
    run_cmd "${priv[@]}" install -Dm644 "$sddm_src/theme.conf" "$sddm_dst/theme.conf"
    for pair in "${font_pairs[@]}"; do
        src_rel="${pair%%:*}"
        dst_font="${pair#*:}"
        if [[ -f "$dst_font" ]] && command -v cmp >/dev/null 2>&1 && cmp -s "$SCRIPT_DIR/$src_rel" "$dst_font"; then
            continue
        fi
        run_cmd "${priv[@]}" install -Dm644 "$SCRIPT_DIR/$src_rel" "${dst_font}.tmp.$$"
        run_cmd "${priv[@]}" mv -f "${dst_font}.tmp.$$" "$dst_font"
    done
    run_cmd "${priv[@]}" touch "$sddm_dst/background.img"
    run_cmd "${priv[@]}" chmod 644 "$sddm_dst/theme.conf" "$sddm_dst/background.img"
    run_cmd "${priv[@]}" chown "$target_user" "$sddm_dst/theme.conf" "$sddm_dst/background.img"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] write /etc/sddm.conf.d/99-aurora-shell.conf ([Theme] Current=aurora-island)"
        echo "  [dry-run] rm -f /etc/sddm.conf.d/99-mango-island.conf"
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/sync-sddm-theme.sh"
    else
        printf '[Theme]\nCurrent=aurora-island\n' | "${priv[@]}" tee /etc/sddm.conf.d/99-aurora-shell.conf >/dev/null
        "${priv[@]}" chmod 644 /etc/sddm.conf.d/99-aurora-shell.conf
        if [[ -e /etc/sddm.conf.d/99-mango-island.conf ]]; then
            "${priv[@]}" rm -f /etc/sddm.conf.d/99-mango-island.conf
        fi
        if [[ -x "$CONFIG_DIR/quickshell/scripts/sync-sddm-theme.sh" ]]; then
            "$CONFIG_DIR/quickshell/scripts/sync-sddm-theme.sh" || true
        fi
    fi
}

install_system_powerd() {
    if [[ "$INSTALL_POWERD" -eq 0 ]]; then
        return 0
    fi
    if [[ "$NO_SYSTEM" -eq 1 ]]; then
        echo "==> Skipping aurora-powerd service installation (--no-system)"
        return 0
    fi
    if [[ ! -x "$CONFIG_DIR/quickshell/bin/aurora-powerd" ]]; then
        echo "WARNING: aurora-powerd binary unavailable; skipping service installation." >&2
        return 0
    fi

    echo "==> Installing and starting aurora-powerd system service"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] $CONFIG_DIR/quickshell/scripts/manage-powerd.sh install-service"
        return 0
    fi
    if [[ -x "$CONFIG_DIR/quickshell/scripts/manage-powerd.sh" ]]; then
        "$CONFIG_DIR/quickshell/scripts/manage-powerd.sh" install-service >/dev/null || true
    fi
}

check_dependencies
if [[ "$CHECK_ONLY" -eq 1 ]]; then
    exit 0
fi
if [[ "$INTERACTIVE" -eq 1 ]]; then
    run_interactive_wizard
fi
install_system_deps
create_backups
install_configs
build_rust_backends
install_fonts
init_state
install_system_session
install_system_sddm
install_system_powerd
reload_live_session

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run complete. No files were modified."
else
    echo "Done! Welcome to Aurora Shell 2.1. Next steps:"
    echo "  1. Drop wallpapers into $HOME/Pictures/Wallpapers/ for the Theme Switcher & Matugen."
    echo "  2. Press Super+S for Aurora Settings (Split Islands, Sequoia Bar, App Store, CachyOS/Fedora Debloater & Doctor)."
    echo "  3. Press Super+Shift+B to cycle Bar Styles, Super+Alt+S for App Store, Super+Alt+D for Debloater."
    echo "  4. Press Super+Shift+E to open aurora-fm (Dynamic File Manager) or Super+Alt+E for Quick Files."
    echo "  5. Per-device overrides live in $CONFIG_DIR/mango/local.conf and preferences in $CONFIG_DIR/quickshell/shell-prefs.json."
    echo "  6. Log in to Aurora Shell (MangoWC), or press Super+R / run 'mmsg dispatch reload_config' if already running."
fi
