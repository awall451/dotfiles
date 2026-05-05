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

User-facing documentation lives in `README.md` (install flow, hotkey tables for wezterm + lvim, write-up of every CLI tool). Keep it in sync when adding tools, plugins, or keymaps.

There is no build, test, lint, or package manager. Files are consumed directly by their tools at startup. Validation is "open the tool and see if it loads."

## Cross-platform / per-machine architecture

Configs are designed to run unmodified on multiple machines (Linux, WSL on Windows, laptop with smaller display). Per-machine drift is handled by **untracked local-override files**:

- `~/.config/wezterm/local.lua` — wezterm overrides (e.g. smaller `font_size` on the laptop). `wezterm.lua` `pcall(dofile, ...)` it at the bottom and merges the returned table over `config`. **Keep the merge as the last step** so per-machine overrides always win.
- `~/.bashrc.local` — sourced at the end of `shell/bashrc`. Hold work aliases (e.g. AWS ECR login), project sources (e.g. `timelog/dev.sh`), or anything machine-specific. Original work content from the pre-managed bashrc lives in `~/.bashrc.backup-*` after the first `install.sh` run — port what you want into `.bashrc.local`.
- `~/.gitconfig.local` — `[include]`-d at the end of `git/gitconfig`. Hold work email, signing keys, or per-machine credential helpers.

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
- **WezTerm `Ctrl+U/D` scrollback may interact badly with mouse-wheel scroll.** Commit `a466717` added a process-aware `scroll_or_forward` handler in `wezterm/wezterm.lua` that calls `act.ScrollByPage(±0.5)` for `Ctrl+U/D` in shell panes. User has reported one intermittent incident where mouse-wheel scroll caused the active pane / cursor to oscillate between panes nonstop, requiring a wezterm restart. Not yet reproduced; suspected interaction between fractional `ScrollByPage` and wezterm's mouse-scroll handling, or possibly a focus-follow side effect from `pane:get_foreground_process_name()` being polled mid-scroll. If it recurs: try `act.ScrollByLine(±N)` instead of fractional `ScrollByPage`, or gate the bind by `is_shell` allowlist instead of the current `ctrl_ud_apps` blacklist.
- **CapsLock toggle ON breaks `Ctrl+hjkl` pane nav in WezTerm/LunarVim.** TODO: brainstorm. Confirmed 2026-05-02: CapsLock off → works; CapsLock toggle on → breaks (no holding required, just the toggle state). Almost certainly because the terminal sends `CTRL|H/J/K/L` (uppercase) when caps is on, and the `smart_split_action` keytable in `wezterm/wezterm.lua` plus the `smart-splits` keymap in `lunarvim/config.lua` only register the lowercase `h/j/k/l` form. Fix candidates: (a) add uppercase `H/J/K/L` entries alongside the lowercase ones in both `wezterm/wezterm.lua` keytable and `lunarvim/config.lua` smart-splits setup, (b) verify with `wezterm show-keys` or a debug overlay what mod+key actually arrives when caps is on, (c) decide whether `Alt+hjkl` resize bindings need the same treatment. **Do not change config until brainstorm happens.**

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
