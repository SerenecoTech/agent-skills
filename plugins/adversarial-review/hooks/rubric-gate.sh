#!/usr/bin/env bash
# PreToolUse: Bash — fires only on a codex invocation.
#
# Validates rubric integrity before a review round runs.
#
# Convergence requires a round to use a probe id unused in the preceding round. That is
# gameable if the rubric contains near-duplicate probes: define two ids with effectively
# identical instructions, alternate them, and an empty repetition counts as convergence while
# no new attack surface is examined.
#
# Reviewing the rubric by eye is not enforcement, least of all when the same agent authors and
# uses it. So validate at invocation time instead.
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

ENGINE="$(dirname "$0")/../engine"
[ -d "$ENGINE" ] || exit 0

# Extract probe rows: | `ID` | description |
# Normalise the description hard — lowercase, strip punctuation, collapse whitespace, drop
# short filler words — so cosmetic rewording of a duplicate does not slip past.
DUPES="$(
  cat "$ENGINE"/rubric-*.md 2>/dev/null \
  | awk -F'|' '/^\| *`[A-Z][A-Z0-9-]*` *\|/ {
      id=$2; desc=$3
      gsub(/[` ]/, "", id)
      desc=tolower(desc)
      gsub(/[^a-z0-9 ]/, " ", desc)
      gsub(/ +/, " ", desc)
      gsub(/^ | $/, "", desc)
      n=split(desc, w, " "); out=""
      for (i=1; i<=n; i++) if (length(w[i]) > 3) out = out " " w[i]
      if (out != "") print out "\t" id
    }' \
  | sort | awk -F'\t' '{ if ($1 == prev) print prevn " and " $2; prev=$1; prevn=$2 }'
)"

if [ -n "$DUPES" ]; then
  FIRST="$(printf '%s' "$DUPES" | head -1)"
  log_gate rubric "DENY (near-duplicate probes: $FIRST)"
  deny "Rubric integrity check failed: near-duplicate probes detected ($FIRST). Alternating semantically identical probe ids satisfies the convergence rule mechanically while examining nothing new, so the round would count toward convergence dishonestly." \
       "Merge or genuinely differentiate the duplicated probes in the rubric before invoking codex. If they really do test different things, make the descriptions say how."
fi

# Advisory only: remind of the convergence rule with the preceding round's probes, since the
# hook cannot see which probes this round will declare.
PREV="$(jq -r '(.probes_previous_round // []) | join(", ")' "$STATE" 2>/dev/null)"
if [ -n "$PREV" ]; then
  log_gate rubric "ALLOW (advisory, prev=$PREV)"
  jq -nc --arg p "$PREV" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: ("Convergence rule: this round must use at least one probe id absent from the previous round (" + $p + "), and must re-run every probe whose findings were fixed since it last ran. Exception: if the previous round used every id in the rubric, a full-artefact candidate-final pass counts without a new one. Record probes_run in the output.")
    }
  }'
fi
exit 0
