#!/usr/bin/env bash
# =============================================================================
# Test suite for toolchain-guard.sh
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Resolve the guard relative to this test, so the suite runs from any checkout.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

pass=0
fail=0

# Temporary directory simulating a project root
TMPDIR_PROJECT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PROJECT"' EXIT

# --- Helpers ---

run_guard() {
    local cmd="$1"
    local cwd="${2:-$TMPDIR_PROJECT}"
    local extra_env="${3:-}"  # e.g. "VIRTUAL_ENV=/some/venv"
    local json_input
    json_input=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')
    if [ -n "$extra_env" ]; then
        # Set requested env var; still clear any ambient VIRTUAL_ENV first
        env -C "$cwd" -u VIRTUAL_ENV $extra_env bash "$HOOKS_DIR/toolchain-guard.sh" \
            <<<"$json_input" 2>/dev/null || echo ""
    else
        # Clear ambient virtualenv so tests are environment-independent
        env -C "$cwd" -u VIRTUAL_ENV bash "$HOOKS_DIR/toolchain-guard.sh" \
            <<<"$json_input" 2>/dev/null || echo ""
    fi
}

is_denied() {
    echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null | grep -q '^deny$'
}

check() {
    local description="$1"
    local result="$2"
    local expect_deny="$3"

    if is_denied "$result"; then
        blocked=true
        reason=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
    else
        blocked=false
        reason=""
    fi

    if [ "$expect_deny" = "true" ] && [ "$blocked" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} $description"
        pass=$((pass + 1))
    elif [ "$expect_deny" = "false" ] && [ "$blocked" = "false" ]; then
        echo -e "  ${GREEN}✓${NC} $description"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}✗${NC} $description"
        echo -e "    expected deny=$expect_deny, got deny=$blocked"
        [ -n "$reason" ] && echo -e "    reason: $reason"
        fail=$((fail + 1))
    fi
}

# =============================================================================
echo ""
echo "=== 1. Bun project (bun.lock) ==="
touch "$TMPDIR_PROJECT/bun.lock"

check "block npm install"        "$(run_guard 'npm install')"        true
check "block npm ci"             "$(run_guard 'npm ci')"             true
check "block npm add react"      "$(run_guard 'npm add react')"      true
check "block npx create-app"     "$(run_guard 'npx create-react-app .')" true
check "block yarn install"       "$(run_guard 'yarn install')"       true
check "block pnpm install"       "$(run_guard 'pnpm install')"       true
check "allow bun install"        "$(run_guard 'bun install')"        false
check "allow bunx cowsay"        "$(run_guard 'bunx cowsay hello')"  false
check "allow git status"         "$(run_guard 'git status')"         false
check "allow with env prefix"    "$(run_guard 'NODE_ENV=prod npm run build')" true

rm "$TMPDIR_PROJECT/bun.lock"

# =============================================================================
echo ""
echo "=== 2. Bun project (bun.lockb legacy) ==="
touch "$TMPDIR_PROJECT/bun.lockb"

check "block npm install (bun.lockb)" "$(run_guard 'npm install')" true
check "allow bun install (bun.lockb)" "$(run_guard 'bun install')" false

rm "$TMPDIR_PROJECT/bun.lockb"

# =============================================================================
echo ""
echo "=== 3. pnpm project ==="
touch "$TMPDIR_PROJECT/pnpm-lock.yaml"

check "block npm install"    "$(run_guard 'npm install')"          true
check "block npm add react"  "$(run_guard 'npm add react')"        true
check "block npx"            "$(run_guard 'npx some-tool')"        true
check "block yarn"           "$(run_guard 'yarn install')"         true
check "allow pnpm install"   "$(run_guard 'pnpm install')"         false
check "allow pnpm add"       "$(run_guard 'pnpm add react')"       false
check "allow pnpm run"       "$(run_guard 'pnpm run test')"        false

rm "$TMPDIR_PROJECT/pnpm-lock.yaml"

# =============================================================================
echo ""
echo "=== 4. Yarn project ==="
touch "$TMPDIR_PROJECT/yarn.lock"

check "block npm install"         "$(run_guard 'npm install')"            true
check "block npm install react"   "$(run_guard 'npm install react')"      true
check "block npm add lodash"      "$(run_guard 'npm add lodash')"         true
check "block npm ci"              "$(run_guard 'npm ci')"                 true
check "block npm update"          "$(run_guard 'npm update')"             true
check "allow npm run test"        "$(run_guard 'npm run test')"           false
check "allow npm test"            "$(run_guard 'npm test')"               false
check "allow yarn install"        "$(run_guard 'yarn install')"           false
check "allow yarn add"            "$(run_guard 'yarn add react')"         false

rm "$TMPDIR_PROJECT/yarn.lock"

# =============================================================================
echo ""
echo "=== 5. package.json#packageManager (Corepack) ==="
echo '{"packageManager":"bun@1.1.0"}' > "$TMPDIR_PROJECT/package.json"

