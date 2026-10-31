#!/usr/bin/env bash
# Test suite for the adversarial-review gates.
#
# Each gate is fed the documented PreToolUse/PostToolUse stdin JSON and checked for the
# right decision. The most important cases are the FAIL-OPEN ones: a gate that blocks
# ordinary work gets disabled, and a disabled gate is worse than none because the report
# still claims the guarantee.
#
#   bash test-gates.sh
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# $1 name, $2 expect (allow|deny|context), $3 script, $4 event json
check() {
  local name="$1" expect="$2" script="$3" event="$4" out rc
  out="$(printf '%s' "$event" | bash "$HOOKS/$script" 2>/dev/null)"; rc=$?
  # Guard on non-empty output first: `jq -e` on EMPTY stdin exits 0, so testing the filter
  # directly reads every silent allow as a deny. A silent exit 0 IS the allow signal.
  local decision="allow"
  if [ -n "$out" ]; then
    printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 && decision="deny"
    if [ "$decision" = "allow" ]; then
      printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext != null' >/dev/null 2>&1 && decision="context"
    fi
  fi
  [ "$rc" -eq 2 ] && decision="deny"
  if [ "$decision" = "$expect" ]; then
    printf '  PASS  %-58s (%s)\n' "$name" "$decision"; pass=$((pass+1))
  else
    printf '  FAIL  %-58s expected %s, got %s\n' "$name" "$expect" "$decision"; fail=$((fail+1))
    [ -n "$out" ] && printf '        %s\n' "$(printf '%s' "$out" | head -c 200)"
  fi
}

mkstate() { mkdir -p "$1/.claude/adversarial-review"; printf '%s' "$2" > "$1/.claude/adversarial-review/state.json"; }
ev_write() { jq -nc --arg cwd "$1" --arg p "$2" '{cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p}}'; }
ev_bash()  { jq -nc --arg cwd "$1" --arg c "$2" '{cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
# The real payload shapes (dumped from Claude Code 2.1.312): exit 0 fires PostToolUse with no
# exit-code field; a non-zero exit fires PostToolUseFailure with "Exit code N" in `error`.
ev_post()  {
  if [ "$3" = "0" ]; then
    jq -nc --arg cwd "$1" --arg c "$2" '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},
      tool_response:{stdout:"ok",stderr:"",interrupted:false,isImage:false,noOutputExpected:false}}'
  else
    jq -nc --arg cwd "$1" --arg c "$2" --arg e "$3" '{cwd:$cwd,hook_event_name:"PostToolUseFailure",tool_name:"Bash",tool_input:{command:$c},
      error:("Exit code " + $e + "\nsome failure")}'
  fi
}

echo "FAIL-OPEN — no review active must never block ordinary work"
NO="$TMP/norev"; mkdir -p "$NO"
check "write with no state file"        allow write-path-gate.sh        "$(ev_write "$NO" "$NO/lib/x.ts")"
CALL="bash engine/run-reviewer.sh auto . /tmp/r1 < brief.md"
check "reviewer call with no state file" allow appendix-gate.sh       "$(ev_bash  "$NO" "$CALL")"
check "rubric gate, no state file"     allow rubric-gate.sh            "$(ev_bash  "$NO" "$CALL")"
mkstate "$NO" '{"active":false,"loop":"fix","authorized_paths":["nope/**"]}'
check "write with review inactive"     allow write-path-gate.sh        "$(ev_write "$NO" "$NO/lib/x.ts")"
check "malformed state file"           allow write-path-gate.sh        "$(printf '%s' '{"cwd":"'"$TMP"'/broken","tool_name":"Edit","tool_input":{"file_path":"a.ts"}}')"

