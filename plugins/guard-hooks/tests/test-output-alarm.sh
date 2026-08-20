#!/usr/bin/env bash
# =============================================================================
# Test suite for output-alarm.sh
# =============================================================================
# Every "secret" here is fabricated with a realistic shape. None is live.
#
# This hook cannot prevent anything — PostToolUse runs after the tool. The tests
# therefore assert DETECTION, and the suite is deliberately explicit about the
# things it cannot catch, so nobody mistakes it for a control.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

pass=0
fail=0

TOKEN='gho_16C7e42F292c6912E7710c838347Ae178B4aXXXX'

# $1 = command, $2 = the output it returned, $3 = optional file_path
run_alarm() {
    jq -n --arg c "$1" --arg r "$2" --arg p "${3:-}" \
        '{tool_name:"Bash",tool_input:({command:$c} + (if $p == "" then {} else {file_path:$p} end)),tool_response:$r}' \
        | bash "$HOOKS_DIR/output-alarm.sh" 2>/dev/null || echo ""
}

is_alarmed() {
    echo "$1" | jq -e '.systemMessage != null and .continue == false' >/dev/null 2>&1
}

check() {
    local description="$1" result="$2" should_alarm="$3" alarmed=false
    if is_alarmed "$result"; then alarmed=true; fi
    if [ "$should_alarm" = "$alarmed" ]; then
        echo -e "  ${GREEN}✓${NC} $description"
        pass=$((pass + 1))
    else
        echo -e "  ${RED}✗${NC} $description"
        echo "      expected alarm=$should_alarm, got alarm=$alarmed"
        fail=$((fail + 1))
    fi
}

echo "Testing Output Alarm Hook..."
echo ""
echo -e "${YELLOW}--- a credential came back: alarm and stop ---${NC}"
echo ""

check "alarm on a bare token in output" \
    "$(run_alarm 'gh auth token' "$TOKEN")" true

check "alarm on a token behind a stderr redirect" \
    "$(run_alarm 'gh auth token 2>/dev/null' "$TOKEN")" true

check "alarm on 'credential fill' output carrying a token" \
    "$(run_alarm 'git credential fill' "protocol=https
host=github.com
password=$TOKEN")" true

check "alarm on an unmasked gh auth status" \
    "$(run_alarm 'gh auth status -t' "github.com
  - Token: $TOKEN")" true

# The mortar leak: no credential command in the line at all. The printer was
# echo, the credential was an environment variable, and it was nested inside
# docker exec + zsh -lc. This is the only layer that sees it.
check "alarm on the mortar probe's output" \
    "$(run_alarm 'docker exec c zsh -lc '"'"'echo "GH_TOKEN set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}"'"'"'' \
        "GH_TOKEN set: yes${TOKEN}
helpers: osxkeychain
exit=0")" true

check "alarm on a token in a push error URL" \
    "$(run_alarm 'git push origin main 2>&1 | tail -8' \
        "remote: Invalid username or password
fatal: Authentication failed for 'https://x-access-token:${TOKEN}@github.com/o/r/'")" true

check "alarm on a private key in output" \
    "$(run_alarm 'cat ~/.ssh/id_rsa' '-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmU')" true

check "alarm on an AWS key id in output" \
    "$(run_alarm 'env | grep AWS' 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE')" true

echo ""
echo -e "${YELLOW}--- ordinary output stays silent ---${NC}"
echo ""

check "silent on git status" \
    "$(run_alarm 'git status' 'On branch main
nothing to commit, working tree clean')" false

check "silent on a build log" \
    "$(run_alarm 'npm run build' 'vite v5.0.0 building for production...
built in 1.2s')" false

check "silent on commit hashes" \
    "$(run_alarm 'git log --format=%H -3' '4c1d0e9a2b3f5e8d7c6b5a4938271605f4e3d2c1
9f2c1ab8e7d6c5b4a3928170f6e5d4c3b2a19087
1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d')" false

check "silent on a masked token" \
    "$(run_alarm 'gh auth status' 'github.com
  - Token: gho_************************************')" false

check "silent on empty output" \
    "$(run_alarm 'gh auth token > /tmp/f' '')" false

check "silent on a UUID and a hash" \
    "$(run_alarm 'uuidgen' '550e8400-e29b-41d4-a716-446655440000')" false

echo ""
echo -e "${YELLOW}--- strict tier only: a stub helper is not an incident ---${NC}"
echo ""
# The sanctioned inspection form runs a helper you wrote, which legitimately
# prints a password line. Halting a session on that would make the safe form
# unusable, so the contextual patterns are not applied to output.

check "silent on a stub helper's fake password" \
    "$(run_alarm 'git -c credential.helper= -c credential.helper=/tmp/my-helper credential fill' \
        'protocol=https
host=github.com
password=STUB-WAS-INVOKED')" false

check "silent on a placeholder password" \
    "$(run_alarm 'cat config.yml' 'password: changeme')" false

echo ""
echo -e "${YELLOW}--- fixture reads are exempt ---${NC}"
echo ""

check "silent when the file read was a fixture" \
    "$(run_alarm 'read' "GH_TOKEN=$TOKEN" '/repo/tests/fixtures/keys.env')" false

check "alarm when the file read was not a fixture" \
    "$(run_alarm 'read' "GH_TOKEN=$TOKEN" '/repo/config/live.env')" true

echo ""
echo -e "${YELLOW}--- what this hook cannot do ---${NC}"
echo ""
# Asserted so the limitation is visible in the suite rather than only the README.

check "no permission decision is emitted (it cannot deny)" \
    "$(run_alarm 'gh auth token' "$TOKEN" | jq -r '.hookSpecificOutput // "none"')" false

check "silent on an unstructured secret with no recognisable shape" \
    "$(run_alarm 'op read op://vault/item/password' 'correct-horse-battery-staple')" false

check "silent on a bare AWS secret with no key context" \
    "$(run_alarm 'aws configure get aws_secret_access_key' 'wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY123')" false

echo ""
echo "========================================"
echo "Results: ${pass} passed, ${fail} failed"
echo "========================================"

[ $fail -eq 0 ] && exit 0 || exit 1