check "block npm (bun declared)"  "$(run_guard 'npm install')"   true
check "block npx (bun declared)"  "$(run_guard 'npx foo')"       true
check "allow bun (bun declared)"  "$(run_guard 'bun install')"   false

echo '{"packageManager":"pnpm@9.0.0"}' > "$TMPDIR_PROJECT/package.json"
check "block npm (pnpm declared)" "$(run_guard 'npm install')"   true
check "block yarn (pnpm declared)" "$(run_guard 'yarn add x')"   true
check "allow pnpm (pnpm declared)" "$(run_guard 'pnpm install')" false

echo '{"packageManager":"yarn@4.0.0"}' > "$TMPDIR_PROJECT/package.json"
check "block npm install (yarn declared)" "$(run_guard 'npm install')"  true
check "allow npm run (yarn declared)"     "$(run_guard 'npm run test')" false
check "allow yarn (yarn declared)"        "$(run_guard 'yarn install')" false

rm "$TMPDIR_PROJECT/package.json"

# =============================================================================
echo ""
echo "=== 6. Python: VIRTUAL_ENV active ==="
FAKE_VENV=$(mktemp -d)
FAKE_VENV_ENV="VIRTUAL_ENV=$FAKE_VENV"

check "block global /usr/bin/pip install" \
    "$(run_guard '/usr/bin/pip install requests' "" "$FAKE_VENV_ENV")" true

check "block global /usr/local/bin/pip install" \
    "$(run_guard '/usr/local/bin/pip install requests' "" "$FAKE_VENV_ENV")" true

check "block global /usr/bin/pip3 install" \
    "$(run_guard '/usr/bin/pip3 install requests' "" "$FAKE_VENV_ENV")" true

check "block python3 -m pip (venv active)" \
    "$(run_guard 'python3 -m pip install requests' "" "$FAKE_VENV_ENV")" true

check "block global /usr/bin/ansible" \
    "$(run_guard '/usr/bin/ansible-playbook site.yml' "" "$FAKE_VENV_ENV")" true

check "block global /usr/local/bin/poetry" \
    "$(run_guard '/usr/local/bin/poetry install' "" "$FAKE_VENV_ENV")" true

check "allow bare pip (uses venv pip)" \
    "$(run_guard 'pip install requests' "" "$FAKE_VENV_ENV")" false

check "allow python -m pip (uses venv python)" \
    "$(run_guard 'python -m pip install requests' "" "$FAKE_VENV_ENV")" false

check "allow ansible without full path" \
    "$(run_guard 'ansible-playbook site.yml' "" "$FAKE_VENV_ENV")" false

check "no VIRTUAL_ENV, global pip is ok" \
    "$(run_guard '/usr/bin/pip install requests')" false

rm -rf "$FAKE_VENV"

# =============================================================================
echo ""
echo "=== 7. uv project ==="
touch "$TMPDIR_PROJECT/uv.lock"

check "block pip install"         "$(run_guard 'pip install requests')"         true
check "block pip3 install"        "$(run_guard 'pip3 install requests')"        true
check "block python -m pip"       "$(run_guard 'python -m pip install flask')"  true
check "block python3 -m pip"      "$(run_guard 'python3 -m pip install flask')" true
check "allow uv add"              "$(run_guard 'uv add requests')"              false
check "allow uv sync"             "$(run_guard 'uv sync')"                      false
check "allow python script"       "$(run_guard 'python main.py')"               false

rm "$TMPDIR_PROJECT/uv.lock"

# =============================================================================
echo ""
echo "=== 8. No lock files — allow everything ==="
# TMPDIR_PROJECT is now empty
check "allow npm install"   "$(run_guard 'npm install')"   false
check "allow pip install"   "$(run_guard 'pip install x')" false
check "allow yarn install"  "$(run_guard 'yarn install')"  false
check "allow bun install"   "$(run_guard 'bun install')"   false

# =============================================================================
echo ""
echo "=== 9. Bun+yarn co-existence (bun takes priority) ==="
touch "$TMPDIR_PROJECT/bun.lock" "$TMPDIR_PROJECT/yarn.lock"

