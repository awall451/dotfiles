#!/usr/bin/env bash
# Spawn or resume a background Claude Code session with Remote Control enabled.
#
# Usage:
#   spawn.sh <project> [--name NAME] [--task "prompt"] [tier flags]   new session
#   spawn.sh <project> --resume <id-prefix> [--name NAME] [tier flags] resume past session
#   spawn.sh <project> --list [--limit N]                              list past sessions
#
#   <project>   Absolute/relative path, an alias from the registry
#               ($SPAWN_REGISTRY, default ~/.config/claude-hub/projects.tsv,
#               untracked: alias<TAB>path<TAB>note), or a fuzzy dir name
#               resolved against $SPAWN_ROOTS (default: ~/lab:~). Registry alias >
#               exact > prefix > substring, case-insensitive. Ambiguous →
#               lists candidates, exit 2. Output line `via=` says which
#               (path|registry|fuzzy); fuzzy means the caller should confirm.
#   --projects  Print the registry (alias  path  note) and exit.
#   --name      Remote Control display name (default: project dir basename).
#   --task      Initial prompt; session starts working immediately.
#               Without it, session sits idle until prompted from phone.
#   --resume    Session id (full or unique prefix) from --list.
#   --list      Print past sessions: id  date  [state]  title. Newest first.
#   --limit     Max rows for --list (default 8).
#   --roots     Override search roots (colon-separated).
#
# Tier flags (optional; the spawning session picks them from the task):
#   --model M   Model alias or full name for the session (fable, opus, sonnet,
#               haiku). Without it: settings.json default; a resume keeps the
#               session's saved model.
#   --effort E  Reasoning effort: low, medium, high, xhigh, max. Same defaults.
#   --subagent-model M
#               Cheaper model for subagents spawned inside the session
#               (sets CLAUDE_CODE_SUBAGENT_MODEL via --settings, so it reaches
#               sessions hosted by the daemon, where the caller's env does not).
#
# Spawn/resume print key=value lines: id, name, dir, via, model, effort,
# subagent_model, session_url. Unset tier values print as "default" (new
# session) or "saved" (resume).
# Exit 0 ok, 1 spawn/URL failure, 2 resolution or bad-flag failure.

set -euo pipefail

ROOTS="${SPAWN_ROOTS:-$HOME/lab:$HOME}"
REGISTRY="${SPAWN_REGISTRY:-$HOME/.config/claude-hub/projects.tsv}"
NAME="" TASK="" PROJECT="" RESUME="" LIST=0 LIMIT=8 VIA=""
MODEL="" EFFORT="" SUBAGENT_MODEL=""
URL_TIMEOUT="${SPAWN_URL_TIMEOUT:-45}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)   NAME="$2";   shift 2 ;;
    --task)   TASK="$2";   shift 2 ;;
    --resume) RESUME="$2"; shift 2 ;;
    --list)   LIST=1;      shift ;;
    --limit)  LIMIT="$2";  shift 2 ;;
    --roots)  ROOTS="$2";  shift 2 ;;
    --model)  MODEL="$2";  shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --subagent-model) SUBAGENT_MODEL="$2"; shift 2 ;;
    --projects)
      [[ -r "$REGISTRY" ]] || { echo "error: no registry at $REGISTRY" >&2; exit 2; }
      grep -v '^#' "$REGISTRY" | awk -F'\t' 'NF{printf "%-16s %-42s %s\n",$1,$2,$3}'; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) PROJECT="$1"; shift ;;
  esac
done

[[ -n "$PROJECT" ]] || { echo "error: project required" >&2; exit 2; }
case "$EFFORT" in
  ""|low|medium|high|xhigh|max) ;;
  *) echo "error: --effort must be one of low, medium, high, xhigh, max (got '$EFFORT')" >&2; exit 2 ;;
esac

