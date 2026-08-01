#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PermissionRequest - Git Operations
# =============================================================================
# Warns for potentially destructive Git operations.
# Input: JSON via stdin with tool_input.command
# Output: JSON {"systemMessage": "..."} to warn
# =============================================================================

set -euo pipefail

# Read stdin JSON
input=$(cat)

# Extract command from tool_input
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[ -z "$command" ] && exit 0

# Destructive Git patterns
if echo "$command" | grep -qE 'git (push --force|push -f|reset --hard|clean -f|checkout -- \.|restore \.|branch -D|rebase)'; then
    echo '{"systemMessage":"Potentially destructive Git operation. Verify branch and uncommitted changes."}'
fi

exit 0
