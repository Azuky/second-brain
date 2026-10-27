#!/bin/bash
# tests/test-session-start.sh — tests for hooks/session-start and method/rules.md.
# Plain bash, bash 3.2 safe. Sandbox via mktemp -d. jq is used only if present.
# Usage: bash tests/test-session-start.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi; }
has() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (missing [$2])" ;; esac; }
hasnt() { case "$3" in *"$2"*) fail "$1 (unexpected [$2])" ;; *) pass "$1" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOOK="$REPO_ROOT/hooks/session-start"
RULES="$REPO_ROOT/method/rules.md"

[ -x "$HOOK" ] && pass "hook is executable" || fail "hook is executable"
[ -f "$RULES" ] && pass "rules.md exists" || fail "rules.md exists"
if grep -q '@@' "$RULES" 2>/dev/null; then fail "rules.md has no @@"; else pass "rules.md has no @@"; fi

VAULT="$SANDBOX/my vault"
mkdir -p "$VAULT/projects" "$SANDBOX/home" "$SANDBOX/data"

# run_hook <stdin> [VAR=val ...]
run_hook() {
  local in="$1"; shift
  printf '%s' "$in" | env -i PATH="$PATH" HOME="$SANDBOX/home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PLUGIN_DATA="$SANDBOX/data" \
    CLAUDE_PLUGIN_OPTION_VAULT="$VAULT" "$@" bash "$HOOK"
}

OUT="$(run_hook '{"session_id":"abc"}')"; RC=$?
check "normal: exit 0" "0" "$RC"
case "$OUT" in '{"hookSpecificOutput":'*) pass "normal: JSON shape" ;; *) fail "normal: JSON shape" ;; esac
has "normal: vault line (with spaces)" "Vault: $VAULT" "$OUT"
has "normal: method docs line" "Method docs: $REPO_ROOT/method" "$OUT"
has "normal: rules heading" "Always-active rules" "$OUT"
hasnt "normal: no not-set-up line" "not set up" "$OUT"
hasnt "normal: no old-sbm line" "Old sbm" "$OUT"
[ -f "$SANDBOX/data/sessions/abc.start" ] && pass "marker written" || fail "marker written"

if command -v jq >/dev/null 2>&1; then
  CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
  has "jq: additionalContext has rules" "Always-active rules" "$CTX"
  has "jq: vault path round-trips" "Vault: $VAULT" "$CTX"
  check "jq: event name" "SessionStart" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName')"
  N="$(printf '%s' "$CTX" | wc -c | tr -d ' ')"
  [ "$N" -lt 4000 ] && pass "size < 4000 ($N chars)" || fail "size < 4000 ($N chars)"
else
  echo "SKIP: jq not installed"
fi
N="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
[ "$N" -lt 4000 ] && pass "raw output < 4000 ($N bytes)" || fail "raw output < 4000 ($N bytes)"

OUT="$(run_hook '{"session_id":"x"}' CLAUDE_PLUGIN_OPTION_VAULT=)"; RC=$?
check "empty vault: exit 0" "0" "$RC"
has "empty vault: setup hint" "run /second-brain:setup" "$OUT"
has "empty vault: points to /config" 'Vault folder\" is not set' "$OUT"
has "empty vault: config guidance" "/config" "$OUT"
hasnt "empty vault: no not-set-up line" "not set up" "$OUT"
N="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
[ "$N" -lt 4000 ] && pass "empty vault: output < 4000 ($N bytes)" || fail "empty vault: output < 4000 ($N bytes)"

OUT="$(run_hook '{}' CLAUDE_PLUGIN_OPTION_VAULT="$SANDBOX/nope")"
has "vault without projects/: setup hint" "run /second-brain:setup" "$OUT"
has "vault without projects/: not set up line" "Second brain not set up" "$OUT"
hasnt "vault without projects/: no /config line" "is not set" "$OUT"

mkdir -p "$SANDBOX/ch/.second-brain"; : > "$SANDBOX/ch/.second-brain/config.json"
OUT="$(run_hook '{}' CLAUDE_HOME="$SANDBOX/ch")"
has "old sbm config.json: warning" "Old sbm install detected" "$OUT"
rm -f "$SANDBOX/ch/.second-brain/config.json"; : > "$SANDBOX/ch/.second-brain/config"
OUT="$(run_hook '{}' CLAUDE_HOME="$SANDBOX/ch")"
has "legacy sbm config: warning" "Old sbm install detected" "$OUT"

