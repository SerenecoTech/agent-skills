# The codex invocation contract

Two environments have been measured, and they do not agree. Say which one you are in before
relying on a line here; do not soften any of it from documentation.

| | Linux devcontainer | macOS host |
|---|---|---|
| codex-cli | 0.146.0 | 0.147.0 |
| default model observed | — | `gpt-5.6-sol` |
| `-s danger-full-access` | **mandatory**, see below | works; alternatives untested |

## Flags

```bash
# General review (architecture, documents, anything without a diff).
# Also the form to use for CODE review whenever you need to brief the reviewer —
# see the `review` subcommand note below.
codex exec -C "$REPO" -s danger-full-access --json \
  --output-schema "$ABS/schema/findings.json" -o "$ABS/out.json" - < brief.md > trace.jsonl 2>&1

# Native diff review. Takes a target OR a prompt, never both.
codex exec review --uncommitted --dangerously-bypass-approvals-and-sandbox \
  --output-schema "$ABS/schema/findings.json" -o "$ABS/out.json"
# also: --base <branch>, --commit <sha>

# Native diff review WITH a brief: no target flag, brief on stdin, and the brief
# must name the target itself.
codex exec review --dangerously-bypass-approvals-and-sandbox \
  --output-schema "$ABS/schema/findings.json" -o "$ABS/out.json" - < brief.md
```

- **`--uncommitted` and a prompt are mutually exclusive.** Measured on 0.147.0:
  `error: the argument '--uncommitted' cannot be used with '[PROMPT]'`. The same applies to
  the other target flags. ENGINE.md requires a per-round brief, so on any target that would
  use a flag you have two options, and both are compliant: pass the brief on stdin with **no**
  target flag and describe the target in the brief (the third form above), or use the general
  `codex exec` form and give the reviewer paths plus `git status` / `git diff` to run itself.
  What you may not do is drop the brief to keep the flag — an unbriefed round cannot state
  what would falsify the work, and scope exclusions then get adjudicated after the fact.
- **`-s danger-full-access` is mandatory in the devcontainer.** Every other sandbox mode —
  `workspace-write` (which the deprecated `--full-auto` selects) and `read-only` alike — fails
  there with `bwrap: No permissions to create new namespace`: the container drops
  CAP_SYS_ADMIN, so userns creation is denied and bwrap has no fallback. Codex reads files by
  shelling out, so in any mode where that fails it opens nothing and reviews only your prompt
  text, producing a confident, well-formatted review of nothing.
  **On a macOS host that reasoning does not apply** — there is no bwrap. The flag is still
  what we pass and it works; whether `workspace-write` would also suffice on macOS has not
  been tested, so do not assume either way.
- **`codex exec review` has no `-s` flag.** Use `--dangerously-bypass-approvals-and-sandbox`.
- **Always `-C <repo-root>`**, and absolute paths for `--output-schema` and `-o`. Codex
  refuses to start in a non-git working directory.
- **`--uncommitted` includes untracked files.** A hand-written "staged and unstaged" target
  silently omits them, so a brand-new source file gets no review at all.
- **Do not make a rule depend on `-m`.** On the devcontainer account `gpt-5.1-codex` and
  `gpt-5.1-codex-max` were both rejected. The default model has since moved (`gpt-5.6-sol`
  observed on macOS/0.147.0), which is the point: pin nothing to a model name.
- **Quota is a real failure mode.** An exhausted account returns
  `ERROR: You've hit your usage limit … try again at <date>` and the review is simply not
  available until then. That is a blocked review to report, not a licence to substitute your
  own — see the note under "Running it".

## Structured output only

Every call passes `--output-schema`. Never parse prose, never pattern-match markers, never
"infer the missing field". If the schema is not satisfied, the call failed.

**Check that the schema was accepted, not just that the command ran.** The validator requires
`required` to list *every* key in `properties`; an optional field is expressed as a nullable
type, never by omission. A schema that breaks that rule is rejected before the model sees it:

```
"code": "invalid_json_schema",
"message": "… 'required' is required to be supplied and to be an array including every key
             in properties. Missing 'no_findings_reason'."
```

This one bit for real (ISSUE-001). `codex exec` exits non-zero and writes nothing, but
`codex exec review` was observed exiting 0 and writing prose to the `-o` file — a review that
looks complete, parses as nothing, and leaves `verify-proof-of-work.sh` with no `probe_echo`
or `reviewed_path` to check. So the check is `jq -e . "$out"`, on every round. A clean exit is
not evidence.

## Running it

Background shell, 600 s ceiling. **"Codex was slow" never justifies substituting your own
review** — that is what the user already had before invoking this. If a call genuinely fails
(non-zero exit with a concrete error, or empty output after a clean exit), surface the error
verbatim and ask whether to retry. Never downgrade silently.

A finding that could not be adjudicated — call failed, timed out, budget exhausted — is
**UNRESOLVED and reaches the report**. It is never silently dropped.

## Proof of work

Prove codex actually read the artefact. Three checks, run by `verify-proof-of-work.sh`:

1. **Echo probe** — pick 3 line numbers with `shuf` *after* the artefact is final, and require
   them echoed back byte-exact. This is what forces genuine reading; under it codex reaches
   for `od -An -tx1c` to guarantee exactness.
2. **Citations** — every finding carries a verbatim quoted substring, grepped against source.
   Normalise whitespace and unescape transport encoding: a citation legitimately spans a
   hard-wrapped line.
3. **Trace audit** — extract commands with `jq '.. | objects | select(has("command")) |
   .command'`, never a regex (a regex truncates at the first escaped quote, and commands live
   at `.item.command`). Distinguish content-yielding reads (`cat`, `nl`, `sed`, `od`) from
   metadata-only (`wc`, `stat`). Metadata alone is the hollow pass.

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

Stated in codex calls, agreed before starting. **Every call counts** — blind passes, batched
challenges, retries, proof investigations. Default **12**; **hard maximum 40 per review**.
Beyond 40 the review stops and must be re-authorised as a new review with its own output, so
the cost decision resurfaces instead of compounding.

Proof investigation counts against the budget and is capped at **2 cycles per round**; beyond
that the round is reported proof-unverified and the review continues rather than looping.
