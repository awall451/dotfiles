#!/usr/bin/env bash
# Symlink tracked dotfiles into $HOME. Idempotent. Backs up existing
# non-symlink files to <dst>.backup-<timestamp> before replacing.
#
# Usage: ./install.sh [--dry-run] [--no-tools]
#
# Per-machine overrides go in:
#   ~/.bashrc.local         (work aliases, project sources)
#   ~/.gitconfig.local      (work email/signing keys)
#   ~/.config/wezterm/local.lua  (per-machine wezterm tweaks)
#   ~/.claude/settings.json keys not present in claude/settings.json
#                          (preserved by the json deep-merge)
# These files are NOT tracked by this repo.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
SKIP_TOOLS=0
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Make ~/.local/bin discoverable to the script itself so `command -v` finds
# tools installed there (e.g. the bat→batcat shim) on subsequent runs.
export PATH="$HOME/.local/bin:$PATH"

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      echo "(dry-run mode — no changes will be made)"
      ;;
    --no-tools)
      SKIP_TOOLS=1
      ;;
    -h|--help)
      cat <<EOF
Usage: ./install.sh [--dry-run] [--no-tools]
  --dry-run    Preview, no changes
  --no-tools   Skip apt auto-install of coolstuff CLI tools
EOF
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

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

# Deep-merge a tracked JSON file into an existing JSON file at $dst.
# Tracked keys win; any keys present only in $dst are preserved
# (e.g. per-machine hooks, local-only marketplaces). Backs up the
# original to <dst>.backup-<timestamp> on first non-trivial change.
# Idempotent: if the merged result equals the current $dst, no-op.
merge_json() {
  local src="$REPO_DIR/$1"
  local dst="$HOME/$2"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  if [[ ! -e "$src" ]]; then
    echo "skip:  $1 (source missing)"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "skip:  $1 (jq not installed — install jq to merge JSON configs)"
    return
  fi

  run mkdir -p "$dst_dir"

  if [[ ! -e "$dst" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  + cp $src $dst"
    else
      cp "$src" "$dst"
    fi
    echo "merge: $dst (created from $src)"
    return
  fi

  # Compute deep-merged result. jq's `*` operator deep-merges objects;
  # arrays from src replace arrays in dst (acceptable here — settings
  # arrays like statusLine are scalar-ish, not appended lists).
  local merged
  if ! merged="$(jq -s '.[0] * .[1]' "$dst" "$src" 2>/dev/null)"; then
    echo "skip:  $dst (jq merge failed — destination not valid JSON?)"
    return
  fi

  if diff -q <(jq -S . "$dst") <(printf '%s' "$merged" | jq -S .) >/dev/null 2>&1; then
    echo "ok:    $dst already contains tracked keys from $1"
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + backup $dst -> $dst.backup-$TIMESTAMP and write merged result"
  else
    cp "$dst" "$dst.backup-$TIMESTAMP"
    printf '%s\n' "$merged" > "$dst"
  fi
  echo "merge: $dst <- $src (backup: $dst.backup-$TIMESTAMP)"
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

# Bootstrap jq early so the merge_json calls below can deep-merge claude
# settings on a fresh box (without jq the merge silently skips and tracked
# claude keys never land). Debian-gated; non-debian or no apt → caller can
# install jq manually and re-run.
install_bootstrap_jq() {
  if [[ $SKIP_TOOLS -eq 1 ]] || command -v jq >/dev/null 2>&1; then
    return
  fi
  if [[ ! -r /etc/os-release ]]; then
    echo "jq: /etc/os-release missing — install manually so merge_json works"
    return
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *debian*|*ubuntu*) ;;
    *)
      echo "jq: non-debian — install manually so merge_json works"
      return
      ;;
  esac
  echo "jq: apt-installing (sudo) — needed by merge_json"
  run sudo apt-get install -y jq || echo "jq: apt-get install failed"
}
install_bootstrap_jq

# nvim-treesitter compiles parsers from source via `cc`/`gcc`; without a C
# toolchain `:TSInstall markdown markdown_inline` errors with "No C compiler
# found" and render-markdown.nvim can't render. build-essential brings in
# gcc + make + libc-dev. Debian-gated; idempotent (apt-get install is a no-op
# when already present).
install_bootstrap_build_essential() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi
  if command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1; then
    echo "build-essential: C compiler already on PATH"
    return
  fi
  if [[ ! -r /etc/os-release ]]; then
    echo "build-essential: /etc/os-release missing — install a C compiler manually for treesitter parsers"
    return
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *debian*|*ubuntu*) ;;
    *)
      echo "build-essential: non-debian — install gcc/make manually for treesitter parsers"
      return
      ;;
  esac
  echo "build-essential: apt-installing (sudo) — needed by nvim-treesitter parser compilation"
  run sudo apt-get install -y build-essential || echo "build-essential: apt-get install failed"
}
install_bootstrap_build_essential

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

