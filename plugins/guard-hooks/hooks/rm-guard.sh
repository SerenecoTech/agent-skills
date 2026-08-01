#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - rm Guard
# =============================================================================
# Pre-approves `rm` of individual files that resolve strictly inside the
# Claude Code project root. Handles single rm invocations AND compound
# commands (`;`, `&&`, `||`, `|`), provided every segment is statically
# decidable:
#   - rm segments must satisfy rm-guard's safety rules (no recursion, no
#     globs, no quotes, project-relative paths, parent resolved through
#     symlinks stays inside the project root, target is not a directory).
#   - Non-rm segments must either invoke a known-inert builtin or match an
#     existing `permissions.allow` pattern from ~/.claude/settings.json.
#     This mirrors what claude-compound-bash would approve and keeps the
#     hook's `allow` from over-permitting compounds with dangerous
#     siblings, since Claude Code's hook combination treats allow as more
#     permissive than ask.
#
# Anything containing $, backticks, $(, <(, >(, or redirection (<, >)
# falls through to the normal permission flow — the value provided to rm
# (or to a sibling command) can't be statically asserted.
#
# This hook never denies; bash-guard.sh is the defence-in-depth deny.
#
# Input:  JSON via stdin with tool_input.command
# Output: hookSpecificOutput with permissionDecision=allow on safe input,
#         otherwise exits 0 with no decision.
# =============================================================================

set -euo pipefail
trap 'exit 0' ERR

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$command" ] && exit 0

# Reject command/process substitution, variable expansion, and redirection
# outright — these inject values we can't validate statically.
if echo "$command" | LC_ALL=C grep -qE '`|\$\(|<\(|>\(|\$[A-Za-z_{]|[<>]'; then
    exit 0
fi

project_root="${CLAUDE_PROJECT_DIR:-$(pwd -P)}"
project_root=$(cd "$project_root" 2>/dev/null && pwd -P) || exit 0
project_root="${project_root%/}"

# -----------------------------------------------------------------------------
# Static allow/deny patterns from all Claude Code settings layers.
# -----------------------------------------------------------------------------
# Mirrors claude-compound-bash's settings discovery: user-global and
# project-local settings, plus their .local.json siblings. Later files
# don't override earlier ones — patterns are unioned because allow/deny
# are list-merged in Claude Code's permission model.
load_patterns() {
    local key="$1" f
    local files=(
        "$HOME/.claude/settings.json"
        "$HOME/.claude/settings.local.json"
        "$project_root/.claude/settings.json"
        "$project_root/.claude/settings.local.json"
    )
    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            jq -r ".permissions.${key}[]? // empty" "$f" 2>/dev/null || true
        fi
    done
}

SETTINGS_ALLOW=$(load_patterns allow)
SETTINGS_DENY=$(load_patterns deny)

# Bash() pattern → regex. `*` becomes `.*`; other regex specials are escaped.
pattern_to_regex() {
    local pat="$1" inner esc='' i=0 ch
    case "$pat" in
        Bash|'Bash(*)') echo '.*'; return ;;
        Bash\(*\)) inner="${pat#Bash(}"; inner="${inner%)}" ;;
        *) echo ''; return ;;
    esac
    while [ $i -lt ${#inner} ]; do
        ch="${inner:$i:1}"
        case "$ch" in
            '.'|'+'|'?'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'\\') esc+="\\$ch" ;;
            '*') esc+='.*' ;;
            *) esc+="$ch" ;;
        esac
        i=$((i+1))
    done
    echo "$esc"
}

match_patterns() {
    local cmd="$1" patterns="$2" pat regex
    while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        regex=$(pattern_to_regex "$pat")
        [ -z "$regex" ] && continue
        if printf '%s' "$cmd" | LC_ALL=C grep -qE "^${regex}$"; then
            return 0
        fi
    done <<< "$patterns"
    return 1
}

match_static_allow() { match_patterns "$1" "$SETTINGS_ALLOW"; }
match_static_deny()  { match_patterns "$1" "$SETTINGS_DENY"; }

# Known-inert command words (from claude-compound-bash's safe-tier list).
# Anchored full-word match.
SAFE_INERT_RE='^(true|false|:|test|\[|\[\[|ls|cat|head|tail|wc|uniq|date|whoami|basename|dirname|realpath|readlink|which|file|stat|uname|id|hostname|tr|cut|rev|seq|sleep|diff|comm|printenv|echo|printf|cd|pwd|exit|return|shift|unset|read|pushd|popd|dirs|hash|type|umask|wait|times|ulimit|break|continue|getopts)$'

