---
name: handoff-resume
description: Use when a fresh session must pick up in-flight work left by a prior session, such as when the user says resume, continue, or pick up where we left off, or when a HANDOFF.md is present and the task is unfinished.
---

# Handoff Resume

Pick up in-flight work from a `HANDOFF.md` so the user never re-explains the task. Locate the handoff, rehydrate the original context, confirm the world hasn't moved, then act on the handoff's declared **posture**: start the work, confirm once, or ask the blocking questions. Pairs with the `handoff` skill, which writes the **▶ Resume This Work** block this skill reads.

## When to Use

- Fresh session and the user says "resume", "continue", "pick up the handoff", "where were we"
- A `HANDOFF.md` is present and the task is unfinished
- Switching agents or sessions mid-task

**Do NOT use for:** a brand-new task, or when the user's message is itself a specific instruction (follow that instead). If no handoff exists, say so; don't invent one.

## Process

1. **Locate the handoff.** Explicit path arg if given, else `HANDOFF.md` in cwd, else newest under `.claude/handoff/` (if several, list them and ask which), else report "no handoff found" and stop.
2. **Read it fully.** Find the **▶ Resume This Work** block (Posture + Next action). No block? See the legacy row in the posture table.
3. **Drift check, before acting.** Run `git status` and `git log --oneline -10`. Compare against the handoff's **Branch** and any commit it cites. If the tree moved (new commits, different branch, unexpected uncommitted work, or you aren't even in the handoff's working dir), surface it and reconcile before building on the handoff. The handoff is a map written in the past; confirm the territory.
4. **Rehydrate context** (do not skip: this is what removes the need to re-explain):
   - **Built-in agent memory:** read each `[[memory-slug]]` the handoff links; verify it still exists. Skip if your harness has no file-based memory.
   - **memsearch (optional; only if the handoff has a Memory Recall section and `.memsearch/` exists):** invoke the `memsearch:memory-recall` skill (or run `memsearch search "<query>"`) on the handoff's seed queries plus the goal. Do **not** read `.memsearch/memory/*.md` as files; they are large and built for semantic retrieval. If memsearch isn't installed, skip this and rely on the handoff's own narrative.
   - **Project docs:** open the handoff's linked **Project Context Docs**.
5. **Honor the posture** (table below). For work that proceeds, build a TodoWrite from **Not Yet Done**, then start.

## Posture, and what you do

| Posture | Action |
|---|---|
| `autonomous` | Announce `Resuming: <next action>`, then **start executing** immediately. Don't summarize the handoff back. |
| `confirm-first` | State the next action plus a one-line plan, ask **one** go/no-go, then execute. |
| `blocked-on-questions` | Lead with the handoff's listed questions, **highest priority first**. Wait for answers. Do **not** start arbitrary work to look busy. |
| *(no ▶ block: legacy or foreign handoff)* | Derive posture **and** next action from `Resume Instructions` plus `Open Questions`. If they say to resolve questions before proceeding (e.g. "do not proceed until..."), treat as `blocked-on-questions` and lead with those; otherwise `confirm-first`, with next action = the first concrete Resume step. Note the handoff predates posture-tagging. |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Summarizing the handoff back, then asking "what now?" | The **Next action** already answers that. Resume = do it (or ask the *blocking* question), not recap. |
| Posture is `blocked-on-questions` but you start coding anyway | Blocked means ask the listed questions first. Arbitrary progress splits attention and ignores the fork. |
| Picking a task the handoff didn't name | Follow **Next action**. If it's genuinely unclear, that's a blocking question; raise it. |
| Reading `.memsearch/memory/*.md` directly | Use `memory-recall` / `memsearch search`; daily logs are large and built for semantic retrieval. |
| Acting despite git drift | If commits or branch changed since the handoff, reconcile first. |

## Quality Check

Before you start work (or ask the blocking questions):

1. Did you run the git drift check?
2. Did you rehydrate memory via the capability (`memory-recall` / `memsearch search`), not raw file reads?
3. Are you honoring the declared posture exactly: starting when `autonomous`, asking the listed questions when `blocked-on-questions`?
4. If `autonomous`: are you about to **do** the next action, not describe it?
