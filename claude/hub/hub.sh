#!/usr/bin/env bash
# Ensure a Remote Control "hub" background session exists in $HOME and
# restore background sessions that were running at last logout/shutdown.
#
# Usage: hub.sh [start|snapshot|stop|status]
#   start     (default) resume the saved hub session or create one, then
#             resume every background session listed in restore.list
#             (unless HUB_RESTORE=0)
#   snapshot  write the ids of currently running background sessions to
#             restore.list (wired to ExecStop, so it runs at logout/shutdown)
#   stop      snapshot, then stop the hub session (conversation kept)
#   status    print hub id, running state, and Remote Control URL
#
# State in ~/.config/claude-hub/: hub.id, restore.list

set -euo pipefail

STATE_DIR="$HOME/.config/claude-hub"
ID_FILE="$STATE_DIR/hub.id"
HUB_NAME="${HUB_NAME:-hub}"
HUB_RESTORE="${HUB_RESTORE:-1}"
RESTORE_FILE="$STATE_DIR/restore.list"
URL_TIMEOUT="${HUB_URL_TIMEOUT:-60}"
mkdir -p "$STATE_DIR"

strip_ansi() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

hub_id() { [[ -f "$ID_FILE" ]] && tr -d '[:space:]' <"$ID_FILE" || true; }

# Short ids of live background workers, one per line.
running_ids() {
  claude agents --json 2>/dev/null | python3 -c '
import json,sys
for a in json.load(sys.stdin):
    if a.get("kind")=="background" and a.get("pid") and a.get("id"):
        print(a["id"])' 2>/dev/null || true
}

is_running() { running_ids | grep -qx "$1"; }

transcript_for() { ls "$HOME"/.claude/projects/*/"$1"*.jsonl 2>/dev/null | head -1; }

rc_url() {
  claude logs "$1" 2>/dev/null | strip_ansi \
    | grep -o 'https://claude\.ai/code/session_[A-Za-z0-9]*' | tail -1 || true
}

wait_url() {
  local id="$1" url=""
  for ((i=0; i<URL_TIMEOUT; i++)); do
    url="$(rc_url "$id")"; [[ -n "$url" ]] && { echo "$url"; return 0; }
    sleep 1
  done
  return 1
}

start() {
  cd "$HOME"
  local id; id="$(hub_id)"

  if [[ -n "$id" ]] && is_running "$id"; then
    echo "hub: $id already running"
  elif [[ -n "$id" ]] && [[ -n "$(transcript_for "$id")" ]]; then
    # Resume without flags: an ex-background session keeps its saved options
    # (including --remote-control); passing flags would fork a copy.
    out="$(claude --bg --resume "$id" 2>&1)" || { echo "hub: resume failed:" >&2; echo "$out" >&2; exit 1; }
    echo "hub: resumed $id"
  else
    out="$(claude --bg --remote-control "$HUB_NAME" 2>&1)" || { echo "hub: spawn failed:" >&2; echo "$out" >&2; exit 1; }
    id="$(printf '%s\n' "$out" | sed -n 's/.*backgrounded · \([0-9a-f]\{8\}\).*/\1/p' | head -1)"
    [[ -n "$id" ]] || { echo "hub: could not parse id from:" >&2; echo "$out" >&2; exit 1; }
    printf '%s\n' "$id" >"$ID_FILE"
    echo "hub: created $id"
  fi

  if url="$(wait_url "$id")"; then
    echo "hub: $url"
  else
    echo "hub: warning: no Remote Control URL within ${URL_TIMEOUT}s (claude logs $id)" >&2
  fi

  [[ "$HUB_RESTORE" == 1 && -f "$RESTORE_FILE" ]] || return 0
  local sid t
  while read -r sid; do
    [[ -n "$sid" && "$sid" != "$id" ]] || continue
    if is_running "$sid"; then echo "restore: $sid already running"; continue; fi
    t="$(transcript_for "$sid")"
    [[ -n "$t" ]] || { echo "restore: $sid has no transcript, skipping"; continue; }
    # Resume without flags so the saved options (cwd, --remote-control name) apply.
    if out="$(cd "$(dirname "$t")" && claude --bg --resume "$sid" 2>&1)"; then
      echo "restore: resumed $sid"
    else
      echo "restore: $sid failed: $(printf '%s' "$out" | tail -1)" >&2
    fi
  done <"$RESTORE_FILE"
}

snapshot() {
  local ids; ids="$(running_ids)"
  printf '%s\n' "$ids" | sed '/^$/d' >"$RESTORE_FILE"
  echo "snapshot: $(wc -l <"$RESTORE_FILE") session(s) -> $RESTORE_FILE"
}

stop() {
  snapshot
  local id; id="$(hub_id)"
  [[ -n "$id" ]] || { echo "hub: no hub id saved"; return 0; }
  claude stop "$id" 2>&1 || true
}

status() {
  local id; id="$(hub_id)"
  [[ -n "$id" ]] || { echo "hub: none"; return 1; }
  if is_running "$id"; then
    echo "hub: $id running"; echo "url: $(rc_url "$id")"
  else
    echo "hub: $id stopped"; return 1
  fi
}

case "${1:-start}" in
  start)    start ;;
  snapshot) snapshot ;;
  stop)     stop ;;
  status) status ;;
  *) echo "usage: hub.sh [start|snapshot|stop|status]" >&2; exit 2 ;;
esac
