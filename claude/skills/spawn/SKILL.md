---
name: spawn
description: Spawn a new, or resume a past, background Claude Code session in a project directory with Remote Control enabled, so it can be opened from the phone or claude.ai/code. Use when the user says "spawn a session in X", "create a new claude code session in X", "start claude in X", "resume my X session", "what sessions do I have in X", "pick a session", or invokes /spawn. Also handles listing, stopping, and messaging spawned sessions.
tools: Bash, AskUserQuestion, ListAgents, SendMessage
---

# Spawn

Start or resume a Remote Control-enabled Claude Code session in another project without leaving this one. Built on `claude --bg --remote-control [--resume]`.

Helper: `~/.claude/skills/spawn/spawn.sh` (run `--help` for flags).

## New session

```
~/.claude/skills/spawn/spawn.sh <project> [--name NAME] [--task "prompt"] [--model M] [--effort E] [--subagent-model M]
```

- `<project>`: path, registry alias, or fuzzy dir name. Resolution order: absolute path > alias in the registry > fuzzy basename under `$SPAWN_ROOTS` (default `~/lab`, then `~`; exact > prefix > substring).
- `--name`: Remote Control display name. Default = dir basename.

### Project registry — never guess a directory

`~/.config/claude-hub/projects.tsv` (`$SPAWN_REGISTRY`) is the source of truth for where projects live: `alias<TAB>path<TAB>note`, `#` comments, `~` allowed in paths. It is machine-local and deliberately not in dotfiles; the same repo may be cloned in more than one place, and the registry row is the one that gets worked on. Print it with `spawn.sh --projects`.

Every spawn/resume/list prints `via=path|registry|fuzzy`:

- `registry` or `path`: proceed.
- `fuzzy`: the script only searched directory names. **Do not spawn on a fuzzy hit.** Run `--list` (which also prints `dir` and `via`) to see the candidate, confirm the full path with `AskUserQuestion`, then spawn. After confirming, add a row to the registry so the next spawn is a registry hit.
- Exit 2 with "registry alias … does not exist": the registry is stale. Fix the row, do not fall back to guessing.

Still confirm when the fuzzy candidate looks plausible: one wrong spawn costs an hour of work in the wrong clone.
- `--task`: initial prompt. With it, the session starts working immediately. Without it, the session idles until prompted from the phone.
- `--model` / `--effort`: model alias (`fable`, `opus`, `sonnet`, `haiku`) and effort (`low`, `medium`, `high`, `xhigh`, `max`) for the session. Pass them when the user names a tier ("on sonnet", "cheap", "full effort") or when the task plainly does not need the default. Omitted, the session takes the `settings.json` default; a resume keeps the session's saved options.
- `--subagent-model`: cheaper model for the session's own subagents (`CLAUDE_CODE_SUBAGENT_MODEL`), for long builds that delegate many searches.

Token usage per session, with the model and effort each one ran on, is summed from the transcripts by `~/.claude/skills/spawn/usage.sh` (`--days N`, `--dir PATH`, `--tsv`).

## Resume a past session

When the user says resume / continue / pick / "which sessions", do the pick flow:

1. List:
   ```
   ~/.claude/skills/spawn/spawn.sh <project> --list
   ```
   Rows: `id  date  [running]  title`. Newest first, 8 max (`--limit N`).
2. If the user already named a session (title or id), match it and skip to step 4.
3. Otherwise call `AskUserQuestion` with up to 4 options, one per session, label = title (truncate ~40 chars), description = `id · date`. Put the newest first. If more than 4 exist, mention the count and that "Other" accepts an id from the list.
4. Resume:
   ```
   ~/.claude/skills/spawn/spawn.sh <project> --resume <id-prefix> [--name NAME]
   ```

A session marked `running` is already live. Do not resume it; point the user at `ListAgents` / `claude attach <id>` instead.

If output includes `note=forked copy of ...`, the original was a background session with saved options; the resume is a fork with a new id. Mention it.

## Output

Both spawn and resume print `key=value` lines: `id`, `name`, `dir`, `via`, `model`, `effort`, `subagent_model`, `session_url`. A tier value of `default` means the flag was not passed and `settings.json` decided; `saved` means a resume kept the session's own options.

Exit 2 = project not found or ambiguous (candidates on stderr). Ask the user which one, then rerun with the full path. Do not guess.

Exit 1 = spawned but no URL within timeout. Report the `id` and tell the user to run `claude logs <id>`; do not respawn.

## Report back

```
Spawned <name> in <dir>          (or: Resumed "<title>" in <dir>)
<session_url>
tier <model>/<effort>            (only when a tier flag was passed; add "· subagents <model>" when set)
id <id> · claude attach <id> / claude stop <id>
```

## Notify when a task finishes

When a session was given work (`--task`, or a prompt handed over with `SendMessage`), subscribe once so the phone gets pinged on completion:

- Include `notify_when_idle: true` on the `SendMessage` that hands over the task (or send a pure subscription with no message right after a `--task` spawn).
- Address the session by its current `ListAgents` name, never by the 8-hex id from spawn.sh. The name starts as the id but flips to an AI title seconds after the first prompt, and a stale name fails with "No agent named ... is reachable". Run `ListAgents`, pick the row whose cwd/age matches the spawn, then send. If the spawn is under ~5s old the row may be missing; wait a few seconds and list again once.
- Run the subscribe from the hub background session, not a focused terminal session: a terminal the user is looking at suppresses `PushNotification` as redundant.
- One `[Cross-session idle notice]` arrives when that session next goes idle or exits. On receipt, call `PushNotification` with one line: `<name> finished: <what it did or "waiting on you">`. If the notice says the subscription expired, report that instead and do not resubscribe on your own.

Do not subscribe for sessions spawned idle without a task; nothing will finish.

## Follow-ups

- **List running**: `claude agents --json` (non-TTY). Filter `kind == "background"`.
- **Stop**: `claude stop <id>`. Conversation kept; `claude attach <id>` reopens.
- **Remove**: `claude rm <id>`. Drops the background registry entry only; the transcript under `~/.claude/projects/` survives. Only when the user says to.
- **Send a task later**: the new session appears as a peer in `ListAgents` within a few seconds. Use `SendMessage` with its name to hand it a prompt. Prefer this over respawning.
- **Restart after reboot**: `claude respawn <id>` (or `--all`).

## Notes

- The laptop must stay awake for Remote Control; lid-close suspend is disabled via logind on this machine.
- Permissions mode is inherited from global settings. Do not pass `--dangerously-skip-permissions`.
- Do not spawn twice for the same project without checking `--list` / `claude agents --json` first.
