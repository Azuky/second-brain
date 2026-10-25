#!/bin/bash
# tests/test-hooks-common.sh — tests for hooks/common.bash (dependency-free
# shared hook library). Plain bash, bash 3.2 safe. Sandbox via mktemp -d;
# HOME is overridden, the real home is never touched.
# Usage: bash tests/test-hooks-common.sh   (exit 0 = all pass)

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
export HOME="$SANDBOX/home"
mkdir -p "$HOME"

OUT="$(bash -c ". '$REPO_ROOT/hooks/common.bash'" 2>&1)"
check "sourcing prints nothing" "" "$OUT"

# shellcheck source=../hooks/common.bash
. "$REPO_ROOT/hooks/common.bash" 2>/dev/null || { fail "cannot source hooks/common.bash"; echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"; exit 1; }

# --- json_get_string
check "get_string simple with spaces" "/a b/c" "$(json_get_string '{"cwd":"/a b/c","x":1}' cwd)"
check "get_string escaped quote" '/a"b' "$(json_get_string '{"cwd":"/a\"b"}' cwd)"
check "get_string windows path" 'C:\Users\Ana' "$(json_get_string '{"cwd":"C:\\Users\\Ana"}' cwd)"
check "get_string absent key" "" "$(json_get_string '{"a":"b"}' cwd)"
check "get_string garbage" "" "$(json_get_string 'not json' cwd)"
check "get_string whitespace around colon" "v" "$(json_get_string '{"k" : "v"}' k)"
check "get_string escaped slash" "a/b" "$(json_get_string '{"k":"a\/b"}' k)"
NL='
'
check "get_string newline+tab" "a${NL}b	c" "$(json_get_string '{"k":"a\nb\tc"}' k)"
check "get_string backslash then n" 'a\nb' "$(json_get_string '{"k":"a\\nb"}' k)"
json_get_string 'x' cwd; check "get_string returns 0" "0" "$?"

# --- json_get_bool
check "get_bool true" "true" "$(json_get_bool '{"stop_hook_active":true}' stop_hook_active)"
check "get_bool true spaced" "true" "$(json_get_bool '{"a": true}' a)"
check "get_bool false value" "false" "$(json_get_bool '{"a":false}' a)"
check "get_bool absent" "false" "$(json_get_bool '{"x":1}' stop_hook_active)"
check "get_bool garbage" "false" "$(json_get_bool 'zzz' a)"

# --- json_escape round trip
S="q\" b\\ n${NL}t	r$(printf '\r')c$(printf '\001')e"
ESC="$(json_escape "$S")"
case "$ESC" in *"$NL"*) fail "escape has raw newline";; *) pass "escape has no raw newline";; esac
case "$ESC" in *'\u0001'*) pass "escape control char as \\u0001";; *) fail "escape control char ($ESC)";; esac
check "escape basic" 'a\"b\\c\nd\te\r' "$(json_escape "a\"b\\c${NL}d	e$(printf '\r')")"
BACK="$(json_get_string "{\"k\":\"$(json_escape 'q" b\ n
t	r')\"}" k)"
check "round trip" 'q" b\ n
t	r' "$BACK"

# --- emit_json
check "emit_json" '{"a":"b%s"}' "$(emit_json '{"a":"b%s"}')"

# --- normalize_path
check "normalize ~/x" "$HOME/x" "$(normalize_path '~/x')"
check "normalize ~" "$HOME" "$(normalize_path '~')"
check "normalize trailing slash" "/a/b" "$(normalize_path '/a/b/')"
check "normalize spaces" "/a b/c d" "$(normalize_path '/a b/c d')"
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/cygpath" <<'FEOF'
#!/bin/bash
[ "$1" = "-u" ] || exit 1
p="$2"; d="${p%%:*}"; r="${p#*:}"; r="${r//\\//}"
echo "/$(echo "$d" | tr 'A-Z' 'a-z')$r"
FEOF
chmod +x "$FAKEBIN/cygpath"
check "normalize windows via fake cygpath" "/c/Users/Ana/My Brain" "$(PATH="$FAKEBIN:$PATH" normalize_path 'C:\Users\Ana\My Brain\')"
check "normalize windows fwd slash" "/d/x" "$(PATH="$FAKEBIN:$PATH" normalize_path 'D:/x')"
# normalize_path only uses builtins, so an empty PATH guarantees cygpath is
# absent on every platform (on Git Bash /usr/bin:/bin would still expose the
# real cygpath and convert the path).
check "normalize windows w/o cygpath unchanged" 'C:\x' "$(PATH="$FAKEBIN/nonexistent" normalize_path 'C:\x')"

# --- hook_cwd
check "hook_cwd from json" "/some/dir" "$(hook_cwd '{"cwd":"/some/dir"}')"
check "hook_cwd fallback PWD" "$PWD" "$(hook_cwd 'garbage')"

# --- project_context_path
REPO="$SANDBOX/repo"; mkdir -p "$REPO" "$HOME/v/projects/p"
: > "$HOME/v/projects/p/CONTEXT.md"
printf 'Live state: `~/v/projects/p/CONTEXT.md`\n' > "$REPO/CLAUDE.local.md"
check "project_context_path found" "$HOME/v/projects/p/CONTEXT.md" "$(project_context_path "$REPO")"
rm "$HOME/v/projects/p/CONTEXT.md"
check "project_context_path file missing" "" "$(project_context_path "$REPO")"
check "project_context_path no CLAUDE.local.md" "" "$(project_context_path "$SANDBOX/none")"

# spaced paths: backticked resolves; unquoted plain path still resolves
mkdir -p "$HOME/my vault/projects/p" "$HOME/v/projects/p"
: > "$HOME/my vault/projects/p/CONTEXT.md"; : > "$HOME/v/projects/p/CONTEXT.md"
printf 'Live state: `%s/my vault/projects/p/CONTEXT.md`\n' "$HOME" > "$REPO/CLAUDE.local.md"
check "project_context_path backticked spaced" "$HOME/my vault/projects/p/CONTEXT.md" "$(project_context_path "$REPO")"
printf 'Live state: `~/my vault/projects/p/CONTEXT.md`\n' > "$REPO/CLAUDE.local.md"
check "project_context_path backticked spaced tilde" "$HOME/my vault/projects/p/CONTEXT.md" "$(project_context_path "$REPO")"
printf 'Live state: see ~/v/projects/p/CONTEXT.md (x)\n' > "$REPO/CLAUDE.local.md"
check "project_context_path unquoted plain" "$HOME/v/projects/p/CONTEXT.md" "$(project_context_path "$REPO")"
printf 'Old: `~/gone dir/projects/p/CONTEXT.md` and ~/v/projects/p/CONTEXT.md\n' > "$REPO/CLAUDE.local.md"
check "project_context_path falls back past missing quoted" "$HOME/v/projects/p/CONTEXT.md" "$(project_context_path "$REPO")"

# --- file_newer / file_modified_within_min
A="$SANDBOX/a"; B="$SANDBOX/b"; : > "$B"; : > "$A"; touch -t 202001010000 "$B"
file_newer "$A" "$B" && pass "file_newer yes" || fail "file_newer yes"
file_newer "$B" "$A" && fail "file_newer no" || pass "file_newer no"
file_modified_within_min "$A" 5 && pass "modified within yes" || fail "modified within yes"
file_modified_within_min "$B" 5 && fail "modified within no" || pass "modified within no"
file_modified_within_min "$SANDBOX/missing" 5 && fail "modified within missing" || pass "modified within missing"

echo "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
