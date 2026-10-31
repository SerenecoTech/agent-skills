# Reviewer providers

A provider is one way to run the second reviewer. Each lives in its own directory here:

| Provider | What it runs | Why it is in this position |
|---|---|---|
| [`codex`](codex/README.md) | OpenAI Codex, `codex exec` | First: a different model family, with different blind spots |
| [`claude`](claude/README.md) | A separate Claude process, `claude -p` | Fallback: same family as the adjudicator, so it is labelled as such |

[`PRIORITY`](PRIORITY) lists them in the order they are tried. `ADVERSARIAL_REVIEW_PROVIDERS`
overrides it for one shell, for example `ADVERSARIAL_REVIEW_PROVIDERS="claude"`.

Selection and execution are separate scripts:

- `select-reviewer.sh` sources each provider in priority order, asks whether it can run, and
  prints the ones that can.
- `run-reviewer.sh` runs the first of them. If its call fails, it runs the next, and logs the
  fallback. It knows nothing about any one provider.

## The contract

`provider.sh` is sourced, never executed, and defines three functions:

| Function | Must |
|---|---|
| `provider_available` | Return 0 only if a review call can start here: the CLI is installed and logged in. Fast, no model call. |
| `provider_label` | Print one line naming what ran, including the model where it is chosen, for the report. |
| `provider_run` | Read `$OUT/brief.md`, write `$OUT/out.json`, `$OUT/trace.jsonl` and `$OUT/stderr.txt`, and return the CLI's exit status. |

`run-reviewer.sh` provides `$REPO`, `$OUT`, `$SCHEMA` and a `with_timeout` function to wrap the
CLI call in. It checks `out.json` itself after `provider_run` returns.

A provider must also:

- **Enforce the schema.** Use the CLI's structured-output option with `$SCHEMA`. Never parse
  prose.
- **Leave the repository unchanged.** The reviewer reads; Claude adjudicates and fixes.
- **Run blind.** No access to the conversation, and none of the user's own instructions where
  the CLI allows that. Say in the provider's README what it still loads.
- **Leave nothing behind.** No saved session, no history entry, nothing in the user's session
  lists.
- **Write a trace `verify-proof-of-work.sh` can audit.** One JSON event per line, recording
  what each tool call returned and whether it succeeded. If the format is new, teach the trace
  audit where the successful outputs are.

## Adding a provider

1. Create `providers/<name>/provider.sh` implementing the three functions.
2. Create `providers/<name>/README.md`: what it runs, the flags and why each is there, and how
   its trace records reads. Do not name the directory's doc `claude.md` or similar: on a
   case-insensitive filesystem Claude Code loads `CLAUDE.md` as instructions.
3. Add the name to `PRIORITY` where it belongs.
