#!/usr/bin/env bash
# Test suite for the reviewer engine: selection, execution and proof of work.
#
# Runs against a copy of engine/ with mock providers and mock CLIs, so it makes no model call
# and costs nothing.
#
#   bash test-engine.sh
set -uo pipefail
ENGINE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; fail=$((fail+1)); }

# A copy of the engine with three mock providers added.
E="$TMP/engine"; cp -R "$ENGINE" "$E"
REPO="$TMP/repo"; mkdir -p "$REPO"
valid_output='{"reviewed_path":"x","probe_echo":[],"probes_run":[],"findings":[],"no_findings_reason":"none"}'
mock_provider() {   # $1 name, $2 body of provider_run
  mkdir -p "$E/providers/$1"
  printf 'provider_available() { return 0; }\nprovider_label() { echo %s; }\nprovider_run() { %s; }\n' "$1" "$2" \
    > "$E/providers/$1/provider.sh"
}
mock_provider good "echo '$valid_output' > \"\$OUT/out.json\"; : > \"\$OUT/trace.jsonl\""
mock_provider fails "echo 'ERROR: usage limit' >&2; return 1"
mock_provider badjson "echo '{\"findings\":null,\"probe_echo\":\"oops\"}' > \"\$OUT/out.json\""
run() { echo "brief" | ADVERSARIAL_REVIEW_PROVIDERS="$1" bash "$E/run-reviewer.sh" "${@:2}" 2>"$TMP/err"; }

echo "EXECUTION — run-reviewer.sh"
run "badjson good" auto "$REPO" "$TMP/o1" >/dev/null; rc=$?
if [ "$rc" -eq 0 ] && grep -q "FALLBACK: badjson call failed (exited 0 but out.json fails the schema" "$TMP/err" \
   && [ "$(cat "$TMP/o1/reviewer")" = "good" ]; then
  ok "schema-invalid output falls back to the next provider"
else bad "schema-invalid output falls back to the next provider" "rc=$rc $(cat "$TMP/err")"; fi

run "good" auto "$REPO" "$TMP/o1" >/dev/null; rc=$?
if [ "$rc" -eq 2 ] && grep -q "already exists" "$TMP/err"; then ok "an existing output directory is refused"
else bad "an existing output directory is refused" "rc=$rc"; fi

run "fails good" --max-calls 1 auto "$REPO" "$TMP/o2" >/dev/null; rc=$?
if [ "$rc" -eq 5 ] && grep -q "BUDGET: 1 of 1 calls used" "$TMP/err"; then ok "--max-calls stops a fallback past the budget"
else bad "--max-calls stops a fallback past the budget" "rc=$rc $(cat "$TMP/err")"; fi

run "fails good" --max-calls 2 auto "$REPO" "$TMP/o3" >/dev/null; rc=$?
if [ "$rc" -eq 0 ]; then ok "--max-calls allows a fallback within the budget"
else bad "--max-calls allows a fallback within the budget" "rc=$rc"; fi

run "fails" auto "$REPO" "$TMP/o4" >/dev/null; rc=$?
if [ "$rc" -eq 4 ] && grep -q "usage limit" "$TMP/err"; then ok "every provider failing exits 4 with the error"
else bad "every provider failing exits 4 with the error" "rc=$rc"; fi

if grep -q "FALLBACK after: badjson" "$REPO/.claude/adversarial-review/reviewer-log.tsv" 2>/dev/null; then
  ok "fallbacks are logged to reviewer-log.tsv"
else bad "fallbacks are logged to reviewer-log.tsv"; fi

if [ -f "$TMP/o1/failed-badjson/out.json" ] && grep -q '"oops"' "$TMP/o1/failed-badjson/out.json"; then
  ok "a failed call's files are kept after the fallback"
else bad "a failed call's files are kept after the fallback"; fi

