#!/usr/bin/env bash
# List / stop Claude Code sessions on this machine, phone-friendly.
#
# Usage:
#   sessions.sh [list]            running sessions: id, kind, status, age, cwd, name, RC url
#   sessions.sh url <id>          Remote Control URL for a background session
#   sessions.sh stop <id>...      stop background session(s); transcript kept.
#                                 Refuses the hub unless --force is given.
#   sessions.sh stop-idle         stop every idle background session except the hub
#   sessions.sh json              raw `claude agents --json`
#
# Background sessions have an 8-hex id usable with claude attach/logs/stop.
# Interactive (terminal) sessions have only a pid; they cannot be stopped here.

set -euo pipefail
HUB_ID="$(tr -d '[:space:]' <"$HOME/.config/claude-hub/hub.id" 2>/dev/null || true)"

strip_ansi() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g'; }
rc_url() {
  local b
  b="$(grep -l "\"jobId\":\"$1\"" "$HOME"/.claude/sessions/*.json 2>/dev/null | head -1)"
  if [[ -n "$b" ]]; then
    b="$(sed -n 's/.*"bridgeSessionId":"\([^"]*\)".*/\1/p' "$b")"
    [[ -n "$b" ]] && { echo "https://claude.ai/code/$b"; return; }
  fi
  claude logs "$1" 2>/dev/null | strip_ansi | grep -o 'https://claude\.ai/code/session_[A-Za-z0-9]*' | head -1 || true
}

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
  # Source of truth: ~/.claude/sessions/<pid>.json (one per live CLI process).
  # bridgeSessionId gives the Remote Control URL for bg AND terminal sessions.
  python3 - "$HUB_ID" "$HOME/.claude/daemon/roster.json" "$HOME"/.claude/sessions/*.json <<'PYEOF' | column -t -s $'\t'
import json, os, sys, time
hub, roster_path, files = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    workers = json.load(open(roster_path)).get("workers", {})
except Exception:
    workers = {}
def rc_name(job):
    f = workers.get(job, {}).get("dispatch", {}).get("respawnFlags", [])
    if "--remote-control" in f:
        i = f.index("--remote-control")
        if i + 1 < len(f) and not f[i + 1].startswith("--"):
            return f[i + 1]
    return ""
rows = []
now = time.time()
for path in files:
    try:
        d = json.load(open(path))
    except Exception:
        continue
    pid = d.get("pid")
    if not pid or not os.path.exists(f"/proc/{pid}"):
        continue
    kind = "bg" if d.get("kind") == "bg" else "term"
    ident = d.get("jobId") or f"pid{pid}"
    age = int((now - d.get("startedAt", now * 1000) / 1000) / 60)
    age = f"{age}m" if age < 120 else f"{age//60}h"
    cwd = d.get("cwd", "").replace(os.path.expanduser("~"), "~")
    name = rc_name(ident) if kind == "bg" else ""
    title = d.get("name", "")
    label = name or title
    if name and title and title != name and title != ident:
        label = f"{name} · {title}"
    if ident == hub:
        label += " (hub)"
    bsid = d.get("bridgeSessionId", "")
    url = f"https://claude.ai/code/{bsid}" if bsid else ""
    rows.append((d.get("startedAt", 0), [ident, kind, d.get("status", "?"), age, cwd, label, url]))
if not rows:
    print("no sessions"); sys.exit()
print("\t".join(["id", "kind", "status", "age", "cwd", "name", "url"]))
for _, r in sorted(rows):
    print("\t".join(r))
PYEOF
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
  stop)      shift; force=0; [[ "${1:-}" == --force ]] && { force=1; shift; }
             [[ $# -gt 0 ]] || { echo "usage: sessions.sh stop [--force] <id>..." >&2; exit 2; }
             for id in "$@"; do
               if [[ "$id" == "$HUB_ID" && $force -eq 0 ]]; then
                 echo "refusing to stop hub $id (use --force; the watchdog timer would restart it anyway)" >&2; continue
               fi
               claude stop "$id"
             done ;;
  stop-idle) ids="$(idle_bg_ids)"; [[ -n "$ids" ]] || { echo "nothing idle"; exit 0; }
             for id in $ids; do claude stop "$id"; done ;;
  -h|--help) sed -n '2,12p' "$0" ;;
  *) echo "unknown: $1" >&2; exit 2 ;;
esac