# Claude Code: settings.json is deep-merged (preserves local hooks,
# marketplaces, etc). ccstatusline settings are symlinked so the
# ccstatusline TUI writes edits back into the repo.
merge_json claude/settings.json   .claude/settings.json
link claude/ccstatusline/settings.json  .config/ccstatusline/settings.json

# Add the wezterm Fury apt repo and key. Idempotent. Returns non-zero if
# the key fetch fails (e.g. fury.io 5xx) so the caller can drop wezterm
# from this run instead of aborting the whole installer.
install_wezterm_apt_repo() {
  local key=/usr/share/keyrings/wezterm-fury.gpg
  local list=/etc/apt/sources.list.d/wezterm.list

  if [[ ! -s "$key" ]]; then
    echo "  fetching wezterm fury gpg key"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  + curl https://apt.fury.io/wez/gpg.key | sudo gpg --dearmor -o $key"
    else
      local tmp
      tmp="$(mktemp)"
      if ! curl -fsSL --retry 2 --retry-delay 2 https://apt.fury.io/wez/gpg.key -o "$tmp"; then
        echo "  warn: curl failed fetching wezterm fury key (fury.io down or 5xx) — skipping wezterm this run"
        rm -f "$tmp"
        return 1
      fi
      if ! sudo gpg --yes --dearmor -o "$key" "$tmp" 2>/dev/null; then
        echo "  warn: gpg dearmor failed — fetched body not a valid key"
        rm -f "$tmp"
        sudo rm -f "$key"
        return 1
      fi
      rm -f "$tmp"
    fi
  fi

  if [[ ! -f "$list" ]]; then
    echo "  installing wezterm fury apt source list"
    run sudo bash -c "echo 'deb [signed-by=$key] https://apt.fury.io/wez/ * *' > $list"
  fi
  return 0
}

