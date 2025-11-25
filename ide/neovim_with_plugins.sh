#!/usr/bin/env bash
set -euo pipefail

# The name.. Is THE PRIMEAGEN
NVIM_REPO="https://github.com/ThePrimeagen/neovimrc.git"
NVIM_DIR="$HOME/.config/nvim"
BACKUP_DIR="$HOME/.config/nvim_backup_$(date +%Y%m%d_%H%M%S)"
REPO_DIR="$HOME/.config/nvim-primeagen"

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; }

# NeoVim
install_neovim() {
  if command -v nvim >/dev/null 2>&1; then
    info "Neovim already installed: $(nvim --version | head -n1)"
    return
  fi

  info "Installing Neovim via apt..."
  sudo apt update
  sudo apt install -y neovim git curl

  info "Neovim installed: $(nvim --version | head -n1)"
}

# Primeagen neovimrc

clone_config() {
  if [ -d "$REPO_DIR/.git" ]; then
    info "Existing clone found at $REPO_DIR, pulling latest changes..."
    git -C "$REPO_DIR" pull --ff-only
  else
    info "Cloning ThePrimeagen neovimrc into $REPO_DIR..."
    git clone --depth 1 "$NVIM_REPO" "$REPO_DIR"
  fi
}

# for when i break my current config. 

link_config() {
  if [ -e "$NVIM_DIR" ] && [ ! -L "$NVIM_DIR" ]; then
    info "Existing Neovim config detected at $NVIM_DIR, backing up to $BACKUP_DIR"
    mv "$NVIM_DIR" "$BACKUP_DIR"
  elif [ -L "$NVIM_DIR" ]; then
    info "Existing Neovim config symlink at $NVIM_DIR, replacing it"
    rm -f "$NVIM_DIR"
  fi

  mkdir -p "$(dirname "$NVIM_DIR")"

  info "Linking $REPO_DIR to $NVIM_DIR"
  ln -s "$REPO_DIR" "$NVIM_DIR"
}

# plugins 

install_plugins() {
  info "Running neovim headless to trigger plugin installation..."

  nvim --headless "+Lazy! sync" +qa || true
  # verify
  nvim --headless "+Lazy! sync" +qa || true

  info "Plugins installed"
}

# ---------------------------
# Main
# ---------------------------

main() {
  install_neovim
  clone_config
  link_config
  install_plugins

  info "Done!"
  info "Bakcup : $BACKUP_DIR"
}

main "$@"