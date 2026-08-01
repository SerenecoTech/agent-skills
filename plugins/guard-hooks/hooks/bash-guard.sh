#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - Bash Guard (Enhanced)
# =============================================================================
# Blocks dangerous bash commands before execution.
# Improved pattern coverage with bypass resistance.
#
# Input: JSON via stdin with tool_input.command
# Output: JSON with permissionDecision deny if dangerous
# =============================================================================

set -euo pipefail

# Fail-closed: if anything errors, deny by default
trap 'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Hook error - fail-closed\"}}"; exit 0' ERR

# Read stdin JSON
input=$(cat)

# Extract command from tool_input
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[ -z "$command" ] && exit 0

# Normalize command for better detection (remove most escaping/quoting)
normalized=$(echo "$command" | tr -d '\\"'\' | tr -s '[:space:]' ' ')

# === 1. Privilege escalation ===
# Catches: sudo, su, doas, pkexec — even with escaping
if echo "$normalized" | grep -qE '(^|[;&|()` ])(sudo|su|doas|pkexec)([^a-z]|$)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Privilege escalation blocked"}}'
    exit 0
fi

# === 2. Destructive file operations ===
destructive_patterns=(
    # Recursive force removal — handle both -rf and -fr flag orderings,
    # block root, home, and named system directories; allow /tmp
    'rm[[:space:]]+-[^[:space:]]*(rf|fr)[^[:space:]]*[[:space:]]+/($|[[:space:]])'
    'rm[[:space:]]+-[^[:space:]]*(rf|fr)[^[:space:]]*[[:space:]]+/(etc|usr|var|home|root|boot|lib|bin|sbin|opt|proc|sys)(/|[[:space:]]|$)'
    'rm[[:space:]]+-[^[:space:]]*(rf|fr)[^[:space:]]*[[:space:]]+~'
    'rm[[:space:]]+-[^[:space:]]*(rf|fr)[^[:space:]]*[[:space:]]+\*'
    'rm[[:space:]]+-[^[:space:]]*(rf|fr)[^[:space:]]*[[:space:]]+\.($|[[:space:]])'

    # Device writes — only block writes TO devices, not reads FROM them
    # (e.g. dd if=/dev/urandom is a safe read; dd of=/dev/sda is destructive)
    '(^|[[:space:];|&])dd[[:space:]].*of=/dev/'
    '(^|[[:space:];|&])(fdisk|parted|gdisk)[[:space:]].*(/dev|of=)'
    '(^|[[:space:];|&])mkfs[^[:space:]]*[[:space:]]'   # any mkfs variant (mkfs.ext4, mkfs.vfat, …)
    '>[[:space:]]*/dev/(sd|nvme|hd)'

    # Data destruction
    '(shred|wipe|wipefs|scrub)[[:space:]]'
    'truncate[[:space:]]+-s[[:space:]]*0'

    # Permission bombs
    'chmod[[:space:]]+-R[[:space:]]*777'
    'chmod[[:space:]].*[+][sg]'   # setuid (+s) and setgid (+g)

    # Fork bombs
    ':\(\)[[:space:]]*\{[[:space:]]*:'
)

for pattern in "${destructive_patterns[@]}"; do
    if echo "$normalized" | grep -qE "$pattern"; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Destructive operation blocked"}}'
        exit 0
    fi
done

# === 3. Dangerous git operations ===
# Block force operations on protected branches
if echo "$command" | grep -qE 'git[[:space:]]+push[[:space:]]+.*--force'; then
    if echo "$command" | grep -qE '(main|master|production|prod)'; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Force push to protected branch blocked"}}'
        exit 0
    fi
fi

# === 4. Indirect execution / obfuscation ===
obfuscation_patterns=(
    # Pipe to shell
    '(curl|wget|fetch)[^|]*\|[[:space:]]*(ba)?sh'

    # Base64 decode to shell
    'base64[[:space:]]+-d[^|]*\|[[:space:]]*(ba)?sh'

    # Eval with variables (potential code injection)
    'eval[[:space:]]+(\$|`)'

    # Bash process substitution
    '(bash|sh)[[:space:]]+<\('

    # Awk/sed system execution
    '(awk|sed)[^;]*system[[:space:]]*\('

    # Hex/octal encoding
    '\\x[0-9a-f]{2}'
    '\$\\[0-7]{3}'
)

for pattern in "${obfuscation_patterns[@]}"; do
    if echo "$command" | grep -qiE "$pattern"; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Obfuscated execution pattern blocked"}}'
        exit 0
    fi
done

# === 5. Credential/secret access ===

# File-reading checks run only against the first pipeline segment.
# Commands like `ls | grep ".env"` are filtering output — not reading the file.
first_segment=$(echo "$command" | sed 's/|.*//')

file_access_patterns=(
    '(cat|grep|less|tail|head|awk)[^;|]*(\.aws/credentials|\.ssh/id_|\.npmrc|\.pypirc|\.env)'
)

for pattern in "${file_access_patterns[@]}"; do
    if echo "$first_segment" | grep -qE "$pattern"; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Credential access blocked"}}'
        exit 0
    fi
done

# History manipulation checks apply to the full command
history_patterns=(
    'history[[:space:]]+-[[:space:]]*c'
    'HISTFILE=/dev/null'
    'unset[[:space:]]+HISTFILE'
)

for pattern in "${history_patterns[@]}"; do
    if echo "$command" | grep -qE "$pattern"; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"History manipulation blocked"}}'
        exit 0
    fi
done

# === 6. Network exfiltration (optional - may be too strict) ===
# Uncomment if you want to block common exfiltration patterns
# if echo "$command" | grep -qE '(nc|netcat|socat)[[:space:]]+.*[0-9]+\.[0-9]+'; then
#     echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Network exfiltration pattern blocked"}}'
#     exit 0
# fi

# All checks passed - allow execution
exit 0
