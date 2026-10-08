#!/usr/bin/env zsh
# Regression tests for oc-resume. Run: ./test.sh
#
# These cover the zsh-specific traps that silently corrupted data during
# development, so they stay fixed.

emulate -L zsh
setopt no_unset

HERE=${0:A:h}
SCRIPT=$HERE/oc-resume
REAL_DB=${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}
typeset -i pass=0 fail=0

ok()   { print -r -- "  ok   $1"; (( pass++ )) }
bad()  { print -r -- "  FAIL $1"; (( fail++ )) }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi }

print -r -- "syntax"
check "zsh -n passes" "zsh -n $SCRIPT"

if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck (sh)" "shellcheck -s sh $HERE/install.sh"
fi

# --------------------------------------------------------------- zsh traps
print -r -- "zsh semantics that caused data corruption"

# `x=0; x+=1` is STRING append in zsh, so "0"+"1" = "01" -> read as octal 1.
check 'integer += is arithmetic, not string append' '
  local -i e=0; (( e++ )); (( e += 2 ))
  [[ $e -eq 3 ]]'

check 'arithmetic cannot hold strings (ternary guard)' '
  ! zsh -c "print -r -- \"\$(( 1 == 1 ? \"\" : \"s\" ))\"" >/dev/null 2>&1'

# IFS-based read collapses runs of tabs, losing empty fields.
check 'tab-split read loses empty fields (we avoid it)' '
  local a b c
  IFS=$'"'"'\t'"'"' read -r a b c <<< "x\t\ty"
  [[ "$b" != "y" ]]'

check 'NUL-delimited read preserves empty fields' '
  local -a f; f=()
  while IFS= read -r -d $'"'"'\0'"'"' v; do f+=("$v"); done < <(print -n "a\0\0c\0")
  # 3 fields: "a", "", "c" -- a trailing NUL terminates rather than adding one
  [[ ${#f[@]} -eq 3 && "$f[1]" == "a" && -z "$f[2]" && "$f[3]" == "c" ]]'

# `var=$(read -k1)` runs in a subshell that cannot read the tty.
check 'typeset inside a function is local (globals must be top-level)' '
  f() { typeset -gv leaked=1 2>/dev/null || true; }
  zsh -c "f() { typeset v=1 }; f; [[ -z \${v-} ]] && print ok" >/dev/null'

# ---------------------------------------------------------------- the picker
print -r -- "behaviour"

check "reads a real database" "[[ -r '$REAL_DB' ]]"
check "sqlite3 available"  "command -v sqlite3 >/dev/null"
check "jq available"       "command -v jq >/dev/null"

# Row parsing: every record must have 9 fields, even when text/agent are empty.
if command -v jq >/dev/null 2>&1 && [[ -r "$REAL_DB" ]]; then
  check "row JSON parses and has expected keys" '
    out=$(sqlite3 -readonly -noheader "$REAL_DB" "
      SELECT coalesce(json_group_array(json_object(
        '"'"'id'"'"',id,'"'"'dir'"'"',directory,'"'"'title'"'"',coalesce(title,'"'"'(t)'"'"'),
        '"'"'time'"'"',time_updated,'"'"'agent'"'"',coalesce(agent,'"'"''"'"'),
        '"'"'tok'"'"',(tokens_input+tokens_output))), '"'"'[]'"'"')
      FROM session_v2 WHERE parent_id IS NULL;")
    [[ $(print -r -- "$out" | jq -e "length" 2>/dev/null) -gt 0 ]]
    [[ $(print -r -- "$out" | jq -e "[.[] | select(.tok|type==\"number\")] | length" 2>/dev/null) -gt 0 ]]'
fi

# No hardcoded personal paths.
check "no hardcoded home paths" '! grep -q "/Users/" "$SCRIPT"'
check "no hardcoded opencode bin path" '! grep -q "omerdikyol" "$SCRIPT"'

# Passthrough behaviour, using a stub binary.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/fake" <<'EOF'
#!/bin/sh
echo "STUB $*"
EOF
chmod +x "$tmp/fake"
cp "$SCRIPT" "$tmp/opencode"; chmod +x "$tmp/opencode"

check "passes non-flag args through" \
  "OPENCODE_REAL_BIN=$tmp/fake $tmp/opencode --version 2>&1 | grep -q 'STUB'"
check "-r is intercepted, not passed through" \
  "printf '\n' | OPENCODE_REAL_BIN=$tmp/fake $tmp/opencode -r 2>&1 | grep -qE 'no TTY|No sessions recorded'"
check "missing binary is a clear error" \
  "OPENCODE_REAL_BIN=/nonexistent $tmp/opencode -r 2>&1 | grep -q 'could not find the opencode binary'"
check "missing database is a clear error" \
  "OPENCODE_DB=/nonexistent.db $tmp/opencode -r 2>&1 | grep -q 'could not find'"
check "empty directory starts a new session" \
  "(mkdir -p $tmp/empty && cd $tmp/empty && printf '' | OPENCODE_REAL_BIN=$tmp/fake $tmp/opencode -r 2>&1 | grep -q 'No sessions recorded')"

# Standalone mode (script not named "opencode").
check "standalone invocation shows the picker" \
  "[[ -x $HERE/oc-resume ]] && (cd \$HERE && printf '' | OPENCODE_REAL_BIN=$tmp/fake ./oc-resume 2>&1 | grep -q 'no TTY\\|No sessions recorded')"

print -r -- ""
print -r -- "passed: $pass   failed: $fail"
(( fail == 0 )) || exit 1
