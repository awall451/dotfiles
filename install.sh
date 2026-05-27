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
        *)        echo "  $cmd: see upstream project" ;;
      esac
    done
  fi
}

install_tools

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
