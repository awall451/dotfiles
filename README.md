# dotfiles

Personal dotfiles. One source of truth per tool. `install.sh` symlinks every tracked file into `$HOME` and backs up anything it would overwrite.

```bash
./install.sh            # install / re-sync
./install.sh --dry-run  # preview, no changes
./install.sh --no-tools # skip apt auto-install of coolstuff tools
```

On Debian/Ubuntu hosts `install.sh` also tries to install the modern CLI tools used by the `coolstuff` cheat sheet:

- via apt: `wezterm` (Fury apt repo, added on first run), `zoxide`, `git-delta`, `btop`
- via snap (when apt has no package): `glow`, `onefetch`, `procs`, `yazi` (`--classic`)
- anything still missing is printed with a manual install URL

The check is fast-path: it only touches apt/snap when something is actually missing.

On WSL2 `install.sh` also syncs `wezterm/wezterm.lua` over to the Windows-side profile at `/mnt/c/Users/<winuser>/.config/wezterm/wezterm.lua` so the Windows wezterm GUI sees repo edits. Existing Windows file is diffed + backed up to `*.backup-<timestamp>` before replacement. No-op when not WSL2.

Most files are symlinked into `$HOME` so edits in this repo take effect immediately. **`shell/bashrc` is the exception**: install.sh appends a `source <abs-path>/shell/bashrc` block (with markers) to your existing `~/.bashrc` instead of replacing it. Your current `~/.bashrc` is preserved untouched; the repo bashrc runs after it. The path baked into the source line is resolved at install time, so each machine gets its own absolute path.

**`~/.claude/settings.json` is also special**: deep-merged via `jq` (not symlinked), because Claude Code has no native include mechanism and the file mixes portable settings with per-machine state (local hooks, local-only plugin marketplaces). Tracked keys in `claude/settings.json` win; everything else is preserved. See `claude/README.md`.

Per-machine drift goes in untracked override files:

| File | Purpose |
|------|---------|
| `~/.bashrc.local` | work aliases, project `source`s, `RIPGREP_CONFIG_PATH` exports |
| `~/.gitconfig.local` | per-machine signing keys, credential helpers (non-identity) |
| `~/.gitconfig-work` | work `[user]` block — auto-loaded only for Azure DevOps remotes |
| `~/.config/wezterm/local.lua` | per-machine wezterm tweaks (e.g. smaller font) |
| `~/.claude/settings.json` (non-tracked keys) | per-machine hooks, local-only plugins/marketplaces — preserved by the JSON deep-merge |

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

**Browser preview styling** — `iamcco/markdown-preview.nvim` reads `lunarvim/markdown-preview.css` (tokyonight cyberpunk palette, wider column, neon glow). Path is resolved at runtime via `vim.fn.resolve($MYVIMRC)`, so it works on any machine that has the lvim config symlinked from this repo. Edit the CSS to retune colors.

**In-buffer rendering** — `MeanderingProgrammer/render-markdown.nvim` decorates `.md` buffers directly (headings, code blocks, bullets, checkboxes, tables) using tokyonight colors. No browser needed. Toggles via `:RenderMarkdown` / `:RenderMarkdown toggle`. Highlight groups are reapplied on `ColorScheme` so a colorscheme switch keeps the cyberpunk palette.

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
- **gitsigns** (LunarVim built-in) — sign-column hunk markers + inline blame at end of current line (`virt_text_pos = "eol"`, 300ms delay). Hunk navigation/stage/reset keys live under `<leader>g` (LunarVim defaults).

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
- Aliases: `ll`, `la`, `ls=lsd` if installed, `cat=bat --paging=never` if installed, `imcat=wezterm imgcat` if wezterm CLI in `$PATH`.
- `$PATH` includes `~/go/bin`, `~/.local/bin`, `/opt/nvim-linux64/bin`.
- Sources `~/.config/fzf/fzf.bash` (rg-backed file search, bat preview).
- Inits `starship` if installed.
- Inits `zoxide` if installed (`z foo` to jump by frecency, `zi` for fuzzy picker).
- Sources `shell/docker.sh` (docker helpers — see below).
- Defines `coolstuff` function — prints a colored cheat sheet for the modern CLI tools listed below (delta, glow, btop, procs, onefetch, yazi, zoxide, imcat, gitsigns). Run `coolstuff` anytime as a memory jog.
- Sources `~/.bashrc.local` last.
- **WSL2 only:** sets `DISPLAY=:0` and `WAYLAND_DISPLAY=wayland-0` (if unset) and prepends `shell/wsl-bin/` to `$PATH`. That directory holds shim wrappers for `xclip` and `wl-paste` that bridge **Windows clipboard image data** (e.g. `Win+Shift+S` screenshots) into WSL2 by shelling out to PowerShell against the Win32 clipboard. WSLg only round-trips text — image bytes never appear on the X11/Wayland selection — so the wrappers fill that gap. Required for Claude Code image paste and any other tool that reads clipboard images via xclip/wl-paste. Text reads/writes are passed through to the real `/usr/bin/xclip` and `/usr/bin/wl-paste`. Requires `xclip` to be installed: `sudo apt install xclip`.

