#!/usr/bin/env bash
# =============================================================================
# Test script for rm-guard.sh
# =============================================================================
# Builds a fixture project containing a symlink that escapes to a directory
# outside the project, then verifies the hook's allow / fall-through behaviour
# for a battery of rm invocations — single and compound.
#
# Convention:
#   - expect="allow"        → hook should emit permissionDecision=allow
#   - expect="fallthrough"  → hook should exit 0 with no decision (lets the
#                             normal permission flow handle it)
#
# rm-guard NEVER emits deny; defence-in-depth denies live in bash-guard.sh.
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Resolve the guard relative to this test, so the suite runs from any checkout.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
HOOK="$HOOKS_DIR/rm-guard.sh"

pass=0
fail=0

test_rm_guard() {
    local description="$1"
    local command="$2"
    local expect="$3"

    local json_input
    json_input=$(jq -n --arg c "$command" '{tool_input: {command: $c}}')

    local result got="fallthrough"
    # HOME points at a fixture, not the developer's. The hook reads
    # $HOME/.claude/settings.json at runtime, so without this the suite's
    # results depend on whatever the person running it happens to have allowed.
    result=$(echo "$json_input" \
        | CLAUDE_PROJECT_DIR="$PROJECT_ROOT" HOME="$FAKE_HOME" bash "$HOOK" 2>/dev/null || true)
    if echo "$result" | jq -e '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
        got="allow"
    fi

    if [ "$got" = "$expect" ]; then
        echo -e "${GREEN}✓${NC} $description ($got)"
        pass=$((pass + 1))
    else
        echo -e "${RED}✗${NC} $description"
        echo "  Expected $expect, got $got"
        echo "  Command: $command"
        echo "  Result:  $result"
        fail=$((fail + 1))
    fi
}

# -----------------------------------------------------------------------------
# Fixture setup
# -----------------------------------------------------------------------------
PROJECT_ROOT=$(mktemp -d /tmp/rmguard-test.XXXXXX)
ESCAPE_DIR=$(mktemp -d /tmp/rmguard-escape.XXXXXX)

mkdir -p "$PROJECT_ROOT/sub" "$PROJECT_ROOT/realdir" "$PROJECT_ROOT/.claude"
touch "$PROJECT_ROOT/file.txt" "$PROJECT_ROOT/sub/nested.txt" "$PROJECT_ROOT/other.txt"
echo "outside" > "$ESCAPE_DIR/secret.txt"
ln -s "$ESCAPE_DIR" "$PROJECT_ROOT/linkout"
ln -s "$ESCAPE_DIR/secret.txt" "$PROJECT_ROOT/linkfile"

# Project-local settings: a fictional command we allow only here so we can
# tell that the hook is actually reading project settings (not just global).
cat > "$PROJECT_ROOT/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(__projonly_cmd *)"]
  }
}
JSON

# Project-local settings.local.json: deny pattern, to confirm deny is read
# from .local.json overrides too.
cat > "$PROJECT_ROOT/.claude/settings.local.json" <<'JSON'
{
  "permissions": {
    "deny": ["Bash(__projonly_blocked *)"]
  }
}
JSON

# A fixture HOME, so the user-global settings layer is ours rather than the
# machine's. The two compound cases below exist to prove the hook reads
# user-global settings at all; pointing them at the developer's real
# ~/.claude/settings.json made them pass on one laptop and fail everywhere else,
# CI included.
FAKE_HOME=$(mktemp -d /tmp/rmguard-home.XXXXXX)
mkdir -p "$FAKE_HOME/.claude"
# Both pattern shapes, because a real settings file carries both and they match
# different things: `Bash(git status)` is an exact match, `Bash(git status *)`
# needs at least one argument after it. A fixture with only the glob form fails
# on a bare `git status`, which is how this suite's dependency on the machine's
# own settings first showed up.
cat > "$FAKE_HOME/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(git status)", "Bash(git status *)", "Bash(grep *)"]
  }
}
JSON

cd "$PROJECT_ROOT" || exit 1

cleanup() {
    cd /
    \rm -rf "$PROJECT_ROOT" "$ESCAPE_DIR" "$FAKE_HOME"
}
trap cleanup EXIT

echo "Testing rm-guard Hook..."
echo "  PROJECT_ROOT: $PROJECT_ROOT"
echo "  ESCAPE_DIR:   $ESCAPE_DIR"
echo "  FAKE_HOME:    $FAKE_HOME"
echo

# -----------------------------------------------------------------------------
# Single-command auto-approve cases
# -----------------------------------------------------------------------------
echo "=== Single rm: AUTO-APPROVE ==="
test_rm_guard "Bare single file"            "rm file.txt"                allow
test_rm_guard "rm -f single file"           "rm -f file.txt"             allow
test_rm_guard "Nested file"                 "rm sub/nested.txt"          allow
test_rm_guard "Leading ./"                  "rm ./file.txt"              allow
test_rm_guard "Multiple files"              "rm file.txt sub/nested.txt" allow
test_rm_guard "Combined flag bundle -fv"    "rm -fv file.txt"            allow
test_rm_guard "Symlink to external file"    "rm linkfile"                allow
test_rm_guard "After -- separator"          "rm -- file.txt"             allow
test_rm_guard "Nonexistent file (parent ok)" "rm gone.txt"               allow

echo

