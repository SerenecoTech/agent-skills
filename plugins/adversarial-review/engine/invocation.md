# The codex invocation contract

Every value here was measured against `codex-cli 0.146.0` in this devcontainer. Re-verify
after a container rebuild; do not soften any of it from documentation.

## Flags

```bash
# General review (architecture, documents, anything without a diff)
codex exec -C "$REPO" -s danger-full-access --json \
  --output-schema "$ABS/schema/findings.json" -o "$ABS/out.json" - < brief.md > trace.jsonl 2>&1

# Code review against a diff — prefer this over hand-rolled targets
codex exec review --uncommitted --dangerously-bypass-approvals-and-sandbox \
  --output-schema "$ABS/schema/findings.json" -o "$ABS/out.json"
# also: --base <branch>, --commit <sha>
```

- **`-s danger-full-access` is mandatory.** Every other sandbox mode — `workspace-write`
  (which the deprecated `--full-auto` selects) and `read-only` alike — fails with
  `bwrap: No permissions to create new namespace`. The container drops CAP_SYS_ADMIN, so
  userns creation is denied and bwrap has no fallback. Codex reads files by shelling out, so
  in any other mode it opens nothing and reviews only your prompt text — producing a
  confident, well-formatted review of nothing.
- **`codex exec review` has no `-s` flag.** Use `--dangerously-bypass-approvals-and-sandbox`.
- **Always `-C <repo-root>`**, and absolute paths for `--output-schema` and `-o`. Codex
  refuses to start in a non-git working directory.
- **`--uncommitted` includes untracked files.** A hand-written "staged and unstaged" target
  silently omits them, so a brand-new source file gets no review at all.
- **No second model is available** on this account — `gpt-5.1-codex` and
  `gpt-5.1-codex-max` are both rejected. Never make a rule depend on `-m`.

## Structured output only

Every call passes `--output-schema`. Never parse prose, never pattern-match markers, never
"infer the missing field". If the schema is not satisfied, the call failed.

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
