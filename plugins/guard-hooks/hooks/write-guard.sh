#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - Write/Edit Guard (Enhanced)
# =============================================================================
# Blocks writes to protected files AND detects secrets in written content.
# Enhanced with comprehensive patterns and bypass protection.
#
# Input: JSON via stdin with tool_input.file_path, tool_input.content, tool_input.new_string
# Output: JSON with permissionDecision deny if dangerous
# =============================================================================

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"

# Fail-closed: if anything errors, deny by default
trap 'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Hook error - fail-closed\"}}"; exit 0' ERR

# The secret patterns are shared with read-guard and output-alarm. They used to
# live inline here, which meant the gh prefixes were fixed in one place and not
# the others.
# shellcheck source=lib/secret-patterns.sh
. "$LIB_DIR/secret-patterns.sh"

# Read stdin JSON
input=$(cat)

# === 1. Protected file paths ===
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

if [ -n "$file_path" ]; then
    # Resolve symlinks and relative paths to prevent bypass
    if [ -e "$file_path" ]; then
        resolved_path=$(realpath "$file_path" 2>/dev/null || echo "$file_path")
    else
        # For new files, resolve parent directory
        parent_dir=$(dirname "$file_path")
        filename=$(basename "$file_path")
        if [ -e "$parent_dir" ]; then
            resolved_parent=$(realpath "$parent_dir" 2>/dev/null || echo "$parent_dir")
            resolved_path="$resolved_parent/$filename"
        else
            resolved_path="$file_path"
        fi
    fi

    # Protected path patterns (case-insensitive)
    protected_patterns=(
        # Environment files (.env, .env.local, .env.production — but not .env.example)
        '\.env($|\.(local|production|staging|development|test)$)'
        '\.envrc$'

        # SSH keys and config
        '\.ssh/(id_|.*_rsa|.*_ed25519|.*_ecdsa|authorized_keys|known_hosts|config)$'

        # TLS/SSL certificates and keys
        '\.(pem|key|crt|cer|p12|pfx|jks)$'

        # Cloud provider credentials
        '\.aws/(credentials|config)$'
        '\.azure/'
        '\.config/gcloud/'
        'kubeconfig$'
        '\.kube/config$'

        # Docker and container credentials
        '\.docker/config\.json$'
        '\.dockercfg$'

        # Package registry auth
        '\.npmrc$'
        '\.pypirc$'
        '\.netrc$'
        '\.yarnrc$'
        '\.pip/pip\.conf$'

        # Database credentials
        '\.pgpass$'
        '\.my\.cnf$'

        # Git credentials
        '\.git-credentials$'
        '\.gitconfig$'

        # HTTP auth
        '\.htpasswd$'
        '\.htaccess$'

        # Application secrets
        'secrets\.(yaml|yml|json)$'
        'credentials\.(yaml|yml|json)$'

        # Service account files
        'service-?account.*\.json$'
        '.*-key\.json$'

        # Password/keychain files
        '\.password-store/'
        '\.gnupg/'
        'keyring'
    )

    for pattern in "${protected_patterns[@]}"; do
        if echo "$resolved_path" | grep -qiE "$pattern"; then
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Cannot write to protected file: $file_path (resolved: $resolved_path)\"}}"
            exit 0
        fi
    done

    # Absolute path protection (system-critical directories)
    # Note: on macOS /etc -> /private/etc, so check both forms
    critical_paths=(
        '^/etc/'
        '^/private/etc/'
        '^/boot/'
        '^/sys/'
        '^/proc/'
        '^/dev/'
        '^/root/'
        '^/private/root/'
    )

    for pattern in "${critical_paths[@]}"; do
        if echo "$resolved_path" | grep -qE "$pattern"; then
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Cannot write to system directory: $resolved_path\"}}"
            exit 0
        fi
    done
fi

# === 2. Secret detection in content ===
# Combine content from Write tool and new_string from Edit tool
content=$(echo "$input" | jq -r '(.tool_input.content // "") + (.tool_input.new_string // "")' 2>/dev/null || echo "")

if [ -n "$content" ]; then
    # Skip secret detection for test/mock files
    if [ -n "$file_path" ] && secret_path_is_exempt "$file_path"; then
        # Test files often contain fake secrets - skip secret detection
        exit 0
    fi

    # Patterns come from lib/secret-patterns.sh, shared with read-guard and
    # output-alarm. Both tiers apply here: a denied write is cheap to retry.
    secret_patterns=("${SECRET_PATTERNS_STRICT[@]}" "${SECRET_PATTERNS_CONTEXTUAL[@]}")

    for pattern in "${secret_patterns[@]}"; do
        if echo "$content" | grep -qE "$pattern"; then
            # Extract a snippet for context (first 50 chars of match)
            match=$(echo "$content" | grep -oE "$pattern" | head -n 1 | cut -c1-50)
            echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Potential secret detected in content: ${match}...\"}}"
            exit 0
        fi
    done

    # === 3. Entropy-based detection (catches unknown secret formats) ===
    # Detects high-entropy strings assigned to secret-like variable names
    if echo "$content" | grep -qE '(key|secret|token|password|auth|credential)[[:space:]]*[:=][[:space:]]*["'"'"'][a-zA-Z0-9+/=_-]{40,}["'"'"']'; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"High-entropy value detected in secret-like variable"}}'
        exit 0
    fi
fi

# === 4. Additional safety checks ===

# Check if writing to .git/config (could inject credential helpers)
if [ -n "$file_path" ] && echo "$file_path" | grep -qE '\.git/config$'; then
    content_check=$(echo "$input" | jq -r '(.tool_input.content // "") + (.tool_input.new_string // "")' 2>/dev/null || echo "")
    if echo "$content_check" | grep -qE 'credential.*helper'; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot modify git credential configuration"}}'
        exit 0
    fi
fi

# Check if writing hook scripts (could inject malicious code)
if [ -n "$file_path" ] && echo "$file_path" | grep -qE '\.git/hooks/'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Cannot write to git hooks directory"}}'
    exit 0
fi

# All checks passed - allow write
exit 0