echo
echo "PROVIDERS — the real codex and claude provider.sh, against mock CLIs"
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\n[ "$1" = login ] && exit 0\necho "$@" > "%s/codex-args"\nexit 1\n' "$TMP" > "$BIN/codex"
printf '#!/bin/sh\n[ "$1 $2" = "auth status" ] && { echo "{\\"loggedIn\\": false}"; exit 0; }\nexit 1\n' > "$BIN/claude"
chmod +x "$BIN/codex" "$BIN/claude"
echo "brief" | PATH="$BIN:$PATH" ADVERSARIAL_REVIEW_PROVIDERS=codex bash "$E/run-reviewer.sh" codex "$REPO" "$TMP/o5" >/dev/null 2>&1
if grep -q -- "--ephemeral" "$TMP/codex-args" 2>/dev/null; then ok "codex is called with --ephemeral"
else bad "codex is called with --ephemeral" "args: $(cat "$TMP/codex-args" 2>/dev/null)"; fi
sel="$(PATH="$BIN:$PATH" ADVERSARIAL_REVIEW_PROVIDERS=claude bash "$E/select-reviewer.sh" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 3 ] && [ -z "$sel" ]; then ok "a logged-out claude is not selected"
else bad "a logged-out claude is not selected" "rc=$rc selected=$sel"; fi

echo
echo "PROOF OF WORK — verify-proof-of-work.sh"
V="$E/verify-proof-of-work.sh"
P="$TMP/proof"; mkdir -p "$P/src"
printf 'alpha\n\nbeta\ngamma\n' > "$P/src/target.txt"
printf 'other line\n' > "$P/src/other.txt"
T="$P/src/target.txt"
result() {   # $1 reviewed_path, $2 findings json
  jq -n --arg rp "$1" --argjson f "$2" '{reviewed_path:$rp, probes_run:[], no_findings_reason:null, findings:$f,
    probe_echo:[{line:1,text:"alpha"},{line:2,text:""},{line:3,text:"beta"},{line:4,text:"gamma"}]}'
}
use()    { jq -nc --arg id "$1" --arg n "$2" --argjson i "$3" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:$n,input:$i}]}}'; }
res()    { jq -nc --arg id "$1" --argjson e "$2" --arg c "$3" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,is_error:$e,content:$c}]}}'; }
codex()  { jq -nc --arg t "$1" --arg c "$2" --arg s "$3" --arg o "$4" '{type:$t,item:{type:"command_execution",command:$c,status:$s,aggregated_output:$o,
             exit_code:(if $s == "completed" then 0 elif $s == "failed" then 1 else null end)}}'; }
verify() { (cd "$P" && bash "$V" "$1" "$2" "$T" "$3" 2>&1); }
audit_fails() { printf '%s' "$1" | grep -q "content never provably reached the reviewer"; }
result "$P/src" '[]' > "$P/ok.json"
use r1 Read "{\"file_path\":\"$T\"}" > "$P/read.jsonl"; res r1 false "$(cat "$T")" >> "$P/read.jsonl"

out="$(verify "$P/ok.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "PROOF ACCEPTED"; then ok "a successful Read with exact echoes is accepted"
else bad "a successful Read with exact echoes is accepted" "$(printf '%s' "$out" | grep FAIL | head -2)"; fi

out="$(verify "$P/ok.json" "$P/read.jsonl" 1,2,3)"
if printf '%s' "$out" | grep -q "line 2    is blank"; then ok "a blank probe line is rejected"
else bad "a blank probe line is rejected"; fi

use r1 Read "{\"file_path\":\"$T\"}" > "$P/denied.jsonl"; res r1 true "Permission denied" >> "$P/denied.jsonl"
out="$(verify "$P/ok.json" "$P/denied.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a denied Read does not count as a read"
else bad "a denied Read does not count as a read"; fi

use r2 Read "{\"file_path\":\"$T\"}" > "$P/unanswered.jsonl"
out="$(verify "$P/ok.json" "$P/unanswered.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a Read with no result does not count"
else bad "a Read with no result does not count"; fi

codex item.started "cat $T" in_progress "" > "$P/codex-failed.jsonl"
codex item.completed "cat $T" failed "" >> "$P/codex-failed.jsonl"
out="$(verify "$P/ok.json" "$P/codex-failed.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a codex command that started then failed does not count"
else bad "a codex command that started then failed does not count"; fi

