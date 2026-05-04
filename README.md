# dotfiles

Personal dotfiles. One source of truth per tool. `install.sh` symlinks every tracked file into `$HOME` and backs up anything it would overwrite.

```bash
./install.sh            # install / re-sync
./install.sh --dry-run  # preview, no changes
```

Most files are symlinked into `$HOME` so edits in this repo take effect immediately. **`shell/bashrc` is the exception**: install.sh appends a `source <abs-path>/shell/bashrc` block (with markers) to your existing `~/.bashrc` instead of replacing it. Your current `~/.bashrc` is preserved untouched; the repo bashrc runs after it. The path baked into the source line is resolved at install time, so each machine gets its own absolute path.

Per-machine drift goes in untracked override files:

| File | Purpose |
|------|---------|
| `~/.bashrc.local` | work aliases, project `source`s, `RIPGREP_CONFIG_PATH` exports |
| `~/.gitconfig.local` | work email, signing keys, credential helpers |
| `~/.config/wezterm/local.lua` | per-machine wezterm tweaks (e.g. smaller font) |

---

## WezTerm

Defined in `wezterm/wezterm.lua`. Wezterm defaults stay enabled; the bindings below are additions or pane-aware overrides.

### Panes

| Key | Action |
|-----|--------|
| `Ctrl+Shift+E` | Split horizontal |
| `Ctrl+Shift+O` | Split vertical |
| `Ctrl+H/J/K/L` | Move between panes (smart-splits-aware: forwards into nvim if focused pane runs nvim) |
| `Alt+H/J/K/L`  | Resize current pane |
| `Ctrl+Shift+L` | Disabled (was "clear scrollback") to avoid clashing with `Ctrl+L` move |

### Tabs (wezterm built-ins, kept as-is)

