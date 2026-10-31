# shellcheck shell=bash
# Reviewer provider: Claude, as a separate `claude -p` process. Sourced by select-reviewer.sh
# and run-reviewer.sh. The contract every provider implements is in ../README.md.

CLAUDE_MODEL="${ADVERSARIAL_REVIEW_CLAUDE_MODEL:-opus}"
CLAUDE_EFFORT="${ADVERSARIAL_REVIEW_CLAUDE_EFFORT:-high}"

# Read-only: the reviewer may read the repo and run these git and gh commands, nothing else.
# `gh pr diff` and `gh pr view` are how review-code hands over a PR target. --restricted
# ignores the user's settings files, so their allow rules cannot widen this list, and dontAsk
# denies whatever is not on it. `--output=<file>` is the one way these git commands write, so
# it is denied explicitly.
CLAUDE_ALLOW=("Bash(git diff *)" "Bash(git log *)" "Bash(git show *)" "Bash(git status *)"
              "Bash(git ls-files *)" "Bash(git blame *)" "Bash(git rev-parse *)"
              "Bash(gh pr diff *)" "Bash(gh pr view *)")
CLAUDE_DENY=("Bash(git * --output*)")

CLAUDE_PROMPT="You are a hostile, independent reviewer. You did not write the work under review and have no stake in it. Find what is wrong with it: read the files the brief names, cite them verbatim, and report only defects you can support from the source. You cannot edit anything. Return your result in the required structured output."

provider_available() {
  command -v claude >/dev/null 2>&1 \
    && claude auth status --json 2>/dev/null | jq -e '.loggedIn == true' >/dev/null 2>&1
}

provider_label() {
  echo "claude $CLAUDE_MODEL effort=$CLAUDE_EFFORT"
}

provider_run() {
  # --no-session-persistence: without it every call saves a transcript and shows up as a
  # one-message session. --safe-mode: the user's CLAUDE.md, plugins and hooks stay out.
  # --json-schema does not accept the schema's "$schema" key, so it is removed.
  ( cd "$REPO" && with_timeout claude -p --safe-mode --restricted --no-session-persistence \
      --model "$CLAUDE_MODEL" --effort "$CLAUDE_EFFORT" \
      --tools "Read,Grep,Glob,Bash" --allowedTools "${CLAUDE_ALLOW[@]}" \
      --disallowedTools "${CLAUDE_DENY[@]}" \
      --permission-mode dontAsk --permission-prompts none \
      --append-system-prompt "$CLAUDE_PROMPT" \
      --output-format stream-json --verbose \
      --json-schema "$(jq -c 'del(."$schema")' "$SCHEMA")" \
      < "$OUT/brief.md" > "$OUT/trace.jsonl" 2> "$OUT/stderr.txt" ) || return

  # The findings are the structured_output of the final result event.
  jq -c 'select(.type == "result")' "$OUT/trace.jsonl" 2>/dev/null | tail -1 \
    | jq 'select(.is_error == false) | .structured_output // empty' > "$OUT/out.json" 2>/dev/null
  return 0
}
