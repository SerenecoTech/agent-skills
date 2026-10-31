# Provider: Codex

The preferred reviewer. It is a different model family from the one adjudicating, so its
blind spots are less likely to match.

**Available when** `codex` is on PATH and `codex login status` succeeds.

## The call

```bash
codex exec --ephemeral -C "$REPO" -s danger-full-access --json \
  --output-schema "$SCHEMA" -o "$OUT/out.json" - \
  < "$OUT/brief.md" > "$OUT/trace.jsonl" 2> "$OUT/stderr.txt"
```

| Flag | Why |
|---|---|
| `--ephemeral` | Without it every call saves a Codex session file, which the provider contract forbids. |
| `-C "$REPO"` | Codex refuses to start outside a git working directory. |
| `-s danger-full-access` | Codex reads files by shelling out. Where its sandbox cannot start, for example in a container that cannot create user namespaces, every other mode fails and Codex reviews only the brief text: a confident review of nothing. Check whether a stricter mode works in your environment before relying on this one. |
| `--json` | Writes the event trace that proof of work audits. |
| `--output-schema` | Holds the output to the findings schema. The schema must list every property in `required`; an optional field is a nullable type. A schema that breaks this is rejected before the model sees it (ISSUE-001). |
| `-o` | Writes the final structured output to `out.json`. Use absolute paths. |
| `-` | Reads the brief from stdin. |

No `-m`. Which models an account can use varies, so nothing pins a model name.

## Code review targets

The brief names the target and tells Codex to run `git status` and `git diff` itself. The
native `codex exec review` subcommand is not used: it takes a target flag or a prompt, never
both, and the engine requires a brief every round. State in the brief that untracked files are
in scope; a hand-written "staged and unstaged" target omits them.

## What it still loads

Codex reads `AGENTS.md` instruction files from the user's Codex home and from the repository,
and `--ephemeral` does not change that. So the Codex reviewer is blind to the conversation but
not to those files. No CLI option to switch this off has been confirmed. If an `AGENTS.md`
carries review conclusions or policies, say so in the report.

## Failures

A usage limit returns `ERROR: You've hit your usage limit … try again at <date>`. Network
errors and timeouts also fail the call. `run-reviewer.sh` then moves to the next provider.

## Trace

One event per line. Each shell command ends in an `item.completed` event whose `item` has
`type: "command_execution"`, a `status` of `completed` or `failed`, and the command's
`aggregated_output`. The trace audit reads the output of every completed command.