`shell/starship.toml` is a two-line tokyo-night-flavoured prompt with git status, cmd duration, language version icons. Edit symbols in the `[lang]` blocks.

---

## Docker helpers (`shell/docker.sh`)

Sourced from `shell/bashrc`; the whole file no-ops if `docker` is not on `$PATH`. Run `dockerstuff` for the same table in the terminal.

Every `[filter]` argument is an optional substring match on container names — omit it to act on all containers.

| Command | Behaviour |
|---------|-----------|
| `dps [filter]` | Formatted `docker ps -a`: name / age / status. Includes stopped containers. |
| `wdps [filter]` | `dps` under `watch -n 1`. |
| `docker-stats` | Formatted `docker stats --all` (CPU, mem, net, block IO, PIDs). |
| `docker-mem [regex]` | `docker stats` filtered by regex, plus a summed total in GiB. |
| `dih [filter]` | One line per container: name, health status, last probe output. |
| `wdih [filter]` | `dih` under `watch -n 10`. |
| `dihj <partial>` | Full healthcheck JSON (`.State.Health`) of the first matching container: every probe in the log, `ExitCode`, `FailingStreak`. For flapping probes, where `dih`'s single output line isn't enough. |
| `deit <partial> [cmd]` | `docker exec -it` into the first matching running container. Defaults to `sh`. |
| `drit <image>` | `docker run --rm -it --entrypoint bash` — throwaway shell from an image. |
| `dritu <image>` | Same, `--user=root --privileged`. |
| `dil <image\|container>` | Print image labels. Argument containing `:` is treated as an image tag, otherwise resolved as a container name. |
| `dive <image>` | Layer / Dockerfile explorer, run from `wagoodman/dive` — nothing to install. |
| `ctop` | htop-style container metrics, run from `quay.io/vektorlab/ctop`. |
| `dc` / `dcp` / `dcud` / `dcd` / `dcps` / `dclf` | `docker compose` / `pull` / `up -d` / `down` / `ps` / `logs -f --tail=1000`, against the compose project in the current directory. |
| `dcpsg <pattern> <cmd>` | Run one compose command against every service matching a pattern, e.g. `dcpsg worker restart`. |

Requires `jq` for `dih` / `dih2` / `dil`, `perl` for `docker-mem`, `watch` for the `w*` variants.

---

## Recall (reminders + morning briefing)

Defined in `shell/recall.sh`, sourced from `shell/bashrc`. Personal reminders that surface as a "morning briefing" the first time you open an interactive shell each day.

### Subcommands

| Command | Behaviour |
|---------|-----------|
| `recall` | Interactive prompt: "What to remember?" → "When? [tomorrow]" |
| `recall <text>...` | Save reminder, due `tomorrow` |
| `recall --when "<phrase>" <text>...` | Save with a natural-language due date |
| `recall list` (or `ls`) | List open reminders, sorted by due date |
| `recall done <id-or-prefix>` | Mark a reminder done (moves the line to `archive.jsonl`) |
| `recall show` (or `briefing`) | Print the morning briefing now, regardless of last-shown stamp |
| `recall demo` | Render a sample briefing against fake reminders (real state untouched) |
| `recall help` | Usage |

### Date phrases

Common natural-language phrases work directly: `today`, `tomorrow`, `friday`, `next monday`, `next week`, `start of next week`, `end of week`, `end of next week`, `weekend`, `in 3 days`, `+2 weeks`. A small alias table normalizes the fuzzier phrases (`start of next week` → `next monday`, `end of week` → `friday`, etc.) and everything else is forwarded to GNU `date -d`.

### When the briefing fires

On every interactive shell startup, the bashrc hook `__recall_briefing_maybe` runs:

1. Skips if `$RECALL_HOME/last_shown` already equals today's date.
2. Skips if the current time is earlier than `$RECALL_BRIEFING_AFTER` (default `05:00`).
3. Skips silently if there are no reminders due-or-overdue.
4. Otherwise prints the briefing and stamps today's date to `last_shown`.

The fast-path is just a stamp file read + a string compare; no `jq` invocation or file scan happens until step 4.

### State

