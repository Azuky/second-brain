#!/bin/bash
# tests/test-setup.sh — behavioral tests for scripts/setup (vault scaffold /
# adopt). Plain bash, bash 3.2 safe. Every scenario runs under one mktemp -d
# with HOME overridden; the real ~/.claude and real vault are never touched.
# Usage: bash tests/test-setup.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }

TDIR="$(mktemp -d)" || { echo "FAIL: mktemp -d failed"; exit 1; }
trap 'chmod -R u+w "$TDIR" 2>/dev/null; rm -rf "$TDIR"' EXIT
export HOME="$TDIR/home"
mkdir -p "$HOME"
CH="$TDIR/claude-home"   # empty fixture claude home
mkdir -p "$CH"

# run_setup <args...> — sets OUT (stdout+stderr) and RC
run_setup() {
  OUT="$(bash "$SETUP" --plugin-root "$REPO_ROOT" "$@" 2>&1)"
  RC=$?
}

# tree_sum <dir> — checksum listing of every file (path + cksum)
tree_sum() { (cd "$1" && find . -type f -not -path './.git/*' | LC_ALL=C sort | while read -r f; do cksum "$f"; done); }

# 1. missing dir -> created
V="$TDIR/v1"
run_setup --vault "$V" --claude-home "$CH"
[ "$RC" = 0 ] && [ "$OUT" = "created" ] && pass "missing vault -> created (exit 0)" || fail "missing vault: rc=$RC out=$OUT"
[ -d "$V/.git" ] && pass "git init done" || fail "no .git"
for d in projects learning/til learning/concept patterns briefs 00-index; do
  [ -d "$V/$d" ] || fail "dir $d missing"
done
[ -f "$V/.gitignore" ] && grep -qx '.obsidian/cache' "$V/.gitignore" && pass ".gitignore written" || fail ".gitignore"
if head -1 "$V/00-index/home.md" | grep -qx -- '---' && grep -q '^type: moc' "$V/00-index/home.md" \
   && grep -q '^# Home' "$V/00-index/home.md"; then pass "home.md has frontmatter + body"; else fail "home.md content"; fi

# 2. second run -> already set up
before="$(tree_sum "$V")"
run_setup --vault "$V" --claude-home "$CH"
[ "$RC" = 0 ] && [ "$OUT" = "already set up" ] && pass "second run -> already set up" || fail "second run: rc=$RC out=$OUT"
[ "$before" = "$(tree_sum "$V")" ] && pass "second run changes nothing" || fail "second run modified files"

# 3. only .DS_Store -> created
V="$TDIR/v2"; mkdir -p "$V"; : > "$V/.DS_Store"
run_setup --vault "$V" --claude-home "$CH"
[ "$RC" = 0 ] && [ "$OUT" = "created" ] && pass "dotfiles-only dir -> created" || fail "dotfiles-only: rc=$RC out=$OUT"

# 4. dir with projects/ -> adopted, files untouched
V="$TDIR/v3"; mkdir -p "$V/projects/x"
echo "keep me" > "$V/projects/x/CONTEXT.md"
printf 'mine\n' > "$V/.gitignore"
before="$(cd "$V" && cksum projects/x/CONTEXT.md .gitignore)"
run_setup --vault "$V" --claude-home "$CH"
[ "$RC" = 0 ] && [ "$OUT" = "adopted" ] && pass "projects/ vault -> adopted" || fail "adopt: rc=$RC out=$OUT"
[ "$before" = "$(cd "$V" && cksum projects/x/CONTEXT.md .gitignore)" ] && pass "existing files byte-identical" || fail "existing files changed"
[ -f "$V/00-index/home.md" ] && [ -d "$V/.git" ] && pass "adopt filled missing skeleton" || fail "adopt skeleton"

# 5. foreign dir -> exit 3, nothing written
V="$TDIR/v4"; mkdir -p "$V"; echo "note" > "$V/notes.md"
run_setup --vault "$V" --claude-home "$CH"
[ "$RC" = 3 ] && pass "foreign dir -> exit 3" || fail "foreign rc=$RC"
[ "$(ls -A "$V")" = "notes.md" ] && pass "foreign: nothing written" || fail "foreign: wrote files"
case "$OUT" in *notes*|*foreign*|*--confirm-foreign*) pass "foreign: explains why" ;; *) fail "foreign msg: $OUT" ;; esac

# 6. foreign + confirm -> created alongside
before="$(cd "$V" && cksum notes.md)"
run_setup --vault "$V" --claude-home "$CH" --confirm-foreign
[ "$RC" = 0 ] && [ "$OUT" = "created" ] && pass "--confirm-foreign -> created" || fail "confirm: rc=$RC out=$OUT"
[ "$before" = "$(cd "$V" && cksum notes.md)" ] && [ -d "$V/projects" ] && pass "created alongside existing files" || fail "alongside"

# 7. path with spaces
V="$TDIR/my brain/vault dir"
run_setup --vault "$V" --claude-home "$CH"
[ "$RC" = 0 ] && [ "$OUT" = "created" ] && [ -f "$V/00-index/home.md" ] && pass "vault path with spaces" || fail "spaces: rc=$RC out=$OUT"

