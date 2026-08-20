# Sereneco agent skills documentation

The shared skills and Claude Code plugins in this repository: `adversarial-review`, `handoff`,
`guard-hooks`, and the skills under [`skills/`](../skills/).

`README.md` at the repository root is the entry point for what each plugin does and how to install
it. This page is the documentation home: it says which collections exist and what lives where.

## Collections

Collections appear here once they hold their first record.

| Collection           | Holds                                              |
| -------------------- | -------------------------------------------------- |
| [`issues/`](issues/) | Standalone bugs, tasks, chores, gaps and questions |

`roadmap/`, `work/`, `product/`, `architecture/`, `decisions/`, `operations/` and `reference/` do
not exist yet. They are created when their first record does, not in advance.

## Current work

| Record                                                                          | Status     | Subject                                                               |
| ------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------- |
| [`ISSUE-002`](issues/2026-08-17-credential-printing-commands-were-unguarded.md) | `resolved` | Commands whose stdout is a credential were unguarded                  |
| [`ISSUE-001`](issues/2026-08-16-adversarial-review-schema-rejected.md)          | `open`     | The `adversarial-review` findings schema is rejected by the Codex CLI |
