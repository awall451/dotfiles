#!/usr/bin/env bash
# Symlink tracked dotfiles into $HOME. Idempotent. Backs up existing
# non-symlink files to <dst>.backup-<timestamp> before replacing.
#
# Usage: ./install.sh [--dry-run]
#
# Per-machine overrides go in:
#   ~/.bashrc.local         (work aliases, project sources)
#   ~/.gitconfig.local      (work email/signing keys)
#   ~/.config/wezterm/local.lua  (per-machine wezterm tweaks)
# These files are NOT tracked by this repo.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  echo "(dry-run mode — no changes will be made)"
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + $*"
  else
    "$@"
  fi
}

link() {
  local src="$REPO_DIR/$1"
  local dst="$HOME/$2"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  if [[ ! -e "$src" ]]; then
    echo "skip:  $1 (source missing)"
    return
  fi

  run mkdir -p "$dst_dir"

  # If destination exists and is not the symlink we want, back it up.
  if [[ -e "$dst" || -L "$dst" ]]; then
    local current
    current="$(readlink -f "$dst" 2>/dev/null || true)"
    if [[ "$current" == "$src" ]]; then
      echo "ok:    $dst -> $src"
      return
    fi
    if [[ ! -L "$dst" ]]; then
      echo "backup: $dst -> $dst.backup-$TIMESTAMP"
      run mv "$dst" "$dst.backup-$TIMESTAMP"
    fi
  fi

  run ln -sfn "$src" "$dst"
  echo "link:  $dst -> $src"
}

# --- mappings: <repo path>  <home-relative path>
link lunarvim/config.lua          .config/lvim/config.lua
link wezterm/wezterm.lua          .config/wezterm/wezterm.lua

link shell/bashrc                 .bashrc
link shell/starship.toml          .config/starship.toml

link git/gitconfig                .gitconfig
link git/gitignore_global         .config/git/ignore

link cli/ripgreprc                .config/ripgrep/ripgreprc
link cli/bat-config               .config/bat/config
link cli/fzf.bash                 .config/fzf/fzf.bash

link lazygit/config.yml           .config/lazygit/config.yml
link gh/config.yml                .config/gh/config.yml

echo
echo "Done."
if [[ $DRY_RUN -eq 0 ]]; then
  echo "If existing files were backed up, the new repo versions live in"
  echo "this dotfiles repo. Move any work/machine-specific bits from the"
  echo "*.backup-$TIMESTAMP files into ~/.bashrc.local or ~/.gitconfig.local."
fi
