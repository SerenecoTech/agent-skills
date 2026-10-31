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
trap 'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"write-guard.sh failed at line $LINENO while checking this write, and it denies when it fails. No rule matched the write: this is a fault in the hook, not a block of the content.\"}}"; exit 0' ERR

# Emit a denial. The reason names the rule and what matched, so the caller can
# change the write without reading this file.
deny() {
    jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
}

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
        if match=$(printf '%s' "$resolved_path" | grep -oiE "$pattern" | head -1) && [ -n "$match" ]; then
            deny "Cannot write to protected file: $file_path (resolved: $resolved_path). The path matches '$match', a credential or secret file pattern. Write a non-secret template instead (for example .env.example), or ask the user to edit this file."
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
            deny "Cannot write to system directory: $resolved_path is under ${pattern#^}, which belongs to the operating system, not the project."
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
    # secret_scan reports the pattern and a shape hint, never the whole value.
    if hit=$(secret_scan "$content" all); then
        deny "Potential secret detected in content for ${file_path:-this write} (matched ${hit%%$'\t'*}, value ${hit#*$'\t'}). Read the value from an environment variable or a secrets store instead of writing it into the file. If the value is fake, a path naming itself test/fixture/example/sample is exempt from this check."
    fi
    # Entropy-based detection (a long quoted literal assigned to a secret-like
    # name) used to be a separate check here. It is now one of the shared
    # patterns, which also lets read-guard apply it.
fi

# === 3. Additional safety checks ===

# Check if writing to .git/config (could inject credential helpers). Git writes
# the helper as `helper = ...` on its own line under a [credential] section, and
# an Edit may carry only that line, so a bare helper key counts as well as the
# one-line `credential.helper` form. Git config keys are case-insensitive.
if [ -n "$file_path" ] && echo "$file_path" | grep -qE '\.git/config$'; then
    content_check=$(echo "$input" | jq -r '(.tool_input.content // "") + (.tool_input.new_string // "")' 2>/dev/null || echo "")
    if echo "$content_check" | grep -qiE 'credential.*helper|^[[:space:]]*helper[[:space:]]*='; then
        deny "Cannot modify git credential configuration: the content written to $file_path sets a credential helper, a program git runs whenever it needs a password. Ask the user to change credential settings."
    fi
fi

# Check if writing hook scripts (could inject malicious code)
if [ -n "$file_path" ] && echo "$file_path" | grep -qE '\.git/hooks/'; then
    deny "Cannot write to git hooks directory: $file_path is under .git/hooks, and scripts there run automatically on git commands, outside these checks. Ask the user to install the hook."
fi

# All checks passed - allow write
exit 0
