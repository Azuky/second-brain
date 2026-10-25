#!/bin/bash
# tests/test-migrate.sh — behavioral tests for scripts/migrate-sbm (removes an
# old `sbm` install so the plugin replaces it). Plain bash, bash 3.2 safe.
# Fixtures are materialized from tests/fixtures/sbm-install (a frozen capture of
# a real `sbm install --yes`, see its README) into a mktemp -d sandbox; the
# real ~/.claude and real vault are never touched.
# Usage: bash tests/test-migrate.sh   (exit 0 = all pass)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MATERIALIZE="$SCRIPT_DIR/fixtures/sbm-install/materialize"
MIGRATE="$REPO_ROOT/scripts/migrate-sbm"

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1"; }

TDIR="$(mktemp -d)" || { echo "FAIL: mktemp -d failed"; exit 1; }
trap 'chmod -R u+w "$TDIR" 2>/dev/null; rm -rf "$TDIR"' EXIT
export HOME="$TDIR/home"
mkdir -p "$HOME"

# make_fx <name> — frozen sbm install materialized in $TDIR/<name>; sets CH, V, MAN, BK.
# Adds a user hook + keys to settings.json and user text around the
# CLAUDE.md block.
make_fx() {
  local n="$1" tmp
  CH="$TDIR/$n/claude-home"; V="$TDIR/$n/vault"; BK="$TDIR/$n/backup"
  MAN="$CH/.second-brain/manifest.json"
  mkdir -p "$TDIR/$n/home"
  bash "$MATERIALIZE" "$CH" "$V" >"$TDIR/$n/install.log" 2>&1 \
    || { echo "FAIL: materialize ($n): $(tail -3 "$TDIR/$n/install.log")"; exit 1; }
  tmp="$CH/settings.json.tmp"
  jq '.model = "opus"
      | .permissions = {"allow": ["Bash(ls)"]}
      | .hooks.Stop += [{"hooks":[{"type":"command","command":"/usr/local/bin/my-stop-hook"}]}]
      | .hooks.Notification = [{"hooks":[{"type":"command","command":"/usr/local/bin/notify"}]}]' \
    "$CH/settings.json" > "$tmp" && mv "$tmp" "$CH/settings.json"
  { printf 'USER TOP TEXT\n\n'; cat "$CH/CLAUDE.md"; printf '\nUSER BOTTOM TEXT\n'; } > "$CH/CLAUDE.md.tmp" \
    && mv "$CH/CLAUDE.md.tmp" "$CH/CLAUDE.md"
}

tree_sum() { (cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do cksum "$f"; done); }

# run_mig <args...> — sets OUT (stdout+stderr), RC
run_mig() { OUT="$(bash "$MIGRATE" "$@" 2>&1)"; RC=$?; }

# =============================================================================
# 1. --plan lists every manifest file under REMOVE, writes nothing
make_fx t1
before="$(tree_sum "$TDIR/t1")"
run_mig --claude-home "$CH" --vault "$V" --plan
[ "$RC" = 0 ] && pass "plan exits 0" || fail "plan rc=$RC out=$OUT"
missing=0; n=0
while IFS= read -r p; do
  n=$((n + 1))
  printf '%s\n' "$OUT" | grep -Fxq -- "  $p" || { missing=1; echo "  not in plan: $p"; }
done <<EOF2
$(jq -r 'keys[] | select(endswith("#block") | not) | select(startswith("'"$V"'/method/") | not)' "$MAN" | tr -d '\r')
EOF2
[ "$missing" = 0 ] && [ "$n" -gt 5 ] && pass "plan lists all $n manifest files under REMOVE" || fail "plan REMOVE incomplete (n=$n)"
printf '%s\n' "$OUT" | grep -q '#block' && fail "#block listed in plan" || pass "#block key not listed"
printf '%s\n' "$OUT" | grep -Fq "$V/method/" && fail "method/ file listed individually" || pass "method/ entries not listed individually"
printf '%s\n' "$OUT" | grep -Fxq 'SETTINGS: remove 6 hook entries' && pass "plan SETTINGS line" || fail "SETTINGS line: $OUT"
printf '%s\n' "$OUT" | grep -Fxq 'CLAUDE.md: remove managed block' && pass "plan CLAUDE.md line" || fail "CLAUDE.md line"
printf '%s\n' "$OUT" | grep -Fxq 'VAULT: rename method/ -> method.sbm-old/' && pass "plan VAULT line" || fail "VAULT line"
[ "$before" = "$(tree_sum "$TDIR/t1")" ] && pass "plan writes nothing (cksum unchanged)" || fail "plan modified the tree"
# trailing slash / ~ forms of the vault compare equal
run_mig --claude-home "$CH" --vault "$V/" --plan
[ "$RC" = 0 ] && pass "vault with trailing slash accepted" || fail "trailing slash rc=$RC"

