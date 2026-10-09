#!/usr/bin/env bash
# Token usage per Claude Code session, from the transcripts under
# ~/.claude/projects/*/<session-id>.jsonl. Assistant lines carry
# message.model, message.usage and effort, so the model/effort routing done
# at spawn time can be reviewed after the fact without extra plumbing.
#
# Usage:
#   usage.sh [--days N] [--dir PATH] [--all] [--tsv]
#
#   --days N   Only sessions with activity in the last N days (default 14).
#   --dir P    Only sessions whose project dir is P (path or basename substring).
#   --all      Every session, regardless of age.
#   --tsv      Tab-separated rows, no header or totals (for further jq/awk).
#
# Columns: last activity, id (8), model(s), effort(s), turns, input, output,
# cache read, cache write, project, title. Token counts are summed over the
# session's assistant messages; "k" and "M" suffixes in the table view.
# A session that was restarted on another tier shows both models, comma-joined.
# Totals at the bottom are grouped by model.

set -euo pipefail

DAYS=14 DIR_FILTER="" ALL=0 TSV=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --dir)  DIR_FILTER="$2"; shift 2 ;;
    --all)  ALL=1; shift ;;
    --tsv)  TSV=1; shift ;;
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {sub(/^# ?/, ""); print}' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
command -v jq >/dev/null || { echo "error: jq required" >&2; exit 1; }

PROJECTS="$HOME/.claude/projects"
[[ -d "$PROJECTS" ]] || { echo "no transcripts under $PROJECTS" >&2; exit 0; }

cutoff=0
(( ALL )) || cutoff=$(( $(date +%s) - DAYS*86400 ))

# One row per session: tab-separated raw values.
rows() {
  local f sid mtime
  for f in "$PROJECTS"/*/*.jsonl; do
    [[ -f "$f" ]] || continue
    sid="$(basename "$f" .jsonl)"
    [[ "$sid" =~ ^[0-9a-f-]{36}$ ]] || continue          # skip .orphaned-* copies
    mtime="$(stat -c %Y "$f")"
    (( mtime >= cutoff )) || continue
    # Only lines with usage; one jq pass per file, reduce to a single row.
    jq -r --arg sid "$sid" --arg mtime "$mtime" '
      reduce (inputs | select(.type=="assistant" and (.message.usage? != null))) as $m
        ( {turns:0, inp:0, out:0, cr:0, cw:0, models:{}, efforts:{}, cwd:"", title:""};
          .turns += 1
          | .inp += ($m.message.usage.input_tokens // 0)
          | .out += ($m.message.usage.output_tokens // 0)
          | .cr  += ($m.message.usage.cache_read_input_tokens // 0)
          | .cw  += ($m.message.usage.cache_creation_input_tokens // 0)
          | .models[($m.message.model // "?")] = 1
          | .efforts[($m.effort // "?")] = 1
          | .cwd = (if .cwd == "" then ($m.cwd // "") else .cwd end) )
      | select(.turns > 0)
      | [ $mtime, $sid, (.models|keys|join(",")), (.efforts|keys|join(",")),
          .turns, .inp, .out, .cr, .cw, .cwd ] | @tsv
    ' -n "$f" 2>/dev/null || true
  done
}

# Title: /rename custom title > AI title > first prompt. Same precedence as spawn.sh.
title_of() {
  local f="$1" sid="$2" t
  t="$(jq -r 'select(.type=="custom-title") | .customTitle' "$f" 2>/dev/null | tail -n1)"
  [[ -n "$t" ]] || t="$(jq -r 'select(.type=="ai-title") | .aiTitle' "$f" 2>/dev/null | tail -n1)"
  [[ -n "$t" ]] || t="$(jq -r --arg sid "$sid" 'select(.sessionId==$sid) | .display' "$HOME/.claude/history.jsonl" 2>/dev/null | head -n1 | cut -c1-70)"
  printf '%s' "${t:-(untitled)}"
}

short_model() {  # claude-sonnet-5-5 -> sonnet-5-5 ; keeps unknown names as-is
  sed -E 's/claude-//g'
}

fmt_n() {  # 1234567 -> 1.2M, 12345 -> 12k
  awk -v n="$1" 'BEGIN{ if (n>=1e6) printf "%.1fM", n/1e6; else if (n>=1e3) printf "%.0fk", n/1e3; else printf "%d", n }'
}

all_rows="$(rows | sort -n)"
[[ -n "$all_rows" ]] || { echo "no sessions with usage in the window" >&2; exit 0; }

if (( TSV )); then
  while IFS=$'\t' read -r mtime sid models efforts turns inp out cr cw cwd; do
    [[ -z "$DIR_FILTER" || "$cwd" == *"$DIR_FILTER"* ]] || continue
    f="$(ls "$PROJECTS"/*/"$sid".jsonl 2>/dev/null | head -n1)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -d "@$mtime" '+%Y-%m-%dT%H:%M')" "$sid" "$models" "$efforts" "$turns" "$inp" "$out" "$cr" "$cw" "$cwd" "$(title_of "$f" "$sid")"
  done <<<"$all_rows"
  exit 0
fi

printf '%-16s %-8s %-22s %-11s %5s %7s %7s %7s %7s  %-20s %s\n' \
  "last activity" "id" "model" "effort" "turns" "input" "output" "cache-r" "cache-w" "project" "title"
declare -A T_IN T_OUT T_CR T_CW T_N
while IFS=$'\t' read -r mtime sid models efforts turns inp out cr cw cwd; do
  [[ -z "$DIR_FILTER" || "$cwd" == *"$DIR_FILTER"* ]] || continue
  f="$(ls "$PROJECTS"/*/"$sid".jsonl 2>/dev/null | head -n1)"
  m="$(printf '%s' "$models" | short_model)"
  printf '%-16s %-8s %-22s %-11s %5s %7s %7s %7s %7s  %-20s %s\n' \
    "$(date -d "@$mtime" '+%Y-%m-%d %H:%M')" "${sid:0:8}" "${m:0:22}" "${efforts:0:11}" "$turns" \
    "$(fmt_n "$inp")" "$(fmt_n "$out")" "$(fmt_n "$cr")" "$(fmt_n "$cw")" \
    "$(basename "${cwd:-?}" | cut -c1-20)" "$(title_of "$f" "$sid" | cut -c1-50)"
  T_IN[$m]=$(( ${T_IN[$m]:-0} + inp )); T_OUT[$m]=$(( ${T_OUT[$m]:-0} + out ))
  T_CR[$m]=$(( ${T_CR[$m]:-0} + cr ));  T_CW[$m]=$(( ${T_CW[$m]:-0} + cw ))
  T_N[$m]=$(( ${T_N[$m]:-0} + 1 ))
done <<<"$all_rows"

echo
window="last $DAYS days"; (( ALL )) && window="all time"
echo "totals by model ($window):"
printf '  %-22s %8s %9s %9s %9s %9s\n' "model" "sessions" "input" "output" "cache-r" "cache-w"
for m in "${!T_N[@]}"; do
  printf '  %-22s %8s %9s %9s %9s %9s\n' "$m" "${T_N[$m]}" \
    "$(fmt_n "${T_IN[$m]}")" "$(fmt_n "${T_OUT[$m]}")" "$(fmt_n "${T_CR[$m]}")" "$(fmt_n "${T_CW[$m]}")"
done | sort
