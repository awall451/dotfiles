#!/usr/bin/env bash
# Spawn or resume a background Claude Code session with Remote Control enabled.
#
# Usage:
#   spawn.sh <project> [--name NAME] [--task "prompt"]     new session
#   spawn.sh <project> --resume <id-prefix> [--name NAME]  resume past session
#   spawn.sh <project> --list [--limit N]                  list past sessions
#
#   <project>   Absolute/relative path, or a fuzzy name resolved against
#               $SPAWN_ROOTS (default: ~/lab:~). Exact > prefix > substring,
#               case-insensitive. Ambiguous → lists candidates, exit 2.
#   --name      Remote Control display name (default: project dir basename).
#   --task      Initial prompt; session starts working immediately.
#               Without it, session sits idle until prompted from phone.
#   --resume    Session id (full or unique prefix) from --list.
#   --list      Print past sessions: id  date  [state]  title. Newest first.
#   --limit     Max rows for --list (default 8).
#   --roots     Override search roots (colon-separated).
#
# Spawn/resume print key=value lines: id, name, dir, session_url.
# Exit 0 ok, 1 spawn/URL failure, 2 resolution failure.

set -euo pipefail

ROOTS="${SPAWN_ROOTS:-$HOME/lab:$HOME}"
NAME="" TASK="" PROJECT="" RESUME="" LIST=0 LIMIT=8
URL_TIMEOUT="${SPAWN_URL_TIMEOUT:-45}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)   NAME="$2";   shift 2 ;;
    --task)   TASK="$2";   shift 2 ;;
    --resume) RESUME="$2"; shift 2 ;;
    --list)   LIST=1;      shift ;;
    --limit)  LIMIT="$2";  shift 2 ;;
    --roots)  ROOTS="$2";  shift 2 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) PROJECT="$1"; shift ;;
  esac
done

[[ -n "$PROJECT" ]] || { echo "error: project required" >&2; exit 2; }

# --- resolve project dir --------------------------------------------------
resolve() {
  local q="$1"
  if [[ -d "$q" ]]; then realpath "$q"; return 0; fi

  local -a exact=() prefix=() sub=()
  local ql="${q,,}" root d base bl
  IFS=: read -r -a roots <<<"$ROOTS"
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    for d in "$root"/*/; do
      d="${d%/}"; base="${d##*/}"; bl="${base,,}"
      [[ "$base" == .* ]] && continue
      if [[ "$bl" == "$ql" ]]; then exact+=("$d")
      elif [[ "$bl" == "$ql"* ]]; then prefix+=("$d")
      elif [[ "$bl" == *"$ql"* ]]; then sub+=("$d")
      fi
    done
  done

  local -a hits=()
  if   (( ${#exact[@]}  )); then hits=("${exact[@]}")
  elif (( ${#prefix[@]} )); then hits=("${prefix[@]}")
  elif (( ${#sub[@]}    )); then hits=("${sub[@]}")
  fi

  if (( ${#hits[@]} == 0 )); then
    echo "error: no project matching '$q' under $ROOTS" >&2; return 2
  elif (( ${#hits[@]} > 1 )); then
    echo "error: ambiguous '$q', candidates:" >&2
    printf '  %s\n' "${hits[@]}" >&2
    return 2
  fi
  printf '%s\n' "${hits[0]}"
}

DIR="$(resolve "$PROJECT")" || exit 2
[[ -n "$NAME" ]] || NAME="${DIR##*/}"
SLUG="$(printf '%s' "$DIR" | sed 's#[/.]#-#g')"
PROJ_DIR="$HOME/.claude/projects/$SLUG"

strip_ansi() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }

# Title precedence: /rename custom title > AI title > first prompt in history.
session_title() {
  local f="$1" sid="$2" t
  t="$(grep -h '"type":"custom-title"' "$f" 2>/dev/null | tail -1 | sed -n 's/.*"customTitle":"\([^"]*\)".*/\1/p')"
  [[ -n "$t" ]] || t="$(grep -h '"type":"ai-title"' "$f" 2>/dev/null | tail -1 | sed -n 's/.*"aiTitle":"\([^"]*\)".*/\1/p')"
  [[ -n "$t" ]] || t="$(grep -h "\"sessionId\":\"$sid\"" "$HOME/.claude/history.jsonl" 2>/dev/null | head -1 | sed -n 's/.*"display":"\([^"]\{0,70\}\).*/\1/p')"
  printf '%s' "${t:-(untitled)}"
}

# --- list -----------------------------------------------------------------
if (( LIST )); then
  [[ -d "$PROJ_DIR" ]] || { echo "no sessions for $DIR" >&2; exit 0; }
  running="$(claude agents --json 2>/dev/null | grep -o '"sessionId": *"[0-9a-f-]*"' | grep -o '[0-9a-f-]\{36\}' || true)"
  n=0
  echo "dir=$DIR"
  for f in $(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null); do
    sid="$(basename "$f" .jsonl)"
    [[ "$sid" =~ ^[0-9a-f-]{36}$ ]] || continue
    state=""
    grep -qx "$sid" <<<"$running" && state="running"
    printf '%s  %s  %-8s %s\n' "${sid:0:8}" "$(date -r "$f" '+%Y-%m-%d %H:%M')" "$state" "$(session_title "$f" "$sid")"
    (( ++n >= LIMIT )) && break
  done
  exit 0
fi

# --- spawn / resume -------------------------------------------------------
cd "$DIR"
args=(--bg --remote-control "$NAME")

if [[ -n "$RESUME" ]]; then
  matches=( "$PROJ_DIR"/"$RESUME"*.jsonl )
  if [[ ! -e "${matches[0]}" ]]; then
    echo "error: no session starting with '$RESUME' in $PROJ_DIR" >&2; exit 2
  elif (( ${#matches[@]} > 1 )); then
    echo "error: ambiguous session prefix '$RESUME':" >&2
    printf '  %s\n' "${matches[@]##*/}" >&2; exit 2
  fi
  FULL="$(basename "${matches[0]}" .jsonl)"
  args+=(--resume "$FULL")
fi
[[ -n "$TASK" ]] && args+=("$TASK")

out="$(claude "${args[@]}" 2>&1)" || { echo "error: claude --bg failed:" >&2; echo "$out" >&2; exit 1; }
ID="$(printf '%s\n' "$out" | sed -n 's/.*backgrounded · \([0-9a-f]\{8\}\).*/\1/p' | head -1)"
[[ -n "$ID" ]] || { echo "error: could not parse session id from:" >&2; echo "$out" >&2; exit 1; }
# Resuming an ex-background session with flags forks a copy; surface that.
printf '%s\n' "$out" | grep -q 'started a copy' && echo "note=forked copy of $RESUME (original kept its saved options)"

URL=""
for ((i=0; i<URL_TIMEOUT; i++)); do
  URL="$(claude logs "$ID" 2>/dev/null | strip_ansi \
        | grep -o 'https://claude\.ai/code/session_[A-Za-z0-9]*' | tail -1 || true)"
  [[ -n "$URL" ]] && break
  sleep 1
done

echo "id=$ID"
echo "name=$NAME"
echo "dir=$DIR"
echo "session_url=$URL"
if [[ -z "$URL" ]]; then
  echo "warn: Remote Control URL not seen within ${URL_TIMEOUT}s; check 'claude logs $ID'" >&2
  exit 1
fi
