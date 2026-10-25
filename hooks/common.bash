# hooks/common.bash — shared, dependency-free helpers for the plugin hooks.
# Sourced, never executed. No jq/perl/python/node; no BSD- or GNU-only flags.
# Bash 3.2 safe. Does not set options, does not exit, prints nothing on source.

# _jr <string> <literal-pattern> <literal-replacement> -> $_JR (replace all).
# Pattern and replacement are held in variables so backslashes stay literal
# (quoting inside ${//} differs between bash 3.2 and newer).
_jr() {
  local _s="$1" _p="$2" _r="$3" _o=""
  while :; do
    case "$_s" in
      *"$_p"*) _o="$_o${_s%%"$_p"*}$_r"; _s="${_s#*"$_p"}" ;;
      *) break ;;
    esac
  done
  _JR="$_o$_s"
}

# json_get_string <json> <key>
# Prints the value of a top-level-style string field, unescaping \" \\ \/ \n
# \t \r. Prints nothing if absent. Always returns 0.
json_get_string() {
  local json="$1" key="$2" span v bs ph
  span=$(printf '%s' "$json" | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" 2>/dev/null | head -1)
  [ -n "$span" ] || return 0
  v=$(printf '%s' "$span" | sed -e 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')
  bs='\'
  ph=$'\001'
  _jr "$v" "$bs$bs" "$ph"; v="$_JR"
  _jr "$v" "$bs\"" '"'; v="$_JR"
  _jr "$v" "$bs/" '/'; v="$_JR"
  _jr "$v" "${bs}n" $'\n'; v="$_JR"
  _jr "$v" "${bs}t" $'\t'; v="$_JR"
  _jr "$v" "${bs}r" $'\r'; v="$_JR"
  _jr "$v" "$ph" "$bs"; v="$_JR"
  printf '%s' "$v"
  return 0
}

# json_get_bool <json> <key> -> true|false (false if absent)
json_get_bool() {
  if printf '%s' "$1" | grep -qE "\"$2\"[[:space:]]*:[[:space:]]*true" 2>/dev/null; then
    printf 'true'
  else
    printf 'false'
  fi
  return 0
}

# json_escape <string> -> string escaped for a JSON string body
json_escape() {
  local s="$1" bs='\' i hex c
  _jr "$s" "$bs" "$bs$bs"; s="$_JR"
  _jr "$s" '"' "$bs\""; s="$_JR"
  _jr "$s" $'\n' "${bs}n"; s="$_JR"
  _jr "$s" $'\t' "${bs}t"; s="$_JR"
  _jr "$s" $'\r' "${bs}r"; s="$_JR"
  i=1
  while [ "$i" -le 31 ]; do
    if [ "$i" -ne 9 ] && [ "$i" -ne 10 ] && [ "$i" -ne 13 ]; then
      hex=$(printf '%02x' "$i")
      c=$(printf "\\x$hex")
      case "$s" in
        *"$c"*) _jr "$s" "$c" "${bs}u00$hex"; s="$_JR" ;;
      esac
    fi
    i=$((i + 1))
  done
  printf '%s' "$s"
}

# emit_json <text> -> stdout via printf '%s', piped through cat when available
# (absorbs EPIPE like superpowers' session-start).
emit_json() {
  if command -v cat >/dev/null 2>&1; then
    printf '%s' "$1" | cat
  else
    printf '%s' "$1"
  fi
}

# normalize_path <path> -> expands leading ~, converts Windows drive paths via
# cygpath when present, strips one trailing slash.
normalize_path() {
  local p="$1" c
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  if command -v cygpath >/dev/null 2>&1; then
    case "$p" in
      [A-Za-z]:[\\/]*)
        c=$(cygpath -u "$p" 2>/dev/null) && [ -n "$c" ] && p="$c"
        ;;
    esac
  fi
  case "$p" in
    ?*/) p="${p%/}" ;;
    ?*\\) p="${p%\\}" ;;
  esac
  printf '%s' "$p"
}

# hook_cwd <json> -> cwd from the hook input, else $PWD
hook_cwd() {
  local c
  c=$(json_get_string "$1" cwd)
  [ -n "$c" ] || c="$PWD"
  printf '%s' "$c"
}

# project_context_path <cwd> -> vault CONTEXT.md named in <cwd>/CLAUDE.local.md
# (nothing if CLAUDE.local.md or the file is missing)
project_context_path() {
  local f="$1/CLAUDE.local.md" ctx
  [ -f "$f" ] || return 0
  ctx=$(grep -oE '[~/][^ `)]*/projects/[^ `)]*CONTEXT\.md' "$f" 2>/dev/null | head -1)
  [ -n "$ctx" ] || return 0
  ctx=$(normalize_path "$ctx")
  [ -f "$ctx" ] || return 0
  printf '%s' "$ctx"
}

# file_newer <a> <b> -> exit 0 if a is newer than b
file_newer() { [ "$1" -nt "$2" ]; }

# file_modified_within_min <file> <minutes> -> exit 0 if modified in that window
file_modified_within_min() {
  [ -n "$(find "$1" -mmin "-$2" 2>/dev/null)" ]
}
