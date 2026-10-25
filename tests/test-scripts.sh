#!/bin/bash
# tests/test-scripts.sh — tests for hooks/metrics-event and method/scripts/*.
# Plain bash, bash 3.2 safe. Sandbox via mktemp -d. jq-dependent checks skip
# when jq is absent.
# Usage: bash tests/test-scripts.sh   (exit 0 = all pass)

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

HOOK="$REPO_ROOT/hooks/metrics-event"
HEALTH="$REPO_ROOT/method/scripts/brain-health.sh"
METRICS="$REPO_ROOT/method/scripts/brain-metrics.sh"
COLLECT="$REPO_ROOT/method/scripts/collect-metrics.sh"
HOME_D="$SANDBOX/home"
mkdir -p "$HOME_D"

[ -x "$HOOK" ] && pass "hook is executable" || fail "hook is executable"

# PATH without jq: symlinks to the basic tools only
NOJQ="$SANDBOX/nojq-bin"
mkdir -p "$NOJQ"
for t in bash grep sed find date mkdir cat dirname head tr awk sort wc rm mktemp basename; do
  p="$(command -v "$t" 2>/dev/null)"
  [ -n "$p" ] && ln -s "$p" "$NOJQ/$t"
done

# Repo + spaced vault path
REPO="$SANDBOX/repo"
VAULT="$SANDBOX/vault"
PROJ="$VAULT/projects/p"
mkdir -p "$REPO" "$PROJ"
: > "$PROJ/CONTEXT.md"
echo "state: see $PROJ/CONTEXT.md" > "$REPO/CLAUDE.local.md"
EV="$PROJ/metrics/events.jsonl"
IN="{\"session_id\":\"s1\",\"cwd\":\"$REPO\"}"

run_hook() { # <path> <event> <stdin>
  printf '%s' "$3" | env -i PATH="$1" HOME="$HOME_D" /bin/bash "$HOOK" "$2"
}

# --- metrics-event with jq
if command -v jq >/dev/null 2>&1; then
  OUT="$(run_hook "$PATH" stop "$IN")"; RC=$?
  check "metrics-event: exit 0" "0" "$RC"
  check "metrics-event: silent" "" "$OUT"
  check "metrics-event: one line" "1" "$(wc -l < "$EV" 2>/dev/null | tr -d ' ')"
  check "metrics-event: event stop" "stop" "$(jq -r .event "$EV" 2>/dev/null)"
  check "metrics-event: session id" "s1" "$(jq -r .session_id "$EV" 2>/dev/null)"
  run_hook "$PATH" session-start "$IN" >/dev/null
  check "metrics-event: appends" "2" "$(wc -l < "$EV" | tr -d ' ')"
  rm -f "$EV"
else
  echo "SKIP: jq not installed (metrics-event with jq)"
fi

# --- without jq: exit 0, no file
OUT="$(run_hook "$NOJQ" stop "$IN")"; RC=$?
check "metrics-event no jq: exit 0" "0" "$RC"
check "metrics-event no jq: silent" "" "$OUT"
[ ! -e "$EV" ] && pass "metrics-event no jq: no file" || fail "metrics-event no jq: no file"

# --- garbage / empty / non-JSON stdin, repo without CLAUDE.local.md
mkdir -p "$SANDBOX/bare"
for g in "" "not json at all" '{"cwd":' '}{][' "$(printf '\001\002\377')"; do
  OUT="$(cd "$SANDBOX/bare" && run_hook "$PATH" stop "$g")"; RC=$?
  check "metrics-event garbage [$g]: exit 0" "0" "$RC"
  check "metrics-event garbage [$g]: silent" "" "$OUT"
done
[ ! -e "$EV" ] && pass "metrics-event garbage: no file" || fail "metrics-event garbage: no file"
OUT="$(run_hook "$PATH" stop "{\"cwd\":\"$SANDBOX/bare\"}")"; RC=$?
check "metrics-event no CLAUDE.local.md: exit 0" "0" "$RC$OUT"
OUT="$(cd "$REPO" && run_hook "$PATH" stop "")"; RC=$?
check "metrics-event empty stdin falls back to PWD: exit 0" "0" "$RC"
rm -rf "$PROJ/metrics"

