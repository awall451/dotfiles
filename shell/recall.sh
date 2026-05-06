#
# recall — terminal reminder CLI + morning briefing.
# Sourced from shell/bashrc.
#
# Subcommands:
#   recall                          interactive prompt
#   recall <text>...                save reminder, due tomorrow
#   recall --when "<phrase>" <text> save with natural-language due date
#   recall list | ls                list open reminders
#   recall done <id-or-prefix>      mark done (moves to archive)
#   recall show | briefing          print briefing now
#   recall help                     usage
#
# State lives in $RECALL_HOME (default: ~/.local/share/recall).
# Briefing fires from the bashrc hook on the first interactive shell of each
# new calendar day, but only after $RECALL_BRIEFING_AFTER (default 05:00).

RECALL_HOME="${RECALL_HOME:-$HOME/.local/share/recall}"
RECALL_BRIEFING_AFTER="${RECALL_BRIEFING_AFTER:-05:00}"

__recall_have_jq() { command -v jq >/dev/null 2>&1; }

__recall_ensure_dir() {
    [[ -d "$RECALL_HOME" ]] || mkdir -p "$RECALL_HOME"
}

__recall_id() {
    LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 5
}

__recall_today() {
    local t
    printf -v t '%(%Y-%m-%d)T' -1
    printf '%s' "$t"
}

# Translate a natural-language phrase to YYYY-MM-DD on stdout.
# Maps a small alias table, then defers to `date -d` for everything else.
# Returns 1 on parse failure.
__recall_parse_when() {
    local phrase="${1:-tomorrow}"
    local lower
    lower="$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        ""|"tomorrow")                                  phrase="tomorrow" ;;
        "today"|"now")                                  phrase="today" ;;
        "next week"|"start of next week"|"beginning of next week") phrase="next monday" ;;
        "end of week"|"end of this week")               phrase="friday" ;;
        "end of next week")                             phrase="next friday" ;;
        "weekend"|"this weekend")                       phrase="saturday" ;;
        "next weekend")                                 phrase="next saturday" ;;
        "in "*)                                         phrase="${lower#in }" ;;
    esac
    local out
    out="$(date -d "$phrase" +%Y-%m-%d 2>/dev/null)" || return 1
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
}

# Render a YYYY-MM-DD due date as a human-relative string.
__recall_relative() {
    local due="$1"
    local today_epoch due_epoch diff
    today_epoch="$(date -d "$(__recall_today)" +%s 2>/dev/null)" || { printf '%s' "$due"; return; }
    due_epoch="$(date -d "$due" +%s 2>/dev/null)" || { printf '%s' "$due"; return; }
    diff=$(( (due_epoch - today_epoch) / 86400 ))
    if   (( diff < -1 )); then printf 'overdue %d days' "$(( -diff ))"
    elif (( diff == -1 )); then printf 'overdue 1 day'
    elif (( diff == 0 )); then printf 'due today'
    elif (( diff == 1 )); then printf 'due tomorrow'
    else                       printf 'due in %d days' "$diff"
    fi
}

__recall_add() {
    local when_phrase="tomorrow" text=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --when)    when_phrase="$2"; shift 2 ;;
            --when=*)  when_phrase="${1#--when=}"; shift ;;
            *)         text="${text:+$text }$1"; shift ;;
        esac
    done

    if [[ -z "$text" ]]; then
        printf 'What to remember? '
        IFS= read -r text
        [[ -z "$text" ]] && { printf 'recall: empty reminder, nothing saved.\n' >&2; return 1; }
        printf 'When? [%s] ' "$when_phrase"
        local user_when
        IFS= read -r user_when
        [[ -n "$user_when" ]] && when_phrase="$user_when"
    fi

    if ! __recall_have_jq; then
        printf 'recall: jq is required. Install with: sudo apt install jq\n' >&2
        return 1
    fi

    local due
    if ! due="$(__recall_parse_when "$when_phrase")"; then
        printf 'recall: could not parse date phrase: %s\n' "$when_phrase" >&2
        return 1
    fi

    __recall_ensure_dir
    local id created
    id="$(__recall_id)"
    created="$(date -Iseconds)"

    jq -nc \
        --arg id      "$id" \
        --arg created "$created" \
        --arg due     "$due" \
        --arg text    "$text" \
        '{id:$id, created_at:$created, due:$due, text:$text}' \
        >> "$RECALL_HOME/reminders.jsonl"

    printf 'saved [%s] — %s (%s)\n' "$id" "$due" "$(__recall_relative "$due")"
}

