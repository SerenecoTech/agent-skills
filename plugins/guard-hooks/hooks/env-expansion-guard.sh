#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PreToolUse - Credential Env-Var Expansion Guard
# =============================================================================
# Denies a command that would print the value of a credential-bearing
# environment variable.
#
# Written after the August 2026 mortar leak, which no other guard came close to:
#
#   docker exec "$C" zsh -lc 'cd /workspace &&
#     echo "GH_TOKEN set: ${GH_TOKEN:+yes}${GH_TOKEN:-no}" && …'
#
# The author read that as a set/unset probe. It is not. `:-` substitutes the
# default only when the variable is EMPTY, so with a token present it prints
# "yes" followed by the token. Output was `GH_TOKEN set: yesgho_…`.
#
# There is no credential command in that line to enumerate — the printer is
# `echo` — so toolchain-guard's whole model has nothing to bite on. What makes
# this checkable is that parameter expansion is a five-form grammar, and the
# dangerous forms are literal substrings that survive any amount of nesting.
# `${GH_TOKEN:-no}` reads the same through docker exec, through zsh -lc, and
# through two layers of quoting. No shell parsing required.
#
# Measured, with a token in the variable:
#   ${V:+word}   → "word"        safe
#   ${#V}        → length        safe
#   ${V:0:4}     → 4-char prefix safe
#   [ -n "$V" ]  → nothing       safe
#   ${V:-word}   → THE VALUE     leaks
#   $V  ${V}     → THE VALUE     leaks
#
# Only fires when the command can print. Using a credential is not showing it,
# so `curl -H "Authorization: Bearer $GH_TOKEN"` is untouched.
#
# Fails CLOSED. The prototype for this hook first shipped a `pipefail` bug that
# made it fail OPEN and allow everything silently; denying loudly is the failure
# mode worth having.
#
# Input:  JSON via stdin with tool_input.command
# Output: hookSpecificOutput with permissionDecision deny, or exit 0 to allow
# =============================================================================

set -euo pipefail

trap 'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"env-expansion-guard error - failing closed\"}}"; exit 0' ERR

input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
[ -z "$command" ] && exit 0

deny() {
    jq -n --arg r "$1" \
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
    exit 0
}

# Variables that hold a credential, by suffix so tomorrow's SOMETHING_TOKEN
# needs no edit. Bare KEY is deliberately absent: PUBLIC_KEY, LICENSE_KEY and
# AWS_ACCESS_KEY_ID are not secrets, so the secret-bearing compounds are named.
CRED_VAR='[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|APIKEY|API_KEY|ACCESS_KEY|SECRET_KEY|PRIVATE_KEY|CREDENTIAL[S]?|PAT)'

# No printer, nothing to show. This is what keeps legitimate use working.
if ! printf '%s' "$command" | grep -qE '(^|[^a-zA-Z0-9_-])(echo|printf|print|cat|tee)([[:space:]]|$)'; then
    exit 0
fi

# Expansions that reveal the value, as literal syntax.
unsafe=""
for re in \
    "\\\$\\{${CRED_VAR}:?[-=][^}]*\\}" \
    "\\\$\\{${CRED_VAR}\\}" \
    "\\\$${CRED_VAR}([^A-Z0-9_]|\$)"
do
    if printf '%s' "$command" | grep -qE "$re"; then
        unsafe=$( { printf '%s' "$command" | grep -oE "$re" || true; } | head -1)
        break
    fi
done

[ -z "$unsafe" ] && exit 0

# A plain $V inside a test is never printed. If every plain occurrence is one of
# those, and no default-substitution form is present, there is nothing to deny.
# Each pipeline is guarded: grep returns non-zero when it finds nothing, and
# under `pipefail` that would reach the ERR trap and deny a safe command.
plain_count=$( { printf '%s' "$command" | grep -oE "\\\$\\{?${CRED_VAR}\\}?" || true; } | wc -l | tr -d ' ')
tested_count=$( { printf '%s' "$command" | grep -oE "\\-[nz][[:space:]]+\"?\\\$\\{?${CRED_VAR}\\}?\"?" || true; } | wc -l | tr -d ' ')
default_count=$( { printf '%s' "$command" | grep -cE "\\\$\\{${CRED_VAR}:?[-=][^}]*\\}" || true; } | tail -1)

if [ "${default_count:-0}" -eq 0 ] && [ "${plain_count:-0}" -le "${tested_count:-0}" ]; then
    exit 0
fi

deny "This command prints the value of a credential-bearing environment variable, and stdout becomes transcript.

Found: $unsafe

If the intent is to check whether it is set, note that ':-' prints the VALUE when the variable is set — it substitutes the default only when the variable is empty. So \${VAR:+yes}\${VAR:-no} prints 'yes' followed by the secret, which is how a real token reached a transcript in August 2026.

Forms that reveal nothing:
  \${VAR:+set}          prints 'set', or nothing when unset
  \${#VAR}              prints the length
  \${VAR:0:4}           prints a 4-character prefix
  [ -n \"\$VAR\" ] && echo present

To USE the credential rather than show it, pass it straight to the consumer — 'curl -H \"Authorization: Bearer \$VAR\"' is not affected by this rule."
