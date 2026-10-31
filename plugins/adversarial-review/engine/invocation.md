# The reviewer invocation contract

Every reviewer call goes through [`run-reviewer.sh`](run-reviewer.sh). Do not hand-write a
`codex exec` or `claude -p` line: each provider's flags are in its `provider.sh`, and an
improvised call drops some of them. The providers and the contract they share are in
[`providers/README.md`](providers/README.md). [`../WORKFLOW.md`](../WORKFLOW.md) diagrams the
whole flow.

```bash
bash "$ENGINE/run-reviewer.sh" --max-calls "$CALLS_LEFT" auto "$REPO" "$OUT/round-1" < brief.md
```

- **The output directory must not exist yet.** The wrapper creates it and refuses one that
  exists, so a retry or a concurrent call can never mix its brief and results with another's.
  Give every call, including a retry, a new directory, and keep the brief file outside it.
- **Pass `--max-calls` with the calls the review has left** (see Budget). A fallback is a
  second call, and without the limit one invocation could take the review past its budget.

It writes `brief.md`, `out.json`, `trace.jsonl`, `stderr.txt`, `schema-errors.json` and
`reviewer` into the output directory, and prints `REVIEWER: <label>` on success. A failed
call's files move to `failed-<provider>/` in the same directory before the next provider runs,
so its full stderr and trace survive a fallback.

| Exit | Meaning |
|---|---|
| 0 | findings written and schema-valid |
| 2 | usage error, or the output directory already exists |
| 3 | no provider can run here |
| 4 | every provider tried failed; the errors are on stderr |
| 5 | the call budget ran out before a call succeeded |

## Choosing the reviewer

[`select-reviewer.sh`](select-reviewer.sh) prints the providers that can run here, best first.
The order is [`providers/PRIORITY`](providers/PRIORITY): Codex, then Claude.
`ADVERSARIAL_REVIEW_PROVIDERS` overrides it. Pass `auto` by default, so the wrapper uses that
list. Pass a single provider name in exactly two cases: the user named a reviewer, or a
fallback happened earlier in this review (below).

A different model family is the point of this review, so Codex comes first. The Claude
reviewer still runs blind with a hostile brief and still has to pass proof of work. It is
labelled as same-family in the report.

**If the reviewer fails partway through, do not stop.** In `auto` mode a failed call (quota,
network, timeout, schema-invalid output) is followed at once by the next provider on the same
brief. The wrapper prints a `FALLBACK:` line with the error and appends it to
`.claude/adversarial-review/reviewer-log.tsv`.

**After a fallback, pin the provider that succeeded.** Pass its name, not `auto`, for the
remaining rounds, so one reviewer covers the rest of the review rather than switching back and
forth. If the pinned provider later fails, return to `auto` for that call: the full list is
tried again, Codex first.

**Record every fallback in the report**: which rounds each reviewer ran, and the error that
caused the switch, quoted from the `FALLBACK:` line. A report that hides a change of reviewer
claims a cross-model review it did not get.

If every provider fails, surface each error verbatim, from each `failed-<provider>/stderr.txt`,
and ask whether to retry.

## Never substitute your own review

The reviewer is a separate process with no access to this conversation. "The reviewer was
slow" never justifies writing the findings yourself, in-context — that is what the user
already had before invoking this.

A finding that could not be adjudicated — call failed, timed out, budget exhausted — is
**UNRESOLVED and reaches the report**. It is never silently dropped.

## Structured output only

Every call is held to [`schema/findings.json`](schema/findings.json). Never parse prose, never
pattern-match markers, never "infer the missing field". If the schema is not satisfied, the
call failed.

**Check the output, not the exit status.** `codex exec review` was once observed exiting 0 and
writing prose to its output file (ISSUE-001): a review that looks complete, parses as nothing,
and leaves `verify-proof-of-work.sh` with no `probe_echo` or `reviewed_path` to check. The
wrapper checks every `out.json` against the schema itself, with
[`schema/check-output.jq`](schema/check-output.jq): required fields, types, enums and nested
findings. A call whose output fails is a failed call, and falls back like any other. A clean
exit is not evidence.

## Running it

Background shell. The wrapper stops a call at 600 s when `timeout` or `gtimeout` is installed;
without either, a call has no limit.

## Proof of work

Prove the reviewer actually read the artefact. Four checks, run by `verify-proof-of-work.sh`
from the repository root on `out.json` and `trace.jsonl`, for any provider:

1. **Reviewed path** — the echo-probe target must sit inside the `reviewed_path` the review
   reports.
2. **Echo probe** — pick 3 **non-blank** line numbers *after* the artefact is final, with
   `awk 'NF{print NR}' <file> | shuf -n 3`, and require them echoed back byte-exact. This is
   what forces genuine reading. A blank line proves nothing, because `""` can be guessed, so
   the verifier rejects one. **When the target is a change, take at least one probe line from
   the changed lines.** An unchanged line reads the same in an older copy, so it cannot show
   the reviewer read the current one.
3. **Citations** — every finding carries a verbatim quoted substring, checked against the file
   that finding cites. Normalise whitespace: a citation legitimately spans a hard-wrapped
   line. A citation that fails, including one naming a missing file, makes **that finding**
   unverified: adjudicate it only after checking the claim yourself. The proof as a whole
   fails only when most citations fail.
4. **Trace audit** — the text of every probe line must appear in the output of a tool call
   that succeeded. That judges what the reviewer received, not what it asked for: a command
   name proves nothing, because the call can be denied, fail, never finish, read a same-named
   file elsewhere, or be text inside another command. A read that only returned hex (`od`)
   or file names fails the audit and needs investigating. Outputs are extracted with `jq`,
   never a regex: a regex truncates at the first escaped quote.

**A failed proof quarantines the result for an explicit accept-or-reject by the operator.**
Never an automatic discard, never a silent pass. A verifier is at least as likely to be wrong
as the reviewer it polices — in practice most proof failures are defects in the checking
pipeline rather than dishonest reviews, so investigate the verifier before doubting the
findings.

Proof of work proves **access, not comprehension**. `sed -n '1p'` per file passes. Publish the
trace summary so a reader can judge read depth themselves.

**Record the reviewed path with each finding set** — the audit matches on path, so moving or
renaming the artefact later invalidates its proof.

## Budget

Stated in reviewer calls, agreed before starting. **Every call counts** — blind passes, batched
challenges, retries, fallbacks, proof investigations. A Codex call that fails and falls back to
Claude counts as two, so pass the calls left as `--max-calls` on every call and the wrapper
will not start a fallback the budget cannot cover. Default **12**; **hard maximum 40 per
review**. Beyond 40 the review
stops and must be re-authorised as a new review with its own output, so the cost decision
resurfaces instead of compounding.

Proof investigation counts against the budget and is capped at **2 cycles per round**. After
that, stop investigating and put the quarantined result to the user: accept it, reject it, or
rerun the round. Until they decide, its findings are not adjudicated and the round is reported
proof-unverified. Other rounds may continue meanwhile.
