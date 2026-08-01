#!/usr/bin/env bash
# Proof of work: verify a codex review actually read the target it reports on.
#
#   verify-proof-of-work.sh <result.json> <trace.jsonl> <target-file> <probe-lines-csv>
#
# Three independent checks:
#   1. probe echo   — verbatim text of unpredictably chosen lines must match the file
#   2. citations    — each finding's quoted substring must occur in the source
#   3. trace audit  — the event stream must show a CONTENT-YIELDING read of the target
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

# Collapse all whitespace runs to single spaces and unescape @tsv's \n and \t, so a quote
# spanning a wrapped line compares equal to the source it came from.
norm() {
  sed 's/\\n/ /g; s/\\t/ /g' | tr '\n' ' ' | tr -s '[:space:]' ' ' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

hr; echo "1. PROBE ECHO  (lines chosen unpredictably at launch)"; hr
for n in ${PROBES//,/ }; do
  claimed=$(jq -r --argjson n "$n" '.probe_echo[] | select(.line==$n) | .text' "$RESULT" 2>/dev/null)
  actual=$(sed -n "${n}p" "$TARGET")
  if [ -z "$claimed" ]; then
    printf 'FAIL    line %-4s not echoed at all\n' "$n"; fail=1
  elif [ "$claimed" = "$actual" ]; then
    printf 'OK      line %-4s exact match\n' "$n"
  elif [ "$(printf '%s' "$claimed" | norm)" = "$(printf '%s' "$actual" | norm)" ]; then
    printf 'OK*     line %-4s match modulo whitespace\n' "$n"
  else
    printf 'FAIL    line %-4s MISMATCH\n          claimed: %s\n          actual : %s\n' \
      "$n" "$claimed" "$actual"; fail=1
  fi
done

hr; echo "2. CITATIONS  (quoted substring must occur in the source)"; hr
total=0; bad=0
normfile=$(mktemp); norm < "$TARGET" > "$normfile"
while IFS=$'\t' read -r id line quote; do
  [ -z "$id" ] && continue
  total=$((total+1))
  src=$(sed -n "${line}p" "$TARGET")
  nq=$(printf '%s' "$quote" | norm)
  if [ -n "$src" ] && [ "${src#*"$quote"}" != "$src" ]; then
    printf 'OK      %-14s line %s\n' "$id" "$line"
  elif [ -n "$nq" ] && grep -qF -- "$nq" "$normfile"; then
    printf 'OK*     %-14s line %s — spans a wrapped line, matches after normalization\n' "$id" "$line"
  else
    printf 'FAIL    %-14s line %s — quote absent from source\n          %s\n' "$id" "$line" "$quote"
    bad=$((bad+1))
  fi
done < <(jq -r '.findings[] | [.id, (.citation.line|tostring), .citation.verbatim] | @tsv' "$RESULT" 2>/dev/null)
rm -f "$normfile"
echo "        $((total-bad))/$total citations verifiable"
[ "$total" -gt 0 ] && [ "$bad" -gt $((total/2)) ] && { echo "FAIL    majority unverifiable"; fail=1; }

hr; echo "3. TRACE AUDIT  (a content-yielding read, not just metadata)"; hr
if [ ! -s "$TRACE" ]; then
  echo "FAIL    trace empty"; fail=1
else
  base=$(basename "$TARGET")
  # Extract with jq, not a regex. `grep -o '"command":"[^"]*"'` truncates at the first
  # ESCAPED quote, so `zsh -lc \"nl -ba spec.md\"` is cut before the filename and the audit
  # reports a hollow read for a review that genuinely read the file. Commands also sit at
  # .item.command rather than .command, so recurse for the key instead of assuming a path.
  cmds=$(jq -r '.. | objects | select(has("command")) | .command' "$TRACE" 2>/dev/null \
         | grep -F -- "$base")
  if [ -z "$cmds" ]; then
    echo "FAIL    target never appears in any executed command"; fail=1
  else
    # wc/stat/ls yield metadata only: they prove the path was touched, not that content was read.
    content=$(printf '%s\n' "$cmds" | grep -cE '\b(cat|nl|sed|awk|head|tail|od|rg|grep|less|python)\b')
    meta=$(printf '%s\n' "$cmds" | grep -cE '\b(wc|stat|ls|find|file)\b')
    printf '        commands touching %s: %s  (content-yielding: %s, metadata-only: %s)\n' \
      "$base" "$(printf '%s\n' "$cmds" | wc -l | tr -d ' ')" "$content" "$meta"
    printf '%s\n' "$cmds" | sed 's/^/          /' | cut -c1-150 | head -4
    if [ "$content" -eq 0 ]; then
      echo "FAIL    only metadata commands ran — the content was never actually read"; fail=1
    else
      echo "OK      content was actually read"
    fi
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