# Try to apt-install the modern CLI tools used by `coolstuff`. Debian-gated,
# idempotent (fast-paths out if everything is already installed).
install_tools() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi

  # cmd-name -> apt package name (empty = not in default apt, try snap below)
  local -A apt_for=(
    [wezterm]=wezterm
    [zoxide]=zoxide
    [delta]=git-delta
    [btop]=btop
    [procs]=""
    [glow]=""
    [onefetch]=""
    [yazi]=""
    [rg]=ripgrep
    [fzf]=fzf
    [lsd]=lsd
  )

  # cmd-name -> snap install args (the binary name plus any flags like --classic).
  # Snap fallback runs for anything still in the manual list after the apt pass.
  local -A snap_for=(
    [glow]="glow"
    [onefetch]="onefetch"
    [procs]="procs"
    [yazi]="yazi --classic"
  )

  local missing=()
  for cmd in "${!apt_for[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "tools: all coolstuff tools already installed"
    return
  fi

  if [[ ! -r /etc/os-release ]]; then
    echo "tools: /etc/os-release missing — skipping auto-install (missing: ${missing[*]})"
    return
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *debian*|*ubuntu*) ;;
    *)
      echo "tools: non-debian system (${ID:-unknown}) — skipping (missing: ${missing[*]})"
      return
      ;;
  esac

  local apt_pkgs=() manual=()
  for cmd in "${missing[@]}"; do
    local pkg="${apt_for[$cmd]}"
    if [[ -n "$pkg" ]]; then
      apt_pkgs+=("$pkg")
    else
      manual+=("$cmd")
    fi
  done

  if [[ ${#apt_pkgs[@]} -gt 0 ]]; then
    echo "tools: apt-installing: ${apt_pkgs[*]} (sudo)"
    # wezterm isn't in default apt — wire Fury repo first. If the repo
    # setup fails (e.g. fury.io 5xx), drop wezterm from this run.
    local skip_wezterm=0
    for pkg in "${apt_pkgs[@]}"; do
      if [[ "$pkg" == "wezterm" ]]; then
        if ! install_wezterm_apt_repo; then
          skip_wezterm=1
        fi
        break
      fi
    done
    if [[ $skip_wezterm -eq 1 ]]; then
      local pruned=()
      for pkg in "${apt_pkgs[@]}"; do
        [[ "$pkg" == "wezterm" ]] || pruned+=("$pkg")
      done
      apt_pkgs=("${pruned[@]}")
      manual+=("wezterm")
    fi
    # Don't let stale third-party repos / GPG errors abort the install.
    run sudo apt-get update -qq || echo "tools: apt-get update had warnings — continuing"
    # Filter packages actually present in cache so one missing pkg doesn't
    # fail the batch on older Debian/Ubuntu releases.
    local final_pkgs=()
    for pkg in "${apt_pkgs[@]}"; do
      if [[ $DRY_RUN -eq 1 ]] || apt-cache show "$pkg" >/dev/null 2>&1; then
        final_pkgs+=("$pkg")
      else
        echo "  not in apt on this release: $pkg — add to manual list"
        manual+=("$pkg")
      fi
    done
    if [[ ${#final_pkgs[@]} -gt 0 ]]; then
      run sudo apt-get install -y "${final_pkgs[@]}"
    fi
  fi

  # Snap fallback for tools not in apt (glow, onefetch, procs, yazi).
  if [[ ${#manual[@]} -gt 0 ]] && command -v snap >/dev/null 2>&1; then
    local still_manual=()
    for cmd in "${manual[@]}"; do
      local args="${snap_for[$cmd]:-}"
      if [[ -z "$args" ]]; then
        still_manual+=("$cmd")
        continue
      fi
      echo "tools: snap-installing $args (sudo)"
      # Word-splitting on $args is intentional — it may carry flags like --classic.
      # shellcheck disable=SC2086
      if ! run sudo snap install $args; then
        echo "  snap install failed for $cmd — leaving in manual list"
        still_manual+=("$cmd")
      fi
    done
    manual=("${still_manual[@]}")
  fi

  if [[ ${#manual[@]} -gt 0 ]]; then
    echo "tools: install manually:"
    for cmd in "${manual[@]}"; do
      case "$cmd" in
        wezterm)  echo "  wezterm:  apt.fury.io was unreachable — retry ./install.sh later, or grab .deb from https://github.com/wez/wezterm/releases" ;;
        glow)     echo "  glow:     https://github.com/charmbracelet/glow/releases  (or: sudo snap install glow)" ;;
        procs)    echo "  procs:    https://github.com/dalance/procs/releases  (or: sudo snap install procs)" ;;
        onefetch) echo "  onefetch: https://github.com/o2sh/onefetch/releases  (or: sudo snap install onefetch)" ;;
        yazi)     echo "  yazi:     https://github.com/sxyazi/yazi/releases  (or: sudo snap install yazi --classic)" ;;
        rg)       echo "  ripgrep:  https://github.com/BurntSushi/ripgrep/releases" ;;
        fzf)      echo "  fzf:      https://github.com/junegunn/fzf/releases" ;;
        lsd)      echo "  lsd:      https://github.com/lsd-rs/lsd/releases" ;;
        *)        echo "  $cmd: see upstream project" ;;
      esac
    done
  fi
}

install_tools

# Install ccstatusline (the binary that renders the multi-line status bar
# configured in claude/ccstatusline/settings.json). Without it, Claude Code's
# statusLine command resolves to a missing binary and renders blank.
# npm-based — skip cleanly if npm is missing.
install_ccstatusline() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi

  if command -v ccstatusline >/dev/null 2>&1; then
    echo "ccstatusline: already installed"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "ccstatusline: npm not on PATH — install manually:"
    echo "  npm install -g ccstatusline   (after: npm config set prefix ~/.npm-global)"
    return
  fi

  echo "ccstatusline: npm install -g ccstatusline"
  if ! run npm install -g ccstatusline; then
    echo "ccstatusline: npm install failed — try:"
    echo "  npm config set prefix ~/.npm-global && npm install -g ccstatusline"
    echo "  then add ~/.npm-global/bin to PATH"
  fi
}

install_ccstatusline

# Install neovim from the official GitHub release tarball (NOT apt) then
# bootstrap LunarVim. Apt nvim on Ubuntu 24.04 is 0.9.5 which is too old for
# plugins like render-markdown.nvim (requires 0.10+); tarball avoids that.
# Extracted into /opt/nvim-linux64 to match the PATH entry in shell/bashrc.
# LunarVim's installer is interactive by default; --no-install-dependencies
# skips the node/python/rust provider prompts.
install_neovim_lunarvim() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi

  # Required nvim version for render-markdown.nvim and other modern plugins.
  local min_major=0 min_minor=10
  local need_install=0
  if ! command -v nvim >/dev/null 2>&1; then
    need_install=1
  else
    local ver major minor
    ver="$(nvim --version 2>/dev/null | head -1 | grep -Po 'v\K[0-9]+\.[0-9]+' || true)"
    major="${ver%%.*}"
    minor="${ver##*.}"
    if [[ -z "$ver" ]] || (( major < min_major )) || (( major == min_major && minor < min_minor )); then
      echo "neovim: found $ver, need >= ${min_major}.${min_minor} for render-markdown.nvim — reinstalling from tarball"
      need_install=1
    else
      echo "neovim: already installed (v$ver, >= ${min_major}.${min_minor})"
    fi
  fi

  if (( need_install )); then
    if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
      echo "neovim: need curl + tar on PATH — install manually: https://github.com/neovim/neovim/releases"
    else
      local nv_arch nv_asset
      case "$(uname -m)" in
        x86_64)        nv_arch=x86_64 ;;
        aarch64|arm64) nv_arch=arm64 ;;
        *)
          echo "neovim: unknown arch $(uname -m) — install manually: https://github.com/neovim/neovim/releases"
          nv_arch=""
          ;;
      esac
      if [[ -n "$nv_arch" ]]; then
        # Recent releases use nvim-linux-x86_64.tar.gz; older used nvim-linux64.
        # Try the new name first, fall back to the old one.
        local nv_dst=/opt/nvim-linux64
        echo "neovim: downloading stable tarball (linux-$nv_arch) → $nv_dst"
        if [[ $DRY_RUN -eq 1 ]]; then
          echo "  + curl -L .../nvim-linux-${nv_arch}.tar.gz | sudo tar -xz --strip-components=1 -C $nv_dst"
        else
          local tmp
          tmp="$(mktemp)"
          nv_asset="nvim-linux-${nv_arch}.tar.gz"
          if ! curl -fsSL "https://github.com/neovim/neovim/releases/download/stable/${nv_asset}" -o "$tmp"; then
            nv_asset="nvim-linux64.tar.gz"
            if ! curl -fsSL "https://github.com/neovim/neovim/releases/download/stable/${nv_asset}" -o "$tmp"; then
              echo "neovim: download failed (tried both asset names) — install manually"
              rm -f "$tmp"
              nv_arch=""
            fi
          fi
          if [[ -n "$nv_arch" ]]; then
            sudo mkdir -p "$nv_dst"
            if sudo tar -xzf "$tmp" --strip-components=1 -C "$nv_dst"; then
              echo "neovim: extracted to $nv_dst (bin at $nv_dst/bin/nvim)"
              # Make nvim discoverable to the rest of this script run.
              export PATH="$nv_dst/bin:$PATH"
            else
              echo "neovim: tar extract failed"
            fi
          fi
          rm -f "$tmp"
        fi
      fi
    fi
  fi

  if ! command -v nvim >/dev/null 2>&1; then
    echo "lunarvim: skipping — nvim not on PATH"
    return
  fi

  if command -v lvim >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/lvim" ]]; then
    echo "lunarvim: already installed"
    return
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "lunarvim: need curl + git on PATH — install manually: https://www.lunarvim.org/"
    return
  fi

  local lv_branch="release-1.4/neovim-0.9"
  local lv_url="https://raw.githubusercontent.com/LunarVim/LunarVim/${lv_branch}/utils/installer/install.sh"

  echo "lunarvim: bootstrapping (branch=$lv_branch, --no-install-dependencies)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + LV_BRANCH=$lv_branch bash <(curl -s $lv_url) --no-install-dependencies"
    return
  fi

  local lv_installer
  lv_installer="$(mktemp)"
  if ! curl -fsSL "$lv_url" -o "$lv_installer"; then
    echo "lunarvim: curl failed — install manually: https://www.lunarvim.org/docs/installation"
    rm -f "$lv_installer"
    return
  fi
  if ! LV_BRANCH="$lv_branch" bash "$lv_installer" --no-install-dependencies; then
    echo "lunarvim: bootstrap failed — see https://www.lunarvim.org/docs/installation"
  fi
  rm -f "$lv_installer"

  if [[ -x "$HOME/.local/bin/lvim" ]] && ! command -v lvim >/dev/null 2>&1; then
    echo "lunarvim: installed to ~/.local/bin/lvim — ensure ~/.local/bin is on PATH"
  fi
}