# -----------------------------------------------------------------------------
# Split a command on top-level &&, ||, ;, | — respecting single/double
# quotes. We've already rejected $/`/$(/<(/>( upstream, so quote handling
# is the only contextual subtlety left.
# -----------------------------------------------------------------------------
split_segments() {
    awk '
    {
        in_sq=0; in_dq=0; out="";
        n=length($0);
        for (i=1; i<=n; i++) {
            ch=substr($0,i,1);
            nx=(i<n)?substr($0,i+1,1):"";
            if (in_sq) { out=out ch; if (ch=="\047") in_sq=0; continue; }
            if (in_dq) { out=out ch; if (ch=="\"") in_dq=0; continue; }
            if (ch=="\047") { in_sq=1; out=out ch; continue; }
            if (ch=="\"")   { in_dq=1; out=out ch; continue; }
            if ((ch=="&" && nx=="&") || (ch=="|" && nx=="|")) {
                print out; out=""; i++; continue;
            }
            if (ch==";" || ch=="|" || ch=="&") { print out; out=""; continue; }
            out=out ch;
        }
        if (length(out)>0) print out;
    }'
}

# -----------------------------------------------------------------------------
# Validate a single rm sub-command. Returns 0 if it is safe to auto-approve,
# 1 otherwise.
# -----------------------------------------------------------------------------
validate_rm_segment() {
    local segment="$1"

    # Trim outer whitespace and any wrapping parens.
    segment=$(printf '%s' "$segment" | sed -E 's/^[[:space:]]*\(?[[:space:]]*//; s/[[:space:]]*\)?[[:space:]]*$//')

    # rm segments must not be quoted at the first-word level; quotes
    # complicate operand tokenization and we'd rather fall through.
    case "$segment" in
        *\"*|*\'*) return 1 ;;
    esac

    case "$segment" in
        rm|rm\ *|rm$'\t'*) : ;;
        *) return 1 ;;
    esac

    set -f
    # shellcheck disable=SC2086
    set -- $segment
    set +f

    [ "${1:-}" = "rm" ] || return 1
    shift

    local operands=()
    local tok end_of_opts=0
    for tok in "$@"; do
        if [ "$end_of_opts" -eq 1 ]; then
            operands+=("$tok")
            continue
        fi
        case "$tok" in
            --) end_of_opts=1 ;;
            --recursive|--recursive=*|--dir) return 1 ;;
            --*) : ;;
            -*)
                if [[ "$tok" == *[rR]* ]]; then
                    return 1
                fi
                ;;
            *) operands+=("$tok") ;;
        esac
    done

    [ ${#operands[@]} -gt 0 ] || return 1

    local path abs parent base resolved_parent resolved
    for path in "${operands[@]}"; do
        case "$path" in
            *'*'*|*'?'*|*'['*) return 1 ;;
            '~'*|/*) return 1 ;;
        esac

        abs="$project_root/$path"
        parent=$(dirname "$abs")
        base=$(basename "$abs")

        [ -d "$parent" ] || return 1
        resolved_parent=$(cd "$parent" 2>/dev/null && pwd -P) || return 1
        resolved="$resolved_parent/$base"

        case "$resolved" in
            "$project_root"/*) : ;;
            *) return 1 ;;
        esac

        if [ -d "$resolved" ]; then
            return 1
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# Validate a non-rm sub-command: either its first word is a known-inert
# builtin, or the segment matches one of the static allow patterns.
# -----------------------------------------------------------------------------
validate_other_segment() {
    local segment="$1"
    segment=$(printf '%s' "$segment" | sed -E 's/^[[:space:]]*\(?[[:space:]]*//; s/[[:space:]]*\)?[[:space:]]*$//')
    [ -z "$segment" ] && return 0   # empty segments (trailing operators) are inert

    # Deny always wins (compound-bash semantics).
    if match_static_deny "$segment"; then
        return 1
    fi

    local first_word
    first_word=$(printf '%s' "$segment" | awk '{
        for (i=1; i<=NF; i++) if ($i !~ /^[A-Z_][A-Z_0-9]*=/) { print $i; exit }
    }')
    [ -z "$first_word" ] && return 1

    local base
    base=$(basename "$first_word")

    if printf '%s' "$base" | LC_ALL=C grep -qE "$SAFE_INERT_RE"; then
        return 0
    fi

    match_static_allow "$segment"
}

# -----------------------------------------------------------------------------
# Walk segments. At least one must be a safe rm; every segment must validate.
# -----------------------------------------------------------------------------
saw_safe_rm=0
while IFS= read -r segment; do
    trimmed=$(printf '%s' "$segment" | sed -E 's/^[[:space:]]*\(?[[:space:]]*//; s/[[:space:]]*\)?[[:space:]]*$//')
    [ -z "$trimmed" ] && continue

    first_word=$(printf '%s' "$trimmed" | awk '{
        for (i=1; i<=NF; i++) if ($i !~ /^[A-Z_][A-Z_0-9]*=/) { print $i; exit }
    }')

    case "$first_word" in
        rm)
            if match_static_deny "$trimmed"; then
                exit 0
            fi
            if ! validate_rm_segment "$trimmed"; then
                exit 0
            fi
            saw_safe_rm=1
            ;;
        *)
            if ! validate_other_segment "$trimmed"; then
                exit 0
            fi
            ;;
    esac
done < <(printf '%s' "$command" | split_segments)

[ "$saw_safe_rm" -eq 1 ] || exit 0

jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"rm-guard: all rm sub-commands target individual files inside project root; all sibling sub-commands match safe-builtin or allow patterns"}}'
exit 0
