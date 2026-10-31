# Provider: Claude

The fallback reviewer: a separate `claude -p` process on the latest Opus.

**Available when** `claude` is on PATH and `claude auth status --json` reports
`"loggedIn": true`.

**It is the same model family as the agent adjudicating.** It runs blind, in a fresh context,
with a hostile brief, so the workflow still holds: independent findings, adjudication with
evidence, challenge, proof of work. It does not give you a second family's blind spots. Two
Claude instances agreeing is weaker evidence than Claude and Codex agreeing, and the report
says which reviewer ran.

`ADVERSARIAL_REVIEW_CLAUDE_MODEL` (default `opus`, the alias for the latest Opus) and
`ADVERSARIAL_REVIEW_CLAUDE_EFFORT` (default `high`) override the model and effort.

## The call

See `provider.sh` for the full command. Each flag is there for a reason:

| Flag | Why |
|---|---|
| `--no-session-persistence` | Without it every call saves a transcript, and each round and challenge appears as a one-message session in `/resume` and the IDE session list. The skill sends every reviewer call through `run-reviewer.sh` so this flag is never left off. |
| `--safe-mode` | Keeps the user's CLAUDE.md, plugins, hooks and memory out of the reviewer, including this plugin's own gates. |
| `--restricted` | Ignores the user's settings files, so their allow rules do not widen what the reviewer may run. |
| `--tools`, `--allowedTools`, `--disallowedTools` | Read, Grep, Glob, and a fixed list of read-only `git` commands. `git * --output*` is denied because `git diff`, `log` and `show` can write a file with it. |
| `--permission-mode dontAsk`, `--permission-prompts none` | Anything not on the list is denied, with nobody to ask. |
| `--append-system-prompt` | The hostile reviewer stance. |
| `--json-schema` | Holds the output to the findings schema. It rejects the schema's `$schema` key, so that key is removed first. |
| `--output-format stream-json --verbose` | Writes the event trace that proof of work audits. |

The findings arrive as `.structured_output` on the final `result` event. `provider_run` copies
them to `out.json`, and the call fails if they are missing or the result is an error.

## Trace

One event per line. Each tool call is a `tool_use` event, and what it returned is a
`tool_result` event with `content` and, when it failed or was denied, `is_error: true`. The
trace audit reads the `content` of every `tool_result` without `is_error`.