__recall_list() {
    __recall_have_jq || { printf 'recall: jq required.\n' >&2; return 1; }
    __recall_ensure_dir
    local file="$RECALL_HOME/reminders.jsonl"
    if [[ ! -s "$file" ]]; then
        printf 'No open reminders.\n'
        return 0
    fi
    local rows
    rows="$(jq -rs 'sort_by(.due)[] | "\(.id)\t\(.due)\t\(.text)"' "$file")"
    if [[ -z "$rows" ]]; then
        printf 'No open reminders.\n'
        return 0
    fi
    local id due text
    while IFS=$'\t' read -r id due text; do
        printf '  [%s] %-40s %s\n' "$id" "$text" "$(__recall_relative "$due")"
    done <<< "$rows"
}

__recall_done() {
    local prefix="$1"
    if [[ -z "$prefix" ]]; then
        printf 'usage: recall done <id-or-prefix>\n' >&2
        return 1
    fi
    __recall_have_jq || { printf 'recall: jq required.\n' >&2; return 1; }
    __recall_ensure_dir
    local file="$RECALL_HOME/reminders.jsonl"
    [[ -s "$file" ]] || { printf 'recall: no open reminders.\n' >&2; return 1; }

    local matches count
    matches="$(jq -rc --arg p "$prefix" 'select(.id|startswith($p))' "$file")"
    count=0
    [[ -n "$matches" ]] && count="$(printf '%s\n' "$matches" | grep -c .)"

    if (( count == 0 )); then
        printf 'recall: no reminder with id prefix %q\n' "$prefix" >&2
        return 1
    elif (( count > 1 )); then
        printf 'recall: prefix %q matches multiple reminders, be more specific:\n' "$prefix" >&2
        printf '%s\n' "$matches" | jq -r '"  [\(.id)] \(.text)"' >&2
        return 1
    fi

    local matched_id done_at
    matched_id="$(printf '%s' "$matches" | jq -r .id)"
    done_at="$(date -Iseconds)"

    printf '%s\n' "$matches" | jq -c --arg done_at "$done_at" '. + {done_at:$done_at}' \
        >> "$RECALL_HOME/archive.jsonl"

    local tmp
    tmp="$(mktemp "$RECALL_HOME/.reminders.XXXXXX")" || return 1
    jq -c --arg id "$matched_id" 'select(.id != $id)' "$file" > "$tmp"
    mv "$tmp" "$file"

    printf 'done [%s]\n' "$matched_id"
}

# Print the briefing block to stdout. Silent (no output) if nothing is due.
__recall_show() {
    __recall_have_jq || return 0
    __recall_ensure_dir
    local file="$RECALL_HOME/reminders.jsonl"
    [[ -s "$file" ]] || return 0
    local today
    today="$(__recall_today)"
    local rows
    rows="$(jq -rsc --arg t "$today" \
        '[.[] | select(.due <= $t)] | sort_by(.due) | .[] | "\(.id)\t\(.due)\t\(.text)"' \
        "$file")"
    [[ -z "$rows" ]] && return 0

    local count
    count="$(printf '%s\n' "$rows" | grep -c .)"
    local header
    header="$(date '+%A, %B %-d')"

    printf '\n☀ %s\n\n' "$header"
    printf 'Reminders (%d):\n' "$count"
    local id due text
    while IFS=$'\t' read -r id due text; do
        printf '  [%s] %-40s %s\n' "$id" "$text" "$(__recall_relative "$due")"
    done <<< "$rows"
    printf '\n(recall done <id> to clear)\n\n'
}

