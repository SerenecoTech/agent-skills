#!/usr/bin/env bash
# Shared helpers for the adversarial-review gates.
#
# Design rule for every gate: FAIL OPEN. If the state file is absent, malformed, or the
# review is not active, the hook must allow the call. A gate that breaks ordinary editing
# gets disabled, and a disabled gate is worse than none — the report still claims the
# guarantee while nothing enforces it.

STATE_REL=".claude/adversarial-review/state.json"

# Read the whole hook event from stdin once; callers use $HOOK_JSON.
# $CWD is the session's directory at the time of the call. $ROOT is the directory holding the
# review's state: the nearest ancestor of $CWD with a state.json, so a `cd src` mid-review does
# not switch the gates off. Without one, $ROOT is $CWD.
read_event() {
  HOOK_JSON="$(cat)"
  [ -n "$HOOK_JSON" ] || exit 0
  CWD="$(printf '%s' "$HOOK_JSON" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -n "$CWD" ] || CWD="$PWD"
  ROOT="$CWD"
  local dir="$CWD"
  while [ -n "$dir" ]; do
    if [ -f "$dir/$STATE_REL" ]; then ROOT="$dir"; break; fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  STATE="$ROOT/$STATE_REL"
}

# Exit 0 silently unless a review is active.
require_active_review() {
  [ -f "$STATE" ] || exit 0
  jq -e '.active == true' "$STATE" >/dev/null 2>&1 || exit 0
}

# True when a Bash command runs the reviewer wrapper. The skill sends every reviewer call
# through run-reviewer.sh, so that is the one form the gates recognise. They guide the review
# rather than police the shell: a reviewer CLI called directly, against the skill's
# instructions, is not detected.
is_reviewer_call() {
  case "$1" in *run-reviewer.sh*) return 0 ;; esac
  return 1
}

# An absolute path with . and .. resolved and symlinked directories followed, so
# `.claude/adversarial-review/../../src/x.ts` is judged as src/x.ts. Relative paths resolve
# from $2. Prints nothing for a path with an unexpanded variable or glob.
canonical_path() {
  local p="$1" base="$2" seg dir rest="" out=""
  case "$p" in *'$'*|*'*'*|*'?'*|*'['*) return 1 ;; esac
  # shellcheck disable=SC2088  # matching a literal ~ in the path, to expand it here
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    /*) ;;
    *) p="$base/$p" ;;
  esac
  local IFS=/
  local -a parts stack=()
  read -ra parts <<< "$p"
  for seg in "${parts[@]}"; do
    case "$seg" in
      ''|.) ;;
      ..) [ ${#stack[@]} -gt 0 ] && unset "stack[$((${#stack[@]} - 1))]" ;;
      *) stack+=("$seg") ;;
    esac
  done
  out="/${stack[*]}"
  # Follow symlinks in the longest prefix that exists (macOS /tmp is /private/tmp).
  dir="$out"
  while [ "$dir" != "/" ] && [ ! -d "$dir" ]; do
    rest="/${dir##*/}$rest"; dir="${dir%/*}"; [ -n "$dir" ] || dir="/"
  done
  dir="$(cd -P "$dir" 2>/dev/null && pwd)" || return 1
  printf '%s%s\n' "${dir%/}" "$rest"
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
  local dir="$ROOT/.claude/adversarial-review"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$dir/gate-log.tsv" 2>/dev/null || true
}
