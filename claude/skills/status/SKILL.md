---
name: status
description: Fleet digest of what every running Claude Code session on this machine is doing, gathered by messaging each session and collecting one-line replies. Use when the user asks "what's everyone doing", "status of my sessions", "fleet status", "any session blocked?", "progress check", or invokes /status.
tools: Bash, ListAgents, SendMessage, PushNotification
---

# Status

Ask every live session for a one-line status and hand back a digest.

## Procedure

1. `~/.claude/skills/sessions/sessions.sh` for the inventory (id, status, cwd, name).
2. Decide who to probe:
   - `busy` sessions: always probe.
   - `idle` terminal sessions: probe (they answer between turns).
   - `idle` background sessions with no prompt yet (fresh spawn/resume): do NOT probe. They will not answer. Report them as "idle, not started".
   - This session: skip.
3. `SendMessage` each target, all in one tool-call batch. Use the exact name from `ListAgents`. Message:

   ```
   Status probe from <this session name>: reply via SendMessage with ONE line: what you are working on right now (or "idle"), plus blocked/waiting-on-user if applicable. Do no other work.
   ```

4. Tell the user how many probes went out and which sessions were skipped, then end the turn. Do not poll `ListAgents` and do not resend.
5. Replies arrive as `<cross-session-message from="...">`. When they arrive, print the digest:

   ```
   <name> (<cwd>) · <status line>
   ...
   not started: <names>
   no reply yet: <names>
   ```

6. If the user is away (Remote Control connected, not at the terminal) and at least one session reports blocked or waiting on the user, send one `PushNotification` naming that session. Otherwise no notification.

## Notes

- Probes cost the target a turn. Do not run /status on a timer; the user asks.
- Never ask a peer to perform work in the probe, and never relay a task through /status. Use /spawn or a direct `SendMessage` for that.