# 2. edited command + .new -> KEEP, survive --apply
make_fx t2
echo "my edit" >> "$CH/commands/close.md"
echo "pending" > "$CH/commands/start.md.new"
run_mig --claude-home "$CH" --vault "$V" --plan
printf '%s\n' "$OUT" | awk '/^KEEP \(edited\):/{f=1;next} /^[A-Z]/{f=0} f' | grep -Fxq "  $CH/commands/close.md" \
  && pass "edited file under KEEP (edited)" || fail "edited not kept: $OUT"
printf '%s\n' "$OUT" | awk '/^KEEP \(pending .new\):/{f=1;next} /^[A-Z]/{f=0} f' | grep -Fxq "  $CH/commands/start.md.new" \
  && pass ".new under KEEP (pending .new)" || fail ".new not kept: $OUT"
printf '%s\n' "$OUT" | awk '/^REMOVE:/{f=1;next} /^[A-Z]/{f=0} f' | grep -Fxq "  $CH/commands/close.md" \
  && fail "edited file also under REMOVE" || pass "edited file not under REMOVE"
run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK"
[ "$RC" = 0 ] && [ -f "$CH/commands/close.md" ] && [ -f "$CH/commands/start.md.new" ] \
  && pass "edited file and .new survive --apply" || fail "apply removed kept files rc=$RC"

# 3. full --apply
make_fx t3
removed="$(jq -r 'keys[] | select(endswith("#block") | not) | select(startswith("'"$V"'/method/") | not)' "$MAN" | tr -d '\r')"
cp "$CH/settings.json" "$TDIR/t3/settings.before"
cp "$CH/CLAUDE.md" "$TDIR/t3/claude.before"
run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK"
[ "$RC" = 0 ] && pass "apply exits 0" || fail "apply rc=$RC out=$OUT"
gone=1; bk=1
while IFS= read -r p; do
  [ -e "$p" ] && { gone=0; echo "  still there: $p"; }
  [ -f "$BK$p" ] || { bk=0; echo "  no backup: $p"; }
done <<EOF2
$removed
EOF2
[ "$gone" = 1 ] && pass "unedited files removed" || fail "files left behind"
[ "$bk" = 1 ] && pass "removed files backed up, mirroring absolute paths" || fail "backup incomplete"
[ -f "$BK$CH/settings.json" ] && cmp -s "$BK$CH/settings.json" "$TDIR/t3/settings.before" \
  && pass "pre-edit settings.json backed up" || fail "settings backup"
[ -f "$BK$CH/CLAUDE.md" ] && cmp -s "$BK$CH/CLAUDE.md" "$TDIR/t3/claude.before" \
  && pass "pre-edit CLAUDE.md backed up" || fail "CLAUDE.md backup"
if jq -e '.model == "opus" and .permissions.allow[0] == "Bash(ls)"
          and (.hooks.Notification[0].hooks[0].command == "/usr/local/bin/notify")
          and (.hooks.Stop | length == 1)
          and (.hooks.Stop[0].hooks[0].command == "/usr/local/bin/my-stop-hook")' "$CH/settings.json" >/dev/null; then
  pass "settings.json keeps user hook and keys"
else fail "settings.json user content lost: $(cat "$CH/settings.json")"; fi
grep -Eq 'check-close|check-brief|metrics-event' "$CH/settings.json" && fail "sbm hooks left in settings" || pass "no sbm hooks in settings.json"
jq -e '.hooks | has("SessionStart") or has("PreCompact") or has("SubagentStop") | not' "$CH/settings.json" >/dev/null \
  && pass "empty event arrays removed" || fail "empty event arrays remain"
grep -q 'USER TOP TEXT' "$CH/CLAUDE.md" && grep -q 'USER BOTTOM TEXT' "$CH/CLAUDE.md" \
  && pass "CLAUDE.md keeps user text" || fail "CLAUDE.md user text lost"
grep -q 'SECOND BRAIN METHOD' "$CH/CLAUDE.md" && fail "markers remain" || pass "CLAUDE.md has no markers"
[ "$(cat "$CH/CLAUDE.md")" = "$(printf 'USER TOP TEXT\n\nUSER BOTTOM TEXT')" ] \
  && pass "blank line collapsed" || fail "CLAUDE.md shape: $(cat "$CH/CLAUDE.md")"
