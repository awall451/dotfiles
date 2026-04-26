# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Personal dotfiles for two tools:

- `lunarvim/config.lua` — deployed to `~/.config/lvim/config.lua`
- `wezterm/wezterm.lua` — deployed to `~/.config/wezterm/wezterm.lua`

There is no build, test, lint, or package manager. Files in this repo are consumed directly by LunarVim and WezTerm at startup. Validation is "open the app and see if it loads."

## Cross-platform / per-machine architecture

Both configs are designed to run unmodified on multiple machines (Linux, WSL on Windows, laptop with smaller display).

- **WezTerm**: `wezterm.lua` detects Windows via `wezterm.target_triple:find('windows')` and switches `default_domain`/`default_prog` to `WSL:Ubuntu-24.04`. At the **bottom** of the file it `pcall(dofile, ...)` an optional `~/.config/wezterm/local.lua` and merges its returned table over `config`. `local.lua` is intentionally not in this repo — it is the per-machine override (e.g. smaller `font_size` on the laptop). When editing `wezterm.lua`, keep the `local.lua` merge as the last step so per-machine overrides always win.
- **LunarVim**: clipboard block at the bottom unconditionally configures `win32yank-wsl`. This is WSL-specific; if cross-OS support is added, gate it the same way WezTerm gates its WSL block.

## LunarVim config shape

`lunarvim/config.lua` is a single file driving LunarVim. Two things to know before editing:

- **Plugins** are declared in the `lvim.plugins = { ... }` table using lazy.nvim spec format. Adding a plugin = adding an entry to that table (with `config = function() ... end` for setup). Don't introduce a separate plugin manager.
- **Helm vs YAML LSP conflict** is handled in two coordinated places (lines ~248–276): an `LspAttach` autocmd detaches `yamlls` from `helm` buffers after attach, and `helm_ls.setup` disables its internal yamlls integration. Both are needed — removing either causes diagnostic spam on `.helm`/template files. Touch them together.
- **Claude Code plugin** (`coder/claudecode.nvim`) hardcodes `terminal_cmd = "/home/dillon/.local/bin/claude"`. This path is user-specific and will need to change if the repo is used by anyone else or if claude is installed elsewhere.
- `vim.notify` is wrapped to suppress `position_encoding` and `deprecated` warnings. New noisy warnings can be added to that match list rather than redefining `vim.notify` again.

## Deploying changes

This repo is the source of truth, but the configs only take effect when symlinked or copied to `~/.config/lvim/` and `~/.config/wezterm/`. There is no install script — that linking is done manually per machine. Editing files here without also linking them does nothing on the running system.