check "block npm (bun wins over yarn)" "$(run_guard 'npm install')" true
result=$(run_guard 'npm install')
reason_msg=$(echo "$result" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if echo "$reason_msg" | grep -qi "bun"; then
    echo -e "  ${GREEN}✓${NC} deny reason mentions bun (correct priority)"
    ((pass++))
else
    echo -e "  ${RED}✗${NC} deny reason should mention bun, got: $reason_msg"
    ((fail++))
fi

rm "$TMPDIR_PROJECT/bun.lock" "$TMPDIR_PROJECT/yarn.lock"

# =============================================================================
echo ""
echo "=== 10. git -C absolute path ==="
# The guard only blocks when the path is within the current project (TMPDIR_PROJECT).
# External repo paths must be allowed.

# Block: path IS the project root
check "block git -C project-root status" \
    "$(run_guard "git -C $TMPDIR_PROJECT status")" true

# Block: path is a subdirectory of the project
check "block git -C project-subdir log" \
    "$(run_guard "git -C $TMPDIR_PROJECT/src log --oneline")" true

# Block: trailing slash on project path (normalised away)
check "block git -C project-root with trailing slash" \
    "$(run_guard "git -C $TMPDIR_PROJECT/ status")" true

# Block: leading flag before -C still caught
check "block git --no-pager -C project-root" \
    "$(run_guard "git --no-pager -C $TMPDIR_PROJECT log")" true

# Allow: completely different absolute path (external repo)
check "allow git -C /tmp (external repo)" \
    "$(run_guard 'git -C /tmp status')" false

check "allow git -C /usr/local/share/git-core (external)" \
    "$(run_guard 'git -C /usr/local/share/git-core log')" false

# Allow: relative paths are always fine
check "allow git -C . (relative)" \
    "$(run_guard 'git -C . log')" false

check "allow git -C ../sibling (relative)" \
    "$(run_guard 'git -C ../sibling-repo status')" false

# Allow: bare git, no -C
check "allow bare git status" \
    "$(run_guard 'git status')" false

check "allow git log without -C" \
    "$(run_guard 'git log --oneline -10')" false

# =============================================================================
echo ""
echo "=== 11. Interpreter heredoc anti-pattern ==="

check "block python3 << 'EOF'" \
    "$(run_guard "python3 << 'EOF'
import re
print('x')
EOF")" true

check "block python3 <<EOF (no space)" \
    "$(run_guard "python3 <<EOF
print('x')
EOF")" true

check "block python <<-EOF (dash variant)" \
    "$(run_guard "python <<-EOF
print('x')
EOF")" true

check "block python3 -u << PYSCRIPT (flag + quoted)" \
    "$(run_guard "python3 -u << 'PYSCRIPT'
print('x')
PYSCRIPT")" true

check "block node << 'JS'" \
    "$(run_guard "node << 'JS'
console.log(1)
JS")" true

check "block perl << 'PERL'" \
    "$(run_guard "perl << 'PERL'
print 'hi';
PERL")" true

check "block ruby << RB" \
    "$(run_guard "ruby << RB
puts 1
RB")" true

# --- Allowed cases ---
check "allow bash heredoc (shell, not interpreter)" \
    "$(run_guard "bash << 'EOF'
echo hi
EOF")" false

check "allow cat heredoc to file" \
    "$(run_guard "cat > /tmp/foo << 'EOF'
hello
EOF")" false

check "allow short python -c one-liner" \
    "$(run_guard 'python3 -c "print(2**32)"')" false

check "allow python3 with script file" \
    "$(run_guard 'python3 /tmp/analyze.py arg1')" false

check "allow python3 -c with bit-shift (not heredoc)" \
    "$(run_guard 'python3 -c "x = 1 << 2; print(x)"')" false

check "allow <<< here-string (not a heredoc)" \
    "$(run_guard 'wc -l <<< "some text"')" false

# =============================================================================
echo ""
echo "=== 12. Legacy search tools allowed (grep/find/tree/ls -R) ==="
# Section 5 of the guard was removed: blocking these for style cost more in
# retry tokens than rg/fd saved in wall-clock. Convention still lives in
# CLAUDE.md as a preference, not a hard block.

check "allow bare grep"                 "$(run_guard 'grep pattern file.txt')"          false
check "allow grep in pipeline"          "$(run_guard 'cat file.txt | grep pattern')"    false
check "allow bare find"                 "$(run_guard 'find . -name test')"              false
check "allow bare tree"                 "$(run_guard 'tree /some/path')"                false
check "allow ls -R"                     "$(run_guard 'ls -R')"                          false

# =============================================================================
echo ""
echo "=== 13. Interpreter one-liner filesystem-deletion anti-pattern ==="
# Block deletes performed through interpreter -c/-e to bypass shell aliases
# and the Bash permission surface.

# --- Python: the original reported attack and variants ---
check "block python3 -c os.remove" \
    "$(run_guard "python3 -c \"import os; os.remove('/tmp/x')\"")" true

check "block python3 -c os.unlink" \
    "$(run_guard "python3 -c \"import os; os.unlink('/tmp/x')\"")" true

check "block python3 -c shutil.rmtree" \
    "$(run_guard "python3 -c \"import shutil; shutil.rmtree('/tmp/d')\"")" true

check "block python -c pathlib unlink" \
    "$(run_guard "python -c \"from pathlib import Path; Path('/tmp/x').unlink()\"")" true

check "block python3 -c os.rmdir" \
    "$(run_guard "python3 -c \"import os; os.rmdir('/tmp/d')\"")" true

check "block python -c subprocess shell-out to rm" \
    "$(run_guard "python -c \"import subprocess; subprocess.run(['rm', '/tmp/x'])\"")" true

check "block python -c os.system shell-out to rm" \
    "$(run_guard "python -c \"import os; os.system('rm /tmp/x')\"")" true

# --- Node / Deno / Bun ---
check "block node -e fs.unlinkSync" \
    "$(run_guard "node -e \"require('fs').unlinkSync('/tmp/x')\"")" true

