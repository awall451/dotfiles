# Claude Code config

Portable subset of `~/.claude/` and `~/.config/ccstatusline/` for this dotfiles repo.

## What's tracked

- `settings.json` — portable Claude Code user settings: status line, `skipAutoPermissionPrompt`, caveman marketplace + enabled plugin.
- `ccstatusline/settings.json` — full ccstatusline layout (the multi-line bar with model / context / git / context-bar / session-usage / weekly-usage / caveman line).

## What's NOT tracked (machine-local)

- Per-machine hooks (e.g. auto-commit Stop hook).
- Local-only plugin marketplaces (e.g. `themes` pointing at `~/lab/projectorion/themes`).
- Local-only enabled plugins (e.g. `rock@themes`).

These survive `install.sh` thanks to the JSON deep-merge — only keys present in `claude/settings.json` are overwritten; everything else in `~/.claude/settings.json` is preserved.

## How it's deployed

`install.sh` does two things for this directory:

1. **`merge_json claude/settings.json .claude/settings.json`** — deep-merges using `jq`. Tracked keys win, local keys preserved. Backup written as `~/.claude/settings.json.backup-<timestamp>` before any write. No-op if the merged result equals the current file.
2. **`link claude/ccstatusline/settings.json .config/ccstatusline/settings.json`** — symlinks. Edits made via the ccstatusline TUI land back in this repo automatically.

Requires `jq` on PATH. If missing, the merge step skips with a notice (rest of install still runs).

## First-time setup on a new machine

1. Run `./install.sh` from the repo root. It auto-installs `ccstatusline` via `npm install -g` (skipped cleanly if `npm` is missing or if `--no-tools` is passed — in that case install manually: `npm install -g ccstatusline`, configuring `npm config set prefix ~/.npm-global` first if needed).
2. Open a new shell (or `source ~/.bashrc`) so the npm global bin dir lands on PATH.
3. Launch `claude`. The caveman marketplace + plugin registration in the merged settings auto-resolves on first run; the marketplace is fetched from GitHub and the plugin enabled.
4. Verify with `/plugin` — `caveman@caveman` should appear as enabled.

## Caveman statusline path quirk

`ccstatusline/settings.json` has a `custom-command` line referencing the caveman statusline hook:

```
/home/dillon/.claude/plugins/cache/caveman/caveman/<HASH>/hooks/caveman-statusline.sh
```

The `<HASH>` segment is the cached caveman version. It:

- Changes when caveman updates → the third line of the status bar may go blank or error until you re-select the command via `ccstatusline` TUI (`Custom Commands` → pick the new caveman hook path).
- Differs across machines on first install — the value committed here will not match the freshly fetched cache on another machine.

If this becomes annoying, options:

- Drop the caveman line from the tracked file and add it via the ccstatusline TUI per machine.
- Teach `install.sh` to glob `~/.claude/plugins/cache/caveman/caveman/*/hooks/caveman-statusline.sh` and substitute the current hash into the tracked file at install time.

For now: live with the occasional re-selection.

## Adding new portable settings

Edit `claude/settings.json` — anything you add will be merged in on next `install.sh` run. To remove a previously-tracked key from machines, you have to delete it from `~/.claude/settings.json` by hand (the merge only adds/overwrites, never deletes).

## Adding new plugins

1. Add the marketplace entry under `extraKnownMarketplaces` in `claude/settings.json`.
2. Add the plugin under `enabledPlugins` in the same file.
3. Run `./install.sh`.
4. Inside `claude`, run `/plugin` and confirm. Marketplace fetch happens on first claude launch after the settings change.

If the plugin source is a local directory (like `themes`), it is not portable — leave it out of tracked settings and rely on the merge to preserve it in each machine's local `~/.claude/settings.json`.