install_neovim_lunarvim

# bat: on Ubuntu/Debian the apt `bat` package conflicts with bacula's `bat`,
# so the binary lands as `batcat`. Install via apt then symlink batcat→bat in
# ~/.local/bin (already on PATH per shell/bashrc and our local export above)
# so bashrc's `alias cat='bat --paging=never --style=plain'` resolves.
install_bat() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi
  if command -v bat >/dev/null 2>&1; then
    echo "bat: already installed"
    return
  fi
  if ! command -v batcat >/dev/null 2>&1; then
    if [[ ! -r /etc/os-release ]]; then
      echo "bat: install manually: https://github.com/sharkdp/bat/releases"
      return
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
      *debian*|*ubuntu*)
        echo "bat: apt-installing (sudo) — binary will land as batcat"
        run sudo apt-get install -y bat || { echo "bat: apt-get install failed"; return; }
        ;;
      *)
        echo "bat: non-debian — install manually: https://github.com/sharkdp/bat/releases"
        return
        ;;
    esac
  fi
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    run mkdir -p "$HOME/.local/bin"
    run ln -sfn "$(command -v batcat)" "$HOME/.local/bin/bat"
    echo "bat: symlinked ~/.local/bin/bat -> $(command -v batcat)"
  fi
}

install_bat