[ ! -e "$CH/.second-brain" ] && pass ".second-brain/ removed" || fail ".second-brain left"
[ -d "$V/method.sbm-old" ] && [ ! -e "$V/method" ] && pass "vault method/ renamed to method.sbm-old/" || fail "vault rename"
[ -d "$V/projects" ] && pass "rest of vault untouched" || fail "vault damaged"

# 7. second apply -> exit 1 nothing to migrate
run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK"
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -qi 'nothing to migrate' && pass "second apply -> exit 1 nothing to migrate" || fail "second apply rc=$RC out=$OUT"

# 4. edited CLAUDE.md block -> kept, reported
make_fx t4
sed 's/^# Personal working method/# Personal working method (mine)/' "$CH/CLAUDE.md" > "$CH/CLAUDE.md.tmp" && mv "$CH/CLAUDE.md.tmp" "$CH/CLAUDE.md"
cp "$CH/CLAUDE.md" "$TDIR/t4/claude.before"
run_mig --claude-home "$CH" --vault "$V" --plan
printf '%s\n' "$OUT" | grep -Fxq 'CLAUDE.md: block edited, keep' && pass "edited block reported" || fail "edited block: $OUT"
run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK"
cmp -s "$CH/CLAUDE.md" "$TDIR/t4/claude.before" && [ "$RC" = 0 ] && pass "edited block left untouched by apply" || fail "edited CLAUDE.md modified"
# corrupt markers (duplicate BEGIN) -> kept
make_fx t4b
printf '<!-- BEGIN SECOND BRAIN METHOD -->\n' >> "$CH/CLAUDE.md"
cp "$CH/CLAUDE.md" "$TDIR/t4b/claude.before"
run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK"
cmp -s "$CH/CLAUDE.md" "$TDIR/t4b/claude.before" && printf '%s\n' "$OUT" | grep -Fxq 'CLAUDE.md: block edited, keep' \
  && pass "corrupt markers -> kept" || fail "corrupt markers: $OUT"

# 5. vault mismatch -> exit 5, nothing written
make_fx t5
before="$(tree_sum "$TDIR/t5")"
mkdir -p "$TDIR/t5/other"
run_mig --claude-home "$CH" --vault "$TDIR/t5/other" --apply --backup-dir "$BK"
[ "$RC" = 5 ] && printf '%s' "$OUT" | grep -Fq "$V" && printf '%s' "$OUT" | grep -Fq "$TDIR/t5/other" \
  && pass "vault mismatch -> exit 5, both paths printed" || fail "mismatch rc=$RC out=$OUT"
[ "$before" = "$(tree_sum "$TDIR/t5")" ] && [ ! -e "$BK" ] && pass "mismatch writes nothing" || fail "mismatch wrote files"

# 6. no jq -> exit 6 with manual list
make_fx t6
BIN="$TDIR/t6/bin"; mkdir -p "$BIN"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    # Git Bash: symlinked/copied .exe tools lose msys-2.0.dll next to the real
    # binary and cannot run from $BIN. Hide jq by dropping its directory from
    # PATH instead (valid as long as that directory holds no other tool we need).
    JQDIR="$(dirname "$(command -v jq)")"
    NOJQ_PATH=""
    OLDIFS="$IFS"; IFS=:
    for d in $PATH; do [ "$d" = "$JQDIR" ] || NOJQ_PATH="${NOJQ_PATH:+$NOJQ_PATH:}$d"; done
    IFS="$OLDIFS"
    if [ "$JQDIR" = "$(dirname "$(command -v grep)")" ]; then NOJQ_PATH=""; fi
    ;;
  *)
    for tool in bash sh grep sed awk cat dirname basename mkdir ls date shasum sha256sum sort tr head tail cut mktemp rm cp mv cmp wc perl env printf find xargs; do
      src="$(command -v "$tool" 2>/dev/null)"
      [ -n "$src" ] && [ -x "$src" ] && ln -s "$src" "$BIN/$tool"
    done
    [ -e "$BIN/jq" ] && rm -f "$BIN/jq"
    NOJQ_PATH="$BIN"
    ;;
esac
if [ -z "$NOJQ_PATH" ]; then
  echo "SKIP: no-jq case (Git Bash: jq lives in the same directory as the other tools, cannot hide it)"
else
before="$(tree_sum "$TDIR/t6")"
OUT="$(PATH="$NOJQ_PATH" /bin/bash "$MIGRATE" --claude-home "$CH" --vault "$V" --plan 2>&1)"; RC=$?
[ "$RC" = 6 ] && pass "no jq -> exit 6" || fail "no jq rc=$RC out=$OUT"
printf '%s\n' "$OUT" | grep -Fq "$CH/commands/close.md" && ! printf '%s\n' "$OUT" | grep -q '#block' \
  && pass "manual list derived from manifest keys" || fail "manual list: $OUT"
