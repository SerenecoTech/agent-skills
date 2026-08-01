#!/usr/bin/env bash
# PostToolUse: Bash
#
# The observational half of write authorisation. The write-path gate stops unauthorised edits;
# this records what verification actually ran and what it actually returned, so "verified" in a
# report is backed by something the agent did not author.
#
# Purely observational — never blocks, never fails the tool call.
set -uo pipefail
. "$(dirname "$0")/lib-state.sh"

read_event
require_active_review

CMD="$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.command // empty')"
[ -n "$CMD" ] || exit 0

# Only record plausible verification commands. Recording everything makes the log useless.
case "$CMD" in
  *test*|*vitest*|*pytest*|*jest*|*playwright*|*"bun run"*|*make*|*lint*|*tsc*|*ruff*) ;;
  *) exit 0 ;;
esac

STATUS="$(printf '%s' "$HOOK_JSON" | jq -r '
  .tool_response.exit_code // .tool_response.exitCode // .tool_response.status // "unknown"' 2>/dev/null)"

DIR="$CWD/.claude/adversarial-review"
mkdir -p "$DIR" 2>/dev/null || exit 0
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cmd "$CMD" --arg st "$STATUS" \
  '{ts: $ts, command: $cmd, exit: $st}' >> "$DIR/verifications.jsonl" 2>/dev/null || true

# Surface it back so the agent cannot claim a verification the log contradicts.
if [ "$STATUS" != "0" ] && [ "$STATUS" != "unknown" ]; then
  jq -nc --arg st "$STATUS" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: ("Verification command exited " + $st + ". It is recorded in .claude/adversarial-review/verifications.jsonl with that status — a fix cannot be reported as verified on the strength of this run.")
    }
  }'
fi
exit 0
