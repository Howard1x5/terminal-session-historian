#!/usr/bin/env bash
# Terminal Session Historian - Installation Script
# Sets up directories, config, and optionally the systemd service

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/terminal-historian"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/terminal-historian"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

prompt_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local reply

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    read -rp "$prompt" reply
    reply="${reply:-$default}"

    [[ "$reply" =~ ^[Yy] ]]
}

# ============================================================================
# INSTALLATION STEPS
# ============================================================================

create_directories() {
    info "Creating directories..."

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$DATA_DIR/sessions"
    mkdir -p "$BIN_DIR"

    success "Directories created"
}

install_config() {
    local config_file="$CONFIG_DIR/config"

    if [[ -f "$config_file" ]]; then
        warn "Config file already exists: $config_file"
        if prompt_yn "Overwrite with new config?" "n"; then
            cp "$SCRIPT_DIR/config/historian.conf.example" "$config_file"
            success "Config updated"
        else
            info "Keeping existing config"
        fi
    else
        cp "$SCRIPT_DIR/config/historian.conf.example" "$config_file"
        success "Config installed to $config_file"
    fi
}

install_scripts() {
    info "Installing scripts..."

    # Make scripts executable
    chmod +x "$SCRIPT_DIR/scripts/"*.sh

    # Create symlinks in ~/.local/bin
    ln -sf "$SCRIPT_DIR/scripts/monitor.sh" "$BIN_DIR/terminal-historian-monitor"
    ln -sf "$SCRIPT_DIR/scripts/summarizer.sh" "$BIN_DIR/terminal-historian-summarize"

    success "Scripts installed to $BIN_DIR"

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        warn "$BIN_DIR is not in your PATH"
        echo "  Add this to your shell profile (.bashrc, .zshrc, etc.):"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

install_systemd_service() {
    if [[ ! -d "$HOME/.config/systemd" ]]; then
        warn "systemd user directory not found. Skipping service installation."
        return
    fi

    if ! prompt_yn "Install systemd user service for automatic monitoring?" "y"; then
        info "Skipping systemd service installation"
        return
    fi

    info "Installing systemd service..."

    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$SCRIPT_DIR/config/systemd/terminal-historian.service" "$SYSTEMD_USER_DIR/"

    # Reload systemd
    systemctl --user daemon-reload

    success "Systemd service installed"

    if prompt_yn "Enable and start the service now?" "y"; then
        systemctl --user enable terminal-historian.service
        systemctl --user start terminal-historian.service
        success "Service enabled and started"
        echo ""
        echo "  Check status: systemctl --user status terminal-historian"
        echo "  View logs:    journalctl --user -u terminal-historian -f"
    else
        info "Service installed but not started"
        echo "  To start later:"
        echo "    systemctl --user enable terminal-historian.service"
        echo "    systemctl --user start terminal-historian.service"
    fi
}

detect_shell_history() {
    info "Detecting shell history location..."

    local detected=""
    local locations=(
        "$HOME/.bash_history:bash"
        "$HOME/.zsh_history:zsh"
        "$HOME/.local/share/fish/fish_history:fish"
    )

    for loc in "${locations[@]}"; do
        local path="${loc%%:*}"
        local shell="${loc##*:}"
        if [[ -f "$path" ]]; then
            info "Found $shell history at $path"
            detected="$path"
        fi
    done

    if [[ -n "$detected" ]]; then
        success "Shell history detected"
        echo ""
        echo "  The config file is set to auto-detect, but you can also"
        echo "  explicitly set SHELL_ACTIVITY_SOURCE in:"
        echo "    $CONFIG_DIR/config"
    else
        warn "Could not detect shell history location"
        echo "  Please edit $CONFIG_DIR/config and set SHELL_ACTIVITY_SOURCE"
    fi
}

print_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Installation Complete!${NC}"
    echo "=============================================="
    echo ""
    echo "Installed locations:"
    echo "  Config:   $CONFIG_DIR/config"
    echo "  Data:     $DATA_DIR/"
    echo "  Scripts:  $BIN_DIR/terminal-historian-*"
    echo ""
    echo "Next steps:"
    echo "  1. Edit your config: ${YELLOW}nano $CONFIG_DIR/config${NC}"
    echo "  2. Run manually:     ${YELLOW}terminal-historian-monitor -f${NC}"
    echo "  3. Generate summary: ${YELLOW}terminal-historian-summarize${NC}"
    echo ""
    echo "Your history will be saved to:"
    echo "  $DATA_DIR/raw_history.txt"
    echo ""
    echo "Context summaries will be at:"
    echo "  $DATA_DIR/context_summary.md"
    echo ""
}

# ============================================================================
# UNINSTALL
# ============================================================================

uninstall() {
    warn "This will remove Terminal Session Historian"
    echo "  It will NOT delete your history data in $DATA_DIR"
    echo ""

    if ! prompt_yn "Continue with uninstall?" "n"; then
        info "Uninstall cancelled"
        exit 0
    fi

    info "Stopping service..."
    systemctl --user stop terminal-historian.service 2>/dev/null || true
    systemctl --user disable terminal-historian.service 2>/dev/null || true

    info "Removing files..."
    rm -f "$BIN_DIR/terminal-historian-monitor"
    rm -f "$BIN_DIR/terminal-historian-summarize"
    rm -f "$SYSTEMD_USER_DIR/terminal-historian.service"
    systemctl --user daemon-reload 2>/dev/null || true

    success "Uninstalled"
    echo ""
    echo "Your data remains in: $DATA_DIR"
    echo "Your config remains in: $CONFIG_DIR"
    echo ""
    echo "To fully remove all data:"
    echo "  rm -rf $DATA_DIR"
    echo "  rm -rf $CONFIG_DIR"
}

# ============================================================================
# MAIN
# ============================================================================

show_help() {
    cat << EOF
Terminal Session Historian - Installation Script

Usage: $(basename "$0") [COMMAND]

Commands:
    install     Install Terminal Session Historian (default)
    uninstall   Remove Terminal Session Historian (keeps data)
    help        Show this help message

Examples:
    ./install.sh              # Run interactive installation
    ./install.sh uninstall    # Remove installation
EOF
}

main() {
    local command="${1:-install}"

    case "$command" in
        install)
            echo ""
            echo "=============================================="
            echo "  Terminal Session Historian Installer"
            echo "=============================================="
            echo ""

            create_directories
            install_config
            install_scripts
            detect_shell_history
            install_systemd_service
            print_summary
            ;;
        uninstall)
            uninstall
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command"
            ;;
    esac
}

main "$@"
