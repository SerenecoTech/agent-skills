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
echo "========================================"
echo "Results: ${pass} passed, ${fail} failed"
echo "========================================"

[ $fail -eq 0 ] && exit 0 || exit 1
