# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Personal dotfiles, organized by tool. Each top-level directory holds the source-of-truth files for one tool:

- `lunarvim/config.lua` — deployed to `~/.config/lvim/config.lua`
- `wezterm/wezterm.lua` — deployed to `~/.config/wezterm/wezterm.lua`
- `shell/bashrc` — deployed to `~/.bashrc`
- `shell/starship.toml` — deployed to `~/.config/starship.toml`
- `git/gitconfig` — deployed to `~/.gitconfig`
- `git/gitignore_global` — deployed to `~/.config/git/ignore`
- `cli/ripgreprc` — deployed to `~/.config/ripgrep/ripgreprc`
- `cli/bat-config` — deployed to `~/.config/bat/config`
- `cli/fzf.bash` — sourced from bashrc; symlinked to `~/.config/fzf/fzf.bash`
- `lazygit/config.yml` — deployed to `~/.config/lazygit/config.yml`
- `gh/config.yml` — deployed to `~/.config/gh/config.yml`

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
- **Pane navigation** uses `smart-splits.nvim` (mrjones2014/smart-splits.nvim). Ctrl+hjkl moves between nvim windows AND wezterm panes seamlessly. The wezterm half is a process-aware key handler in `wezterm/wezterm.lua` that forwards Ctrl+hjkl to nvim when the focused pane runs nvim, else moves wezterm panes. **Touch both halves together**: `smart-splits` setup in lvim and `smart_split_action` helper in wezterm.lua.
- **Helm vs YAML LSP conflict** is handled in two coordinated places: an `LspAttach` autocmd detaches `yamlls` from `helm` buffers after attach, and `helm_ls.setup` disables its internal yamlls integration. Both are needed — removing either causes diagnostic spam on `.helm`/template files. Touch them together.
- **Claude Code plugin** (`coder/claudecode.nvim`) hardcodes `terminal_cmd = "/home/dillon/.local/bin/claude"`. This path is user-specific and will need to change if the repo is used by anyone else or if claude is installed elsewhere.
- `vim.notify` is wrapped to suppress `position_encoding` and `deprecated` warnings. New noisy warnings can be added to that match list rather than redefining `vim.notify` again.

## Deploying changes

Run `./install.sh` from the repo root. The script is idempotent: it symlinks every tracked file into the right place under `$HOME`, backing up any pre-existing non-symlink file as `<dst>.backup-<timestamp>` before replacing it. Use `./install.sh --dry-run` to preview without changing anything.

Editing files in this repo takes effect immediately on the running system **only if the symlinks already exist**. On a fresh machine, run `install.sh` once before edits will be visible.
