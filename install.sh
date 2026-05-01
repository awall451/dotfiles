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

# Append a `source <absolute-path>` block into an existing rc file if not
# already present. Unlike link(), this does NOT replace the user's file —
# their existing content is preserved and the block runs at the end.
# Idempotent via the BEGIN/END markers.
source_into() {
  local src="$REPO_DIR/$1"
  local dst="$HOME/$2"
  local marker="$3"
  local begin="# >>> dotfiles: $marker >>>"
  local end="# <<< dotfiles: $marker <<<"

  if [[ ! -e "$src" ]]; then
    echo "skip:  $1 (source missing)"
    return
  fi

  # Create dst if missing so subsequent shells still work.
  if [[ ! -e "$dst" ]]; then
    run touch "$dst"
  fi

  if grep -qF "$begin" "$dst" 2>/dev/null; then
    echo "ok:    $dst already sources $src"
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + append source block for $src into $dst"
  else
    {
      printf '\n%s\n' "$begin"
      printf '[ -f %q ] && source %q\n' "$src" "$src"
      printf '%s\n' "$end"
    } >> "$dst"
  fi
  echo "source: $dst now sources $src"
}

# --- mappings: <repo path>  <home-relative path>
link lunarvim/config.lua          .config/lvim/config.lua
link wezterm/wezterm.lua          .config/wezterm/wezterm.lua

source_into shell/bashrc          .bashrc                bashrc
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
  echo "Notes:"
  echo "  - bashrc is sourced (not replaced). Your existing ~/.bashrc is untouched;"
  echo "    a 'source $REPO_DIR/shell/bashrc' block was appended."
  echo "  - Other configs are symlinked. If existing files were backed up, the"
  echo "    new repo versions live in this dotfiles repo. Move any work/"
  echo "    machine-specific bits from the *.backup-$TIMESTAMP files into"
  echo "    ~/.bashrc.local or ~/.gitconfig.local."
fi