# starship: not in default apt. Use the official installer (writes to
# /usr/local/bin via sudo). -y skips interactive confirmation.
install_starship() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi
  if command -v starship >/dev/null 2>&1; then
    echo "starship: already installed"
    return
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "starship: need curl on PATH — install manually: https://starship.rs/"
    return
  fi
  echo "starship: official installer (curl https://starship.rs/install.sh | sh -s -- -y)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + curl -sS https://starship.rs/install.sh | sh -s -- -y"
    return
  fi
  if ! curl -sS https://starship.rs/install.sh | sh -s -- -y; then
    echo "starship: install failed — see https://starship.rs/"
  fi
}

install_starship

# gh (GitHub CLI): not in default apt. Wire the official cli.github.com apt
# source (mirrors GitHub's documented install path) then apt-install.
install_gh() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi
  if command -v gh >/dev/null 2>&1; then
    echo "gh: already installed"
    return
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "gh: need curl on PATH — install manually: https://github.com/cli/cli/releases"
    return
  fi
  if [[ ! -r /etc/os-release ]]; then
    echo "gh: /etc/os-release missing — install manually: https://github.com/cli/cli/releases"
    return
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *debian*|*ubuntu*) ;;
    *)
      echo "gh: non-debian (${ID:-unknown}) — install manually: https://github.com/cli/cli/releases"
      return
      ;;
  esac
  local key=/usr/share/keyrings/githubcli-archive-keyring.gpg
  local list=/etc/apt/sources.list.d/github-cli.list
  if [[ ! -s "$key" ]]; then
    echo "  fetching gh GPG key"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  + curl https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=$key"
    else
      local tmp
      tmp="$(mktemp)"
      if ! curl -fsSL --retry 2 --retry-delay 2 https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$tmp"; then
        echo "gh: GPG key fetch failed — install manually"
        rm -f "$tmp"
        return
      fi
      sudo install -m 0644 "$tmp" "$key"
      sudo chmod go+r "$key"
      rm -f "$tmp"
    fi
  fi
  if [[ ! -f "$list" ]]; then
    local arch
    arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    echo "  installing gh apt source list"
    run sudo bash -c "echo 'deb [arch=$arch signed-by=$key] https://cli.github.com/packages stable main' > $list"
  fi
  run sudo apt-get update -qq || echo "gh: apt-get update had warnings — continuing"
  run sudo apt-get install -y gh || echo "gh: apt-get install failed"
}

