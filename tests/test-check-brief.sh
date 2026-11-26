#!/bin/bash
# tests/test-check-brief.sh — tests for hooks/check-brief (SubagentStop).
# Plain bash, bash 3.2 safe. Sandbox via mktemp -d. jq is used only if present.
# Usage: bash tests/test-check-brief.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FX="$SCRIPT_DIR/fixtures/transcripts"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi; }
has() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (missing [$2])" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HOOK="$REPO_ROOT/hooks/check-brief"
[ -x "$HOOK" ] && pass "hook is executable" || fail "hook is executable"

REPO="$SANDBOX/repo"
mkdir -p "$REPO" "$SANDBOX/bare"
echo "see ~/vault/projects/p/CONTEXT.md" > "$REPO/CLAUDE.local.md"

# run_hook <stdin> -> stdout; sets RC
run_hook() {
  printf '%s' "$1" | env -i PATH="$PATH" HOME="$SANDBOX/home" bash "$HOOK"
}
# in_for <fixture-or-path> [extra json]
in_for() { printf '{"session_id":"s1","cwd":"%s","agent_transcript_path":"%s"%s}' "$REPO" "$1" "${2:-}"; }

# ok -> no output
OUT="$(run_hook "$(in_for "$FX/brief-ok.jsonl")")"; RC=$?
check "ok: exit 0" "0" "$RC"
check "ok: no output" "" "$OUT"

# missing evidence -> block (decoy api-request-blob line after the report is ignored)
OUT="$(run_hook "$(in_for "$FX/brief-missing-evidence.jsonl")")"; RC=$?
check "missing evidence: exit 0" "0" "$RC"
has "missing evidence: block" '"decision":"block"' "$OUT"
has "missing evidence: reason text" "Method brief rule: the subagent report must include a Verification line" "$OUT"
has "missing evidence: escaped backticks kept" 'Verification: `<command>` -> <literal result>' "$OUT"
has "missing evidence: reask text" "re-emit the full report." "$OUT"
case "$OUT" in *"/close"*|*"/start"*) fail "no sbm command names" ;; *) pass "no sbm command names" ;; esac
if command -v jq >/dev/null 2>&1; then
  check "missing evidence: jq parses" "block" "$(printf '%s' "$OUT" | jq -r .decision 2>/dev/null)"
  has "missing evidence: jq reason" "Criteria evidence" "$(printf '%s' "$OUT" | jq -r .reason 2>/dev/null)"
fi

# no brief -> no output even though the report lacks evidence
OUT="$(run_hook "$(in_for "$FX/no-brief.jsonl")")"
check "no brief: no output" "" "$OUT"

# last assistant line is a tool_use -> judged on the previous text line (ok)
OUT="$(run_hook "$(in_for "$FX/brief-last-is-tool-use.jsonl")")"
check "last is tool_use: judged on text line" "" "$OUT"

# content as plain string -> handled (ok)
OUT="$(run_hook "$(in_for "$FX/brief-content-string.jsonl")")"
check "content string: handled" "" "$OUT"

# content string without evidence -> block
sed 's/Criteria evidence/Notes/' "$FX/brief-content-string.jsonl" > "$SANDBOX/str-bad.jsonl"
OUT="$(run_hook "$(in_for "$SANDBOX/str-bad.jsonl")")"
has "content string missing evidence: block" '"decision":"block"' "$OUT"

# ASCII arrow and spaced-colon JSON formatting are tolerated
sed 's/\\u2192/->/' "$FX/brief-ok.jsonl" > "$SANDBOX/ascii.jsonl"
OUT="$(run_hook "$(in_for "$SANDBOX/ascii.jsonl")")"
check "ascii arrow: ok" "" "$OUT"
sed -e 's/"role":"/"role": "/g' -e 's/"type":"/"type": "/g' -e 's/"text":"/"text": "/g' "$FX/brief-ok.jsonl" > "$SANDBOX/spaced.jsonl"
OUT="$(run_hook "$(in_for "$SANDBOX/spaced.jsonl")")"
check "spaced colons: ok" "" "$OUT"
sed -e 's/"role":"/"role": "/g' -e 's/"type":"/"type": "/g' -e 's/"text":"/"text": "/g' "$FX/brief-missing-evidence.jsonl" > "$SANDBOX/spaced-bad.jsonl"
OUT="$(run_hook "$(in_for "$SANDBOX/spaced-bad.jsonl")")"
has "spaced colons: block" '"decision":"block"' "$OUT"

