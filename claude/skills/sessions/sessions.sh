#!/usr/bin/env bash
# List / stop Claude Code sessions on this machine, phone-friendly.
#
# Usage:
#   sessions.sh [list]            running sessions: id, kind, status, age, cwd, name, RC url
#   sessions.sh url <id>          Remote Control URL for a background session
#   sessions.sh stop <id>...      stop background session(s); transcript kept
#   sessions.sh stop-idle         stop every idle background session except the hub
#   sessions.sh json              raw `claude agents --json`
#
# Background sessions have an 8-hex id usable with claude attach/logs/stop.
# Interactive (terminal) sessions have only a pid; they cannot be stopped here.

set -euo pipefail
HUB_ID="$(tr -d '[:space:]' <"$HOME/.config/claude-hub/hub.id" 2>/dev/null || true)"

strip_ansi() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
rc_url() { claude logs "$1" 2>/dev/null | strip_ansi | grep -o 'https://claude\.ai/code/session_[A-Za-z0-9]*' | tail -1 || true; }

# Remote Control display name, from the daemon roster's saved flags.
rc_name() {
  python3 -c '
import json,sys
try:
    w=json.load(open(sys.argv[1]))["workers"].get(sys.argv[2],{})
    f=w.get("dispatch",{}).get("respawnFlags",[])
    i=f.index("--remote-control"); print(f[i+1] if i+1<len(f) and not f[i+1].startswith("--") else "")
except Exception: pass' "$HOME/.claude/daemon/roster.json" "$1" 2>/dev/null || true
}

agents_json() { claude agents --json 2>/dev/null || echo '[]'; }

list() {
  local rows
  rows="$(agents_json | python3 -c '
import json,sys,time,os
now=time.time()
hub=sys.argv[1]
for a in json.load(sys.stdin):
    kind=a.get("kind","?")
    if kind=="background" and not a.get("pid"):
        continue  # exited; `claude agents --json --all` would show it
    ident=a.get("id") or "pid%s" % a.get("pid")
    st=a.get("status") or a.get("state") or "?"
    age=int((now-a.get("startedAt",now*1000)/1000)/60)
    age=f"{age}m" if age<120 else f"{age//60}h"
    cwd=a.get("cwd","").replace(os.path.expanduser("~"),"~")
    name=a.get("name","")
    tag=" (hub)" if ident==hub else ""
    print("\t".join([ident,"bg" if kind=="background" else "term",st,age,cwd,name+tag]))
' "$HUB_ID")"
  [[ -n "$rows" ]] || { echo "no sessions"; return 0; }
  {
    printf 'id\tkind\tstatus\tage\tcwd\tname\turl\n'
    while IFS=$'\t' read -r id kind st age cwd name; do
      url=""
      if [[ "$kind" == bg ]]; then
        url="$(rc_url "$id")"
        rc="$(rc_name "$id")"; [[ -n "$rc" ]] && name="$rc${name#"$id"}"
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$kind" "$st" "$age" "$cwd" "$name" "$url"
    done <<<"$rows"
  } | column -t -s $'\t'
}

idle_bg_ids() {
  agents_json | python3 -c '
import json,sys
hub=sys.argv[1]
for a in json.load(sys.stdin):
    if a.get("kind")=="background" and a.get("pid") and a.get("id")!=hub and a.get("status")=="idle":
        print(a["id"])' "$HUB_ID"
}

case "${1:-list}" in
  list)      list ;;
  json)      agents_json ;;
  url)       [[ -n "${2:-}" ]] || { echo "usage: sessions.sh url <id>" >&2; exit 2; }; rc_url "$2" ;;
  stop)      shift; [[ $# -gt 0 ]] || { echo "usage: sessions.sh stop <id>..." >&2; exit 2; }
             for id in "$@"; do claude stop "$id"; done ;;
  stop-idle) ids="$(idle_bg_ids)"; [[ -n "$ids" ]] || { echo "nothing idle"; exit 0; }
             for id in $ids; do claude stop "$id"; done ;;
  -h|--help) sed -n '2,12p' "$0" ;;
  *) echo "unknown: $1" >&2; exit 2 ;;
esac
