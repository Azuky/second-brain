#!/bin/bash
# tests/test-manifest.sh — checks the plugin and marketplace manifests.
# Plain bash, grep only, bash 3.2 safe.
# Usage: bash tests/test-manifest.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN="$REPO_ROOT/.claude-plugin/plugin.json"
MARKET="$REPO_ROOT/.claude-plugin/marketplace.json"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }

# check <file> <fixed string> <label>
check() {
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then pass "$3"; else fail "$3"; fi
}

check "$PLUGIN" '"name": "second-brain"' "plugin.json name"
check "$PLUGIN" '"version"' "plugin.json version"
check "$PLUGIN" '"userConfig"' "plugin.json userConfig"
check "$PLUGIN" '"vault"' "plugin.json userConfig.vault"
check "$PLUGIN" '"type": "directory"' "plugin.json vault type directory"
check "$PLUGIN" '"required": true' "plugin.json vault required"
check "$PLUGIN" '"default": "~/second-brain"' "plugin.json vault default"
check "$MARKET" '"name": "azuky"' "marketplace.json name"
check "$MARKET" '"name": "second-brain"' "marketplace.json plugin entry"
check "$MARKET" '"source": "./"' "marketplace.json plugin source"

if command -v claude >/dev/null 2>&1; then
  # Non-strict: strict is enforced in check-content.sh once components exist.
  if (cd "$REPO_ROOT" && claude plugin validate . >/dev/null 2>&1); then
    pass "claude plugin validate ."
  else
    fail "claude plugin validate ."
  fi
else
  echo "SKIP: claude not installed"
fi

echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
