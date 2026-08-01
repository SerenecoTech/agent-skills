#!/usr/bin/env bash
# =============================================================================
# Test script for write-guard.sh
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Resolve the guard relative to this test, so the suite runs from any checkout.
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

pass=0
fail=0

test_write_guard() {
    local description="$1"
    local file_path="$2"
    local content="$3"
    local should_block="$4"

    # Build JSON input
    if [ -n "$content" ]; then
        json_input=$(jq -n --arg fp "$file_path" --arg c "$content" '{tool_input: {file_path: $fp, content: $c}}')
    else
        json_input=$(jq -n --arg fp "$file_path" '{tool_input: {file_path: $fp}}')
    fi

    # Run the guard
    result=$(echo "$json_input" | bash "$HOOKS_DIR/write-guard.sh")
    exit_code=$?

    # Check if it was blocked
    if echo "$result" | grep -q '"permissionDecision":"deny"'; then
        blocked=true
    else
        blocked=false
    fi

    # Verify expectation
    if [ "$should_block" = "true" ] && [ "$blocked" = "true" ]; then
        echo -e "${GREEN}✓${NC} $description (correctly blocked)"
        pass=$((pass + 1))
        return 0
    elif [ "$should_block" = "false" ] && [ "$blocked" = "false" ]; then
        echo -e "${GREEN}✓${NC} $description (correctly allowed)"
        pass=$((pass + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        echo "  Expected block=$should_block, got block=$blocked"
        echo "  Result: $result"
        fail=$((fail + 1))
        return 1
    fi
}

echo "Testing Write Guard Hook..."
echo ""

# Test protected file paths
echo "=== Protected File Paths ==="
test_write_guard "Block .env file" "/path/to/.env" "" "true"
test_write_guard "Block SSH private key" "/home/user/.ssh/id_rsa" "" "true"
test_write_guard "Block AWS credentials" "/home/user/.aws/credentials" "" "true"
test_write_guard "Block kubeconfig" "/home/user/.kube/config" "" "true"
test_write_guard "Allow normal file" "/home/user/code/app.js" "" "false"
test_write_guard "Allow .env.example" "/path/to/.env.example" "" "false"

echo ""
echo "=== Secret Detection ==="
test_write_guard "Block AWS access key" "/tmp/config.js" "const key = 'AKIAIOSFODNN7EXAMPLE';" "true"
test_write_guard "Block Anthropic API key" "/tmp/api.js" "ANTHROPIC_API_KEY=sk-ant-api03-abcdef123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123" "true"
test_write_guard "Block OpenAI API key" "/tmp/openai.py" "openai.api_key = 'sk-proj-abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGH'" "true"
test_write_guard "Block GitHub PAT" "/tmp/gh.sh" "GITHUB_TOKEN=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" "true"
test_write_guard "Block private key" "/tmp/cert.js" "const key = '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg...';" "true"
test_write_guard "Block database URI with password" "/tmp/db.js" "mongodb://admin:SuperSecret123@localhost:27017/mydb" "true"
test_write_guard "Allow safe content" "/tmp/app.js" "const message = 'Hello World';" "false"
test_write_guard "Allow API_ENDPOINT" "/tmp/config.js" "API_ENDPOINT='https://api.example.com';" "false"

echo ""
echo "=== System Directories ==="
test_write_guard "Block /etc/passwd" "/etc/passwd" "root:x:0:0:root:/root:/bin/bash" "true"
test_write_guard "Block /root/.bashrc" "/root/.bashrc" "export PATH=..." "true"

echo ""
echo "=== Git Safety ==="
test_write_guard "Block git hooks" "/path/to/.git/hooks/pre-commit" "#!/bin/bash\nmalicious code" "true"
test_write_guard "Block git credential helper" "/path/to/.git/config" "[credential]\n\thelper = store" "true"

echo ""
echo "=== High Entropy Detection ==="
test_write_guard "Block suspicious high-entropy" "/tmp/config.js" "const secret_key='a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6';" "true"
test_write_guard "Allow normal base64 usage" "/tmp/img.js" "const imageData = Buffer.from('hello').toString('base64');" "false"

echo ""
echo "========================================"
echo "Results: ${pass} passed, ${fail} failed"
echo "========================================"

# Exit non-zero on any failure so run-all.sh and CI can see it.
[ "$fail" -eq 0 ]