| Key | Action |
|-----|--------|
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` | Close tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / prev tab |
| `Ctrl+Shift+1..9` | Jump to tab N |

### Smart-splits handshake

`Ctrl+H/J/K/L` and `Alt+H/J/K/L` work seamlessly across nvim windows AND wezterm panes. The wezterm side detects whether the focused pane is running `(n)vim` and forwards the key; otherwise it acts on the wezterm pane directly. The nvim side (smart-splits.nvim) handles the in-editor half. Edit both halves together.

---

## LunarVim

Defined in `lunarvim/config.lua`. Leader is `<space>` (LunarVim default).

### Pane / window navigation

| Key | Action |
|-----|--------|
| `Ctrl+H/J/K/L` | Smart-splits move (nvim window or wezterm pane) |
| `Alt+H/J/K/L`  | Smart-splits resize |

### Folding (nvim-ufo + treesitter)

| Key | Action |
|-----|--------|
| `zR` | Open all folds |
| `zM` | Close all folds |
| `zp` | Peek folded lines under cursor |

Folds use treesitter; everything starts unfolded (`foldlevel=99`).

### Harpoon (file marks)

| Key | Action |
|-----|--------|
| `<leader>ha` | Add current file to harpoon list |
| `<leader>hh` | Toggle quick menu |
| `<leader>h1..4` | Jump to file 1..4 |

### Trouble (diagnostics / refs panel)

| Key | Action |
|-----|--------|
| `<leader>xx` | All diagnostics |
| `<leader>xd` | Buffer diagnostics |
| `<leader>xs` | Symbols |
| `<leader>xl` | LSP refs / defs |
| `<leader>xq` | Quickfix list |
| `<leader>xL` | Location list |

### Oil (edit dirs as buffers)

| Key | Action |
|-----|--------|
| `<leader>o` | Open Oil at CWD |
| `-` | Open Oil at parent dir |

Edit the buffer like text — rename, delete, add lines for new files, then `:w` to commit changes to disk.

### Claude Code (`coder/claudecode.nvim`)

| Key | Action |
|-----|--------|
| `<leader>ac` | Toggle Claude |
| `<leader>af` | Focus Claude |
| `<leader>ar` | Resume |
| `<leader>aC` | Continue |
| `<leader>am` | Select model |
| `<leader>ab` | Add current buffer |
| `<leader>as` (visual) | Send selection |
| `<leader>as` (file tree) | Add file |
| `<leader>aa` / `<leader>ad` | Accept / deny diff |

Note: `terminal_cmd` hardcodes `/home/dillon/.local/bin/claude`. Edit on other machines.

### Markdown

| Key | Action |
|-----|--------|
| `<leader>mT` | Insert / update TOC (`:Mtoc`) |
| `<leader>mp` | Live preview in browser |
| `<leader>mP` | Stop preview |

Preview plugin needs `npm install` on first load (`cd app && npm install` runs automatically).

### Treesitter / treesj

| Key | Action |
|-----|--------|
| `<leader>tc` | Toggle treesitter context (sticky scope at top) |
| `<leader>tg` | Jump to enclosing context |
| `<leader>j`  | Toggle join/split (treesj — collapse/expand multi-line constructs) |

### Other plugins

- **nvim-treesitter-context** — sticky function/class header at top of buffer.
- **codediff.nvim** — visual diff helper.
- **schemastore.nvim** — JSON/YAML schema completions for jsonls/yamlls.
- **nvim-lint** — extra linters on top of LunarVim's defaults.
- **PICO-8.vim** — `.p8` syntax.
- **vim-helm** — Helm template highlighting (with the `helm_ls` / `yamlls` detach autocmd to avoid duplicate diagnostics).
- **snacks.nvim** — QoL picker, dashboard, scroll, indent guides, notifier (used by claudecode).

### Other config bits

- Spell check on (`en_us`), undercurl underline.
- Mouse enabled in all modes.
- WSL clipboard via `win32yank-wsl` (Windows-side binary required).
- `vim.notify` filters `position_encoding` and `deprecated` warnings.
- nvim-tree opens on the right, 50 cols wide.

---

## Shell (bash + starship)

`shell/bashrc` does:

- Sane history (10k entries, dedup).
- Aliases: `ll`, `la`, `ls=lsd` if installed, `cat=bat --paging=never` if installed.
- `$PATH` includes `~/go/bin`, `~/.local/bin`, `/opt/nvim-linux64/bin`.
- Sources `~/.config/fzf/fzf.bash` (rg-backed file search, bat preview).
- Inits `starship` if installed.
- Sources `~/.bashrc.local` last.
- **WSL2 only:** sets `DISPLAY=:0` and `WAYLAND_DISPLAY=wayland-0` (if unset) and prepends `shell/wsl-bin/` to `$PATH`. That directory holds shim wrappers for `xclip` and `wl-paste` that bridge **Windows clipboard image data** (e.g. `Win+Shift+S` screenshots) into WSL2 by shelling out to PowerShell against the Win32 clipboard. WSLg only round-trips text — image bytes never appear on the X11/Wayland selection — so the wrappers fill that gap. Required for Claude Code image paste and any other tool that reads clipboard images via xclip/wl-paste. Text reads/writes are passed through to the real `/usr/bin/xclip` and `/usr/bin/wl-paste`. Requires `xclip` to be installed: `sudo apt install xclip`.

`shell/starship.toml` is a two-line tokyo-night-flavoured prompt with git status, cmd duration, language version icons. Edit symbols in the `[lang]` blocks.

---

## CLI tools

### ripgrep (`cli/ripgreprc`)

Smart-case, hidden, follow symlinks. Excludes `.git`, `node_modules`, `.venv`, `__pycache__`, `*.lock`, `dist`, `build`, `target`.

> **Heads up:** ripgrep does not auto-load its config file. Add this to `~/.bashrc.local`:
> ```bash
> export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/ripgreprc"
> ```

### bat (`cli/bat-config`)

`TwoDark` theme, line numbers + git changes + filename header. Maps `*.helm` → YAML, `Dockerfile.*` → Dockerfile, `.gitignore` → Git Ignore. Loaded automatically from `~/.config/bat/config`.

### fzf (`cli/fzf.bash`)

- `Ctrl+T` — fuzzy-pick a file (rg-backed, bat preview).
- `Ctrl+R` — fuzzy history search.
- `Alt+C`  — fuzzy-cd into a subdirectory.
- `**<Tab>` — trigger fuzzy completion for the current command.

Falls back to package-installed key-bindings from `/usr/share/fzf/` (Arch) or `/usr/share/doc/fzf/examples/` (Debian/Ubuntu).

### lazygit (`lazygit/config.yml`)

- Tokyo-night theme.
- Auto-fetch on startup, auto-stage resolved conflicts.
- Uses `delta` as the diff pager.
- Editor is `lvim`.

Run `lazygit` in any repo; press `?` for in-app help.

### gh (`gh/config.yml`)

Aliases:

| Alias | Expands to |
|-------|-----------|
| `gh co` | `pr checkout` |
| `gh prc` | `pr create --fill` |
| `gh prv` | `pr view --web` |
| `gh prl` | `pr list --author @me` |
| `gh prs` | `pr status` |
| `gh rv`  | `pr view` |

### git (`git/gitconfig`)

- `pull.rebase=true`, `push.autoSetupRemote=true`, `fetch.prune=true`.
- `merge.conflictStyle=zdiff3`, `rerere.enabled=true`.
- Diff: `algorithm=histogram`, `colorMoved=default`.
- Editor: `lvim`. Credential helper: `gh auth git-credential`.
- Aliases: `co`, `br`, `st`, `ci`, `d`, `dc`, `lg`, `last`, `unstage`, `amend`.
- Includes `~/.gitconfig.local` at the end (work email / signing keys).

`git/gitignore_global` is symlinked to `~/.config/git/ignore` and applies to every repo.

---

## Adding a new tool

1. Drop the source-of-truth file into a topical directory (`cli/`, `shell/`, etc.).
2. Add an `install.sh` mapping line:
   - `link <repo path> <home-relative path>` — symlink replace (the default; back up + replace destination).
   - `source_into <repo path> <home-rc> <marker>` — append a `source` block to an existing rc file (use this for `bashrc`-style files where you want to preserve the user's own content).
3. Run `./install.sh` — existing files get backed up, new ones get symlinked.
4. Document the keymap / behaviour here.
