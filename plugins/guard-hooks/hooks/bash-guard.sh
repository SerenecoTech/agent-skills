#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - Bash Guard (Enhanced)
# =============================================================================
# Blocks dangerous bash commands before execution.
#
# Checks that describe a command being RUN are matched in command position,
# using lib/shell-segments.awk to split the command the way a shell would.
# A word inside a heredoc body, a quoted string or a search pattern is data,
# and data does not get to deny a call.
#
# Input: JSON via stdin with tool_input.command
# Output: JSON with permissionDecision deny if dangerous
# =============================================================================

set -euo pipefail

# Fail-closed: if anything errors, deny by default
trap 'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Hook error - fail-closed\"}}"; exit 0' ERR

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEGMENTER="$HOOK_DIR/lib/shell-segments.awk"

# Read stdin JSON
input=$(cat)

# Extract command from tool_input
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[ -z "$command" ] && exit 0

# Emit a denial. The reason names the rule, the token that matched and the
# segment it matched in, so the caller can tell a real block from a bad rule
# without reading this file.
deny() {
    local reason="$1" json
    json=$(jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}')
    printf '%s\n' "$json"
    exit 0
}

snippet() {
    local text="$1"
    if [ "${#text}" -gt 60 ]; then
        printf '%s…' "${text:0:60}"
    else
        printf '%s' "$text"
    fi
}

# === 0. Split the command ====================================================
# seg_cmd[i] and seg_orig[i] describe the same segment. The label is
# L<list>S<stage>: stage 1 of a list is a command, later stages read its output.
seg_cmd=()
seg_orig=()
seg_stage=()

while IFS= read -r line; do
    seg_stage+=("${line%%$'\t'*}")
    seg_cmd+=("${line#*$'\t'}")
done < <(printf '%s' "$command" | awk -v mode=unquoted -f "$SEGMENTER")

while IFS= read -r line; do
    seg_orig+=("${line#*$'\t'}")
done < <(printf '%s' "$command" | awk -v mode=orig -f "$SEGMENTER")

[ "${#seg_cmd[@]}" -eq 0 ] && exit 0

flat=$(printf '%s' "$command" | awk -v mode=flat -f "$SEGMENTER")

# The word a segment actually runs: skip leading VAR=value assignments and
# wrappers that take a command as their argument, then take the basename.
ASSIGNMENT_RE='^[A-Za-z_][A-Za-z0-9_]*='
WRAPPER_RE='^(env|command|builtin|exec|nohup|time|nice|ionice|timeout|stdbuf|then|else|elif|do|!)$'

command_word() {
    local text="$1" tok
    set -f
    # shellcheck disable=SC2086
    set -- $text
    set +f
    while [ $# -gt 0 ]; do
        tok="$1"
        shift
        [[ "$tok" =~ $ASSIGNMENT_RE ]] && continue
        tok="${tok##*/}"
        [[ "$tok" =~ $WRAPPER_RE ]] && continue
        printf '%s' "$tok"
        return 0
    done
    printf ''
}

# === 0b. Read-only inspection of the guard's own tree ========================
# Auditing what this guard blocks is legitimate work, and the patterns below
# necessarily contain the words they block. Allow a single read-only command
# whose target is a guard file, provided it touches no credential file and
# writes nothing.
GUARD_PATH_RE='(guard-hooks|bash-guard\.sh|rm-guard\.sh|read-guard\.sh|write-guard\.sh|github-guard\.sh|toolchain-guard\.sh|env-expansion-guard\.sh|output-alarm\.sh|git-permission\.sh|shell-segments\.awk|secret-patterns\.sh)'
INSPECT_RE='^(cat|head|tail|less|more|nl|wc|grep|egrep|fgrep|rg|ls|stat|file|diff|shasum|md5sum|cksum)$'

if [ "${#seg_cmd[@]}" -eq 1 ] \
   && [[ "$(command_word "${seg_cmd[0]}")" =~ $INSPECT_RE ]] \
   && [[ "$flat" =~ $GUARD_PATH_RE ]] \
   && [[ "$flat" != *[\>\<]* ]]; then
    exit 0
fi

# === 1. Privilege escalation =================================================
# The binary has to BE the command. Naming it in a heredoc, a string or a
# search pattern is not running it.
ELEVATION_RE='^(sudo|su|doas|pkexec)$'

# These carry a command in their arguments rather than in command position, so
# an elevation binary anywhere in their segment is still a command to run.
COMMAND_CARRIER_RE='^(bash|sh|zsh|dash|ksh|eval|xargs|find|watch|ssh)$'
ELEVATION_ANYWHERE='(^|[;&|()` ])(sudo|su|doas|pkexec)([^a-z]|$)'

for i in "${!seg_cmd[@]}"; do
    word=$(command_word "${seg_cmd[$i]}")
    if [[ "$word" =~ $ELEVATION_RE ]]; then
        deny "Privilege escalation blocked: '$word' is the command in: $(snippet "${seg_orig[$i]}")"
    fi
    if [[ "$word" =~ $COMMAND_CARRIER_RE ]] \
       && match=$(printf '%s' "${seg_cmd[$i]}" | grep -oE "$ELEVATION_ANYWHERE" | head -1) \
       && [ -n "$match" ]; then
        deny "Privilege escalation blocked: '$word' carries a command containing '$(snippet "$match")' in: $(snippet "${seg_orig[$i]}")"
    fi
done

# === 2. Destructive file operations ==========================================
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
    if match=$(printf '%s' "$flat" | grep -oE "$pattern" | head -1) && [ -n "$match" ]; then
        deny "Destructive operation blocked: matched '$(snippet "$match")'"
    fi
done

# === 3. Dangerous git operations =============================================
# Block force operations on protected branches
if echo "$command" | grep -qE 'git[[:space:]]+push[[:space:]]+.*--force'; then
    if echo "$command" | grep -qE '(main|master|production|prod)'; then
        deny "Force push to protected branch blocked"
    fi
fi

# === 4. Indirect execution / obfuscation =====================================
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
    if match=$(printf '%s' "$command" | grep -oiE "$pattern" | head -1) && [ -n "$match" ]; then
        deny "Obfuscated execution pattern blocked: matched '$(snippet "$match")'"
    fi
done

# === 5. Credential/secret access =============================================
# Only stage 1 of a list reads a file. `ls | grep .env` is filtering output.
READ_COMMAND_RE='^(cat|grep|less|tail|head|awk)$'

# A committed defaults file is not a credential. These suffixes exist precisely
# because the file holds nothing, so .env.default and .env.example read fine
# while .env.local and .env.production do not.
is_credential_target() {
    local tok="$1" name suffix
    case "$tok" in
        *.aws/credentials) return 0 ;;
        *.ssh/id_*) return 0 ;;
    esac
    name="${tok##*/}"
    name="${name#*=}"
    case "$name" in
        .env|.envrc|.npmrc|.pypirc) return 0 ;;
        .env.*)
            suffix="${name#.env.}"
            case "$suffix" in
                default|defaults|example|examples|sample|samples|template|templates|dist|schema|tpl)
                    return 1 ;;
                *) return 0 ;;
            esac
            ;;
    esac
    return 1
}

