#!/usr/bin/env bash
# PostToolUse and PostToolUseFailure: Bash
#
# The observational half of write authorisation. The write-path gate stops unauthorised edits;
# this records what verification actually ran and what it actually returned, so "verified" in a
# report is backed by something the agent did not author.
#
# Claude Code reports a Bash command's outcome by which event fires, not by a field: a command
# that exits 0 fires PostToolUse, whose tool_response holds stdout and stderr but no exit code;
# one that exits non-zero usually fires PostToolUseFailure, whose `error` begins "Exit code N".
# Some non-zero exits still fire PostToolUse, marked by returnCodeInterpretation; see below.
# (Observed by dumping the payloads, Claude Code 2.1.312.)
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
  *test*|*jest*|*playwright*|*"bun run"*|*make*|*lint*|*tsc*|*ruff*) ;;   # *test* covers vitest, pytest
  *) exit 0 ;;
esac

EVENT="$(printf '%s' "$HOOK_JSON" | jq -r '.hook_event_name // empty')"
if [ "$EVENT" = "PostToolUseFailure" ]; then
  STATUS="$(printf '%s' "$HOOK_JSON" | jq -r '
    (.error // "") | (capture("^Exit code (?<n>[0-9]+)").n // "failed")' 2>/dev/null)"
  [ -n "$STATUS" ] || STATUS="failed"
else
  # PostToolUse is not proof of exit 0: Claude Code treats some non-zero exits as ordinary
  # results (`test` exiting 1 arrives with returnCodeInterpretation "Condition is false"), and
  # a command sent to the background has not finished. Only record 0 when neither applies.
  STATUS="$(printf '%s' "$HOOK_JSON" | jq -r '
    .tool_response as $r
    | if ($r.backgroundTaskId? // null) != null then "background (not finished)"
      elif ($r.returnCodeInterpretation? // null) != null then "non-zero (" + $r.returnCodeInterpretation + ")"
      else "0" end' 2>/dev/null)"
  [ -n "$STATUS" ] || STATUS="unknown"
fi

DIR="$ROOT/.claude/adversarial-review"
mkdir -p "$DIR" 2>/dev/null || exit 0
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cmd "$CMD" --arg st "$STATUS" \
  '{ts: $ts, command: $cmd, exit: $st}' >> "$DIR/verifications.jsonl" 2>/dev/null || true

# Surface it back so the agent cannot claim a verification the log contradicts.
if [ "$STATUS" != "0" ]; then
  jq -nc --arg st "$STATUS" --arg ev "${EVENT:-PostToolUseFailure}" '{
    hookSpecificOutput: {
      hookEventName: $ev,
      additionalContext: ("Verification command exited " + $st + ". It is recorded in .claude/adversarial-review/verifications.jsonl with that status — a fix cannot be reported as verified on the strength of this run.")
    }
  }'
fi
exit 0
