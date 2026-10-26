#!/bin/bash
# tests/check-content.sh — content checks for the second-brain plugin:
# skills, agents, method docs, vault skeleton and hook references.
# Plain bash, bash 3.2 safe. Usage: bash tests/check-content.sh (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }

TDIR="$(mktemp -d)" || { echo "FAIL: mktemp -d failed"; exit 1; }
trap 'rm -rf "$TDIR"' EXIT

SKILLS="start close learn kickoff gate new-project setup"
NOMODEL="close kickoff new-project setup"

# 1. directories exist
for d in skills agents method vault-skeleton hooks; do
  if [ -d "$d" ]; then pass "dir $d exists"; else fail "dir $d missing"; fi
done

# 2. no unrendered placeholders
hits="$(grep -rn '@@' skills agents method vault-skeleton hooks 2>/dev/null)"
if [ -z "$hits" ]; then pass "no @@ placeholders"; else fail "@@ placeholders found: $hits"; fi

# 3. templates carry no plugin-root reference
hits="$(grep -ln 'CLAUDE_PLUGIN_ROOT' method/*.template.md 2>/dev/null)"
if [ -z "$hits" ]; then pass "templates free of CLAUDE_PLUGIN_ROOT"; else fail "plugin root in templates: $hits"; fi

# 4. no bare slash commands
hits="$(grep -rnE '(^|[^:a-z-])/(start|close|learn|kickoff|gate|new-project)\b' skills agents method 2>/dev/null)"
if [ -z "$hits" ]; then pass "no unprefixed slash commands"; else fail "unprefixed commands: $hits"; fi

# 4b. no sbm install paths
hits="$(grep -rnE '~/\.claude/(commands|agents|hooks)|\./sbm' skills agents method 2>/dev/null)"
if [ -z "$hits" ]; then pass "no sbm install paths"; else fail "sbm paths: $hits"; fi

# 5. skill frontmatter
for s in $SKILLS; do
  f="skills/$s/SKILL.md"
  if [ ! -f "$f" ]; then fail "$f missing"; continue; fi
  fm="$(awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$f")"
  n="$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | head -1)"
  d="$(printf '%s\n' "$fm" | sed -n 's/^description: *//p' | head -1)"
  if [ "$n" = "$s" ]; then pass "$s: name matches folder"; else fail "$s: name '$n'"; fi
  if [ -n "$d" ]; then pass "$s: description set"; else fail "$s: description empty"; fi
  has=0; printf '%s\n' "$fm" | grep -q '^disable-model-invocation: true$' && has=1
  want=0; case " $NOMODEL " in *" $s "*) want=1;; esac
  if [ "$has" = "$want" ]; then pass "$s: disable-model-invocation=$want"; else fail "$s: disable-model-invocation expected $want"; fi
done
for f in skills/*/SKILL.md; do
  s="$(basename "$(dirname "$f")")"
  case " $SKILLS " in *" $s "*) ;; *) fail "unexpected skill $s";; esac
done

# 6. agents
for a in implementer tester; do
  f="agents/$a.md"
  if [ -f "$f" ] && grep -q "^name: $a$" "$f"; then pass "agent $a"; else fail "agent $a missing or misnamed"; fi
done
hits="$(grep -rn 'subagent_type' skills agents method 2>/dev/null | grep -E 'implementer|tester' | grep -v 'second-brain:')"
if [ -z "$hits" ]; then pass "subagent_type names prefixed"; else fail "unprefixed subagent_type: $hits"; fi

# 7. method docs and skeleton
for m in BRAIN CLAUDE-LOCAL.template CONTEXT.template GRAPHIFY METRICS MODEL-ROUTING MULTI-AGENT PROJECT-BRIEF.template README REVIEW-CHECKLIST.template SKILLS-REGISTRY TASK-BRIEF.template; do
  if [ -s "method/$m.md" ]; then pass "method/$m.md"; else fail "method/$m.md missing"; fi
done
[ -s method/rules.md ] && pass "method/rules.md" || fail "method/rules.md missing"
[ -s vault-skeleton/home.md ] && pass "vault-skeleton/home.md" || fail "vault-skeleton/home.md missing"

# 8. close skill telemetry wording
if grep -q 'CLAUDE_PLUGIN_ROOT}/method/scripts/collect-metrics.sh' skills/close/SKILL.md 2>/dev/null \
   && grep -q 'jq' skills/close/SKILL.md; then pass "close: telemetry gated on jq"; else fail "close: telemetry block"; fi

# 9. hooks.json references existing executable scripts (ruling R2)
refs="$(grep -o 'run-hook\.cmd\\" [a-z-]*' hooks/hooks.json 2>/dev/null | awk '{print $2}' | sort -u)"
if [ -z "$refs" ]; then fail "hooks.json: no script references found"; fi
for r in $refs; do
  if [ -f "hooks/$r" ] && [ -x "hooks/$r" ]; then pass "hook script $r exists+executable"; else fail "hook script $r missing/not executable"; fi
done

# 10. strict plugin validation on an export without untracked local files
if command -v claude >/dev/null 2>&1; then
  EXP="$TDIR/export"; mkdir -p "$EXP"
  git ls-files --cached --others --exclude-standard | grep -v '^CLAUDE\.local\.md$' | grep -v '^\.idea/' | while IFS= read -r p; do
    [ -e "$p" ] || continue
    mkdir -p "$EXP/$(dirname "$p")"; cp -p "$p" "$EXP/$p"
  done
  out="$(cd "$EXP" && claude plugin validate --strict . 2>&1)"; rc=$?
  # ICON_MISSING is tolerated on purpose: the user decided (2026-10-25) to ship
  # the plugin without an icon for now. This is not a temporary gap.
  rest="$(printf '%s\n' "$out" | grep -iE 'warn|error|✘|✗|fail' | grep -v 'ICON_MISSING' | grep -viE 'Validating|passed with|0 error')"
  if [ "$rc" = 0 ] || { printf '%s' "$out" | grep -q 'ICON_MISSING' && [ -z "$rest" ]; }; then
    pass "claude plugin validate --strict (ICON_MISSING tolerated)"
  else fail "strict validate: $out"; fi
else
  echo "SKIP: claude not found; strict validation not run"
fi

echo "---"; echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
