#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - Read Guard
# =============================================================================
# Denies a file read when the file already holds a credential.
#
# This is the one credential check that needs no knowledge of commands. The file
# exists on disk before the tool runs, so the hook opens it, looks at what is
# actually there, and refuses. No shell to parse, no command to enumerate — the
# question "does this contain a secret" is asked of the data itself.
#
# Scope is the Read tools. A `cat` in Bash is a different shape (bash-guard
# category 5 covers the well-known credential paths) and is not handled here.
#
# Fails CLOSED, like write-guard: a broken guard that denies every read stops
# work immediately and visibly, which gets fixed. One that allows every read
# leaks silently, which does not.
#
# Input:  JSON via stdin with tool_input.file_path
# Output: hookSpecificOutput with permissionDecision deny, or exit 0 to allow
# =============================================================================

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"

trap 'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"read-guard error - failing closed\"}}"; exit 0' ERR

# shellcheck source=lib/secret-patterns.sh
. "$LIB_DIR/secret-patterns.sh"

input=$(cat)

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || echo "")
[ -z "$path" ] && exit 0
[ -f "$path" ] || exit 0

# Conventionally-fake secrets live in fixtures and examples. Skipping them is a
# deliberate blind spot, not an oversight — see the note in secret-patterns.sh.
if secret_path_is_exempt "$path"; then
    exit 0
fi

# Cap the read. A secret past this offset is missed; the alternative is a hook
# that stalls on a multi-gigabyte file on every single Read.
sample=$(head -c 262144 "$path" 2>/dev/null || true)
[ -z "$sample" ] && exit 0

if hit=$(secret_scan "$sample" all); then
    pattern="${hit%%$'\t'*}"
    shape="${hit#*$'\t'}"
    reason="Not reading $path: it holds what looks like a live credential (matched $pattern, value $shape).

Reading it would copy the credential into the transcript, and a credential in a transcript has to be treated as rotated rather than deleted.

Ways to work with this file without reading the value:
  grep -c 'pattern' $path                          confirm a key exists
  grep -oE '^[A-Za-z_]+=' $path                    list the key names only
  sed -E 's/=.*/=REDACTED/' $path > /tmp/redacted   then read that

If the value is genuinely fake, a path naming itself test/fixture/example/sample is exempt from this check."

    jq -n --arg r "$reason" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
    exit 0
fi

exit 0