| Path | Contents |
|------|----------|
| `~/.local/share/recall/reminders.jsonl` | One JSON object per open reminder: `{id, created_at, due, text}` |
| `~/.local/share/recall/archive.jsonl` | Same shape + `done_at`, appended whenever you `recall done <id>` |
| `~/.local/share/recall/last_shown` | Single line, `YYYY-MM-DD`, the date the briefing last ran |

Override the directory via `RECALL_HOME`. Override the briefing time gate via `RECALL_BRIEFING_AFTER` (`HH:MM`).

Requires `jq`. The briefing hook silently no-ops when `jq` is missing, so a fresh machine without `jq` will not break shell startup.

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
- Diff: `algorithm=histogram`, `colorMoved=default`. Pager: `delta` (side-by-side, line numbers, navigate, hyperlinks, TwoDark syntax).
- Editor: `lvim`. Credential helper: `gh auth git-credential`.
- Aliases: `co`, `br`, `st`, `ci`, `d`, `dc`, `lg`, `last`, `unstage`, `amend`.
- Default `[user]` is the personal identity. Azure DevOps remotes (`**dev.azure.com**`, `**visualstudio.com**`) auto-load `~/.gitconfig-work` for the work identity via `[includeIf "hasconfig:remote.*.url:..."]`. Drop a `[user]` block into `~/.gitconfig-work` on the work machine; leave it absent everywhere else.
- `~/.gitconfig.local` is `[include]`-d at the end for non-identity per-machine bits (signing keys, credential helpers).

`git/gitignore_global` is symlinked to `~/.config/git/ignore` and applies to every repo.

---

## Claude Code (`claude/`)

Portable user-level config for the `claude` CLI plus the `ccstatusline` status bar tool.

| File | Deploys to | How |
|------|-----------|-----|
| `claude/settings.json` | `~/.claude/settings.json` | `jq` deep-merge (preserves local hooks, marketplaces, plugins) |
| `claude/ccstatusline/settings.json` | `~/.config/ccstatusline/settings.json` | symlink (TUI edits flow back into the repo) |

Tracked: status line command (`ccstatusline`), `skipAutoPermissionPrompt`, caveman plugin marketplace + enablement. Not tracked: per-machine Stop hooks, local-directory plugin marketplaces (like the `themes` marketplace at `~/lab/projectorion/themes`), locally-enabled plugins like `rock@themes`.

First-time setup on a new machine: `npm install -g ccstatusline`, then `./install.sh`, then open a new shell, then launch `claude`. Caveman marketplace + plugin auto-resolve on first run. Full notes (including the caveman statusline path-hash quirk) in `claude/README.md`.

Requires `jq` for the merge step; install step skips with a notice if missing.

---

## Unconfigured CLI tools (install-only)

These are installed system-wide (pacman / your package manager) and used with defaults — no tracked config file in this repo. Listed here so they don't get forgotten.

| Tool | What it does | Quick start |
|------|--------------|-------------|
| `delta` | Syntax-highlighted, side-by-side git diff pager. Wired in `git/gitconfig` (`core.pager`, `interactive.diffFilter`, `[delta]` block). | Run any `git diff` / `git log -p` / `git show`. |
| `glow` | Terminal Markdown renderer. | `glow README.md`, or `glow .` for a TUI file picker. |
| `btop` | System monitor (CPU, mem, disks, net, processes). | `btop`. `q` to quit, `?` for help, `Esc` for menu. |
| `procs` | Modern `ps` — colored, tree mode, search. | `procs`, `procs --tree`, `procs <pattern>`. |
| `onefetch` | Repo summary card (langs, commits, contributors, LOC). Eye candy on `cd` into a repo. | `onefetch` inside any git repo. |
| `yazi` | TUI file manager with image previews via the kitty graphics protocol (works in WezTerm out of the box). | `yazi`. `q` quit, `?` help, `Enter` open, `Space` select. |
| `zoxide` | Smart `cd` that learns frecent dirs. Init lives in `shell/bashrc`. | `z <partial>` to jump, `zi` for fuzzy picker. `z -` goes back. |
| `imcat` (alias) | Shortcut for `wezterm imgcat`. Renders an image inline in the WezTerm pane. Defined in `shell/bashrc`. | `imcat path/to/img.png`. |

If any of these grow a config file, move them up into the "CLI tools" section above and add an `install.sh` mapping.

---

## Adding a new tool

1. Drop the source-of-truth file into a topical directory (`cli/`, `shell/`, etc.).
2. Add an `install.sh` mapping line:
   - `link <repo path> <home-relative path>` — symlink replace (the default; back up + replace destination).
   - `source_into <repo path> <home-rc> <marker>` — append a `source` block to an existing rc file (use this for `bashrc`-style files where you want to preserve the user's own content).
3. Run `./install.sh` — existing files get backed up, new ones get symlinked.
4. Document the keymap / behaviour here.