codex item.completed "sed -n 1,4p $T" completed "$(cat "$T")" > "$P/codex-ok.jsonl"
out="$(verify "$P/ok.json" "$P/codex-ok.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "PROOF ACCEPTED"; then ok "a completed codex read of the target counts"
else bad "a completed codex read of the target counts"; fi

mkdir -p "$P/elsewhere"; printf 'zzz\n' > "$P/elsewhere/target.txt"
use r3 Read "{\"file_path\":\"$P/elsewhere/target.txt\"}" > "$P/samename.jsonl"; res r3 false "zzz" >> "$P/samename.jsonl"
out="$(verify "$P/ok.json" "$P/samename.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "reading a different file with the same name does not count"
else bad "reading a different file with the same name does not count"; fi

codex item.completed "printf %s 'cat target.txt'" completed "cat target.txt" > "$P/mention.jsonl"
out="$(verify "$P/ok.json" "$P/mention.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a command that only mentions cat does not count"
else bad "a command that only mentions cat does not count"; fi

use g1 Grep "{\"path\":\"$P/src\",\"glob\":\"target.txt\",\"pattern\":\"^\",\"output_mode\":\"content\"}" > "$P/grep.jsonl"; res g1 false "$(cat "$T")" >> "$P/grep.jsonl"
out="$(verify "$P/ok.json" "$P/grep.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "content was actually read"; then ok "a content Grep over a folder, globbed to the target, counts"
else bad "a content Grep over a folder, globbed to the target, counts"; fi

use g2 Grep "{\"path\":\"$T\",\"pattern\":\"x\",\"output_mode\":\"files_with_matches\"}" > "$P/files.jsonl"; res g2 false "$T" >> "$P/files.jsonl"
out="$(verify "$P/ok.json" "$P/files.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a files-only Grep does not count"
else bad "a files-only Grep does not count"; fi

result "$P/src" '[{"id":"F1","probe_id":"C-LOGIC","severity":"low","claim":"c","scenario":"s","falsifier":"f","citation":{"file":"src/other.txt","line":1,"verbatim":"other line"}}]' > "$P/cite.json"
out="$(verify "$P/cite.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "OK      F1"; then ok "a citation is checked against the file it cites"
else bad "a citation is checked against the file it cites" "$(printf '%s' "$out" | grep F1)"; fi

result "$P/src" '[{"id":"F2","probe_id":"C-LOGIC","severity":"low","claim":"c","scenario":"s","falsifier":"f","citation":{"file":"src/missing.txt","line":999,"verbatim":"alpha"}}]' > "$P/missing.json"
out="$(verify "$P/missing.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "F2 .*does not exist"; then ok "a citation of a missing file fails"
else bad "a citation of a missing file fails"; fi

result "$P/src" '[{"id":"F4","probe_id":"C-LOGIC","severity":"low","claim":"c","scenario":"s","falsifier":"f","citation":{"file":"src/target.txt","line":999,"verbatim":"alpha"}}]' > "$P/wrongline.json"
out="$(verify "$P/wrongline.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "F4 .*not at that line"; then ok "a quote found only at another line fails"
else bad "a quote found only at another line fails" "$(printf '%s' "$out" | grep F4)"; fi

mkdir -p "$P/elsewhere"; result "$P/elsewhere" '[]' > "$P/elsewhere.json"
out="$(verify "$P/elsewhere.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "is not inside reviewed_path"; then ok "a reviewed_path that excludes the target fails"
else bad "a reviewed_path that excludes the target fails"; fi

cat > "$P/src/backslash.sh" <<'EOF'
printf '%s\n' "$x"
EOF
result "$P/src" '[{"id":"F3","probe_id":"C-LOGIC","severity":"low","claim":"c","scenario":"s","falsifier":"f","citation":{"file":"src/backslash.sh","line":1,"verbatim":"printf '"'"'%s\\n'"'"' \"$x\""}}]' > "$P/backslash.json"
out="$(verify "$P/backslash.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "^OK      F3"; then ok "a citation containing a literal \\n matches exactly"
else bad "a citation containing a literal \\n matches exactly" "$(printf '%s' "$out" | grep F3)"; fi

