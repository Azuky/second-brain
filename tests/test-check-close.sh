#!/bin/bash
# tests/test-check-close.sh — tests for hooks/check-close.
# Plain bash, bash 3.2 safe. Sandbox via mktemp -d. jq is used only if present.
# Usage: bash tests/test-check-close.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi; }
has() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (missing [$2])" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOOK="$REPO_ROOT/hooks/check-close"
[ -x "$HOOK" ] && pass "hook is executable" || fail "hook is executable"

# ago_stamp <hours> -> touch -t timestamp (YYYYMMDDhhmm), portable BSD/GNU
ago_stamp() {
  local h="$1"
  date -v-"${h}"H +%Y%m%d%H%M 2>/dev/null && return 0
  date -d "$h hours ago" +%Y%m%d%H%M 2>/dev/null && return 0
  return 1
}
OLD="$(ago_stamp 2)"
OLDER="$(ago_stamp 3)"
[ -n "$OLD" ] && [ -n "$OLDER" ] && pass "portable timestamp" || fail "portable timestamp"

HOME_D="$SANDBOX/home"
DATA="$SANDBOX/data"
REPO="$SANDBOX/repo"
CTXF="$HOME_D/vault/projects/p/CONTEXT.md"
MARK="$DATA/sessions/s1.start"
mkdir -p "$HOME_D/vault/projects/p" "$DATA/sessions" "$REPO" "$SANDBOX/bare"
echo "see ~/vault/projects/p/CONTEXT.md" > "$REPO/CLAUDE.local.md"
: > "$CTXF"

# run_hook <event> <stdin> [VAR=val ...]
run_hook() {
  local ev="$1" in="$2"; shift 2
  printf '%s' "$in" | env -i PATH="$PATH" HOME="$HOME_D" \
    CLAUDE_PLUGIN_DATA="$DATA" "$@" bash "$HOOK" "$ev"
}
IN="{\"session_id\":\"s1\",\"cwd\":\"$REPO\"}"

# Stale: CONTEXT 3h old, marker 2h old
: > "$MARK"; touch -t "$OLDER" "$CTXF"; touch -t "$OLD" "$MARK"
OUT="$(run_hook stop "$IN")"; RC=$?
check "stop stale: exit 0" "0" "$RC"
has "stop stale: block" '"decision":"block"' "$OUT"
has "stop stale: message with ~ path" "(~/vault/projects/p/CONTEXT.md)" "$OUT"
has "stop stale: close rule text" "Method close rule:" "$OUT"
has "stop stale: plugin command name" "/second-brain:close routine now:" "$OUT"
if command -v jq >/dev/null 2>&1; then
  check "stop stale: jq parses" "block" "$(printf '%s' "$OUT" | jq -r .decision 2>/dev/null)"
fi

# Fresh: CONTEXT now, marker 2h old
touch "$CTXF"
OUT="$(run_hook stop "$IN")"; RC=$?
check "stop fresh: exit 0" "0" "$RC"
check "stop fresh: no output" "" "$OUT"

# stop_hook_active
touch -t "$OLDER" "$CTXF"
OUT="$(run_hook stop "{\"session_id\":\"s1\",\"cwd\":\"$REPO\",\"stop_hook_active\":true}")"
check "stop_hook_active: no output" "" "$OUT"

# precompact stale
OUT="$(run_hook precompact "$IN")"; RC=$?
check "precompact stale: exit 0" "0" "$RC"
has "precompact: systemMessage" '"systemMessage":' "$OUT"
has "precompact: hookEventName" '"hookEventName":"PreCompact"' "$OUT"
has "precompact: path" "~/vault/projects/p/CONTEXT.md" "$OUT"
has "precompact: plugin command in message" "run /second-brain:close to persist" "$OUT"
has "precompact: plugin command in context" "per /second-brain:close:" "$OUT"
if command -v jq >/dev/null 2>&1; then
  check "precompact: jq parses" "PreCompact" "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.hookEventName 2>/dev/null)"
fi

# precompact ignores stop_hook_active
OUT="$(run_hook precompact "{\"session_id\":\"s1\",\"cwd\":\"$REPO\",\"stop_hook_active\":true}")"
has "precompact ignores stop_hook_active" "PreCompact" "$OUT"

# Compaction: session-start re-runs with same session_id; marker must stay old
: > "$MARK"; touch -t "$OLDER" "$MARK"; touch -t "$OLD" "$MARK"; touch "$CTXF"
printf '%s' "$IN" | env -i PATH="$PATH" HOME="$HOME_D" CLAUDE_PLUGIN_DATA="$DATA" \
  CLAUDE_PLUGIN_ROOT="$REPO_ROOT" bash "$REPO_ROOT/hooks/session-start" >/dev/null
OUT="$(run_hook stop "$IN")"
check "after session-start re-run: CONTEXT updated earlier, no output" "" "$OUT"

# No marker: fallback 30 min
rm -f "$MARK"
touch "$CTXF"
OUT="$(run_hook stop "$IN")"
check "no marker, CONTEXT now: no output" "" "$OUT"
touch -t "$OLD" "$CTXF"
OUT="$(run_hook stop "$IN")"
has "no marker, CONTEXT 2h ago: block" '"decision":"block"' "$OUT"

# CLAUDE_PLUGIN_DATA unset -> fallback too
OUT="$(printf '%s' "$IN" | env -i PATH="$PATH" HOME="$HOME_D" bash "$HOOK" stop)"
has "no plugin data: fallback block" '"decision":"block"' "$OUT"

# Unsafe session id -> ignored marker, fallback
: > "$MARK"; touch -t "$OLDER" "$MARK"; touch "$CTXF"
OUT="$(run_hook stop "{\"session_id\":\"../s1\",\"cwd\":\"$REPO\"}")"
check "unsafe session id: fallback, fresh CONTEXT no output" "" "$OUT"

# No CLAUDE.local.md
OUT="$(run_hook stop "{\"session_id\":\"s1\",\"cwd\":\"$SANDBOX/bare\"}")"; RC=$?
check "no CLAUDE.local.md: exit 0" "0" "$RC"
check "no CLAUDE.local.md: no output" "" "$OUT"

# Garbage stdin (cwd = $PWD of the test run, which has no method file in sandbox)
OUT="$(cd "$SANDBOX/bare" && printf '%s' 'not json {{{' | env -i PATH="$PATH" HOME="$HOME_D" CLAUDE_PLUGIN_DATA="$DATA" bash "$HOOK" stop)"; RC=$?
check "garbage stdin: exit 0" "0" "$RC"
check "garbage stdin: no output" "" "$OUT"

echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
