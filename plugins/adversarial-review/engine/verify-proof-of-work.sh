#!/usr/bin/env bash
# Proof of work: verify a reviewer actually read the target it reports on. Reads the trace
# format of either reviewer that run-reviewer.sh drives: codex --json and claude stream-json.
#
#   verify-proof-of-work.sh <result.json> <trace.jsonl> <target-file> <probe-lines-csv>
#
# Run it from the repository root: relative citation paths resolve from there.
#
# Four independent checks:
#   1. reviewed path — the target must sit inside the reviewed_path the review reports
#   2. probe echo    — verbatim text of unpredictably chosen, non-blank lines must match the file
#   3. citations     — each finding's quoted substring must occur in the file it cites
#   4. trace audit   — every probe line's text must appear in the output of a tool call that
#                      succeeded, so the content provably reached the reviewer
#
# Exit 0 = proof accepted. Exit 1 = proof failed -> INVESTIGATE before voiding.
#
# Deliberately not "exit 1 = void". A verifier is at least as likely to be wrong as the
# reviewer it polices, so a failure is a prompt to investigate, not an automatic discard of
# the findings. Two known false-positive modes make the point: a staleness race, where line
# counts are compared against a file edited since the read — routine in a fix loop — and
# transport escaping, where `jq @tsv` escapes the newline inside a citation that spans a
# hard-wrapped line.
set -uo pipefail

RESULT="$1"; TRACE="$2"; TARGET="$3"; PROBES="$4"
fail=0
hr() { printf '%s\n' "-------------------------------------------------------------"; }

# Collapse all whitespace runs, newlines included, to single spaces, so a quote spanning a
# wrapped line compares equal to the source it came from. Fields are read from the JSON one at
# a time, never through @tsv, so no transport escaping needs undoing: undoing it would also
# rewrite a literal \n in the source.
norm() {
  tr '\n' ' ' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

abspath() {
  if [ -d "$1" ]; then (cd "$1" && pwd)
  elif [ -e "$1" ]; then printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd)" "$(basename "$1")"
  fi
}

hr; echo "1. REVIEWED PATH  (the target must be inside what the review says it reviewed)"; hr
reviewed=$(jq -r '.reviewed_path // ""' "$RESULT" 2>/dev/null)
reviewed_abs=$(abspath "$reviewed")
target_abs=$(abspath "$TARGET")
if [ -z "$reviewed_abs" ]; then
  echo "FAIL    reviewed_path '$reviewed' does not exist"; fail=1
