---
name: handoff
description: Use when context is running low, before /clear, the conversation is being compacted, or the user asks to summarize work so a fresh agent can continue a task in a future session.
---

# Handoff

Write HANDOFF.md so a fresh agent can pick up in-flight work without re-deriving context. Pulls from three context sources: built-in user memory, per-project memsearch recall, and non-boilerplate project docs. The **▶ Resume This Work** block at the top is the entry point the `handoff-resume` skill acts on to continue without re-prompting.

## When to Use

- User says "handoff", "wrap up", "summarize for next session", invokes /handoff
- About to /clear, compact context, or end a session mid-task
- Context window approaching limit and work is unfinished
- Switching between agents/sessions on the same task

**Proactively offer** (do not auto-write) when context is clearly running low and the task is incomplete: "Want me to write a handoff before we continue?" Never write one without confirmation outside an explicit request.

**Do NOT use for:**
- Completed tasks (the diff/PR/commit is the handoff)
- One-shot questions
- Tasks already fully captured by memory entries

## Where It Goes

- **Default:** `HANDOFF.md` in current working directory
- **If `HANDOFF.md` already exists:** create `.claude/handoff/` if missing, move existing file to `.claude/handoff/handoff-<YYYYMMDD-HHMM>.md`, then write the new one. Never silent overwrite.
- **Unsafe cwd** (`~`, `/`, anywhere outside an actual project): stop and ask for a path

## Process

1. **Gather git state** (parallel):
   - `git status`
   - `git diff --stat`
   - `git log --oneline -10`
2. **Archive existing** `HANDOFF.md` per the rule above
3. **Discover context sources** (parallel):
   - **Built-in agent memory (if the harness provides one):** the session's own memory directory — for Claude Code, `~/.claude/projects/<project-slug>/memory/*.md` (skim the `MEMORY.md` index first). Skip if your harness has no file-based memory.
   - **Project memsearch (capability, not files; optional):** if `.memsearch/` exists, memsearch is active. Don't enumerate or link the daily logs; instead derive 2-5 **recall seed queries** from this session's work for the next agent to search (optionally sanity-check with `memsearch search "<topic>"`).
   - **Project context docs:** glob `**/*.md` in cwd, exclude boilerplate and build dirs (see below), surface anything non-standard
4. **Extract from conversation:**
   - Original goal
   - Done vs. not done
   - **Failed approaches** — highest-value section, mandatory if any exist
   - Decisions and *why*
   - User preferences expressed this session
   - Errors hit and how they resolved
5. **Cross-link, don't duplicate:**
   - Memory entries → `[[memory-slug]]`
   - Project docs → relative path and one-line relevance
6. **Write `HANDOFF.md`** using the template
7. **Verify** by re-reading as if you were a fresh agent. Gaps? Fix them before declaring done.

### Choosing the resume posture

The ▶ Resume block's **Posture** tells the next session whether to act or ask:

- **autonomous**: next action is safe, unambiguous, and you'd just do it yourself.
- **confirm-first**: next action is clear but consequential (destructive, externally-visible, or costly), or enough time or ambiguity has passed to warrant a quick check.
- **blocked-on-questions**: a decision or open question gates the next step. List those questions in the block, highest-priority first; the resuming agent will ask them and nothing else.

If you can't name one concrete **Next action**, the posture is **blocked-on-questions**: name the decision instead. Never write a vague next action like "pick up wherever makes sense"; that is the exact gap that forces the next session to re-prompt.

### Project doc scan — what counts as non-standard

**Always include when present** (at any depth):
- Per-folder `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` (agent instructions for sub-trees)
- Anything under `.ai/`, `.context/`, `.cursor/`
- ADRs, RFCs, `SPEC*`, `ROADMAP*`, `KNOWN-ISSUES*`, `ARCHITECTURE*`, `DESIGN*`, `TODO*`
- Prior `HANDOFF*.md` archives under `.claude/handoff/`
- Anything under `docs/` or `notes/` that looks bespoke (not auto-generated)

**Always skip:**
- `README*`, `LICENSE*`, `CHANGELOG*`, `CONTRIBUTING*`, `CODE_OF_CONDUCT*`, `SECURITY*`, `PULL_REQUEST_TEMPLATE*`
- Anything under `node_modules/`, `vendor/`, `dist/`, `build/`, `.git/`, `.next/`, `.nuxt/`, `target/`, `__pycache__/`, `.venv/`, generated API doc trees

Example command:

```bash
fd -e md --hidden \
  --exclude node_modules --exclude vendor --exclude dist --exclude build \
  --exclude .next --exclude .nuxt --exclude target --exclude __pycache__ --exclude .venv \
  | grep -vE '/(README|LICENSE|CHANGELOG|CONTRIBUTING|CODE_OF_CONDUCT|SECURITY|PULL_REQUEST_TEMPLATE)([._-][^/]*)?\.md$'
```

For each surfaced doc: open it briefly, write a one-line relevance note. Skip entries the next agent wouldn't need.

## Template

