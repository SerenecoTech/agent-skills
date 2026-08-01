#!/usr/bin/env bash
# Shared helpers for the adversarial-review gates.
#
# Design rule for every gate: FAIL OPEN. If the state file is absent, malformed, or the
# review is not active, the hook must allow the call. A gate that breaks ordinary editing
# gets disabled, and a disabled gate is worse than none — the report still claims the
# guarantee while nothing enforces it.

STATE_REL=".claude/adversarial-review/state.json"

# Read the whole hook event from stdin once; callers use $HOOK_JSON.
read_event() {
  HOOK_JSON="$(cat)"
  [ -n "$HOOK_JSON" ] || exit 0
  CWD="$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -n "$CWD" ] || CWD="$PWD"
  STATE="$CWD/$STATE_REL"
}

# Exit 0 silently unless a review is active.
require_active_review() {
  [ -f "$STATE" ] || exit 0
  jq -e '.active == true' "$STATE" >/dev/null 2>&1 || exit 0
}

state_get() {
  jq -r "$1 // empty" "$STATE" 2>/dev/null
}

# Emit a PreToolUse deny decision and exit. $1 = reason, $2 = optional additionalContext.
deny() {
  if [ -n "${2:-}" ]; then
    jq -nc --arg r "$1" --arg c "$2" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r,
        additionalContext: $c
      }
    }'
  else
    jq -nc --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
  fi
  exit 0
}

# Record which gates actually fired, so a report can state what was enforced rather than
# assuming. A gate nobody can prove ran is indistinguishable from one that is not installed.
log_gate() {
  local dir="$CWD/.claude/adversarial-review"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$dir/gate-log.tsv" 2>/dev/null || true
}