# Render a sample briefing against fake reminders so you can see the format
# without touching real state.
__recall_demo() {
    if ! __recall_have_jq; then
        printf 'recall: jq required.\n' >&2
        return 1
    fi
    local tmp
    tmp="$(mktemp -d)" || return 1
    local saved_home="$RECALL_HOME"
    RECALL_HOME="$tmp"

    local today yesterday three_days_ago
    today="$(__recall_today)"
    yesterday="$(date -d 'yesterday' +%Y-%m-%d)"
    three_days_ago="$(date -d '3 days ago' +%Y-%m-%d)"

    {
        jq -nc --arg t "$today" --arg due "$three_days_ago" --arg id "demo1" \
            '{id:$id, created_at:$t, due:$due, text:"submit timesheet"}'
        jq -nc --arg t "$today" --arg due "$yesterday"      --arg id "demo2" \
            '{id:$id, created_at:$t, due:$due, text:"reply to landlord"}'
        jq -nc --arg t "$today" --arg due "$today"          --arg id "demo3" \
            '{id:$id, created_at:$t, due:$due, text:"check the mail"}'
        jq -nc --arg t "$today" --arg due "$today"          --arg id "demo4" \
            '{id:$id, created_at:$t, due:$due, text:"pick up prescription"}'
    } > "$tmp/reminders.jsonl"

    printf '(demo — fake reminders, real state untouched)\n'
    __recall_show

    RECALL_HOME="$saved_home"
    rm -rf "$tmp"
}

# Bashrc hook. Cheap fast-paths (last-shown stamp, time gate); only invokes
# jq when there's a chance something will print. Stamps the day only when a
# briefing was actually printed.
__recall_briefing_maybe() {
    [[ $- == *i* ]] || return 0
    __recall_have_jq || return 0

    local today now_hm
    today="$(__recall_today)"
    printf -v now_hm '%(%H:%M)T' -1

    [[ "$now_hm" < "$RECALL_BRIEFING_AFTER" ]] && return 0

    __recall_ensure_dir
    local stamp="$RECALL_HOME/last_shown"
    if [[ -f "$stamp" ]] && [[ "$(<"$stamp")" == "$today" ]]; then
        return 0
    fi

    local out
    out="$(__recall_show)"
    [[ -z "$out" ]] && return 0

    printf '%s' "$out"
    printf '%s' "$today" > "$stamp"
}

__recall_help() {
    cat <<'EOF'
recall — reminder CLI + morning briefing

Usage:
  recall                          interactive prompt; defaults to "tomorrow"
  recall <text>...                save reminder, due tomorrow
  recall --when "<phrase>" <text> save with natural-language due date
  recall list | ls                list open reminders, sorted by due date
  recall done <id-or-prefix>      mark a reminder done (moves to archive)
  recall show | briefing          print the morning briefing now
  recall demo                     render a sample briefing (fake data)
  recall help                     this message

Date phrases (examples):
  today, tomorrow, friday, next monday, next week,
  start of next week, end of week, in 3 days, +2 weeks

State (default ~/.local/share/recall, override via $RECALL_HOME):
  reminders.jsonl   open reminders (one JSON object per line)
  archive.jsonl     done reminders
  last_shown        date of last briefing

Env:
  RECALL_HOME              storage directory
  RECALL_BRIEFING_AFTER    earliest HH:MM the briefing fires (default 05:00)
EOF
}

recall() {
    case "$#" in
        0) __recall_add ;;
        1)
            case "$1" in
                list|ls)        __recall_list ;;
                show|briefing)  __recall_show ;;
                demo)           __recall_demo ;;
                help|-h|--help) __recall_help ;;
                done)           printf 'usage: recall done <id-or-prefix>\n' >&2; return 1 ;;
                *)              __recall_add "$@" ;;
            esac
            ;;
        2)
            case "$1" in
                done) __recall_done "$2" ;;
                *)    __recall_add "$@" ;;
            esac
            ;;
        *) __recall_add "$@" ;;
    esac
}