jq -nc --arg c "cat $T; false" --arg o "$(cat "$T")" '{type:"item.completed",item:{type:"command_execution",command:$c,status:"completed",exit_code:1,aggregated_output:$o}}' > "$P/exit1.jsonl"
out="$(verify "$P/ok.json" "$P/exit1.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a codex command that exited non-zero does not count"
else bad "a codex command that exited non-zero does not count"; fi

echo
echo "SCOPE — check-changes.sh"
C="$E/check-changes.sh"
G="$TMP/git"; mkdir -p "$G/src" "$G/docs"; printf 'a\n' > "$G/src/a.ts"; printf 'b\n' > "$G/src/b.ts"
git -C "$G" init -q && git -C "$G" add -A && git -C "$G" -c user.email=t@t -c user.name=t commit -qm init
mkdir -p "$G/.claude/adversarial-review"
echo '{"active":true,"loop":"fix","authorized_paths":["src/a.ts"]}' > "$G/.claude/adversarial-review/state.json"
bash "$C" start "$G" >/dev/null
out="$(bash "$C" check "$G")"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q ", 0 out of scope"; then ok "no change outside bookkeeping since the baseline passes"
else bad "no change outside bookkeeping since the baseline passes" "rc=$rc $out"; fi
printf 'changed\n' > "$G/src/a.ts"; printf 'changed\n' > "$G/src/b.ts"; printf 'new\n' > "$G/docs/new.md"
out="$(bash "$C" check "$G")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "ALLOWED       src/a.ts" \
   && printf '%s' "$out" | grep -q "OUT OF SCOPE  src/b.ts" && printf '%s' "$out" | grep -q "OUT OF SCOPE  docs/new.md"; then
  ok "a shell edit outside the allowlist, and a new file, are flagged"
else bad "a shell edit outside the allowlist, and a new file, are flagged" "rc=$rc $out"; fi
echo '{"active":true,"loop":"verdict"}' > "$G/.claude/adversarial-review/state.json"
out="$(bash "$C" check "$G")"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "OUT OF SCOPE  src/a.ts"; then ok "in a verdict review every change is out of scope"
else bad "in a verdict review every change is out of scope" "rc=$rc"; fi
if [ -z "$(git -C "$G" diff --cached --name-only)" ]; then ok "the snapshot leaves the real index untouched"
else bad "the snapshot leaves the real index untouched"; fi
printf 'secret\n' > "$G/locked.txt"; chmod 000 "$G/locked.txt"
out="$(bash "$C" start "$G" 2>&1)"; rc=$?
chmod 600 "$G/locked.txt"
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "NOT COVERED   locked.txt"; then ok "an unreadable file is reported as not covered, not fatal"
else bad "an unreadable file is reported as not covered, not fatal" "rc=$rc $out"; fi
/bin/rm -f "$G/locked.txt"

H="$TMP/git2"; mkdir -p "$H"; printf 'p\n' > "$H/protected.txt"; printf 'k\n' > "$H/keep.txt"
git -C "$H" init -q && git -C "$H" add -A && git -C "$H" -c user.email=t@t -c user.name=t commit -qm init
echo 'keep.txt' > "$H/.gitignore"
mkdir -p "$H/.claude/adversarial-review"
printf '{"active":true,"loop":"fix","authorized_paths":["allowed.txt","café.txt",".gitignore"]}' > "$H/.claude/adversarial-review/state.json"
bash "$C" start "$H" >/dev/null 2>&1
git -C "$H" mv protected.txt allowed.txt
out="$(bash "$C" check "$H" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "OUT OF SCOPE  protected.txt"; then ok "a rename reports the removed source path"
else bad "a rename reports the removed source path" "rc=$rc $out"; fi
git -C "$H" mv allowed.txt protected.txt
printf 'changed\n' > "$H/keep.txt"
out="$(bash "$C" check "$H" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "OUT OF SCOPE  keep.txt"; then ok "a tracked file matching an ignore pattern is still covered"
else bad "a tracked file matching an ignore pattern is still covered" "rc=$rc $out"; fi
printf 'k\n' > "$H/keep.txt"; printf 'new\n' > "$H/café.txt"
out="$(bash "$C" check "$H" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "ALLOWED       café.txt"; then ok "a non-ASCII file name matches the allowlist as written"
else bad "a non-ASCII file name matches the allowlist as written" "rc=$rc $out"; fi
for n in $(seq 1 25); do printf 'x\n' > "$H/locked$n.txt"; chmod 000 "$H/locked$n.txt"; done
out="$(bash "$C" start "$H" 2>&1)"; rc=$?
for n in $(seq 1 25); do chmod 600 "$H/locked$n.txt"; done
if [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | grep -c "NOT COVERED")" -eq 25 ]; then ok "25 unreadable files are all reported, and the snapshot still succeeds"
else bad "25 unreadable files are all reported, and the snapshot still succeeds" "rc=$rc"; fi

