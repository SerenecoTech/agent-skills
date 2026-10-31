#!/usr/bin/env bash
# PreToolUse: Edit|Write|MultiEdit|NotebookEdit
#
# Keeps a review's edits on its scope for the duration of the review.
#
# The reviewing agent is the sole writer, adjudicator and verifier of its own fixes, so
# asking it to check its own diff is attestation rather than control: the same agent selects
# the diff, chooses the verification command and interprets the result. This gate constrains
# it because it is not the agent.
#
# Catches two things self-review structurally cannot:
#   1. a write to a file the agent never intended to touch (a generated file alongside the
#      intended source);
#   2. any write at all while no fix loop was authorised.
#
# It covers the file tools only. Writes made through Bash are not predicted here: working out
# what an arbitrary shell command writes has no end, and this gate limits a review's focus
# rather than policing the shell. engine/check-changes.sh compares the working tree against
# the snapshot taken when the review began and reports any change outside the allowed paths,
# however it was made.
#
# Paths are resolved first — . and .. collapsed, symlinked directories followed — so
# `.claude/adversarial-review/../../src/x.ts` is judged as src/x.ts. `..` is collapsed before
# symlinks are followed, so a symlink planted inside an exempt folder can still mislead it;
# check-changes.sh catches the resulting edit. Only the repository is governed: a write to
# /tmp or another project is not the review's concern.
set -uo pipefail
. "$(dirname "$0")/lib-state.sh"

read_event
require_active_review

TOOL="$(printf '%s' "$HOOK_JSON" | jq -r '.tool_name // empty')"
RAW="$(printf '%s' "$HOOK_JSON" | jq -r '
  .tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty')"
[ -n "$RAW" ] || exit 0

REPO="$(cd -P "$ROOT" 2>/dev/null && pwd)" || exit 0
TARGET="$(canonical_path "$RAW" "$CWD")"
[ -n "$TARGET" ] || TARGET="$RAW"
case "$TARGET" in "$REPO"/*) ;; *) exit 0 ;; esac
REL="${TARGET#"$REPO"/}"
LOOP="$(state_get '.loop')"

# The review's own bookkeeping must always be writable, or the skill cannot record anything.
case "$REL" in .claude/adversarial-review/*) exit 0 ;; esac
APPENDIX="$(state_get '.appendix')"
if [ -n "$APPENDIX" ] && [ "$TARGET" = "$(canonical_path "$APPENDIX" "$ROOT")" ]; then
  exit 0
fi

# A verdict review has no write authority whatsoever. This is the case ownership-based
# reasoning got wrong: "review my patch before I push" authorises review, not editing.
if [ "$LOOP" != "fix" ]; then
  log_gate write-path "DENY (loop=$LOOP) $REL"
  deny "Adversarial review is active in '${LOOP:-verdict}' mode, which carries no write authority. $TOOL on '$REL' was blocked. If you intend to fix findings, the user must explicitly authorise editing and the review state must declare the paths." \
       "The review is read-only. Report the finding instead of fixing it, or ask the user to authorise a fix loop with an explicit path allowlist."
fi

# Fix loop: the allowlist must exist and must match.
COUNT="$(jq -r '(.authorized_paths // []) | length' "$STATE" 2>/dev/null || echo 0)"
if [ "$COUNT" = "0" ]; then
  log_gate write-path "DENY (empty allowlist) $REL"
  deny "Adversarial review is in fix mode but declares no authorised paths, so every write is unauthorised. $TOOL on '$REL' was blocked." \
       "Declare authorized_paths in .claude/adversarial-review/state.json before fixing, and keep it to the files the finding actually requires."
fi

while IFS= read -r pattern; do
  [ -n "$pattern" ] || continue
  # shellcheck disable=SC2254  # the allowlist entries are globs
  case "$REL" in $pattern) exit 0 ;; esac
done < <(jq -r '(.authorized_paths // [])[]' "$STATE" 2>/dev/null)

PATTERNS="$(jq -r '(.authorized_paths // []) | join(", ")' "$STATE" 2>/dev/null)"
log_gate write-path "DENY (outside allowlist) $REL"
deny "'$REL' is outside the authorised paths for this review ($PATTERNS). $TOOL was blocked." \
     "Either the write is a mistake — check whether you meant a different file — or the finding genuinely requires a path nobody authorised, in which case report it rather than widening the allowlist yourself."