# Verification without a result after the arrow -> block
sed 's/ 3 passed, 0 failed//' "$FX/brief-ok.jsonl" > "$SANDBOX/noresult.jsonl"
OUT="$(run_hook "$(in_for "$SANDBOX/noresult.jsonl")")"
has "arrow without result: block" '"decision":"block"' "$OUT"

# stop_hook_active true -> no output
OUT="$(run_hook "$(in_for "$FX/brief-missing-evidence.jsonl" ',"stop_hook_active":true')")"
check "stop_hook_active: no output" "" "$OUT"

# missing agent_transcript_path -> no output
OUT="$(run_hook "{\"cwd\":\"$REPO\"}")"; RC=$?
check "no transcript path: exit 0" "0" "$RC"
check "no transcript path: no output" "" "$OUT"

# unreadable / nonexistent file -> no output
OUT="$(run_hook "$(in_for "$SANDBOX/nope.jsonl")")"; RC=$?
check "missing file: exit 0" "0" "$RC"
check "missing file: no output" "" "$OUT"

# repo without CLAUDE.local.md -> no output
OUT="$(run_hook "$(printf '{"cwd":"%s","agent_transcript_path":"%s"}' "$SANDBOX/bare" "$FX/brief-missing-evidence.jsonl")")"
check "no CLAUDE.local.md: no output" "" "$OUT"

# garbage stdin -> exit 0 silent (cwd falls back to PWD, which has no CLAUDE.local.md here)
OUT="$(cd "$SANDBOX/bare" && printf 'not json {{{' | env -i PATH="$PATH" HOME="$SANDBOX/home" bash "$HOOK")"; RC=$?
check "garbage: exit 0" "0" "$RC"
check "garbage: no output" "" "$OUT"
OUT="$(cd "$REPO" && printf '\377\376 garbage' | env -i PATH="$PATH" HOME="$SANDBOX/home" bash "$HOOK")"; RC=$?
check "garbage in method repo: exit 0" "0" "$RC"
check "garbage in method repo: no output" "" "$OUT"
OUT="$(printf '' | env -i PATH="$PATH" HOME="$SANDBOX/home" bash "$HOOK")"; RC=$?
check "empty stdin: exit 0" "0" "$RC"

# large transcript (thousands of lines) is judged quickly, on the last text line
BIG="$SANDBOX/big.jsonl"
{
  sed -n 1p "$FX/brief-ok.jsonl"
  _i=0
  while [ "$_i" -lt 2250 ]; do
    sed -n 2,3p "$FX/brief-ok.jsonl"
    _i=$((_i + 1))
  done
  sed -n 5p "$FX/brief-ok.jsonl"
} > "$BIG"
T0="$(date +%s)"
OUT="$(run_hook "$(in_for "$BIG")")"
T1="$(date +%s)"
check "large transcript: ok, no output" "" "$OUT"
[ $((T1 - T0)) -le 2 ] && pass "large transcript: under 2s" || fail "large transcript: took $((T1 - T0))s"

# same results under /bin/bash (3.2 on macOS)
if [ -x /bin/bash ]; then
  OUT="$(in_for "$FX/brief-missing-evidence.jsonl" | env -i PATH="$PATH" HOME="$SANDBOX/home" /bin/bash "$HOOK")"
  has "/bin/bash: block" '"decision":"block"' "$OUT"
  OUT="$(in_for "$FX/brief-ok.jsonl" | env -i PATH="$PATH" HOME="$SANDBOX/home" /bin/bash "$HOOK")"
  check "/bin/bash: ok" "" "$OUT"
fi

echo
echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
