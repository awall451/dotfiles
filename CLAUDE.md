# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Personal dotfiles, organized by tool. Each top-level directory holds the source-of-truth files for one tool:

- `lunarvim/config.lua` — symlinked to `~/.config/lvim/config.lua`
- `wezterm/wezterm.lua` — symlinked to `~/.config/wezterm/wezterm.lua`
- `shell/bashrc` — **sourced** from `~/.bashrc` via an appended block (NOT symlinked — see "Bashrc deployment" below)
- `shell/starship.toml` — symlinked to `~/.config/starship.toml`
- `git/gitconfig` — deployed to `~/.gitconfig`
- `git/gitignore_global` — deployed to `~/.config/git/ignore`
- `cli/ripgreprc` — deployed to `~/.config/ripgrep/ripgreprc`
- `cli/bat-config` — deployed to `~/.config/bat/config`
- `cli/fzf.bash` — sourced from bashrc; symlinked to `~/.config/fzf/fzf.bash`
- `lazygit/config.yml` — deployed to `~/.config/lazygit/config.yml`
- `gh/config.yml` — deployed to `~/.config/gh/config.yml`
- `claude/settings.json` — **deep-merged** into `~/.claude/settings.json` via `jq` (NOT symlinked — see "Claude Code config" below)
- `claude/ccstatusline/settings.json` — symlinked to `~/.config/ccstatusline/settings.json`

User-facing documentation lives in `README.md` (install flow, hotkey tables for wezterm + lvim, write-up of every CLI tool). Keep it in sync when adding tools, plugins, or keymaps.

There is no build, test, lint, or package manager. Files are consumed directly by their tools at startup. Validation is "open the tool and see if it loads."

## Cross-platform / per-machine architecture

Configs are designed to run unmodified on multiple machines (Linux, WSL on Windows, laptop with smaller display). Per-machine drift is handled by **untracked local-override files**:

- `~/.config/wezterm/local.lua` — wezterm overrides (e.g. smaller `font_size` on the laptop). `wezterm.lua` `pcall(dofile, ...)` it at the bottom and merges the returned table over `config`. **Keep the merge as the last step** so per-machine overrides always win.
- `~/.bashrc.local` — sourced at the end of `shell/bashrc`. Hold work aliases (e.g. AWS ECR login), project sources (e.g. `timelog/dev.sh`), or anything machine-specific. Original work content from the pre-managed bashrc lives in `~/.bashrc.backup-*` after the first `install.sh` run — port what you want into `.bashrc.local`.
- `~/.gitconfig.local` — `[include]`-d at the end of `git/gitconfig`. Holds non-identity per-machine bits (signing keys, credential helpers). **Do not put `[user]` here** — identity is routed by URL pattern (see below).
- `~/.gitconfig-work` — loaded **only** for Azure DevOps remotes via `[includeIf "hasconfig:remote.*.url:..."]` blocks at the bottom of `git/gitconfig`. Three patterns are needed (HTTPS Azure, SSH Azure, legacy `*.visualstudio.com`); a single `**dev.azure.com**` does NOT work because git's wildmatch runs with `WM_PATHNAME`, so `*`/`**` only span path components when bordered by `/`. Untracked. Holds the work `[user]` block on the work machine; absent on personal machines (the `includeIf` no-ops). The tracked `[user]` block sets a personal email as the default; Azure remotes override via this file. Never write the employer name in tracked files — keep work-routing references generic ("work identity", "Azure DevOps remotes").

Other tool-specific cross-platform notes:

- **WezTerm**: detects Windows via `wezterm.target_triple:find('windows')` and switches `default_domain`/`default_prog` to `WSL:Ubuntu-24.04`.
- **LunarVim**: clipboard block at the bottom unconditionally configures `win32yank-wsl`. This is WSL-specific; if cross-OS support is added, gate it the same way WezTerm gates its WSL block.

## LunarVim config shape