Omit empty sections except the **▶ Resume** block (always required), **Failed Approaches**, and **Resume Instructions** (the latter two mandatory whenever the data exists).

````markdown
# Handoff: <task title>

**Generated:** <YYYY-MM-DD HH:MM>
**Working dir:** <absolute path>
**Branch:** <git branch>

## ▶ Resume This Work
**Posture:** autonomous | confirm-first | blocked-on-questions
**Next action:** <one concrete, imperative sentence: the single first thing to do>
**Read first:** <1-3 pointers: [[memory-slug]], `path/to/doc.md`, or a section below>
<!-- include the next two lines ONLY when posture is blocked-on-questions -->
**Resolve before any work (highest priority first):**
1. <the specific decision/question that gates progress>

Full steps in [Resume Instructions](#resume-instructions).

## Goal
<what the user is trying to achieve>

## Status
- **Phase:** exploration | planning | implementation | debugging | review
- **Progress:** <milestone or rough %>
- **Working:** <what's functional right now>
- **Broken:** <what's not, with error if relevant>
- **Uncommitted:** <summary of staged/unstaged>

## Completed
- [x] <specific item>

## Not Yet Done
- [ ] <remaining item — be specific>

## Failed Approaches (Don't Repeat)
- **Tried:** <what>
  **Why it failed:** <error / perf / design flaw>
  **Why current approach is better:** <reason>

## Key Decisions
| Decision | Rationale |
|---|---|
| <choice> | <why> |

## Open Questions
- [ ] <unresolved question>

## Files to Know
| File | Why it matters |
|---|---|
| `src/foo.ts:42` | <brief> |

## Resume Instructions
1. <setup step if needed>
2. <first action with exact command or `file:line`>
3. <verification step>
   - **Expected:** <outcome>
   - **If it fails:** <what to check>

## Related Memory

**Built-in user memory:**
- [[memory-slug]] — <one-line why relevant>

## Memory Recall (memsearch)
memsearch is active for this project. Rehydrate by recalling these topics (invoke the `memsearch:memory-recall` skill, or `memsearch search "<query>"`); do not read the daily files by hand:
- "<seed query drawn from this session's work>"
- "<another seed query>"

## Project Context Docs
Non-standard markdown that may help orient the next agent:
- `subdir/CLAUDE.md` — per-folder agent instructions
- `docs/architecture.md` — overall system shape
- `.ai/rules.md` — project-specific agent rules
- `KNOWN-ISSUES.md` — pre-existing bugs out of scope here

## Warnings
<gotchas, things that look wrong but are intentional>
````

## Cross-linking, Not Duplicating

Three context stores, three rules:

| Store | Contains | In handoff |
|---|---|---|
| Built-in memory (`~/.claude/projects/.../memory/`) | Durable user facts, preferences, project notes | Link via `[[slug]]`; never inline |
| Project memsearch (`.memsearch/`) | Per-project semantic session memory | Don't link files. Seed recall queries; the resuming agent recalls via `memsearch search` / `memory-recall` |
| Project docs (any `*.md`) | Specs, ADRs, per-folder CLAUDE.md, roadmaps | Link by path; surface the relevant ones with a one-line note |

If a fact will outlive the current task, write it to memory and link — don't trap it in HANDOFF.md.

## Format Rules

- File paths as `src/foo.ts:42` (clickable)
- Bullets and tables over prose
- Don't paste `git diff` content — reference files and intent
- Don't re-explain unchanged code
- Capture conclusions and reasons, not intermediate reasoning

## Common Mistakes

| Mistake | Fix |
|---|---|
| Vague next action ("pick up where it makes sense") | Name ONE concrete next action in the ▶ block, or set posture `blocked-on-questions` and list the decision |
| Omitting Failed Approaches | Mandatory whenever any exist — saves hours next session |
| Vague resume steps ("test it works") | Specific commands, expected output, and failure recovery |
| Duplicating memory content | Use `[[slug]]` or path link instead |
| Skipping per-folder CLAUDE.md / AGENTS.md | Scan recursively; these override global rules |
| Linking `.memsearch/` daily files instead of seeding recall queries | memsearch is a search capability; give the next agent seed queries and let it recall via `memsearch search` / `memory-recall` |
| Including boilerplate (README, LICENSE) | Skip — they don't aid resumption |
| Dumping full code blocks | Reference `file:line`; inline only if file no longer reflects state |
| Writing handoff for completed work | Use PR/commit message instead |
| Silent overwrite of prior handoff | Always archive to `.claude/handoff/handoff-<YYYYMMDD-HHMM>.md` first |

## Quality Check

Before declaring done:
1. Does the **▶ Resume** block name one concrete **Next action** (not a vague "continue") and a justified **Posture**?
2. If posture is `blocked-on-questions`, are the gating questions listed in priority order?
3. Could a fresh agent resume from this alone?
4. Are Failed Approaches captured?
5. Do Resume Instructions include expected outputs?
6. Did you scan for per-folder CLAUDE.md and project context docs?
7. If memsearch is active, did you seed recall queries (not link daily files)?

Any "no" → fix before saving.
