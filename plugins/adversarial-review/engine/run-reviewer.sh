#!/usr/bin/env bash
# Run one reviewer call.
#
#   run-reviewer.sh [--max-calls N] <auto|provider> <repo-root> <out-dir> < brief.md
#
# auto takes the providers select-reviewer.sh lists, best first, and runs the first one. If
# that call fails it runs the next on the same brief instead of stopping, prints a FALLBACK
# line, and logs it, so the report can say what happened. A provider name runs only that one.
#
# --max-calls N stops after N provider calls, so a fallback cannot take the review past its
# budget. Pass the calls the review has left. Without it, every listed provider may be tried.
#
# Nothing here is specific to a provider. Each provider's flags live in
# providers/<name>/provider.sh; the contract is in providers/README.md.
#
# <out-dir> must not exist yet: it is created here, so two calls can never share one. Writes
# brief.md, out.json (checked against schema/findings.json), trace.jsonl (for
# verify-proof-of-work.sh), stderr.txt, schema-errors.json and reviewer (the provider's label).
# Every attempt is appended to <repo-root>/.claude/adversarial-review/reviewer-log.tsv. A failed
# call's files are moved to <out-dir>/failed-<provider>/, so a fallback does not erase them.
#
# Exit: 0 findings written, 2 usage, 3 no provider can run, 4 every attempted call failed,
#       5 the call budget ran out before any call succeeded.
set -uo pipefail

ENGINE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVIDERS="$ENGINE/providers"
SCHEMA="$ENGINE/schema/findings.json"
TIMEOUT_S=600
NO_OUTPUT=99   # the call exited 0 but out.json failed the schema check

usage() { echo "usage: $0 [--max-calls N] <auto|provider> <repo-root> <out-dir> < brief.md" >&2; exit 2; }

MAX_CALLS=""
if [ "${1:-}" = "--max-calls" ]; then
  [[ "${2:-}" =~ ^[0-9]+$ ]] || usage
  MAX_CALLS="$2"; shift 2
fi
[ $# -eq 3 ] || usage
MODE="$1"; REPO="$2"; OUT="$3"
[ "$MODE" = "auto" ] || [ -f "$PROVIDERS/$MODE/provider.sh" ] || usage
[ -d "$REPO" ] || { echo "repo root '$REPO' is not a directory" >&2; exit 2; }
REPO="$(cd "$REPO" && pwd)"

# mkdir without -p fails if the directory exists, and does so atomically, so a retry or a
# concurrent call cannot overwrite another call's brief and results.
mkdir -p "$(dirname "$OUT")" || exit 2
mkdir "$OUT" 2>/dev/null || { echo "output directory '$OUT' already exists; give each call a new one" >&2; exit 2; }
OUT="$(cd "$OUT" && pwd)"
cat > "$OUT/brief.md"
[ -s "$OUT/brief.md" ] || { echo "empty brief on stdin" >&2; exit 2; }
export REPO OUT SCHEMA

# Without timeout or gtimeout installed, a call runs without a limit.
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
with_timeout() {
  if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$TIMEOUT_S" "$@"; else "$@"; fi
}

log_attempt() {
  local dir="$REPO/.claude/adversarial-review"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$OUT" >> "$dir/reviewer-log.tsv" 2>/dev/null || true
}

# A clean exit is not evidence: out.json must satisfy the schema itself.
output_ok() {
  jq -c --slurpfile schema "$SCHEMA" -f "$ENGINE/schema/check-output.jq" "$OUT/out.json" \
    > "$OUT/schema-errors.json" 2>/dev/null || echo '["out.json is missing or is not JSON"]' > "$OUT/schema-errors.json"
  [ "$(cat "$OUT/schema-errors.json")" = "[]" ]
}

failure_note() {
  if [ "$1" -eq 124 ]; then echo "timed out after ${TIMEOUT_S}s"
  elif [ "$1" -eq "$NO_OUTPUT" ]; then echo "exited 0 but out.json fails the schema: $(jq -r '.[0:3] | join("; ")' "$OUT/schema-errors.json" 2>/dev/null)"
  else echo "exit $1: $(tail -n 3 "$OUT/stderr.txt" 2>/dev/null | tr '\n' ' ' | cut -c1-300)"
  fi
}

# Run one provider in a subshell, so one provider's variables cannot leak into the next.
run_provider() {
  (
    # shellcheck disable=SC1090
    . "$PROVIDERS/$1/provider.sh" || exit 2
    rm -f "$OUT/out.json"
    provider_label > "$OUT/reviewer"
    provider_run || exit
    output_ok || exit "$NO_OUTPUT"
  )
}

if [ "$MODE" = "auto" ]; then
  candidates="$(bash "$ENGINE/select-reviewer.sh")" || exit 3
else
  candidates="$MODE"
fi

previous=""
calls=0
for name in $candidates; do
  if [ -n "$MAX_CALLS" ] && [ "$calls" -ge "$MAX_CALLS" ]; then
    echo "BUDGET: $calls of $MAX_CALLS calls used; not trying $name. Last failure: ${previous:-none}" >&2
    log_attempt "$name" "NOT RUN: call budget of $MAX_CALLS used"
    exit 5
  fi
  if [ -n "$previous" ]; then
    echo "FALLBACK: $previous. Running $name instead. State this in the report." >&2
    log_attempt "$name" "FALLBACK after: $previous"
  fi
  calls=$((calls + 1))
  run_provider "$name"; rc=$?
  if [ "$rc" -eq 0 ]; then
    log_attempt "$name" "ok"
    echo "REVIEWER: $(cat "$OUT/reviewer") — findings in $OUT/out.json, trace in $OUT/trace.jsonl (calls used: $calls)"
    exit 0
  fi
  previous="$name call failed ($(failure_note "$rc"))"
  log_attempt "$name" "FAILED: $(failure_note "$rc")"
  # Keep the failed call's evidence: the next provider would overwrite it in place.
  mkdir -p "$OUT/failed-$name"
  for f in trace.jsonl stderr.txt out.json schema-errors.json reviewer; do
    [ -e "$OUT/$f" ] && /bin/mv -f "$OUT/$f" "$OUT/failed-$name/$f"
  done
  echo "FAILED: $name — full stderr and trace kept in $OUT/failed-$name/" >&2
done

echo "$previous. No provider left to try. Calls used: $calls" >&2
exit 4
