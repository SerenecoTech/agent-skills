# handoff

Two skills for one problem: work outlasts the context window, and you should not have to explain the
same task twice.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install handoff@sereneco
```

Works immediately. No restart, because there are no hooks.

Needs `git`.

## Using it

No commands to memorise. Both skills trigger from ordinary phrasing.

```text
handoff                                  before /clear, or when context is running low
wrap up, we'll continue tomorrow
summarize this for the next session

resume                                   in a fresh session
continue where we left off
pick up the handoff
```

The first group writes `HANDOFF.md` in the working directory. The second finds it, checks the repo
has not moved underneath it, and starts work.

## What ends up in the file

Goal, branch and commit, what is done and what is not, and decisions with the reasoning attached.

The section that earns its keep is **failed approaches**, mandatory whenever there are any. A fresh
agent that does not know what was already tried will try it again, confidently.

It also records a **posture**: start the work, confirm once first, or open with blocking questions.
That is what lets `handoff-resume` act instead of interrogating you.

An existing `HANDOFF.md` is archived to `.claude/handoff/handoff-<YYYYMMDD-HHMM>.md` rather than
overwritten.

## What resuming does first

`handoff-resume` reads the file, then checks for drift with `git status` and `git log` against the
branch and commit the handoff names. A handoff describes the repository as it was, and the
repository may have moved. Drift gets raised and reconciled before anything is built on top of it.
Only then does the posture apply.

## Worth knowing

- When `handoff` offers proactively, it asks first. An explicit request writes straight away.
- Neither skill invents a handoff. If there is not one, `handoff-resume` says so and stops.
- Finished work does not need one. The diff, the PR and the commit message are the handoff.

## Optional integrations

| Integration | Used for |
|---|---|
| an agent memory directory | linked as `[[slug]]` when the harness has one |
| [`memsearch`](https://github.com/zilliztech/memsearch) | seeding semantic recall queries when `.memsearch/` exists |

Both degrade to nothing. Without them the handoff still carries its own narrative, which is most of
the value.

## Portability

Both skills are plain `SKILL.md` files with no scripts and no harness-specific tool calls, so they
work anywhere skills are read from a directory: Claude Code via this plugin, or a shared skills
store symlinked into whatever else you run. The one Claude Code-shaped assumption is the
`.claude/handoff/` archive path.
