#!/bin/bash
# tests/test-launcher.sh — tests for hooks/run-hook.cmd (polyglot launcher)
# and hooks/hooks.json wiring. Plain bash, bash 3.2 safe. Sandbox via mktemp -d.
# Usage: bash tests/test-launcher.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

LAUNCHER="$REPO_ROOT/hooks/run-hook.cmd"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

[ -f "$LAUNCHER" ] && pass "launcher exists" || fail "launcher exists"

# --- launcher behavior: copy into a temp dir next to a probe script
mkdir -p "$SANDBOX/h"
cp "$LAUNCHER" "$SANDBOX/h/run-hook.cmd" 2>/dev/null
cat > "$SANDBOX/h/probe" <<'PROBE'
#!/bin/bash
echo "$*"
cat
exit "${PROBE_EXIT:-0}"
PROBE
OUT="$(bash "$SANDBOX/h/run-hook.cmd" probe a b <<<'{}' 2>&1)"
check "args and stdin pass through" "a b
{}" "$OUT"

PROBE_EXIT=3 bash "$SANDBOX/h/run-hook.cmd" probe </dev/null >/dev/null 2>&1
check "exit code propagates" "3" "$?"

# --- executable bit
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "SKIP: launcher executable bit (Git Bash derives -x from extension/shebang; run-hook.cmd starts with ':'; the git index mode is checked below)"
    [ "$(git -C "$(dirname "$LAUNCHER")" ls-files -s -- "$(basename "$LAUNCHER")" | cut -c1-6)" = "100755" ] \
      && pass "launcher is 100755 in the git index" || fail "launcher mode in git index" ;;
  *) [ -x "$LAUNCHER" ] && pass "launcher is executable" || fail "launcher is executable" ;;
esac

# --- hooks.json
if [ -f "$HOOKS_JSON" ]; then
  if grep -q '\.sh' "$HOOKS_JSON"; then fail "hooks.json contains no .sh"; else pass "hooks.json contains no .sh"; fi
  BAD=""
  for s in $(grep -o 'run-hook\.cmd\\" [a-z-]*' "$HOOKS_JSON" | sed 's/.* //'); do
    case "$s" in session-start|check-close|check-brief|metrics-event) ;; *) BAD="$BAD $s" ;; esac
  done
  N="$(grep -c 'run-hook\.cmd' "$HOOKS_JSON")"
  [ -z "$BAD" ] && [ "$N" = "7" ] && pass "hooks.json names only allowed scripts (7 entries)" || fail "hooks.json scripts (bad:[$BAD] entries:$N)"
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$HOOKS_JSON" >/dev/null 2>&1 && pass "hooks.json parses as JSON" || fail "hooks.json parses as JSON"
    check "SessionStart rules group matcher (includes resume)" "startup|resume|clear|compact" \
      "$(jq -r '[.hooks.SessionStart[] | select(any(.hooks[]; (.command | test("run-hook\\.cmd\\\" session-start$")))) | .matcher] | first' "$HOOKS_JSON" 2>/dev/null)"
    check "SessionStart metrics group has no matcher" "true" \
      "$(jq -r '[.hooks.SessionStart[] | select(any(.hooks[]; (.command | test("metrics-event session-start$")))) | has("matcher")] | first | not' "$HOOKS_JSON" 2>/dev/null)"
    check "SessionStart groups do not mix rules and metrics" "2" \
      "$(jq -r '.hooks.SessionStart | length' "$HOOKS_JSON" 2>/dev/null)"
  else
    echo "SKIP: jq missing, JSON assertions skipped"
  fi
else
  fail "hooks.json exists"
fi

echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