# The tokens a segment treats as filenames. The search pattern of a
# grep-family command and the program text of awk or sed are not files, so
# `grep "\.env" src/` searches source for a string and reads no credential.
file_arguments() {
    local text="$1" tok word="" pattern_pending=0
    set -f
    # shellcheck disable=SC2086
    set -- $text
    set +f
    while [ $# -gt 0 ]; do
        tok="$1"
        [[ "$tok" =~ $ASSIGNMENT_RE ]] && { shift; continue; }
        if [[ "${tok##*/}" =~ $WRAPPER_RE ]]; then shift; continue; fi
        word="${tok##*/}"
        shift
        break
    done
    case "$word" in
        grep|egrep|fgrep|rg|awk|sed) pattern_pending=1 ;;
    esac
    while [ $# -gt 0 ]; do
        tok="$1"
        shift
        case "$tok" in
            -e|-f|--regexp|--file)
                pattern_pending=0
                [ $# -gt 0 ] && shift
                continue ;;
            --regexp=*|--file=*) pattern_pending=0; continue ;;
            --) continue ;;
            -?*) continue ;;
        esac
        if [ "$pattern_pending" -eq 1 ]; then
            pattern_pending=0
            continue
        fi
        printf '%s\n' "$tok"
    done
}

for i in "${!seg_cmd[@]}"; do
    [ "${seg_stage[$i]#*S}" = "1" ] || continue
    word=$(command_word "${seg_cmd[$i]}")
    [[ "$word" =~ $READ_COMMAND_RE ]] || continue

    while IFS= read -r tok; do
        if is_credential_target "$tok"; then
            deny "Credential access blocked: '$word' reads '$tok' in: $(snippet "${seg_orig[$i]}")"
        fi
    done < <(file_arguments "${seg_cmd[$i]}")
done

# History manipulation checks apply to the full command
history_patterns=(
    'history[[:space:]]+-[[:space:]]*c'
    'HISTFILE=/dev/null'
    'unset[[:space:]]+HISTFILE'
)

for pattern in "${history_patterns[@]}"; do
    if match=$(printf '%s' "$command" | grep -oE "$pattern" | head -1) && [ -n "$match" ]; then
        deny "History manipulation blocked: matched '$(snippet "$match")'"
    fi
done

# === 6. Network exfiltration (optional - may be too strict) ===================
# Uncomment if you want to block common exfiltration patterns
# if echo "$command" | grep -qE '(nc|netcat|socat)[[:space:]]+.*[0-9]+\.[0-9]+'; then
#     deny "Network exfiltration pattern blocked"
# fi

# All checks passed - allow execution
exit 0