check "block node -e fs.rmSync" \
    "$(run_guard "node -e \"require('fs').rmSync('/tmp/x')\"")" true

check "block deno -e Deno.removeSync" \
    "$(run_guard "deno -e \"Deno.removeSync('/tmp/x')\"")" true

# --- Perl / Ruby / PHP ---
check "block perl -e unlink" \
    "$(run_guard "perl -e \"unlink '/tmp/x'\"")" true

check "block ruby -e File.delete" \
    "$(run_guard "ruby -e \"File.delete('/tmp/x')\"")" true

check "block ruby -e FileUtils.rm_rf" \
    "$(run_guard "ruby -e \"require 'fileutils'; FileUtils.rm_rf('/tmp/d')\"")" true

check "block php -r unlink" \
    "$(run_guard "php -r \"unlink('/tmp/x');\"")" true

# --- `py` launcher alias ---
check "block py -c os.remove (py alias)" \
    "$(run_guard "py -c \"import os; os.remove('/tmp/x')\"")" true

check "block py heredoc (py alias)" \
    "$(run_guard "py << 'EOF'
import os; os.remove('/tmp/x')
EOF")" true

check "allow py -c print (py alias, benign)" \
    "$(run_guard 'py -c "print(2+2)"')" false

# --- Additional interpreter binaries ---
check "block ipython -c os.remove" \
    "$(run_guard "ipython -c \"import os; os.remove('/tmp/x')\"")" true

check "block ipython3 -c os.remove" \
    "$(run_guard "ipython3 -c \"import os; os.remove('/tmp/x')\"")" true

check "block pypy3 -c shutil.rmtree" \
    "$(run_guard "pypy3 -c \"import shutil; shutil.rmtree('/tmp/d')\"")" true

check "block nodejs -e fs.unlinkSync (Debian alias)" \
    "$(run_guard "nodejs -e \"require('fs').unlinkSync('/tmp/x')\"")" true

check "block tsx -e fs.rmSync (TypeScript runner)" \
    "$(run_guard "tsx -e \"require('fs').rmSync('/tmp/x')\"")" true

check "block ts-node -e fs.unlinkSync" \
    "$(run_guard "ts-node -e \"require('fs').unlinkSync('/tmp/x')\"")" true

# --- Version-suffixed binaries ---
check "block perl5 -e unlink" \
    "$(run_guard "perl5 -e \"unlink '/tmp/x'\"")" true

check "block ruby2.7 -e File.delete" \
    "$(run_guard "ruby2.7 -e \"File.delete('/tmp/x')\"")" true

check "block php8.2 -r unlink" \
    "$(run_guard "php8.2 -r \"unlink('/tmp/x');\"")" true

# --- Path-prefixed invocations (anchor gap) ---
check "block /usr/bin/python3 -c os.remove" \
    "$(run_guard "/usr/bin/python3 -c \"import os; os.remove('/tmp/x')\"")" true

check "block /opt/homebrew/bin/node -e fs.unlinkSync" \
    "$(run_guard "/opt/homebrew/bin/node -e \"require('fs').unlinkSync('/tmp/x')\"")" true

check "block /usr/local/bin/perl -e unlink" \
    "$(run_guard "/usr/local/bin/perl -e \"unlink '/tmp/x'\"")" true

check "allow /usr/bin/python3 -c print (path-prefixed, benign)" \
    "$(run_guard '/usr/bin/python3 -c "print(1+1)"')" false

# --- Allowed cases (must NOT trigger) ---
check "allow python3 -c print" \
    "$(run_guard 'python3 -c "print(2**32)"')" false

check "allow python3 -c bit-shift" \
    "$(run_guard 'python3 -c "x = 1 << 2; print(x)"')" false

check "allow python3 script.py (no -c, destructive call in file is out of hook scope)" \
    "$(run_guard 'python3 /tmp/script.py')" false

check "allow node -e console.log" \
    "$(run_guard "node -e \"console.log('hi')\"")" false

check "allow grep for unlink in a file (not interpreter -c)" \
    "$(run_guard 'grep -rn "os.unlink" src/')" false

check "allow python3 -c open for write (not a delete)" \
    "$(run_guard "python3 -c \"open('/tmp/x', 'w').write('hi')\"")" false

# =============================================================================
echo ""
echo -e "${YELLOW}--- Section 6: commands whose stdout IS a credential ---${NC}"
echo ""

# The incident this section was written for: `git credential fill` was run to
# inspect which fields a helper receives. The stub helper returned nothing, git
# fell through to the configured osxkeychain helper, and a live OAuth token with
# org-admin and SSH-key-write scopes was printed into the transcript.

check "block bare git credential fill" \
    "$(run_guard 'git credential fill')" true

check "block git credential fill fed from printf" \
    "$(run_guard "printf 'protocol=https\nhost=github.com\n\n' | git credential fill")" true

check "block git credential fill with an explicit helper but no reset" \
    "$(run_guard 'git -c credential.helper=/tmp/my-helper credential fill')" true