# --- resolve project dir --------------------------------------------------
# Registry first: exact alias in $REGISTRY (alias<TAB>path<TAB>note, '#' comments).
# Return 0 hit, 1 no such alias, 2 alias points at a missing dir.
registry_lookup() {
  local q="${1,,}" alias path _
  [[ -r "$REGISTRY" ]] || return 1
  while IFS=$'\t' read -r alias path _; do
    [[ -z "$alias" || "$alias" == \#* ]] && continue
    [[ "${alias,,}" == "$q" ]] || continue
    path="${path/#\~/$HOME}"
    [[ -d "$path" ]] || { echo "error: registry alias '$alias' → $path does not exist" >&2; return 2; }
    realpath "$path"; return 0
  done < "$REGISTRY"
  return 1
}

# Sets DIR and VIA (path|registry|fuzzy). Runs in the main shell, not $(...).
resolve() {
  local q="$1" hit rc=0
  if [[ -d "$q" ]]; then VIA=path; DIR="$(realpath "$q")"; return 0; fi
  hit="$(registry_lookup "$q")" || rc=$?
  if (( rc == 0 )); then VIA=registry; DIR="$hit"; return 0; fi
  (( rc == 2 )) && return 2
  VIA=fuzzy

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
  DIR="${hits[0]}"
}

DIR=""
resolve "$PROJECT" || exit 2
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
  echo "dir=$DIR"
  echo "via=$VIA"
  [[ -d "$PROJ_DIR" ]] || { echo "no sessions for $DIR" >&2; exit 0; }
  running="$(claude agents --json 2>/dev/null | grep -o '"sessionId": *"[0-9a-f-]*"' | grep -o '[0-9a-f-]\{36\}' || true)"
  n=0
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
  # Real transcripts only: <uuid>.orphaned-*.jsonl copies are not resumable
  # (the name lands in the picker as a search term and the session hangs).
  matches=()
  for f in "$PROJ_DIR"/"$RESUME"*.jsonl; do
    if [[ "$(basename "$f" .jsonl)" =~ ^[0-9a-f-]{36}$ ]]; then matches+=("$f"); fi
  done
  if (( ${#matches[@]} == 0 )); then
    echo "error: no session starting with '$RESUME' in $PROJ_DIR" >&2; exit 2
  elif (( ${#matches[@]} > 1 )); then
    echo "error: ambiguous session prefix '$RESUME':" >&2
    printf '  %s\n' "${matches[@]##*/}" >&2; exit 2
  fi
  FULL="$(basename "${matches[0]}" .jsonl)"
  args+=(--resume "$FULL")
fi
# Tier. Omitted flags fall through to settings.json (new) or the saved
# options (resume). --settings rides along with the saved options too.
[[ -n "$MODEL" ]]  && args+=(--model "$MODEL")
[[ -n "$EFFORT" ]] && args+=(--effort "$EFFORT")
[[ -n "$SUBAGENT_MODEL" ]] && args+=(--settings "{\"env\":{\"CLAUDE_CODE_SUBAGENT_MODEL\":\"$SUBAGENT_MODEL\"}}")
[[ -n "$TASK" ]] && args+=("$TASK")

out="$(claude "${args[@]}" 2>&1)" || { echo "error: claude --bg failed:" >&2; echo "$out" >&2; exit 1; }
ID="$(printf '%s\n' "$out" | strip_ansi | sed -n 's/.*backgrounded · \([0-9a-f]\{8\}\).*/\1/p' | head -1)"
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

unset_tier="default"; [[ -n "$RESUME" ]] && unset_tier="saved"
echo "id=$ID"
echo "name=$NAME"
echo "dir=$DIR"
echo "via=$VIA"
echo "model=${MODEL:-$unset_tier}"
echo "effort=${EFFORT:-$unset_tier}"
echo "subagent_model=${SUBAGENT_MODEL:-$unset_tier}"
echo "session_url=$URL"
if [[ -z "$URL" ]]; then
  echo "warn: Remote Control URL not seen within ${URL_TIMEOUT}s; check 'claude logs $ID'" >&2
  exit 1
fi
