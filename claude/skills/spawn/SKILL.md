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
~/.claude/skills/spawn/spawn.sh <project> [--name NAME] [--task "prompt"] --model M --effort E [--subagent-model M]
```

- `<project>`: path or fuzzy name (resolved against `~/lab`, then `~`). Exact > prefix > substring.
- `--name`: Remote Control display name. Default = dir basename.
- `--task`: initial prompt. With it, the session starts working immediately. Without it, the session idles until prompted from the phone.
- `--model` / `--effort`: the session's tier. Always pass both on a new spawn; pick them with the routing table below. Omitted, the session takes the `settings.json` default.
- `--subagent-model`: cheaper model for the session's own subagents (`CLAUDE_CODE_SUBAGENT_MODEL`). Only for the long-build row.

## Routing

You are the router. Every spawn gets a model and an effort, chosen from the task you were given. No classifier, no second opinion: read the task once, pick a row, pass the flags.

1. **A tier named in the request wins.** Override words map straight to flags and are not part of the task text:

   | Words | Flags |
   |---|---|
   | "on opus", "on sonnet", "on haiku", "on fable" | `--model <that>` |
   | "cheap", "cheaply", "low effort" | `--model sonnet --effort low` |
   | "full effort", "high effort" | `--model fable --effort high` |
   | "max" | `--model fable --effort max` |

2. **Otherwise classify by task shape:**

   | Task looks like | Model | Effort |
   |---|---|---|
   | Mechanical: restart a unit, reconnect a device, move or rename files, run a script whose steps are already known | `sonnet` | `low` |
   | Ordinary dev or ops work with a known shape: apply an update, check a pipeline, add a field, write a small script | `fable` | `medium` |
   | Debugging, root-causing, design, anything that must read logs or code to decide what to do | `fable` | `high` |
   | Long autonomous build with many file reads | `fable` | `high`, plus `--subagent-model sonnet` |
   | Idle session to be driven from the phone (no `--task`) | `fable` | `medium` (the user can `/model` and `/effort` inside it) |

3. **Unsure means the middle row** (`fable` / `medium`). A session started too low has to be stopped and resumed on a higher tier, which costs a restart; a session started one step too high costs only tokens. Reserve `sonnet`/`low` for work whose steps are already known before the session starts. `haiku` is not in the table: it handles one command, but a second, harder prompt from the phone would be stuck on it.

The tier is per session. If the user objects to the tier after the report, or the session outgrows it, `claude stop <id>` and resume with the new flags: `spawn.sh <project> --resume <id> --model M --effort E` (same transcript, new process). Without tier flags a resume keeps the session's saved model and effort.

Review the routing after a couple of weeks with `~/.claude/skills/spawn/usage.sh` (`--days N`, `--dir PATH`, `--tsv`). It sums input, output and cache tokens per session from the transcripts and lists the model and effort each session ran on; a session that was restarted on another tier shows both models. If the low row keeps showing restarts, narrow it.

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

Both spawn and resume print `key=value` lines: `id`, `name`, `dir`, `model`, `effort`, `subagent_model`, `session_url`. A tier value of `default` means the flag was not passed and `settings.json` decided; `saved` means a resume kept the session's own options.

Exit 2 = project not found or ambiguous (candidates on stderr). Ask the user which one, then rerun with the full path. Do not guess.

Exit 1 = spawned but no URL within timeout. Report the `id` and tell the user to run `claude logs <id>`; do not respawn.

## Report back

```
Spawned <name> in <dir>          (or: Resumed "<title>" in <dir>)
<session_url>
tier <model>/<effort>            (e.g. tier sonnet/low; add "· subagents sonnet" when set)
id <id> · claude attach <id> / claude stop <id>
```

The tier line is how the user sees the routing choice and objects in one word. Do not ask before picking a tier; report it.

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