[ "$before" = "$(tree_sum "$TDIR/t6")" ] && pass "no-jq path writes nothing" || fail "no-jq modified tree"
fi

# 8. existing method.sbm-old -> timestamped name
make_fx t8
mkdir -p "$V/method.sbm-old"; echo keep > "$V/method.sbm-old/marker"
run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK"
n="$(ls -d "$V"/method.sbm-old-* 2>/dev/null | wc -l | tr -d ' ')"
[ "$RC" = 0 ] && [ "$n" = 1 ] && [ -f "$V/method.sbm-old/marker" ] && [ ! -e "$V/method" ] \
  && pass "existing method.sbm-old -> timestamped name, old one intact" || fail "timestamped rename rc=$RC n=$n"

# 9. nothing installed -> exit 1; usage errors -> exit 2
mkdir -p "$TDIR/empty"
run_mig --claude-home "$TDIR/empty" --vault "$TDIR/empty/v" --plan
[ "$RC" = 1 ] && pass "no sbm install -> exit 1" || fail "empty rc=$RC"
run_mig --claude-home "$TDIR/empty" --vault "$TDIR/empty/v"
[ "$RC" = 2 ] && pass "missing mode -> exit 2" || fail "usage rc=$RC"
make_fx t9
run_mig --claude-home "$CH" --vault "$V" --apply
[ "$RC" = 2 ] && pass "--apply without --backup-dir -> exit 2" || fail "apply w/o backup rc=$RC"
before="$(tree_sum "$TDIR/t9")"
for bad in "" "relative/dir" "\${CLAUDE_PLUGIN_DATA}/migration-backup/x"; do
  run_mig --claude-home "$CH" --vault "$V" --apply --backup-dir "$bad"
  [ "$RC" = 2 ] && pass "bad --backup-dir '$bad' -> exit 2" || fail "bad backup '$bad' rc=$RC"
done
[ "$before" = "$(tree_sum "$TDIR/t9")" ] && pass "bad --backup-dir writes nothing" || fail "bad backup wrote files"

# 10. jq that writes CRLF (native Windows jq.exe through a pipe) -> still migrates
make_fx t10
REALJQ="$(command -v jq)"
CRBIN="$TDIR/t10/crbin"; mkdir -p "$CRBIN"
# every output line ends in CR, like a native jq.exe writing through a pipe
cat > "$CRBIN/jq" <<'JEOF'
#!/bin/bash
out="$(@@REALJQ@@ "$@")"; rc=$?
[ -n "$out" ] && printf '%s\n' "$out" | awk '{ printf "%s\r\n", $0 }'
exit $rc
JEOF
sed "s|@@REALJQ@@|\"$REALJQ\"|" "$CRBIN/jq" > "$CRBIN/jq.tmp" && mv "$CRBIN/jq.tmp" "$CRBIN/jq"
chmod +x "$CRBIN/jq"
OUT="$(PATH="$CRBIN:$PATH" bash "$MIGRATE" --claude-home "$CH" --vault "$V" --plan 2>&1)"; RC=$?
# every claude-home manifest file must be under REMOVE (this is the multi-line manifest read)
miss=0
for f in agents/implementer.md agents/tester.md commands/close.md commands/gate.md commands/kickoff.md commands/learn.md \
         commands/new-project.md commands/start.md hooks/check-brief.sh hooks/check-close.sh hooks/metrics-event.sh; do
  printf '%s\n' "$OUT" | grep -Fxq "  $CH/$f" || { miss=1; echo "  CRLF plan misses: $f"; }
done
[ "$miss" = 0 ] && printf '%s\n' "$OUT" | grep -Fxq 'SETTINGS: remove 6 hook entries' \
  && printf '%s\n' "$OUT" | grep -Fxq 'CLAUDE.md: remove managed block' \
  && pass "CRLF jq: plan lists all 11 files, settings and block" || fail "CRLF jq plan: $OUT"
OUT="$(PATH="$CRBIN:$PATH" bash "$MIGRATE" --claude-home "$CH" --vault "$V" --apply --backup-dir "$BK" 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ ! -e "$CH/commands/close.md" ] && [ ! -e "$CH/hooks/metrics-event.sh" ] && ! grep -q 'SECOND BRAIN METHOD' "$CH/CLAUDE.md" \
  && ! grep -q "$(printf '\r')" "$CH/settings.json" && pass "CRLF jq: apply removes files and block, settings keep LF" || fail "CRLF jq apply rc=$RC out=$OUT"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1