echo
echo "WRITE-PATH GATE — write authorisation"
V="$TMP/verdict"; mkstate "$V" '{"active":true,"loop":"verdict"}'
check "verdict loop has no write authority" deny write-path-gate.sh     "$(ev_write "$V" "$V/lib/creaseWall.ts")"
F="$TMP/fix"; mkstate "$F" '{"active":true,"loop":"fix","authorized_paths":["lib/creaseWall.ts","tests/unit/*.test.ts"],"appendix":"docs/reviews/x/appendix.md"}'
check "authorised exact path"           allow write-path-gate.sh        "$(ev_write "$F" "$F/lib/creaseWall.ts")"
check "authorised glob"                 allow write-path-gate.sh        "$(ev_write "$F" "$F/tests/unit/creaseMesh.test.ts")"
check "unauthorised sibling file"       deny  write-path-gate.sh        "$(ev_write "$F" "$F/lib/creaseMesh.ts")"
check "unauthorised generated file"     deny  write-path-gate.sh        "$(ev_write "$F" "$F/app/generated/policy.json")"
check "review bookkeeping always writable" allow write-path-gate.sh     "$(ev_write "$F" "$F/.claude/adversarial-review/state.json")"
check "declared appendix writable"      allow write-path-gate.sh        "$(ev_write "$F" "docs/reviews/x/appendix.md")"
E="$TMP/empty"; mkstate "$E" '{"active":true,"loop":"fix","authorized_paths":[]}'
check "fix loop with empty allowlist"   deny  write-path-gate.sh        "$(ev_write "$E" "$E/lib/x.ts")"
check "bookkeeping path climbing out with .." deny write-path-gate.sh   "$(ev_write "$V" "$V/.claude/adversarial-review/../../protected.ts")"
check "write outside the repository"    allow write-path-gate.sh        "$(ev_write "$V" "/tmp/adversarial-review-test.txt")"

echo
echo "APPENDIX GATE — refutation carry-forward"
A="$TMP/appendix"; mkdir -p "$A/docs/reviews/x"
printf 'REFUTED: race in flushQueue\nFALSIFIER: holds only while the broker dedupes retries.\n' > "$A/docs/reviews/x/appendix.md"
mkstate "$A" '{"active":true,"loop":"verdict","appendix":"docs/reviews/x/appendix.md","appendix_read":false}'
check "a command that is not a reviewer call" allow appendix-gate.sh   "$(ev_bash "$A" "ls -la")"
check "reviewer call while appendix unread" deny appendix-gate.sh       "$(ev_bash "$A" "$CALL")"
check "quoted path to the wrapper"      deny  appendix-gate.sh          "$(ev_bash "$A" "bash \"/repo/engine/run-reviewer.sh\" auto /repo /tmp/r1 < brief.md")"
mkdir -p "$A/src/deep"
check "reviewer call after cd into a subdirectory" deny appendix-gate.sh "$(ev_bash "$A/src/deep" "$CALL")"
mkstate "$A" '{"active":true,"loop":"verdict","appendix":"docs/reviews/x/appendix.md","appendix_read":true}'
check "reviewer call once appendix read" allow appendix-gate.sh         "$(ev_bash "$A" "$CALL")"
M="$TMP/noappendix"; mkstate "$M" '{"active":true,"loop":"verdict","appendix":"docs/reviews/none/appendix.md"}'
check "no prior appendix on disk"       allow appendix-gate.sh          "$(ev_bash "$M" "$CALL")"

echo
echo "  content check: does the denial actually carry the appendix?"
mkstate "$A" '{"active":true,"loop":"verdict","appendix":"docs/reviews/x/appendix.md","appendix_read":false}'
CTX="$(ev_bash "$A" "$CALL" | bash "$HOOKS/appendix-gate.sh" | jq -r '.hookSpecificOutput.additionalContext // ""')"
if printf '%s' "$CTX" | grep -q 'race in flushQueue' && printf '%s' "$CTX" | grep -q 'FALSIFIER'; then
  echo "  PASS  appendix contents injected into the denial"; pass=$((pass+1))
else
  echo "  FAIL  appendix contents missing from denial context"; fail=$((fail+1))
fi