check "block git credential fill with useHttpPath but no reset" \
    "$(run_guard 'git -c credential.useHttpPath=true credential fill')" true

# The safe form: an empty credential.helper resets the list, so only a helper
# named on the same command line can answer.
check "allow git credential fill when the helper list is reset" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=/tmp/my-helper credential fill')" false

check "allow git credential fill with only the reset" \
    "$(run_guard 'git -c credential.helper= credential fill')" false

# approve and reject read stdin and print nothing.
check "allow git credential approve" \
    "$(run_guard 'git credential approve')" false

check "allow git credential reject" \
    "$(run_guard 'git credential reject')" false

# --- direct helper invocation: no helper list to reset, so no safe form ---
check "block git credential-osxkeychain get" \
    "$(run_guard 'git credential-osxkeychain get')" true

check "block git-credential-osxkeychain get (hyphenated binary)" \
    "$(run_guard 'git-credential-osxkeychain get')" true

check "block a path-prefixed credential helper get" \
    "$(run_guard '/usr/local/bin/git-credential-manager get')" true

check "block git credential-libsecret get behind a pipe" \
    "$(run_guard 'echo host=github.com | git credential-libsecret get')" true

check "allow git credential-osxkeychain store (writes, prints nothing)" \
    "$(run_guard 'git credential-osxkeychain store')" false

check "allow git credential-osxkeychain erase" \
    "$(run_guard 'git credential-osxkeychain erase')" false

# --- CLI token printers ---
check "block bare gh auth token" \
    "$(run_guard 'gh auth token')" true

check "block gh auth token piped into another command" \
    "$(run_guard 'gh auth token | pbcopy')" true

check "block gh auth token in a command substitution" \
    "$(run_guard 'TOKEN=$(gh auth token)')" true

check "block gh auth status --show-token" \
    "$(run_guard 'gh auth status --show-token')" true

# --- command boundaries ---
# The first version of this section used only whitespace and shell operators as
# boundaries, so `TOKEN=$(gh auth token)` matched nothing and was allowed. A
# command substitution opens a command as much as a pipe does.
check "block gh auth token in backticks" \
    "$(run_guard 'TOKEN=`gh auth token`')" true

check "block git credential fill in a command substitution" \
    "$(run_guard 'CRED=$(git credential fill)')" true

check "block git credential fill in backticks" \
    "$(run_guard 'CRED=`git credential fill`')" true

check "block a credential helper get in a command substitution" \
    "$(run_guard 'X=$(git credential-osxkeychain get)')" true

# The reset still exempts the safe form inside a substitution.
check "allow a reset git credential fill in a command substitution" \
    "$(run_guard 'CRED=$(git -c credential.helper= credential fill)')" false

# Redirecting to a file keeps the value out of stdout, which is the whole point.
check "allow gh auth token redirected to a file" \
    "$(run_guard 'gh auth token > /tmp/token-file')" false

check "allow gh auth token appended to a file" \
    "$(run_guard 'gh auth token >> /tmp/tokens')" false

check "allow gh auth status without --show-token" \
    "$(run_guard 'gh auth status')" false

# --- must not over-reach ---
check "allow a grep for the phrase" \
    "$(run_guard 'grep -rn "credential fill" docs/')" false

check "allow git status" \
    "$(run_guard 'git status')" false

check "allow gh pr view" \
    "$(run_guard 'gh pr view 42 --json title')" false

# =============================================================================
echo ""
echo -e "${YELLOW}--- Section 6b: the exemptions are not loopholes ---${NC}"
echo ""

# Every case below was allowed by the first version of Section 6 while still
# printing a live token to stdout. An adversarial review found them by running
# strings through the guard rather than reading the regexes.

# --- the redirect exemption belongs to one stream of one command -------------
# `2>` is stderr. stdout still prints, so the token still reaches the transcript.
check "block gh auth token with stderr sent to /dev/null" \
    "$(run_guard 'gh auth token 2>/dev/null')" true

check "block gh auth token with a spaced stderr redirect" \
    "$(run_guard 'gh auth token 2> /dev/null')" true

check "block gh auth status --show-token with stderr redirected" \
    "$(run_guard 'gh auth status --show-token 2>/dev/null')" true

check "block gh auth token piped onward with stderr redirected" \
    "$(run_guard 'gh auth token | pbcopy 2>/dev/null')" true

# A redirect attached to a different command in the line protects nothing.
check "block gh auth token when the redirect belongs to an earlier command" \
    "$(run_guard 'echo hi > /tmp/f; gh auth token')" true

check "block gh auth token when the redirect belongs to a later command" \
    "$(run_guard 'gh auth token; echo done > /tmp/f')" true

check "block gh auth token after a redirected command joined with &&" \
    "$(run_guard 'gh auth status > /tmp/s && gh auth token')" true

check "block git credential fill after a redirected command" \
    "$(run_guard 'git rev-parse HEAD > /tmp/sha; git credential fill')" true

# A redirect target that is a terminal or a std stream is still the transcript.
check "block gh auth token redirected to /dev/stdout" \
    "$(run_guard 'gh auth token > /dev/stdout')" true

