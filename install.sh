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

# Look up the browser_download_url of the first asset matching $pattern in the
# latest release of a GitHub repo. Echoes the URL on success, exits non-zero
# (with no output) on failure.
github_latest_asset_url() {
  local repo=$1 pattern=$2
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
    | grep -oE '"browser_download_url": *"[^"]+"' \
    | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/' \
    | grep -E "$pattern" \
    | head -1
}

# Install a .deb from a GitHub release. $1=cmd label (logging), $2=repo,
# $3=asset name regex.
install_github_deb() {
  local cmd=$1 repo=$2 pattern=$3 url tmp
  url="$(github_latest_asset_url "$repo" "$pattern")"
  if [[ -z "$url" ]]; then
    echo "  github: no asset matching '$pattern' in latest $repo release"
    return 1
  fi
  echo "  github: $cmd <- $url"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + curl ... | sudo dpkg -i"
    return 0
  fi
  tmp="$(mktemp --suffix=.deb)"
  if ! curl -fsSL --retry 2 "$url" -o "$tmp"; then
    echo "  curl: download failed for $cmd"
    rm -f "$tmp"
    return 1
  fi
  if ! sudo dpkg -i "$tmp"; then
    echo "  dpkg: install failed for $cmd"
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  return 0
}

# Install a single binary from a zip in a GitHub release into ~/.local/bin.
# $1=cmd label, $2=repo, $3=asset regex, $4=binary name inside the zip.
install_github_zip_bin() {
  local cmd=$1 repo=$2 pattern=$3 binary=$4 url tmpdir
  url="$(github_latest_asset_url "$repo" "$pattern")"
  if [[ -z "$url" ]]; then
    echo "  github: no asset matching '$pattern' in latest $repo release"
    return 1
  fi
  echo "  github: $cmd <- $url"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  + curl ... | unzip -> ~/.local/bin/$cmd"
    return 0
  fi
  tmpdir="$(mktemp -d)"
  if ! curl -fsSL --retry 2 "$url" -o "$tmpdir/x.zip"; then
    echo "  curl: download failed for $cmd"
    rm -rf "$tmpdir"
    return 1
  fi
  if ! unzip -q -o "$tmpdir/x.zip" -d "$tmpdir"; then
    echo "  unzip: extract failed for $cmd"
    rm -rf "$tmpdir"
    return 1
  fi
  local src
  src="$(find "$tmpdir" -type f -name "$binary" -perm -u+x 2>/dev/null | head -1)"
  if [[ -z "$src" ]]; then
    src="$(find "$tmpdir" -type f -name "$binary" 2>/dev/null | head -1)"
  fi
  if [[ -z "$src" ]]; then
    echo "  zip: binary '$binary' not found inside archive"
    rm -rf "$tmpdir"
    return 1
  fi
  mkdir -p "$HOME/.local/bin"
  cp "$src" "$HOME/.local/bin/$cmd"
  chmod +x "$HOME/.local/bin/$cmd"
  rm -rf "$tmpdir"
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

  # cmd-name -> "github_repo|asset-name-regex" for tools that ship .deb files.
  # Used as a fallback when apt has no package. .deb gives a real native
  # install (snap was tried initially but its strict confinement broke these
  # tools outside $HOME — they couldn't read /opt, /var, etc.).
  local -A gh_deb=(
    [glow]="charmbracelet/glow|glow_.*_amd64\\.deb$"
    [onefetch]="o2sh/onefetch|onefetch_amd64\\.deb$"
    [yazi]="sxyazi/yazi|yazi-x86_64-unknown-linux-gnu\\.deb$"
  )
  # cmd-name -> "github_repo|asset-regex|binary-name-inside-zip" for tools
  # whose upstream only ships zips (no .deb). Binary lands in ~/.local/bin.
  local -A gh_zip=(
    [procs]="dalance/procs|procs-v.*-x86_64-linux\\.zip$|procs"
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

  # GitHub-release fallback for tools not in apt (glow, onefetch, yazi via
  # .deb; procs via zip extract). Native installs sidestep snap strict
  # confinement, which blocked these tools from reading /opt, /var, etc.
  if [[ ${#manual[@]} -gt 0 ]]; then
    local still_manual=()
    for cmd in "${manual[@]}"; do
      if [[ -n "${gh_deb[$cmd]:-}" ]]; then
        local repo="${gh_deb[$cmd]%%|*}"
        local pattern="${gh_deb[$cmd]#*|}"
        echo "tools: installing $cmd via GitHub release .deb (sudo)"
        if ! install_github_deb "$cmd" "$repo" "$pattern"; then
          still_manual+=("$cmd")
        fi
      elif [[ -n "${gh_zip[$cmd]:-}" ]]; then
        local spec="${gh_zip[$cmd]}"
        local repo="${spec%%|*}"
        spec="${spec#*|}"
        local pattern="${spec%%|*}"
        local binary="${spec#*|}"
        echo "tools: installing $cmd via GitHub release zip -> ~/.local/bin"
        if ! install_github_zip_bin "$cmd" "$repo" "$pattern" "$binary"; then
          still_manual+=("$cmd")
        fi
      else
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