# 8. sbm install marker -> exit 4, nothing written
CH2="$TDIR/ch-sbm"; mkdir -p "$CH2/.second-brain"; : > "$CH2/.second-brain/config.json"
V="$TDIR/v5"
run_setup --vault "$V" --claude-home "$CH2"
[ "$RC" = 4 ] && [ "$OUT" = "migrate" ] && [ ! -e "$V" ] && pass "sbm config.json -> exit 4, migrate, nothing written" || fail "sbm: rc=$RC out=$OUT"
CH2L="$TDIR/ch-sbm-legacy"; mkdir -p "$CH2L/.second-brain"; : > "$CH2L/.second-brain/config"
run_setup --vault "$TDIR/v5l" --claude-home "$CH2L"
[ "$RC" = 4 ] && [ "$OUT" = "migrate" ] && [ ! -e "$TDIR/v5l" ] && pass "legacy sbm config -> exit 4" || fail "legacy sbm: rc=$RC out=$OUT"
# frozen real sbm install (tests/fixtures/sbm-install) materialized in the sandbox -> exit 4
CH2R="$TDIR/ch-sbm-real"
bash "$REPO_ROOT/tests/fixtures/sbm-install/materialize" "$CH2R" "$TDIR/v5r" >"$TDIR/sbm-real.log" 2>&1 \
  || fail "materialize sbm fixture failed: $(tail -3 "$TDIR/sbm-real.log")"
run_setup --vault "$TDIR/v5r" --claude-home "$CH2R"
[ "$RC" = 4 ] && [ "$OUT" = "migrate" ] && pass "real sbm install -> exit 4" || fail "real sbm: rc=$RC out=$OUT"

# 9. hand-copied rules outside markers -> note, CLAUDE.md unchanged
CH3="$TDIR/ch-rules"; mkdir -p "$CH3"
printf '# mine\n## Always-active rules\n- x\n' > "$CH3/CLAUDE.md"
sum="$(cksum < "$CH3/CLAUDE.md")"
V="$TDIR/v6"
run_setup --vault "$V" --claude-home "$CH3"
case "$OUT" in *"note: your CLAUDE.md has its own copy of the method rules; delete it so they don't load twice."*) pass "hand-copied rules note printed" ;; *) fail "note missing: $OUT" ;; esac
[ "$sum" = "$(cksum < "$CH3/CLAUDE.md")" ] && pass "CLAUDE.md unchanged" || fail "CLAUDE.md modified"

# 10. heading inside the markers -> no note
CH4="$TDIR/ch-inside"; mkdir -p "$CH4"
printf '<!-- BEGIN SECOND BRAIN METHOD -->\n## Always-active rules\n<!-- END SECOND BRAIN METHOD -->\n' > "$CH4/CLAUDE.md"
run_setup --vault "$TDIR/v7" --claude-home "$CH4"
case "$OUT" in *note:*) fail "note printed for managed block" ;; *) pass "no note inside markers" ;; esac

# 11. usage errors
run_setup --plugin-root "$REPO_ROOT"
[ "$RC" = 2 ] && pass "missing --vault -> exit 2" || fail "usage rc=$RC"
run_setup --vault "$TDIR/v8" --bogus
[ "$RC" = 2 ] && [ ! -e "$TDIR/v8" ] && pass "unknown flag -> exit 2" || fail "bogus rc=$RC"

# 12. unwritable parent -> exit non-zero, error names path, no success word
if [ "$(id -u)" = 0 ]; then
  echo "SKIP: unwritable-path test (running as root ignores permissions)"
elif case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) true ;; *) false ;; esac; then
  echo "SKIP: unwritable-path test (Git Bash: chmod a-w does not make an NTFS directory read-only)"
else
  RO="$TDIR/readonly"; mkdir -p "$RO"; chmod a-w "$RO"
  run_setup --vault "$RO/vault" --claude-home "$CH"
  chmod u+w "$RO"
  case "$OUT" in *created*|*adopted*|*"already set up"*) fail "unwritable: printed success word: $OUT" ;; *) pass "unwritable: no success word" ;; esac
  [ "$RC" != 0 ] && pass "unwritable: exit non-zero ($RC)" || fail "unwritable: rc=0"
  case "$OUT" in *"$RO/vault"*) pass "unwritable: error names the path" ;; *) fail "unwritable: path not named: $OUT" ;; esac
fi

# 8. vault setting not configured -> exit 8, nothing written
NOCFG="$TDIR/nocfg"; mkdir -p "$NOCFG"
run_setup --vault "" --claude-home "$CH"
[ "$RC" = 8 ] && pass "empty --vault -> exit 8" || fail "empty --vault rc=$RC out=$OUT"
case "$OUT" in *"/config"*"edit and save"*) pass "empty --vault: message points to /config" ;; *) fail "empty --vault msg: $OUT" ;; esac
run_setup --vault '${user_config.vault}' --claude-home "$CH"
[ "$RC" = 8 ] && pass "literal placeholder --vault -> exit 8" || fail "placeholder rc=$RC out=$OUT"
case "$OUT" in *"/config"*) pass "placeholder: message points to /config" ;; *) fail "placeholder msg: $OUT" ;; esac
[ -z "$(ls -A "$NOCFG")" ] && [ ! -e '${user_config.vault}' ] && [ ! -e "$PWD/\${user_config.vault}" ] && pass "exit 8: nothing created" || fail "exit 8 created something"
run_setup --claude-home "$CH"
[ "$RC" = 2 ] && pass "missing --vault flag -> still exit 2" || fail "missing --vault rc=$RC"
run_setup --bogus --vault "$TDIR/x" --claude-home "$CH"
[ "$RC" = 2 ] && pass "unknown flag -> still exit 2" || fail "unknown flag rc=$RC"

echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