check "block gh auth token redirected to /dev/stderr" \
    "$(run_guard 'gh auth token > /dev/stderr')" true

check "block gh auth token redirected to /dev/tty" \
    "$(run_guard 'gh auth token > /dev/tty')" true

check "block gh auth token redirected to /dev/fd/1" \
    "$(run_guard 'gh auth token > /dev/fd/1')" true

# The genuine article still works, including alongside a stderr redirect.
check "allow gh auth token with stdout to a file and stderr to /dev/null" \
    "$(run_guard 'gh auth token 2>/dev/null > /tmp/token-file')" false

check "allow gh auth token discarded to /dev/null" \
    "$(run_guard 'gh auth token > /dev/null')" false

# --- a leading backslash only suppresses an alias ---------------------------
check "block \\gh auth token" \
    "$(run_guard '\gh auth token')" true

check "block \\git credential fill" \
    "$(run_guard '\git credential fill')" true

check "block \\git credential-osxkeychain get" \
    "$(run_guard '\git credential-osxkeychain get')" true

# --- quotes around a word change nothing about what runs --------------------
check "block gh auth \"token\"" \
    "$(run_guard 'gh auth "token"')" true

check "block gh \"auth\" token" \
    "$(run_guard 'gh "auth" token')" true

check "block git \"credential\" fill" \
    "$(run_guard 'git "credential" fill')" true

check "block git credential \"fill\"" \
    "$(run_guard 'git credential "fill"')" true

check "block git credential-osxkeychain \"get\"" \
    "$(run_guard 'git credential-osxkeychain "get"')" true

# Quote tolerance must not swallow a quoted phrase inside another command.
check "allow a grep for the phrase including the word git" \
    "$(run_guard 'grep -rn "git credential fill" docs/')" false

# --- resetting the helper list only helps if a helper you wrote is re-added --
# The reset clears the list; naming the real store afterwards puts it straight
# back, and `fill` prints the live token the reset was supposed to prevent.
check "block a reset that re-adds osxkeychain" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=osxkeychain credential fill')" true

check "block a reset that re-adds manager" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=manager credential fill')" true

check "block a reset that re-adds store" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=store credential fill')" true

# A `!…` value is an arbitrary shell snippet, which can call the real store.
check "block a reset that re-adds a shell-snippet helper" \
    "$(run_guard 'git -c credential.helper= -c credential.helper="!git credential-osxkeychain get" credential fill')" true

# A path is a helper the caller wrote, which is the documented safe form.
check "allow a reset that re-adds a relative-path helper" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=./my-helper credential fill')" false

check "allow a reset that re-adds a home-relative path helper" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=~/bin/my-helper credential fill')" false

# --- the reset has ordinary quoting variants, and they are the same reset ----
check "allow a double-quoted empty helper reset" \
    "$(run_guard 'git -c credential.helper="" credential fill')" false

check "allow a single-quoted empty helper reset" \
    "$(run_guard "git -c credential.helper='' credential fill")" false

check "allow a reset with the whole pair quoted" \
    "$(run_guard 'git -c "credential.helper=" credential fill')" false

# =============================================================================
echo ""
echo -e "${YELLOW}--- Section 6c: second adversarial pass ---${NC}"
echo ""

# A second hostile review of the fixed code found nine more. Every case here was
# allowed while still printing a live credential, or denied while printing none.

# --- the short spelling of a blocked flag is the same flag -------------------
# gh's own help: `-t, --show-token   Display the auth token`.
check "block gh auth status -t" \
    "$(run_guard 'gh auth status -t')" true

check "block gh auth status -a -t" \
    "$(run_guard 'gh auth status -a -t')" true

check "block gh auth status -t with a hostname" \
    "$(run_guard 'gh auth status -t --hostname github.com')" true

check "allow gh auth status -h (no token flag)" \
    "$(run_guard 'gh auth status -h github.com')" false

check "allow gh auth status --hostname" \
    "$(run_guard 'gh auth status --hostname github.com')" false

# --- an absolute path is how you name the same binary ------------------------
check "block a path-prefixed gh auth token" \
    "$(run_guard '/opt/homebrew/bin/gh auth token')" true

check "block a path-prefixed git credential fill" \
    "$(run_guard '/usr/local/bin/git credential fill')" true

# --- the system stores are themselves executables at paths -------------------
# "named by a path" cannot mean "written by you": osxkeychain, store, cache and
# netrc all ship as git-credential-* binaries under git's exec-path.
check "block a reset that re-adds osxkeychain by its path" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=/opt/homebrew/opt/git/libexec/git-core/git-credential-osxkeychain credential fill')" true

check "block a reset that re-adds the store helper by its path" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=/usr/lib/git-core/git-credential-store credential fill')" true

check "allow a reset that re-adds a helper of your own by path" \
    "$(run_guard 'git -c credential.helper= -c credential.helper=/tmp/my-own-helper credential fill')" false

