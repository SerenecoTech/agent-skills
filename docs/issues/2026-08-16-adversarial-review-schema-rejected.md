---
id: agent-skills:ISSUE-001
status: resolved
resolved: 2026-08-20
---

# The adversarial-review findings schema is rejected, so every review silently degrades to prose

`plugins/adversarial-review/engine/schema/findings.json` declares `no_findings_reason` as a
property but leaves it out of `required`. The Codex CLI rejects the schema and then falls back to
free-text output, so the review still appears to succeed and nothing enforces the structure the
engine depends on.

## Evidence

The schema's two lists disagree:

```
required:   ["reviewed_path", "probe_echo", "probes_run", "findings"]
properties: ["findings", "no_findings_reason", "probe_echo", "probes_run", "reviewed_path"]
```

Codex's structured-output validator requires every declared property to appear in `required`;
optionality is expressed in the property's own type, not by omitting it. Codex CLI 0.147.0 returns
`invalid_json_schema ... Missing 'no_findings_reason'`.

The call then exits 0 and writes review prose to the `-o` file. Observed on a real review run
(the `mortar` repository, macOS host, plugin 0.1.0): every finding arrived as Markdown, and
`jq` on the output file failed with `Invalid numeric literal`.

## Why it matters

[`engine/invocation.md`](../../plugins/adversarial-review/engine/invocation.md) makes structured
output non-negotiable: "Never parse prose, never pattern-match markers... If the schema is not
satisfied, the call failed." Here the schema is not satisfied and the call looks satisfied, which
is the one outcome that rule exists to prevent.

Everything downstream of the JSON is skipped in silence: the proof-of-work checks in
`verify-proof-of-work.sh` have no `probe_echo` or `reviewed_path` to verify, and no citation field
to grep. A reviewer reading a well-formatted report cannot tell whether any of it was checked.

## Resolution

Add `no_findings_reason` to `required` and make it nullable in its own type
(`"type": ["string", "null"]`), which is how a strict validator expresses an optional field.

Then re-run any review flow end to end and confirm the `-o` file parses as JSON, rather than
confirming only that the command exited 0.

## Related, found on the same run

Two smaller contract drifts, recorded here rather than as their own records because they are
one-line corrections to the same document:

- `codex exec review --uncommitted` refuses a prompt argument in 0.147.0
  (`error: the argument '--uncommitted' cannot be used with '[PROMPT]'`), while
  [`ENGINE.md`](../../plugins/adversarial-review/engine/ENGINE.md) requires a per-round brief.
  On an uncommitted target the code door currently cannot brief the reviewer at all, so scope
  exclusions have to be adjudicated after the fact.
- `invocation.md`'s flag rationale is measured against Codex CLI 0.146.0 inside a devcontainer,
  including the `bwrap` namespace reasoning behind `-s danger-full-access`. On a macOS host with
  0.147.0 that reasoning does not apply as written; the document should distinguish the two
  environments rather than presenting one as universal.

## Acceptance

A review run writes a file that parses as JSON and satisfies the schema, and
`verify-proof-of-work.sh` has fields to check.

## Resolved 2026-08-20

Reproduced first, on macOS with codex-cli 0.147.0, before changing anything:

```
"code": "invalid_json_schema",
"message": "Invalid schema for response_format 'codex_output_schema': In context=(),
            'required' is required to be supplied and to be an array including every key
            in properties. Missing 'no_findings_reason'."
```

`codex exec` exited 1 and wrote nothing to `-o`, so on that subcommand the failure is at least
loud. The silent-degradation path in the report above was observed on `codex exec review`,
which is the worse case and the reason the fix matters.

Fixed as prescribed: `no_findings_reason` added to `required`, typed `["string", "null"]`, with
the reasoning recorded in its own `description` so the next person to "tidy" the schema does not
reintroduce the bug. Re-run with the same command afterwards: exit 0, no rejection, and the `-o`
file parses with all five keys present.

The two related drifts are fixed in the same pass:

- `invocation.md` now documents both measured environments in a table instead of presenting the
  devcontainer as universal, and the `bwrap` reasoning is explicitly scoped to the container.
  Where macOS behaviour is untested it says so rather than implying it was checked.
- The `--uncommitted` / `[PROMPT]` conflict is documented with the measured error and, more
  importantly, with the resolution: the brief wins. Target flags are dropped, the target is
  described in the brief, and the brief must say that untracked files are in scope — that being
  the one thing `--uncommitted` was buying. `rubric-code.md` and the `review-code` front door
  were both saying "use `--uncommitted`" and now agree with the engine's brief requirement.

Also corrected while in there: the "no second model is available" line named specific rejected
models as if permanent. The observed default has since moved to `gpt-5.6-sol`, which is the
argument for the rule rather than against it, so the rule is now stated as "pin nothing to a
model name". A quota-exhaustion note was added, because an unavailable reviewer is a blocked
review to report and not a licence to substitute your own.