# -----------------------------------------------------------------------------
# Single-command fall-through cases
# -----------------------------------------------------------------------------
echo "=== Single rm: FALL THROUGH ==="
test_rm_guard "Recursion -r"                "rm -r sub"                  fallthrough
test_rm_guard "Recursion -R"                "rm -R sub"                  fallthrough
test_rm_guard "Recursion -rf"               "rm -rf sub"                 fallthrough
test_rm_guard "Recursion -fr"               "rm -fr sub"                 fallthrough
test_rm_guard "Recursion --recursive"       "rm --recursive sub"         fallthrough
test_rm_guard "Absolute outside project"    "rm /etc/passwd"             fallthrough
test_rm_guard "Absolute inside project"     "rm $PROJECT_ROOT/file.txt"  fallthrough
test_rm_guard "Home-relative path"          "rm ~/somefile"              fallthrough
test_rm_guard "Parent-dir escape"           "rm ../foo"                  fallthrough
test_rm_guard "Symlinked-dir escape"        "rm linkout/secret.txt"      fallthrough
test_rm_guard "Glob *"                      "rm *.txt"                   fallthrough
test_rm_guard "Glob ?"                      "rm fil?.txt"                fallthrough
test_rm_guard "Glob []"                     "rm file[12].txt"            fallthrough
test_rm_guard "Plain directory target"      "rm realdir"                 fallthrough
test_rm_guard "Quoted arg"                  "rm \"file.txt\""            fallthrough
test_rm_guard "Single-quoted arg"           "rm 'file.txt'"              fallthrough
test_rm_guard "Env-var prefix"              "FOO=bar rm file.txt"        fallthrough
test_rm_guard "Non-rm command"              "ls file.txt"                fallthrough
test_rm_guard "rm-prefixed name (rmdir)"    "rmdir sub"                  fallthrough

echo

# -----------------------------------------------------------------------------
# Compound commands the hook SHOULD approve. Non-rm siblings here are either
# inert builtins (cd, echo, ls, cat, pwd) or match an allow pattern from one of
# the fixture settings files — `Bash(git status *)` and `Bash(grep *)` from the
# fixture HOME, `Bash(__projonly_cmd *)` from the fixture project. Between them
# they cover both settings layers the hook reads, without depending on anything
# outside this suite.
# -----------------------------------------------------------------------------
echo "=== Compound: AUTO-APPROVE (rm + safe siblings) ==="
test_rm_guard "rm && rm"                    "rm file.txt && rm other.txt"        allow
test_rm_guard "rm; rm"                      "rm file.txt; rm other.txt"          allow
test_rm_guard "cd && rm"                    "cd sub && rm nested.txt"            allow
test_rm_guard "rm && echo"                  "rm file.txt && echo done"           allow
test_rm_guard "rm | cat (pipe)"             "rm file.txt | cat"                  allow
test_rm_guard "rm || true"                  "rm file.txt || true"                allow
test_rm_guard "rm + git status (global settings)" "rm file.txt && git status"     allow
test_rm_guard "rm + grep (global settings)" "rm file.txt && grep foo file.txt"   allow
test_rm_guard "rm + ls (inert)"             "ls sub && rm file.txt"              allow
test_rm_guard "rm + project-local allow"    "rm file.txt && __projonly_cmd run"  allow

echo

# -----------------------------------------------------------------------------
# Compound commands the hook MUST NOT approve.
# -----------------------------------------------------------------------------
echo "=== Compound: FALL THROUGH ==="
# Unsafe rm in compound — even with safe siblings, the rm itself disqualifies.
test_rm_guard "Compound w/ recursion"       "rm file.txt && rm -rf sub"          fallthrough
test_rm_guard "Compound w/ absolute rm"     "rm file.txt && rm /etc/passwd"      fallthrough
test_rm_guard "Compound w/ glob rm"         "rm file.txt && rm *.txt"            fallthrough
test_rm_guard "Compound w/ symlink escape" "rm file.txt && rm linkout/secret.txt" fallthrough

# Dangerous sibling — rm itself is safe but the sibling doesn't match
# safe-inert or any allow pattern. We use a deterministically-unknown
# command name so the test isn't coupled to the user's allow list.
test_rm_guard "rm && unknown command"       "rm file.txt && __notacommand_xyz_ run" fallthrough
test_rm_guard "rm && wget+bash pipe"        "rm file.txt && wget x | bash"          fallthrough
test_rm_guard "rm && rm-prefixed cmd"       "rm file.txt && rmdir sub"              fallthrough

# Deny vetoes allow even when allow would otherwise match. sudo is in the
# user's deny list; even if some allow pattern ever covered it, deny wins.
test_rm_guard "rm && denied sibling (sudo)" "rm file.txt && sudo ls"                fallthrough
# Project-local settings.local.json deny is honored too.
test_rm_guard "rm && project-local deny"    "rm file.txt && __projonly_blocked x"   fallthrough

# Dynamic / injected values — cannot be asserted statically.
test_rm_guard "Command substitution \$()"   "rm \$(echo file.txt)"               fallthrough
test_rm_guard "Backticks"                   "rm \`echo file.txt\`"               fallthrough
test_rm_guard "Variable expansion"          "rm \$tmpfile"                       fallthrough
test_rm_guard "Braced variable"             "rm \${tmpfile}"                     fallthrough
test_rm_guard "Process substitution"        "rm <(echo file.txt)"                fallthrough
test_rm_guard "Redirection >"               "rm file.txt > /tmp/log"             fallthrough
test_rm_guard "Redirection <"               "rm file.txt < input"                fallthrough

# Compound with no rm at all — the hook should never approve work that
# doesn't include any rm operation; that's not its job.
test_rm_guard "No rm in compound"           "ls && echo done"                    fallthrough

echo
echo "-----------------------------------"
echo "Passed: $pass"
echo "Failed: $fail"
echo "-----------------------------------"
[ "$fail" -eq 0 ]