# --- other config forms re-arm the list after the reset ----------------------
# Verified against git 2.55 with a stub helper: each of these is consulted even
# though the empty `credential.helper=` came first.
check "block a reset undone by a URL-scoped helper" \
    "$(run_guard 'git -c credential.helper= -c credential.https://github.com.helper=osxkeychain credential fill')" true

check "block a reset undone by --config-env" \
    "$(run_guard 'git -c credential.helper= --config-env=credential.helper=HVAR credential fill')" true

check "block a reset undone by an included config file" \
    "$(run_guard 'git -c credential.helper= -c include.path=/Users/someone/.gitconfig credential fill')" true

# --- a redirect on the first occurrence is not a redirect on the second ------
check "block a second unredirected gh auth token on the same line" \
    "$(run_guard 'gh auth token > /tmp/t; gh auth token')" true

check "block a second unredirected gh auth token joined with &&" \
    "$(run_guard 'gh auth token >/tmp/t && gh auth token')" true

# --- a lone & separates commands too ----------------------------------------
check "block gh auth token backgrounded beside a redirected command" \
    "$(run_guard 'gh auth token & echo done > /tmp/f')" true

check "block gh auth token after a backgrounded redirected command" \
    "$(run_guard 'echo x > /tmp/f & gh auth token')" true

# A redirect inside a command substitution belongs to the inner command.
check "block gh auth token with a redirect only inside a substitution" \
    "$(run_guard 'gh auth token $(: > /tmp/f)')" true

# --- descriptors other than 1 are not stdout, whatever their digits ---------
check "block gh auth token with fd 0 redirected" \
    "$(run_guard 'gh auth token 0>/dev/null')" true

check "block gh auth token with fd 12 redirected" \
    "$(run_guard 'gh auth token 12>/tmp/e')" true

# --- writing about the command is not running it -----------------------------
# A quoted phrase belongs to whatever command owns the quotes. Denying these
# means the commit message for this very section cannot be typed.
check "allow a commit message naming git credential fill" \
    "$(run_guard 'git commit -m "guard: block git credential fill"')" false

check "allow a commit message naming gh auth token" \
    "$(run_guard 'git commit -m "docs: explain gh auth token"')" false

check "allow echoing a sentence about the command" \
    "$(run_guard 'echo "run gh auth token to print it"')" false

check "allow an issue title naming the command" \
    "$(run_guard 'gh issue create --title "gh auth token leaks" --body x')" false

check "allow a log search for the phrase" \
    "$(run_guard 'git log --grep="gh auth token"')" false

# A single quoted word is still the word: this is quoting, not prose.
check "block gh auth \"token\" (still)" \
    "$(run_guard 'gh auth "token"')" true

# --- redirect spellings that do keep the value off the transcript ------------
check "allow gh auth token with a noclobber-override redirect" \
    "$(run_guard 'gh auth token >| /tmp/f')" false

check "allow gh auth token inside a redirected group" \
    "$(run_guard '{ gh auth token; } > /tmp/f')" false

check "allow gh auth token inside a redirected subshell" \
    "$(run_guard '(gh auth token) > /tmp/f')" false

# =============================================================================
echo ""
echo -e "${YELLOW}--- Section 6d: third adversarial pass ---${NC}"
echo ""

# --- a command substitution is a command, wherever it is written -------------
# Ignoring quoted prose is what lets a commit message name these commands. A
# `$(…)` inside those quotes is not prose: the shell runs it and prints the
# result. Substitution bodies are matched in their own right for that reason.
check "block gh auth token inside a quoted command substitution" \
    "$(run_guard 'echo "$(gh auth token)"')" true

check "block git credential fill inside a quoted command substitution" \
    "$(run_guard 'echo "$(git credential fill)"')" true

check "block a helper get inside a quoted command substitution" \
    "$(run_guard 'echo "$(git credential-osxkeychain get)"')" true

check "block gh auth token in quoted backticks" \
    "$(run_guard 'echo "`gh auth token`"')" true

check "block gh auth token substituted into a jq argument" \
    "$(run_guard 'jq -n --arg t "$(gh auth token)" "{t:\$t}"')" true

# --- the reset protects the command it is on, not the whole line -------------
check "block a bare fill following a reset fill" \
    "$(run_guard 'git -c credential.helper= credential fill; git credential fill')" true

check "block a bare fill joined to a reset fill with &&" \
    "$(run_guard 'git -c credential.helper= credential fill && git credential fill')" true

check "block a bare fill preceding a reset fill" \
    "$(run_guard 'git credential fill | tee /tmp/x; git -c credential.helper= credential fill')" true

# A reset inside a comment is not a reset at all.
check "block a fill whose reset is inside a shell comment" \
    "$(run_guard 'git credential fill #-c credential.helper=')" true

# --- --show-token needs the same command boundary as everything else --------
check "block gh auth status --show-token in a command substitution" \
    "$(run_guard 'TOK=$(gh auth status --show-token)')" true

check "block gh auth status --show-token piped without a space" \
    "$(run_guard 'gh auth status --show-token|pbcopy')" true

