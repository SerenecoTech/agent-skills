#!/usr/bin/env bash
# =============================================================================
# Test suite for read-guard.sh
# =============================================================================
# Every "secret" here is fabricated with a realistic shape. None is live.
#
# This guard is the one credential check that needs no shell knowledge: the file
# is on disk before the tool runs, so the content decides. The interesting cases
# are the false positives — a security tool's own source, and documentation that
# quotes secret formats, both look like secrets.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

pass=0
fail=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

run_guard() {
    jq -n --arg p "$1" '{tool_name:"Read",tool_input:{file_path:$p}}' \
        | bash "$HOOKS_DIR/read-guard.sh" 2>/dev/null || echo ""
}

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

# --- fixtures ----------------------------------------------------------------
printf 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\naws_secret_access_key=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY123\n' > "$WORK/dotenv"
printf 'github.com:\n    users:\n        someone:\n            oauth_token: gho_16C7e42F292c6912E7710c838347Ae178B4aXXXX\n' > "$WORK/hosts.yml"
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAA\n-----END OPENSSH PRIVATE KEY-----\n' > "$WORK/id_ed25519"
printf 'protocol=https\nhost=github.com\nusername=someone\npassword=gho_16C7e42F292c6912E7710c838347Ae178B4aXXXX\n' > "$WORK/captured-fill"
printf 'DATABASE_URL=postgres://app:s3cretpassword@db.internal:5432/app\n' > "$WORK/db-url"
printf 'ANTHROPIC_API_KEY=sk-ant-api03-%s\n' "$(printf 'A%.0s' {1..100})" > "$WORK/anthropic"

printf '# Project\n\nRun `npm run build`. See docs/ for guard rules.\n' > "$WORK/readme.md"
printf 'id: 550e8400-e29b-41d4-a716-446655440000\nhash: 5d41402abc4b2a76b9719d911017c592\nblob: aGVsbG8gd29ybGQgdGhpcyBpcyBub3QgYSBzZWNyZXQ=\n' > "$WORK/blobs.yml"
printf 'commit 4c1d0e9a2b3f\nAuthor: Someone\n\n    docs: explain gh auth token\n' > "$WORK/gitlog.txt"
printf 'AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n' > "$WORK/keys.fixture.env"
printf 'GH_TOKEN=gho_16C7e42F292c6912E7710c838347Ae178B4aXXXX\n' > "$WORK/sample.env"

echo "Testing Read Guard Hook..."
echo ""
echo -e "${YELLOW}--- files holding a credential: the read never happens ---${NC}"
echo ""

check "block an env file with AWS keys"          "$(run_guard "$WORK/dotenv")" true
check "block the gh hosts file (gho_ token)"      "$(run_guard "$WORK/hosts.yml")" true
check "block an OpenSSH private key"              "$(run_guard "$WORK/id_ed25519")" true
check "block captured 'credential fill' output"   "$(run_guard "$WORK/captured-fill")" true
check "block a connection string with a password" "$(run_guard "$WORK/db-url")" true
check "block an Anthropic API key"                "$(run_guard "$WORK/anthropic")" true

echo ""
echo -e "${YELLOW}--- ordinary files stay readable ---${NC}"
echo ""

check "allow a README"                            "$(run_guard "$WORK/readme.md")" false
check "allow UUIDs, hashes and base64 blobs"      "$(run_guard "$WORK/blobs.yml")" false
check "allow git log output mentioning a command" "$(run_guard "$WORK/gitlog.txt")" false

echo ""
echo -e "${YELLOW}--- this plugin's own files must stay readable ---${NC}"
echo ""
# A secret detector's source contains secret-shaped text by definition. So does
# any README documenting what it catches. Denying those makes the plugin
# unmaintainable, so they are the sharpest false-positive test available.

check "allow the shared pattern library"   "$(run_guard "$HOOKS_DIR/lib/secret-patterns.sh")" false
check "allow write-guard's source"         "$(run_guard "$HOOKS_DIR/write-guard.sh")" false
check "allow bash-guard's source"          "$(run_guard "$HOOKS_DIR/bash-guard.sh")" false
check "allow toolchain-guard's source"     "$(run_guard "$HOOKS_DIR/toolchain-guard.sh")" false
check "allow read-guard's own source"      "$(run_guard "$HOOKS_DIR/read-guard.sh")" false
check "allow output-alarm's source"        "$(run_guard "$HOOKS_DIR/output-alarm.sh")" false
check "allow env-expansion-guard's source" "$(run_guard "$HOOKS_DIR/env-expansion-guard.sh")" false
check "allow the plugin README"            "$(run_guard "$REPO_ROOT/plugins/guard-hooks/README.md")" false

echo ""
echo -e "${YELLOW}--- the fixture exemption, and its cost ---${NC}"
echo ""
# Paths naming themselves as test material are exempt, because the repo is full
# of deliberately fake secrets. This is a real blind spot, asserted so that
# anyone changing it sees what they are changing.

check "allow a path containing 'fixture'" "$(run_guard "$WORK/keys.fixture.env")" false
check "allow a path containing 'sample'"  "$(run_guard "$WORK/sample.env")" false

echo ""
echo -e "${YELLOW}--- degenerate input ---${NC}"
echo ""

check "allow a path that does not exist" "$(run_guard "$WORK/nope.env")" false
check "allow a directory"                "$(run_guard "$WORK")" false
check "allow an empty file"              "$(run_guard "$(touch "$WORK/empty" && echo "$WORK/empty")")" false
check "allow missing file_path"           "$(jq -n '{tool_name:"Read",tool_input:{}}' | bash "$HOOKS_DIR/read-guard.sh" 2>/dev/null || echo "")" false

echo ""
echo "========================================"
echo "Results: ${pass} passed, ${fail} failed"
echo "========================================"

[ $fail -eq 0 ] && exit 0 || exit 1
