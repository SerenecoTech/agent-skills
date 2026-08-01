#!/usr/bin/env bash
# PreToolUse: Bash — fires only on a codex invocation.
#
# Ensures a previous review's refutation appendix is ingested before a new review begins.
#
# A refutation is only binding while its falsifier still holds. Left to instructions alone the
# appendix goes unread — a finding dismissed because an external guarantee held stays
# suppressed after that guarantee changes, and a fresh session has no reason to go looking.
#
# This turns "ought to read it" into "cannot begin without it", and rather than merely
# denying, it injects the appendix so the ingestion actually happens.
set -uo pipefail
. "$(dirname "$0")/lib-state.sh"

read_event

CMD="$(printf '%s' "$HOOK_JSON" | jq -r '.tool_input.command // empty')"
[ -n "$CMD" ] || exit 0
case "$CMD" in
  *"codex exec"*) ;;
  *) exit 0 ;;
esac

require_active_review

# Already ingested this session — nothing to do.
jq -e '.appendix_read == true' "$STATE" >/dev/null 2>&1 && exit 0

APPENDIX="$(state_get '.appendix')"
[ -n "$APPENDIX" ] || exit 0
case "$APPENDIX" in
  /*) APPENDIX_ABS="$APPENDIX" ;;
  *)  APPENDIX_ABS="$CWD/$APPENDIX" ;;
esac
# No prior appendix means no prior review of this artefact. Nothing to carry forward.
[ -s "$APPENDIX_ABS" ] || exit 0

# Cap what we inject. A whole appendix could crowd out the artefact, which is the failure
# that killed the full-ledger-every-round design in the first place.
BODY="$(head -c 4000 "$APPENDIX_ABS")"
LINES="$(wc -l < "$APPENDIX_ABS" | tr -d ' ')"
TRUNC=""
[ "$(wc -c < "$APPENDIX_ABS" | tr -d ' ')" -gt 4000 ] && TRUNC=$'\n\n[truncated — read the file in full before relying on it]'

log_gate appendix "DENY (unread appendix, ${LINES} lines) $APPENDIX"
deny "A refutation appendix from a previous review of this artefact exists at '$APPENDIX' ($LINES lines) and has not been ingested this session. Read it, then set .appendix_read = true in .claude/adversarial-review/state.json before invoking codex." \
"Previously refuted findings and their falsifiers follow. A refutation is only binding while its falsifier still holds — re-check each one against current state, and reopen any whose falsifier has stopped holding rather than treating it as settled.

--- $APPENDIX ---
${BODY}${TRUNC}"