# Spaced vault path: project_context_path (common.bash) does not resolve paths
# with spaces yet (reported as a finding); the hook must still fail open.
SP="$SANDBOX/My Brain/projects/p"
mkdir -p "$SP"; : > "$SP/CONTEXT.md"
mkdir -p "$SANDBOX/repo2"; echo "state: see $SP/CONTEXT.md" > "$SANDBOX/repo2/CLAUDE.local.md"
OUT="$(run_hook "$PATH" stop "{\"cwd\":\"$SANDBOX/repo2\"}")"; RC=$?
check "metrics-event spaced vault: exit 0" "0" "$RC"
check "metrics-event spaced vault: silent" "" "$OUT"

# --- brain-health
H="$SANDBOX/health vault"
mkdir -p "$H/projects/p"
printf -- '---\ntype: project\ndate: 2026-01-01\n---\nsee [[note]]\n' > "$H/home.md"
printf -- '---\ntype: note\ndate: 2026-01-01\n---\nback to [[home]]\n' > "$H/note.md"
OUT="$(/bin/bash "$HEALTH" "$H" 2>&1)"; RC=$?
check "brain-health: exit 0 on healthy vault" "0" "$RC"
has "brain-health: header" "🧠 brain-health — $H" "$OUT"
has "brain-health: healthy line" "Healthy vault (2 notes)" "$OUT"
printf 'no frontmatter\n' > "$H/bad.md"
OUT="$(/bin/bash "$HEALTH" "$H" 2>&1)"; RC=$?
check "brain-health: exit 1 with issues" "1" "$RC"
has "brain-health: reports no frontmatter" "no frontmatter: bad.md" "$OUT"
OUT="$(/bin/bash "$HEALTH" 2>&1)"; RC=$?
check "brain-health no arg: exit 2" "2" "$RC"
has "brain-health no arg: usage" "Usage: brain-health.sh <vault-path>" "$OUT"
OUT="$(/bin/bash "$HEALTH" "$SANDBOX/nope" 2>&1)"; RC=$?
check "brain-health missing vault: exit 2" "2" "$RC"

# --- brain-metrics
OUT="$(/bin/bash "$METRICS" 2>&1)"; RC=$?
check "brain-metrics no arg: exit 2" "2" "$RC"
has "brain-metrics no arg: usage" "Usage: brain-metrics.sh <vault-path>" "$OUT"
OUT="$(env -i PATH="$NOJQ" HOME="$HOME_D" /bin/bash "$METRICS" "$H" 2>&1)"; RC=$?
check "brain-metrics no jq: exit 0" "0" "$RC"
check "brain-metrics no jq: notice" "jq not installed — metrics are optional; install jq to enable them." "$OUT"
OUT="$(env -i PATH="$NOJQ" HOME="$HOME_D" /bin/bash "$COLLECT" "$SANDBOX/x.jsonl" 2>&1)"; RC=$?
check "collect-metrics no jq: exit 0" "0" "$RC"
check "collect-metrics no jq: notice" "jq not installed — metrics are optional; install jq to enable them." "$OUT"
if command -v jq >/dev/null 2>&1; then
  OUT="$(/bin/bash "$METRICS" "$H" 2>&1)"; RC=$?
  check "brain-metrics with jq, no data: exit 0" "0" "$RC"
  has "brain-metrics with jq: no metrics yet" "close a task with /second-brain:close" "$OUT"
  OUT="$(/bin/bash "$COLLECT" "$SANDBOX/missing.jsonl" 2>&1)"; RC=$?
  check "collect-metrics missing transcript: exit 2" "2" "$RC"
  has "collect-metrics missing transcript: message" "ERROR: transcript not found" "$OUT"
  OUT="$(/bin/bash "$COLLECT" 2>&1)"; RC=$?
  check "collect-metrics no arg: exit 2" "2" "$RC"
  has "collect-metrics no arg: usage" "Usage: collect-metrics.sh" "$OUT"
fi

# --- no leftover placeholders
if grep -rn '@@' "$REPO_ROOT/method/scripts" "$REPO_ROOT/hooks" >/dev/null 2>&1; then
  fail "no @@ placeholders in method/scripts or hooks"
else
  pass "no @@ placeholders in method/scripts or hooks"
fi

echo
echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
