#!/bin/bash
# tests/run-all.sh — runs every tests/test-*.sh and tests/check-*.sh, each with the
# same bash that runs this script (${BASH}), so `/bin/bash tests/run-all.sh` really
# tests under that bash. Exits non-zero if any fails. CI calls this.
# Usage: bash tests/run-all.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
echo "run-all: bash ${BASH_VERSION:-unknown}"
failed=""; n=0
for t in tests/test-*.sh tests/check-*.sh; do
  [ -f "$t" ] || continue
  n=$((n + 1))
  echo "=== $t"
  if "${BASH:-bash}" "$t"; then echo "--- ok: $t"; else failed="$failed $t"; echo "--- FAILED: $t"; fi
done
echo ""
if [ -n "$failed" ]; then echo "run-all: $n suites, FAILED:$failed"; exit 1; fi
echo "run-all: $n suites, all passed"
