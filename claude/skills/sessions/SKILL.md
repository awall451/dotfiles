---
name: sessions
description: List, inspect, or stop Claude Code sessions running on this machine (background and terminal), with Remote Control links. Use when the user asks "what sessions are running", "list my sessions", "show sessions", "stop the X session", "stop idle sessions", "link for X", or invokes /sessions.
tools: Bash, ListAgents
---

# Sessions

Phone-friendly view of every Claude Code session on this machine. Helper: `~/.claude/skills/sessions/sessions.sh`.

## List

```
~/.claude/skills/sessions/sessions.sh
```

Columns: `id kind status age cwd name url`.
- `bg` = background session (8-hex id; `claude attach/logs/stop` work). `term` = interactive terminal session (pid only; cannot be stopped from here).
- `(hub)` marks the always-on hub session started by the `claude-hub` user unit.
- `url` = Remote Control link, background sessions only.

Report as a short list, one line per session: name, status, age, cwd, and the link for bg sessions. Skip the raw table unless asked. Omit this session itself unless the user asks for everything.

## Stop

```
~/.claude/skills/sessions/sessions.sh stop <id> [<id>...]
~/.claude/skills/sessions/sessions.sh stop-idle        # every idle bg session except the hub
```

Stopping keeps the conversation; `claude attach <id>` or `/spawn <project> --resume <id>` brings it back. Never stop the hub unless the user names it explicitly. Never run `claude rm` from this skill.

## Link

```
~/.claude/skills/sessions/sessions.sh url <id>
```

## Notes

- A `bg` session shown `idle` right after spawn/resume has not been prompted yet. It will not react to cross-session messages until it gets its first prompt from the phone or `claude attach`.
- For the hub itself: `~/.config/claude-hub/hub.sh status`.
