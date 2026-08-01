# handoff

Two skills for the same problem: work outlives the context window, and the user should never have
to explain the task twice.

`handoff` writes the record. `handoff-resume` reads it and continues. They are packaged together
because a handoff written in a format nothing reads is just a file, and a resumer with nothing to
resume is dead weight — the `▶ Resume This Work` block is the contract between them.

## Requirements

| Dependency | Required | Used for |
|---|---|---|
| `git` | yes | `handoff` records branch and recent commits; `handoff-resume` drift-checks against them |
| a file-based agent memory | no | linked as `[[slug]]` if the harness has one; skipped otherwise |
| [`memsearch`](https://github.com/zilliztech/memsearch) | no | seeds semantic recall queries when `.memsearch/` exists |

Both optional integrations degrade to nothing. Without them the handoff carries its own narrative
and still works.

## The two skills

| Skill | Fires on |
|---|---|
| `handoff` | "handoff", "wrap up", "summarize for next session", before `/clear`, context running low mid-task |
| `handoff-resume` | "resume", "continue", "pick up where we left off", or a `HANDOFF.md` present with work unfinished |

### What `handoff` captures

Goal, branch and commit, done vs. not done, decisions **with their rationale**, and — the section
that carries the most value — **failed approaches**, which is mandatory whenever any exist. A
fresh agent that doesn't know what was already tried will try it again.

It also records a **posture**: whether the next session should start work, confirm once first, or
open with blocking questions. That is what lets `handoff-resume` act rather than ask.

Existing `HANDOFF.md` files are archived to `.claude/handoff/handoff-<YYYYMMDD-HHMM>.md`, never
silently overwritten.

### What `handoff-resume` does before acting

Reads the handoff fully, then **drift-checks**: `git status` and `git log` against the branch and
commit the handoff cites. A handoff is a map written in the past, and the tree may have moved. If
it has, that gets surfaced and reconciled before anything is built on top of it. Only then does
it honour the posture.

## Behaviour worth knowing about

- `handoff` **proposes rather than writes** when it is offering proactively — a handoff written
  without confirmation costs you a file you didn't ask for at the moment you had least context to
  review it. An explicit request writes immediately.
- Neither skill invents a handoff. If `handoff-resume` finds none, it says so and stops.
- Completed work needs no handoff. The diff, the PR and the commit message are the handoff.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install handoff@serenecotech
```

Skills are available immediately; no restart needed.

## Portability

Both are plain `SKILL.md` files with no scripts, no hooks and no harness-specific tool calls, so
they work anywhere skills are read from a directory — Claude Code via this plugin, or a
shared skills store symlinked into whatever agent you run. The only Claude Code-shaped
convention is the `.claude/handoff/` archive path.