`lunarvim/config.lua` is a single file driving LunarVim. Things to know before editing:

- **Plugins** are declared in the `lvim.plugins = { ... }` table using lazy.nvim spec format. Adding a plugin = adding an entry to that table (with `config = function() ... end` for setup). Don't introduce a separate plugin manager.
- **Pane navigation + resize** use `smart-splits.nvim` (mrjones2014/smart-splits.nvim). `Ctrl+hjkl` moves between nvim windows AND wezterm panes seamlessly; `Alt+hjkl` resizes them with the same forwarding logic. The wezterm half is a process-aware key handler (`smart_split_action`) in `wezterm/wezterm.lua` that forwards the keys to nvim when the focused pane runs `(n)vim`, else acts on the wezterm pane directly. **Touch both halves together**: `smart-splits` setup in lvim and `smart_split_action` helper in wezterm.lua. Note: the resize binding was previously `Ctrl+Alt+hjkl` (raw `AdjustPaneSize`); it is now plain `Alt+hjkl` to match smart-splits' upstream convention — old muscle memory will not work.
- **Helm vs YAML LSP conflict** is handled in two coordinated places: an `LspAttach` autocmd detaches `yamlls` from `helm` buffers after attach, and `helm_ls.setup` disables its internal yamlls integration. Both are needed — removing either causes diagnostic spam on `.helm`/template files. Touch them together.
- **Claude Code plugin** (`coder/claudecode.nvim`) hardcodes `terminal_cmd = "/home/dillon/.local/bin/claude"`. This path is user-specific and will need to change if the repo is used by anyone else or if claude is installed elsewhere.
- `vim.notify` is wrapped to suppress `position_encoding` and `deprecated` warnings. New noisy warnings can be added to that match list rather than redefining `vim.notify` again.

## Known config traps

- **ripgrep does not auto-load `ripgreprc`.** `install.sh` symlinks `cli/ripgreprc` to `~/.config/ripgrep/ripgreprc`, but ripgrep only reads it if `RIPGREP_CONFIG_PATH` points at the file. `shell/bashrc` does **not** export this variable; the user expects to set it in `~/.bashrc.local`. If a request like "why is rg ignoring my excludes" comes up, this is almost always why.
- **gitconfig hardcodes `/home/dillon/.local/bin/gh`** in the credential helper. Cross-machine port → flip to plain `gh auth git-credential` (relies on `$PATH`) or update the path.
- **Windows-side WezTerm config is auto-synced on WSL2.** `install.sh`'s `windows_wezterm_sync()` copies `wezterm/wezterm.lua` to `/mnt/c/Users/<winuser>/.config/wezterm/wezterm.lua` on every run, but only when `/proc/version` matches `microsoft`. Windows username is resolved via `cmd.exe /c echo %USERNAME%` (invoked from `/mnt/c` to suppress the UNC-paths warning), with a fallback that scans `/mnt/c/Users/*` for a profile dir containing `AppData`. Copy (not symlink) — symlinks across `/mnt/c` aren't reliably followed by Windows wezterm. Existing file is diff'd + backed up to `.backup-<timestamp>` before replacement; matching files are a no-op. Non-WSL hosts no-op cleanly.
- **CapsLock toggle ON breaks `Ctrl+hjkl` pane nav in WezTerm/LunarVim.** TODO: brainstorm. Confirmed 2026-05-02: CapsLock off → works; CapsLock toggle on → breaks (no holding required, just the toggle state). Almost certainly because the terminal sends `CTRL|H/J/K/L` (uppercase) when caps is on, and the `smart_split_action` keytable in `wezterm/wezterm.lua` plus the `smart-splits` keymap in `lunarvim/config.lua` only register the lowercase `h/j/k/l` form. Fix candidates: (a) add uppercase `H/J/K/L` entries alongside the lowercase ones in both `wezterm/wezterm.lua` keytable and `lunarvim/config.lua` smart-splits setup, (b) verify with `wezterm show-keys` or a debug overlay what mod+key actually arrives when caps is on, (c) decide whether `Alt+hjkl` resize bindings need the same treatment. **Do not change config until brainstorm happens.**