git -C "$H" -c user.email=t@t -c user.name=t commit -qam more 2>/dev/null
printf 'v1\n' > "$H/local.config"; git -C "$H" add local.config
git -C "$H" -c user.email=t@t -c user.name=t commit -qm config
git -C "$H" update-index --assume-unchanged local.config
bash "$C" start "$H" >/dev/null 2>&1
printf 'v2\n' > "$H/local.config"
out="$(bash "$C" check "$H" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "OUT OF SCOPE  local.config"; then ok "an edit to an assume-unchanged file is seen"
else bad "an edit to an assume-unchanged file is seen" "rc=$rc $out"; fi
if ! printf '%s' "$out" | grep -q "baseline-tree"; then ok "the review's own bookkeeping is left out of the snapshot"
else bad "the review's own bookkeeping is left out of the snapshot"; fi
git -C "$H" update-index --no-assume-unchanged local.config
git -C "$H" update-index --skip-worktree local.config
out="$(bash "$C" start "$H" 2>&1)"; rc=$?
printf 'v3\n' > "$H/local.config"
out2="$(bash "$C" check "$H" 2>&1)"
git -C "$H" update-index --no-skip-worktree local.config
if [ "$rc" -eq 0 ] && printf '%s' "$out2" | grep -q "OUT OF SCOPE  local.config"; then ok "a skip-worktree file neither blocks the snapshot nor hides its edits"
else bad "a skip-worktree file neither blocks the snapshot nor hides its edits" "rc=$rc $out $out2"; fi
mkdir -p "$H/vendor/dep" && git -C "$H/vendor/dep" init -q && printf 'd\n' > "$H/vendor/dep/d.txt" \
  && git -C "$H/vendor/dep" add -A && git -C "$H/vendor/dep" -c user.email=t@t -c user.name=t commit -qm d 2>/dev/null
out="$(bash "$C" start "$H" 2>&1)"
/bin/rm -rf "$H/vendor"
if printf '%s' "$out" | grep -q "NOT COVERED   vendor/dep (a nested repository"; then ok "an untracked nested repository is reported as not covered"
else bad "an untracked nested repository is reported as not covered" "$out"; fi
printf '.claude/adversarial-review/\n' >> "$H/.gitignore"
out="$(bash "$C" start "$H" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "a snapshot works when the bookkeeping folder is gitignored"
else bad "a snapshot works when the bookkeeping folder is gitignored" "rc=$rc $out"; fi

jq -n --arg rp "$P/src" '{reviewed_path:$rp, probes_run:[], no_findings_reason:"n", findings:[],
  probe_echo:[{line:1,text:"alpha"},{line:3,text:"  beta"},{line:4,text:"gamma"}]}' > "$P/indent.json"
out="$(verify "$P/indent.json" "$P/read.jsonl" 1,3,4)"
if printf '%s' "$out" | grep -q "line 3    MISMATCH"; then ok "an echo with different indentation is a mismatch"
else bad "an echo with different indentation is a mismatch"; fi

jq -nc --arg o "$(cat "$T")" '{type:"item.completed",item:{type:"command_execution",command:"cat target.txt",status:"completed",aggregated_output:$o}}' > "$P/noexit.jsonl"
out="$(verify "$P/ok.json" "$P/noexit.jsonl" 1,3,4)"
if audit_fails "$out"; then ok "a codex event with no exit code does not count"
else bad "a codex event with no exit code does not count"; fi

echo
echo "======================================"
printf ' %d passed, %d failed\n' "$pass" "$fail"
echo "======================================"
[ "$fail" -eq 0 ]