check "block gh auth status -t followed by a semicolon" \
    "$(run_guard 'gh auth status -t;true')" true

check "block gh auth status --show-token in backticks" \
    "$(run_guard 'echo `gh auth status --show-token`')" true

# --- short flags cluster in either order ------------------------------------
# pflag decomposes left to right: `-tz` reports z unknown, so t was consumed.
check "block gh auth status -ta (t first in the cluster)" \
    "$(run_guard 'gh auth status -ta')" true

check "allow gh auth status -a (no token flag in the cluster)" \
    "$(run_guard 'gh auth status -a')" false

# --- a quoted redirect target is the same target -----------------------------
check "block gh auth token redirected to a quoted /dev/stdout" \
    "$(run_guard 'gh auth token > "/dev/stdout"')" true

check "block gh auth token redirected to a single-quoted /dev/stdout" \
    "$(run_guard "gh auth token > '/dev/stdout'")" true

check "block gh auth token redirected to a quoted /dev/tty" \
    "$(run_guard 'gh auth token > "/dev/tty"')" true

check "block gh auth token redirected to /dev/./stdout" \
    "$(run_guard 'gh auth token > /dev/./stdout')" true

check "allow gh auth token redirected to a quoted ordinary file" \
    "$(run_guard 'gh auth token > "/tmp/my token file"')" false

# --- a separator inside quotes is data --------------------------------------
# The `;` in a shell-function helper value must not split the command, or
# `git … credential fill` lands across two segments and matches neither.
check "block a reset re-adding a shell-function helper containing a semicolon" \
    "$(run_guard 'git -c credential.helper= -c credential.helper="!f(){ echo password=x; };f" credential fill')" true

check "block a fill whose earlier argument quotes a pipe" \
    "$(run_guard 'git -c credential.helper= -c credential.helper="!f(){ x|y; };f" credential fill')" true

# --- prose spans lines ------------------------------------------------------
# A commit body is the multi-line form of the message the guard must not block.
check "allow a multi-line commit message naming the command" \
    "$(run_guard 'git commit -m "guard: block gh auth token

Section 6 denies it."')" false

# =============================================================================
echo ""
echo -e "${YELLOW}--- Section 6e: fourth adversarial pass ---${NC}"
echo ""

# --- the binary's own name can be quoted too ---------------------------------
# `"echo" x` runs echo. Quote tolerance covered the second and third words and
# left the first one open, which defeated every check in the section at once.
check "block a quoted gh" \
    "$(run_guard '"gh" auth token')" true

check "block a single-quoted gh" \
    "$(run_guard "'gh' auth token")" true

check "block gh behind an empty quote pair" \
    "$(run_guard '""gh auth token')" true

check "block a quoted git before credential fill" \
    "$(run_guard '"git" credential fill')" true

check "block a quoted git before a helper get" \
    "$(run_guard '"git" credential-osxkeychain get')" true

check "block a quoted git-credential helper" \
    "$(run_guard "'git-credential-osxkeychain' get")" true

# --- a substitution body can contain its own parens --------------------------
check "block a substitution whose body quotes a closing paren" \
    "$(run_guard 'echo "$(echo '"'"')'"'"' ; gh auth token)"')" true

check "block a substitution containing a function definition" \
    "$(run_guard 'echo "$(f() { gh auth token; }; f)"')" true

# --- backgrounding is backgrounding whatever precedes the & ------------------
check "block gh auth token after a background job whose file ends in a digit" \
    "$(run_guard 'echo x > /tmp/f2& gh auth token')" true

check "block a second gh auth token after a backgrounded first" \
    "$(run_guard 'gh auth token >/tmp/t1& gh auth token')" true

check "block gh auth token after a backgrounded redirect, no space" \
    "$(run_guard 'echo x > /tmp/f2&gh auth token')" true

# --- an escaped quote is a literal, not a quote ------------------------------
# Counting raw quote bytes leaves an odd count stuck "inside quotes", which
# masks every real separator after it and merges the whole line into one segment.
check "block gh auth token after a command containing an escaped quote" \
    "$(run_guard 'echo "a\"b" > /tmp/f; gh auth token')" true

check "block gh auth token after a sed script containing an escaped quote" \
    "$(run_guard 'sed -i "s/\"/x/g" a.txt > /tmp/o; gh auth token')" true

check "block a bare fill after an escaped quote and a reset fill" \
    "$(run_guard 'echo "a\"b"; git -c credential.helper= credential fill; git credential fill')" true

# Balanced quotes in prose still read as prose.
check "allow a commit message containing escaped quotes" \
    "$(run_guard 'git commit -m "say \"hi\" to the guard"')" false

# --- the mask bytes are internal and must not be supplied from outside -------
check "block gh auth token carrying a literal mask byte" \
    "$(run_guard "$(printf 'gh auth token\002')")" true

# =============================================================================
echo ""
echo "========================================"
echo "Results: ${pass} passed, ${fail} failed"
echo "========================================"

[ $fail -eq 0 ] && exit 0 || exit 1
