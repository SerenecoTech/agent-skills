# shellcheck shell=bash
# Reviewer provider: OpenAI Codex. Sourced by select-reviewer.sh and run-reviewer.sh.
# The contract every provider implements is in ../README.md.

provider_available() {
  command -v codex >/dev/null 2>&1 && codex login status >/dev/null 2>&1
}

provider_label() {
  echo "codex"
}

provider_run() {
  # --ephemeral: without it every call saves a Codex session file.
  with_timeout codex exec --ephemeral -C "$REPO" -s danger-full-access --json \
    --output-schema "$SCHEMA" -o "$OUT/out.json" - \
    < "$OUT/brief.md" > "$OUT/trace.jsonl" 2> "$OUT/stderr.txt"
}
