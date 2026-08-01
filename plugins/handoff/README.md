# handoff

Two skills for one problem: work outlasts the context window, and you shouldn't have to explain the
same task twice.

`handoff` writes the record. `handoff-resume` reads it and carries on. They ship together because
the `▶ Resume This Work` block at the top of the file is the contract between them — one writes it,
the other acts on it.

## Using it

Both skills trigger from ordinary phrasing. There are no commands to memorise.

```text
handoff                                  before /clear, or when context is running low
wrap up, we'll continue tomorrow
summarize this for the next session

resume                                   in a fresh session
continue where we left off
pick up the handoff
```

The first group writes `HANDOFF.md` in the working directory. The second finds it, checks the repo
hasn't moved underneath it, and starts work.

## What ends up in the file

Goal, branch and commit, what's done and what isn't, and decisions with the reasoning attached.

The section that earns its keep is **failed approaches**, which is mandatory whenever there are any.
A fresh agent that doesn't know what was already tried will try it again, confidently.

It also records a **posture** — start the work, confirm once first, or open with blocking questions.
That's what lets `handoff-resume` act instead of interrogating you.

An existing `HANDOFF.md` is archived to `.claude/handoff/handoff-<YYYYMMDD-HHMM>.md` rather than
overwritten.

## What resuming does first

`handoff-resume` reads the file, then **checks for drift** with `git status` and `git log` against
the branch and commit the handoff names. A handoff describes the repository as it was, and the
repository may have moved since. When it has, that gets raised and reconciled before anything is
built on top of it. Only then does the posture apply.

## Worth knowing

- When `handoff` offers proactively, it asks first. A handoff written without confirmation costs you
  a file you didn't ask for, at the moment you had the least context to review it. An explicit
  request writes straight away.
- Neither skill invents a handoff. If there isn't one, `handoff-resume` says so and stops.
- Finished work doesn't need one. The diff, the PR and the commit message are the handoff.

## Requirements

| Dependency | Required | Used for |
|---|---|---|
| `git` | yes | recording branch and commits, and the drift check on resume |
| an agent memory directory | no | linked as `[[slug]]` when the harness has one |
| [`memsearch`](https://github.com/zilliztech/memsearch) | no | seeding semantic recall queries when `.memsearch/` exists |

Both optional integrations degrade to nothing. Without them the handoff still carries its own
narrative, which is most of the value.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install handoff@sereneco
```

Available immediately. No restart, since there are no hooks.

## Portability

Both skills are plain `SKILL.md` files with no scripts and no harness-specific tool calls, so they
work anywhere skills are read from a directory: Claude Code via this plugin, or a shared skills
store symlinked into whatever else you run. The one Claude Code-shaped assumption is the
`.claude/handoff/` archive path.