## Claude Code config (special case)

Unlike most configs, `~/.claude/settings.json` is a single JSON file with no native include mechanism — so it can't be symlinked without clobbering per-machine state (auto-commit Stop hooks, local-only plugin marketplaces like `themes` pointing at `~/lab/projectorion/themes`, locally-enabled plugins like `rock@themes`).

`install.sh` handles it with a `merge_json` helper that uses `jq -s '.[0] * .[1]'` to deep-merge `claude/settings.json` over the existing `~/.claude/settings.json`. Properties:

- Tracked keys (`statusLine`, `skipAutoPermissionPrompt`, `extraKnownMarketplaces.caveman`, `enabledPlugins.caveman@caveman`) overwrite whatever is there.
- Untracked keys (local hooks, local marketplaces, local plugins) are preserved across runs.
- Backup written as `~/.claude/settings.json.backup-<timestamp>` only when the merged result differs from the current file (so re-runs that change nothing don't litter backups).
- Requires `jq`; install step skips with a notice if missing.

**`ccstatusline` binary is auto-installed** by `install.sh` (function `install_ccstatusline`) via `npm install -g ccstatusline`. Skips cleanly if `npm` is missing or `--no-tools` is passed. Without the binary on PATH, `statusLine.command: "ccstatusline"` resolves to nothing and the status bar renders blank — a common "my config didn't apply" failure mode after a fresh install.

**`ccstatusline/settings.json` IS symlinked** (via `link`), because ccstatusline's TUI writes edits back to disk — symlinking means TUI edits land in the repo. The caveman line in that file has a version-hash path (`.../caveman/<hash>/hooks/caveman-statusline.sh`) that drifts when caveman updates and differs across machines; expect to re-pick the command via the ccstatusline TUI occasionally. Full write-up in `claude/README.md`.

Anything machine-specific (work-only hooks, local plugin marketplaces) should stay out of the tracked `claude/settings.json` and just live in `~/.claude/settings.json` directly — the merge will preserve it.

## Bashrc deployment (special case)

Unlike the other configs, `shell/bashrc` is **not** symlinked over `~/.bashrc`. The user's existing `~/.bashrc` may contain work-specific or pre-existing content that must not be lost. Instead, `install.sh` calls `source_into shell/bashrc .bashrc bashrc`, which appends a marker-delimited block:

```
# >>> dotfiles: bashrc >>>
[ -f /abs/path/to/lab/dotfiles/shell/bashrc ] && source /abs/path/to/lab/dotfiles/shell/bashrc
# <<< dotfiles: bashrc <<<
```

Key properties:

- The absolute path is resolved at install time from `REPO_DIR` (the directory containing `install.sh`), so each machine bakes in its own correct path. Don't hardcode `$HOME/lab/dotfiles` — let `source_into` compute it.
- The append is idempotent (markers are grep'd; re-runs no-op).
- Repo bashrc runs **after** the user's existing content, so its aliases / `PS1` / starship init win for anything that overlaps. The repo bashrc deliberately omits `PS1` fallback and the `[[ $- != *i* ]] && return` interactive guard — both are the parent shell's responsibility.
- If you add another rc-style file that should be merged rather than replaced, use `source_into` (defined in `install.sh`) the same way.

## Deploying changes

Run `./install.sh` from the repo root. The script is idempotent: it symlinks tracked files into `$HOME` (backing up any pre-existing non-symlink file as `<dst>.backup-<timestamp>` before replacing), and appends source blocks for files declared via `source_into`. Use `./install.sh --dry-run` to preview without changing anything.

Editing files in this repo takes effect immediately on the running system **only if the symlinks already exist** (or, for `shell/bashrc`, the source block is in `~/.bashrc`). On a fresh machine, run `install.sh` once before edits will be visible.
