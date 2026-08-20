#!/usr/bin/env bash
# =============================================================================
# Test suite for env-expansion-guard.sh
# =============================================================================
# The August 2026 mortar leak is the first case below. It printed a real token
# because `${VAR:-default}` substitutes the default only when the variable is
# EMPTY — with a token present it prints the token. Every guard in this plugin
# allowed that command before this hook existed.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

pass=0
fail=0

run_guard() {
    jq -n --arg c "$1" '{tool_input:{command:$c}}' \
        | bash "$HOOKS_DIR/env-expansion-guard.sh" 2>/dev/null || echo ""
}

# Match the other suites: read the decision as a consumer would, so the test is
# not coupled to whether the hook emits compact or pretty JSON.
is_denied() {
    echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null | grep -q '^deny$'
}

check() {
    local description="$1" result="$2" should_block="$3" blocked=false
    if is_denied "$result"; then blocked=true; fi
    if [ "$should_block" = "$blocked" ]; then
        echo -e "  ${GREEN}✓${NC} $description"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}✗${NC} $description"
        echo "      expected block=$should_block, got block=$blocked"
        fail=$((fail + 1))
    fi
}

echo "Testing Credential Env-Var Expansion Guard..."
echo ""
echo -e "${YELLOW}--- the incident this hook was written for ---${NC}"
echo ""

MORTAR='C=ui-compass-beacon-app-1
docker exec "$C" zsh -lc '"'"'cd /workspace &&
echo "GH_TOKEN set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}" &&
echo "helpers: $(git config --get-all credential.helper | tr "\n" " ")" &&
echo "git resolves to: $(command -v git)" &&
echo "--- pushing ---" &&
git push origin mortar-gate5-probe 2>&1 | tail -8; echo "exit=$?"'"'"

check "block the mortar probe verbatim" \
    "$(run_guard "$MORTAR")" true

check "block the offending echo on its own" \
    "$(run_guard 'echo "GH_TOKEN set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}"')" true

# Nesting is what defeated the command-matching guards. The dangerous expansion
# is a literal substring, so it survives docker exec and zsh -lc intact.
check "block an expansion nested inside docker exec sh -c" \
    "$(run_guard 'docker exec c sh -c "echo ${GH_TOKEN:-no}"')" true

echo ""
echo -e "${YELLOW}--- expansions that print the value ---${NC}"
echo ""

check "block echo of a bare credential variable" \
    "$(run_guard 'echo $GH_TOKEN')" true

check "block echo of a braced credential variable" \
    "$(run_guard 'echo "${GITHUB_TOKEN}"')" true

check "block printf of an AWS secret" \
    "$(run_guard 'printf "%s\n" "$AWS_SECRET_ACCESS_KEY"')" true

check "block a default-substitution probe on an npm token" \
    "$(run_guard 'echo "tok=${NPM_TOKEN:-none}"')" true

check "block assign-if-unset, which also prints the value" \
    "$(run_guard 'echo "db=${DB_PASSWORD:=changeme}"')" true

check "block an api key written to a file and then printed" \
    "$(run_guard 'echo "key: ${ANTHROPIC_API_KEY}" > /tmp/x; cat /tmp/x')" true

check "block cat of a heredoc-ish credential echo" \
    "$(run_guard 'echo "Bearer $SLACK_TOKEN" | tee /tmp/h')" true

echo ""
echo -e "${YELLOW}--- probe forms that reveal nothing ---${NC}"
echo ""

check "allow the correct set/unset probe" \
    "$(run_guard 'echo "GH_TOKEN set: ${GH_TOKEN:+yes}"')" false

check "allow printing the length" \
    "$(run_guard 'echo "len=${#GH_TOKEN}"')" false

check "allow printing a short prefix" \
    "$(run_guard 'echo "prefix=${GH_TOKEN:0:4}"')" false

check "allow a -n test followed by an echo" \
    "$(run_guard '[ -n "$GH_TOKEN" ] && echo present')" false

check "allow a -z test followed by an echo" \
    "$(run_guard '[ -z "$GITHUB_TOKEN" ] && echo missing')" false

echo ""
echo -e "${YELLOW}--- using a credential is not showing it ---${NC}"
echo ""

check "allow passing a token in a curl header" \
    "$(run_guard 'curl -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user')" false

check "allow a token in an env assignment for a child process" \
    "$(run_guard 'GH_TOKEN="$GH_TOKEN" gh pr list')" false

check "allow git push, which uses the credential implicitly" \
    "$(run_guard 'git push origin main')" false

echo ""
echo -e "${YELLOW}--- must not over-reach ---${NC}"
echo ""

check "allow echo of HOME" \
    "$(run_guard 'echo "$HOME"')" false

check "allow echo of PATH" \
    "$(run_guard 'echo "$PATH"')" false

check "allow echo of ordinary CI variables" \
    "$(run_guard 'echo "repo=$GITHUB_REPOSITORY sha=$GITHUB_SHA"')" false

check "allow echo of AWS_PROFILE" \
    "$(run_guard 'echo "AWS_PROFILE=$AWS_PROFILE"')" false

# AWS_ACCESS_KEY_ID is an identifier, not a secret; PUBLIC_KEY is public by name.
check "allow echo of AWS_ACCESS_KEY_ID" \
    "$(run_guard 'echo "$AWS_ACCESS_KEY_ID"')" false

check "allow echo of an SSH public key" \
    "$(run_guard 'echo "$SSH_PUBLIC_KEY"')" false

check "allow echo of a licence key path" \
    "$(run_guard 'echo "$LICENSE_KEY_PATH"')" false

check "allow an ordinary build command" \
    "$(run_guard 'npm run build')" false

check "allow gh api with a jq filter" \
    "$(run_guard 'gh api user --jq .login')" false

echo ""
echo -e "${YELLOW}--- degenerate input must not error into a deny ---${NC}"
echo ""

check "allow an empty command" \
    "$(run_guard '')" false

check "allow a command that is only whitespace" \
    "$(run_guard '   ')" false

echo ""
echo "========================================"
echo "Results: ${pass} passed, ${fail} failed"
echo "========================================"

[ $fail -eq 0 ] && exit 0 || exit 1