rm -rf "$SANDBOX/data"; mkdir -p "$SANDBOX/data"
OUT="$(run_hook 'not json {{{')"; RC=$?
check "garbage stdin: exit 0" "0" "$RC"
has "garbage stdin: rules emitted" "Always-active rules" "$OUT"
[ -z "$(ls "$SANDBOX/data/sessions" 2>/dev/null)" ] && pass "garbage stdin: no marker" || fail "garbage stdin: no marker"

OUT="$(run_hook '{"session_id":"q"}' CLAUDE_PLUGIN_DATA=)"; RC=$?
check "no plugin data: exit 0" "0" "$RC"
has "no plugin data: rules emitted" "Always-active rules" "$OUT"

OUT="$(printf '{}' | env -i PATH="$PATH" HOME="$SANDBOX/home" CLAUDE_PLUGIN_OPTION_VAULT="$VAULT" bash "$HOOK")"
has "no PLUGIN_ROOT: derived from script dir" "Method docs: $REPO_ROOT/hooks/../method" "$OUT"
has "no PLUGIN_ROOT: rules emitted" "Always-active rules" "$OUT"

run_hook '{"session_id":"old1"}' >/dev/null
touch -t 202001010000 "$SANDBOX/data/sessions/old1.start"
run_hook '{"session_id":"new1"}' >/dev/null
[ ! -f "$SANDBOX/data/sessions/old1.start" ] && pass "old markers cleaned" || fail "old markers cleaned"
[ -f "$SANDBOX/data/sessions/new1.start" ] && pass "new marker kept" || fail "new marker kept"

# marker survives a repeated SessionStart (compact) with its mtime intact
TWO_H="$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M 2>/dev/null)"
run_hook '{"session_id":"keep1"}' >/dev/null
touch -t "$TWO_H" "$SANDBOX/data/sessions/keep1.start"
run_hook '{"session_id":"keep1"}' >/dev/null
if [ -f "$SANDBOX/data/sessions/keep1.start" ] && [ -z "$(find "$SANDBOX/data/sessions/keep1.start" -mmin -60 2>/dev/null)" ]; then
  pass "marker mtime kept on re-run"
else
  fail "marker mtime kept on re-run"
fi

# CLAUDE_CONFIG_DIR is the fallback for the old-sbm check when CLAUDE_HOME is unset
mkdir -p "$SANDBOX/cfg/.second-brain"; : > "$SANDBOX/cfg/.second-brain/config.json"
OUT="$(run_hook '{"session_id":"cfg1"}' CLAUDE_CONFIG_DIR="$SANDBOX/cfg")"
has "CLAUDE_CONFIG_DIR: old sbm detected" "Old sbm install detected" "$OUT"

# stale *.reminded flags are pruned like *.start
: > "$SANDBOX/data/sessions/old1.reminded"; : > "$SANDBOX/data/sessions/fresh1.reminded"
touch -t 200001010000 "$SANDBOX/data/sessions/old1.reminded"
run_hook '{"session_id":"prune1"}' >/dev/null
[ ! -e "$SANDBOX/data/sessions/old1.reminded" ] && [ -e "$SANDBOX/data/sessions/fresh1.reminded" ] && pass "old .reminded pruned, fresh kept" || fail "reminded pruning"

# the current session's own old files survive the prune; another sid's old .reminded does not
: > "$SANDBOX/data/sessions/cur1.start"; : > "$SANDBOX/data/sessions/cur1.reminded"; : > "$SANDBOX/data/sessions/other1.reminded"
touch -t 200001010000 "$SANDBOX/data/sessions/cur1.start" "$SANDBOX/data/sessions/cur1.reminded" "$SANDBOX/data/sessions/other1.reminded"
run_hook '{"session_id":"cur1"}' >/dev/null
[ -e "$SANDBOX/data/sessions/cur1.start" ] && [ -e "$SANDBOX/data/sessions/cur1.reminded" ] && pass "current sid's old .start/.reminded survive prune" || fail "current sid files pruned"
[ ! -e "$SANDBOX/data/sessions/other1.reminded" ] && pass "other sid's old .reminded still pruned" || fail "other old .reminded kept"

echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