install_gh

# lazygit: not in default apt on most releases. Pull the latest GitHub
# release tarball for the host arch and `install` into /usr/local/bin.
install_lazygit() {
  if [[ $SKIP_TOOLS -eq 1 ]]; then
    return
  fi
  if command -v lazygit >/dev/null 2>&1; then
    echo "lazygit: already installed"
    return
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "lazygit: need curl + tar on PATH — install manually: https://github.com/jesseduffield/lazygit/releases"
    return
  fi
  local arch
  case "$(uname -m)" in
    x86_64)         arch=x86_64 ;;
    aarch64|arm64)  arch=arm64 ;;
    *)
      echo "lazygit: unknown arch $(uname -m) — install manually"
      return
      ;;
  esac
  local ver
  ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest 2>/dev/null | grep -Po '"tag_name": "v\K[^"]*' | head -1)"
  if [[ -z "$ver" ]]; then
    echo "lazygit: could not resolve latest version (GitHub API rate-limited?) — install manually"
    return
  fi
  echo "lazygit: installing v$ver (Linux $arch)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + curl -L .../lazygit_${ver}_Linux_${arch}.tar.gz | tar xz && sudo install lazygit /usr/local/bin"
    return
  fi
  local tmpdir
  tmpdir="$(mktemp -d)"
  if ! curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz" -o "$tmpdir/lazygit.tar.gz"; then
    echo "lazygit: download failed"
    rm -rf "$tmpdir"
    return
  fi
  if ! tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" lazygit; then
    echo "lazygit: extract failed"
    rm -rf "$tmpdir"
    return
  fi
  if sudo install "$tmpdir/lazygit" /usr/local/bin/lazygit; then
    echo "lazygit: installed to /usr/local/bin/lazygit"
  else
    echo "lazygit: install to /usr/local/bin failed"
  fi
  rm -rf "$tmpdir"
}

install_lazygit

# On WSL2, also deploy wezterm.lua to the Windows-side user profile so the
# Windows wezterm GUI picks up edits made in this repo. Copy (not symlink) —
# wezterm on Windows doesn't reliably follow symlinks across /mnt/c.
windows_wezterm_sync() {
  if ! grep -qi microsoft /proc/version 2>/dev/null; then
    return
  fi

  local winuser=""
  if command -v cmd.exe >/dev/null 2>&1; then
    # cd to /mnt/c to avoid the "UNC paths not supported" cmd.exe warning.
    winuser="$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n[:space:]')"
  fi
  if [[ -z "$winuser" || ! -d "/mnt/c/Users/$winuser" ]]; then
    # Fallback: scan /mnt/c/Users for a real profile dir (has AppData).
    local d name
    while IFS= read -r name; do
      d="/mnt/c/Users/$name"
      case "$name" in
        Public|Default|"Default User"|"All Users"|desktop.ini) continue ;;
      esac
      if [[ -d "$d/AppData" ]]; then
        winuser="$name"
        break
      fi
    done < <(ls -1 /mnt/c/Users 2>/dev/null)
  fi

  if [[ -z "$winuser" ]]; then
    echo "wezterm-win: could not resolve Windows username — skipping"
    return
  fi

  local src="$REPO_DIR/wezterm/wezterm.lua"
  local dst="/mnt/c/Users/$winuser/.config/wezterm/wezterm.lua"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  if [[ ! -d "$dst_dir" ]]; then
    run mkdir -p "$dst_dir"
  fi

  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      echo "ok:    $dst already matches repo"
      return
    fi
    echo "wezterm-win: existing differs — backing up to $dst.backup-$TIMESTAMP"
    echo "--- diff (current Windows file -> repo) ---"
    diff -u "$dst" "$src" | head -60 || true
    echo "--- end diff ---"
    run cp "$dst" "$dst.backup-$TIMESTAMP"
  fi

  run cp "$src" "$dst"
  echo "copy:  $dst <- $src"
}

windows_wezterm_sync

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
