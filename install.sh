#!/usr/bin/env bash
set -euo pipefail

# MangoWC + Quickshell Dynamic Island Dotfiles Installer
# Works on Fedora, Arch Linux, and Gentoo.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR="$HOME/.config-backup-mango-$(date +%Y%m%d_%H%M%S)"

INSTALL_SESSION=0
SKIP_BACKUP=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  --with-session   Also install /usr/local/bin/mango-session and
                   /usr/share/wayland-sessions/mango.desktop (requires sudo)
  --no-backup      Overwrite existing configs without creating a backup
  -h, --help       Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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
            usage
            exit 1
            ;;
    esac
done

DIRS=(mango quickshell matugen foot kitty xdg-desktop-portal)

if [[ "$SKIP_BACKUP" -eq 0 ]]; then
    backed_up=0
    for d in "${DIRS[@]}"; do
        if [[ -e "$CONFIG_DIR/$d" ]]; then
            if [[ "$backed_up" -eq 0 ]]; then
                mkdir -p "$BACKUP_DIR"
                echo "==> Backing up existing configs to $BACKUP_DIR"
                backed_up=1
            fi
            cp -a "$CONFIG_DIR/$d" "$BACKUP_DIR/$d"
        fi
    done
fi

echo "==> Installing dotfiles to $CONFIG_DIR"
mkdir -p "$CONFIG_DIR" "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots"

for d in "${DIRS[@]}"; do
    mkdir -p "$CONFIG_DIR/$d"
    cp -a "$SCRIPT_DIR/config/$d/." "$CONFIG_DIR/$d/"
done

chmod +x "$CONFIG_DIR/mango/autostart.sh"
chmod +x "$CONFIG_DIR/quickshell/scripts/"*.sh

echo "==> Installing bundled fonts (JetBrains Mono & Symbols Nerd Font)"
FONT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
mkdir -p "$FONT_DIR/JetBrainsMono" "$FONT_DIR/SymbolsNerdFont"
cp -a "$SCRIPT_DIR/fonts/JetBrainsMono/." "$FONT_DIR/JetBrainsMono/"
cp -a "$SCRIPT_DIR/fonts/SymbolsNerdFont/." "$FONT_DIR/SymbolsNerdFont/"
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
fi

echo "==> Initializing visual mode and default theme"
"$CONFIG_DIR/quickshell/scripts/apply-mode.sh" default --no-reload || true
"$CONFIG_DIR/quickshell/scripts/apply-theme.sh" --mode preset --preset catppuccin-mocha --scheme dark --no-wallpaper || true

if [[ "$INSTALL_SESSION" -eq 1 ]]; then
    echo "==> Installing Wayland session entry (requires sudo)"
    sudo install -Dm755 "$SCRIPT_DIR/system/mango-session" /usr/local/bin/mango-session
    sudo install -Dm644 "$SCRIPT_DIR/system/mango.desktop" /usr/share/wayland-sessions/mango.desktop
fi

echo ""
echo "Done! Next steps:"
echo "  1. Drop wallpapers into ~/Pictures/Wallpapers/ for the Theme Switcher & Matugen."
echo "  2. Edit ~/.config/mango/config.conf to adjust keyboard layout or app binds (browser/editor)."
echo "  3. Log in to MangoWC (or run 'mmsg dispatch reload_config' if already in MangoWC)."