else
  case "$target_abs" in
    "$reviewed_abs"|"$reviewed_abs"/*) echo "OK      $reviewed" ;;
    *) echo "FAIL    target $TARGET is not inside reviewed_path '$reviewed'"; fail=1 ;;
  esac
fi

hr; echo "2. PROBE ECHO  (non-blank lines chosen unpredictably at launch)"; hr
for n in ${PROBES//,/ }; do
  claimed=$(jq -r --argjson n "$n" '.probe_echo[] | select(.line==$n) | .text' "$RESULT" 2>/dev/null)
  actual=$(sed -n "${n}p" "$TARGET")
  # A blank line can be "echoed" by guessing "", so it proves nothing. Choose lines with
  # awk 'NF{print NR}' <file> | shuf -n 3.
  if [ -z "$(printf '%s' "$actual" | tr -d '[:space:]')" ]; then
    printf 'FAIL    line %-4s is blank and proves nothing — choose non-blank probe lines\n' "$n"; fail=1
  elif ! jq -e --argjson n "$n" 'any(.probe_echo[]; .line==$n)' "$RESULT" >/dev/null 2>&1; then
    printf 'FAIL    line %-4s not echoed at all\n' "$n"; fail=1
  elif [ "$claimed" = "$actual" ]; then
    printf 'OK      line %-4s exact match\n' "$n"
  elif [ "$(printf '%s' "$claimed" | sed 's/[[:space:]]*$//')" = "$(printf '%s' "$actual" | sed 's/[[:space:]]*$//')" ]; then
    # Only trailing whitespace may differ. Leading whitespace is meaning in Python or YAML, so
    # an echo with different indentation is a mismatch: often the file changed since the read.
    printf 'OK*     line %-4s match except trailing whitespace\n' "$n"
  else
    printf 'FAIL    line %-4s MISMATCH\n          claimed: %s\n          actual : %s\n' \
      "$n" "$claimed" "$actual"; fail=1
  fi
done

hr; echo "3. CITATIONS  (quoted substring must occur in the file the finding cites)"; hr
total=0; bad=0
count=$(jq -r '.findings | length' "$RESULT" 2>/dev/null || echo 0)
for ((i = 0; i < count; i++)); do
  field() { jq -r --argjson i "$i" ".findings[\$i]$1" "$RESULT"; }
  id=$(field '.id'); file=$(field '.citation.file'); line=$(field '.citation.line')
  quote=$(field '.citation.verbatim')
  total=$((total+1))
  if [ ! -f "$file" ]; then
    printf 'FAIL    %-14s cites %s, which does not exist\n' "$id" "$file"
    bad=$((bad+1)); continue
  fi
  src=$(sed -n "${line}p" "$file")
  nq=$(printf '%s' "$quote" | norm)
  if [ -n "$src" ] && [ "${src#*"$quote"}" != "$src" ]; then
    printf 'OK      %-14s %s:%s\n' "$id" "$file" "$line"
  elif [ -n "$nq" ] && sed -n "${line},$((line + 4))p" "$file" | norm | grep -qF -- "$nq"; then
    # A citation may run onto the next few lines when the source is hard-wrapped.
    printf 'OK*     %-14s %s:%s — spans a wrapped line\n' "$id" "$file" "$line"
  elif [ -n "$nq" ] && norm < "$file" | grep -qF -- "$nq"; then
    printf 'FAIL    %-14s %s:%s — the quote is in the file, but not at that line\n' "$id" "$file" "$line"
    bad=$((bad+1))
  else
    printf 'FAIL    %-14s %s:%s — quote absent from that file\n          %s\n' "$id" "$file" "$line" "$quote"
    bad=$((bad+1))
  fi
done
echo "        $((total-bad))/$total citations verifiable"
[ "$total" -gt 0 ] && [ "$bad" -gt $((total/2)) ] && { echo "FAIL    majority unverifiable"; fail=1; }

hr; echo "4. TRACE AUDIT  (each probe line reached the reviewer in a successful tool output)"; hr
if [ ! -s "$TRACE" ]; then
  echo "FAIL    trace empty"; fail=1
else
  # Judge what the reviewer received, not what it asked for. A command name proves nothing:
  # it can be denied, fail, never finish, read a same-named file elsewhere, or be text inside
  # another command. The probe lines' text in a successful output proves the content arrived.
  #   codex:  item.completed command_execution events with status "completed" and exit code 0:
  #           aggregated_output
  #   claude: tool_result events without is_error: their content
  # Extract with jq, never a regex: a regex truncates at the first escaped quote.
  probes_json=$(for n in ${PROBES//,/ }; do sed -n "${n}p" "$TARGET"; done | jq -R . | jq -s .)
  audit=$(jq -rs --argjson probes "$probes_json" '
    [ (.. | objects
       | select(.type? == "item.completed" and .item.type? == "command_execution"
                and .item.status? == "completed" and .item.exit_code? == 0)
       | .item.aggregated_output // ""),
      (.. | objects
       | select(.type? == "tool_result" and .is_error != true)
       | .content
       | if type == "string" then . elif type == "array" then (map(.text? // "") | join("\n")) else "" end)
    ] as $outputs
    | "outputs\t\($outputs | length)",
      ($probes[] | . as $p | "\(if any($outputs[]; contains($p)) then "found" else "missing" end)\t\($p)")
  ' "$TRACE" 2>/dev/null)
  printf '        successful tool outputs in the trace: %s\n' "$(printf '%s\n' "$audit" | awk -F'\t' '$1=="outputs"{print $2}')"
  missing=0
  while IFS=$'\t' read -r state text; do
    case "$state" in
      found)   printf 'OK      received: %s\n' "$(printf '%s' "$text" | cut -c1-70)" ;;
      missing) printf 'FAIL    never in a successful output: %s\n' "$(printf '%s' "$text" | cut -c1-70)"; missing=1 ;;
    esac
  done <<< "$audit"
  if [ -z "$audit" ]; then
    echo "FAIL    trace could not be read"; fail=1
  elif [ "$missing" -eq 1 ]; then
    echo "FAIL    the target's content never provably reached the reviewer"; fail=1
  else
    echo "OK      content was actually read"
  fi
fi

hr
if [ "$fail" -eq 0 ]; then
  echo "PROOF ACCEPTED — findings may be adjudicated"
else
  echo "PROOF FAILED — investigate the verifier AND the review before discarding either"
fi
hr
exit "$fail"
