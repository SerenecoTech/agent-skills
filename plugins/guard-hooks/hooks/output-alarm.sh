#!/usr/bin/env bash
# =============================================================================
# Claude Code Hook: PostToolUse - Output Alarm
# =============================================================================
# Scans what a tool returned and raises an alarm if a credential came back.
#
# Read this before relying on it: PostToolUse CANNOT prevent anything. The docs
# are explicit — "the tool already ran" — and the event accepts no permission
# decision, so there is no redaction and no suppression. By the time this runs
# the credential is in the transcript.
#
# It is here because it is the only layer that covers printers nobody
# enumerated. The August 2026 mortar leak had no credential command in it at
# all: the printer was `echo`, the credential was $GH_TOKEN, and the whole thing
# was nested inside `docker exec … zsh -lc '…'`. Every PreToolUse guard allowed
# it. This one would have caught it — after the fact.
#
# What it buys is the difference between a leak you know about and one you do
# not, which is the difference between rotating a credential and not. It sets
# `continue: false` so the session stops rather than piling more work on top of
# a credential that now needs rotating.
#
# STRICT patterns only. The contextual tier matches a stub helper printing
# `password=STUB`, and halting a session on a heuristic is not a trade worth
# making.
#
# Fails OPEN: an error here must never halt a session by accident.
#
# Input:  JSON via stdin with tool_response
# Output: systemMessage + continue:false, or exit 0 silently
# =============================================================================

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"

trap 'exit 0' ERR

# shellcheck source=lib/secret-patterns.sh
. "$LIB_DIR/secret-patterns.sh"

input=$(cat)

# tool_response may be a string or a structure depending on the tool.
resp=$(printf '%s' "$input" \
    | jq -r '(.tool_response // empty) | if type == "string" then . else tojson end' 2>/dev/null || echo "")
[ -z "$resp" ] && exit 0

# A read of a fixture legitimately returns fake secrets.
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
if [ -n "$path" ] && secret_path_is_exempt "$path"; then
    exit 0
fi

# Cap the scan so a huge response cannot stall the session.
sample=$(printf '%s' "$resp" | head -c 262144 || true)

if hit=$(secret_scan "$sample" strict); then
    pattern="${hit%%$'\t'*}"
    shape="${hit#*$'\t'}"
    tool=$(printf '%s' "$input" | jq -r '.tool_name // "a tool"' 2>/dev/null || echo "a tool")
    jq -n --arg pat "$pattern" --arg s "$shape" --arg t "$tool" \
        '{"systemMessage":("CREDENTIAL IN TRANSCRIPT — output from " + $t + " matched " + $pat + " (value " + $s + "). This hook runs after the tool, so it cannot unsend it: the credential is already in context and in session memory. Treat it as compromised and rotate it now."),
          "continue":false,
          "stopReason":("A live credential reached the transcript (matched " + $pat + "). Stopping so it can be rotated before any further work builds on it.")}'
    exit 0
fi

exit 0