echo
echo "RUBRIC GATE — probe integrity"
R="$TMP/rubric"; mkstate "$R" '{"active":true,"loop":"verdict","probes_previous_round":["C-LOGIC","C-RACE"]}'
check "clean rubric + prev round -> advisory" context rubric-gate.sh    "$(ev_bash "$R" "$CALL")"
# Doctored copy: two ids, same normalised description.
PLUG="$TMP/plug"; mkdir -p "$PLUG/hooks" "$PLUG/engine"
cp "$HOOKS"/*.sh "$PLUG/hooks/"; cp "$HOOKS/../engine"/rubric-*.md "$PLUG/engine/" 2>/dev/null
printf '| `C-DUPE-A` | Logic errors, off-by-one, inverted conditions, wrong operator, unreachable branches |\n' >> "$PLUG/engine/rubric-code.md"
OUT="$(ev_bash "$R" "$CALL" | bash "$PLUG/hooks/rubric-gate.sh" 2>/dev/null)"
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  echo "  PASS  near-duplicate probe detected and blocked"; pass=$((pass+1))
else
  echo "  FAIL  near-duplicate probe NOT detected"; fail=$((fail+1)); printf '        %s\n' "$(printf '%s' "$OUT" | head -c 200)"
fi

echo
echo "WRITE-PATH GATE — after a change of directory"
mkdir -p "$V/src/deep"
check "edit after cd, verdict"          deny  write-path-gate.sh        "$(ev_write "$V/src/deep" "$V/src/a.ts")"

echo
echo "VERIFICATION RECORDER — evidence capture"
P="$TMP/post"; mkstate "$P" '{"active":true,"loop":"fix","authorized_paths":["**"]}'
printf '%s' "$(ev_post "$P" "bun run test:unit" "1")" | bash "$HOOKS/verification-recorder.sh" >/dev/null 2>&1
if [ -s "$P/.claude/adversarial-review/verifications.jsonl" ] && \
   jq -e 'select(.exit=="1") | .command' "$P/.claude/adversarial-review/verifications.jsonl" >/dev/null 2>&1; then
  echo "  PASS  failing verification recorded with its real exit status"; pass=$((pass+1))
else
  echo "  FAIL  failing verification not recorded"; fail=$((fail+1))
fi
printf '%s' "$(ev_post "$P" "ls -la" "0")" | bash "$HOOKS/verification-recorder.sh" >/dev/null 2>&1
if [ "$(wc -l < "$P/.claude/adversarial-review/verifications.jsonl" | tr -d ' ')" = "1" ]; then
  echo "  PASS  non-verification command not recorded"; pass=$((pass+1))
else
  echo "  FAIL  recorded a command that is not a verification"; fail=$((fail+1))
fi
printf '%s' "$(ev_post "$P" "bun run test:unit" "0")" | bash "$HOOKS/verification-recorder.sh" >/dev/null 2>&1
if [ "$(jq -r 'select(.command == "bun run test:unit") | .exit' "$P/.claude/adversarial-review/verifications.jsonl" | tail -1)" = "0" ]; then
  echo "  PASS  passing verification recorded with exit 0"; pass=$((pass+1))
else
  echo "  FAIL  passing verification not recorded as exit 0"; fail=$((fail+1))
fi
# `test` exiting 1 still fires PostToolUse, marked by returnCodeInterpretation (observed).
jq -nc --arg cwd "$P" '{cwd:$cwd,hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"test -f build/out.js"},
  tool_response:{stdout:"",stderr:"",interrupted:false,isImage:false,returnCodeInterpretation:"Condition is false",noOutputExpected:false}}' \
  | bash "$HOOKS/verification-recorder.sh" >/dev/null 2>&1
if [ "$(jq -r 'select(.command == "test -f build/out.js") | .exit' "$P/.claude/adversarial-review/verifications.jsonl" | tail -1)" != "0" ]; then
  echo "  PASS  a non-zero exit reported through PostToolUse is not recorded as 0"; pass=$((pass+1))
else
  echo "  FAIL  a non-zero exit reported through PostToolUse was recorded as 0"; fail=$((fail+1))
fi

echo
echo "GATE LOG"
if [ -s "$F/.claude/adversarial-review/gate-log.tsv" ]; then
  echo "  PASS  gates record that they fired ($(wc -l < "$F/.claude/adversarial-review/gate-log.tsv" | tr -d ' ') entries)"; pass=$((pass+1))
else
  echo "  FAIL  no gate log written"; fail=$((fail+1))
fi

echo
echo "======================================"
printf ' %d passed, %d failed\n' "$pass" "$fail"
echo "======================================"
[ "$fail" -eq 0 ]
