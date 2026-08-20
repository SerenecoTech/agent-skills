# Rubric: code

Applies to diffs, PRs, commits, and source files.

## Confirmed means

A **reproduction**. Ideally a failing test, which then becomes the regression test for the
fix. An argument that something "could" break is not confirmed — it is a hypothesis, and the
adjudication step exists to settle it.

## Probes

Stable ids. Use them verbatim when recording which probes a round ran. **Never invent probes
per run** — a padded or improvised list defeats the convergence rule.

| id | probe |
|---|---|
| `C-LOGIC` | Logic errors, off-by-one, inverted conditions, wrong operator, unreachable branches |
| `C-NULL` | Null/undefined access, unchecked optionals, type coercion surprises |
| `C-RACE` | Shared mutable state, missing locks, async ordering, check-then-act windows |
| `C-ERR` | Swallowed errors, missing cleanup, unclosed resources, partial failure left half-applied |
| `C-INJ` | Injection, unsafe deserialisation, auth bypass, data exposure, unvalidated boundaries |
| `C-PERF` | N+1 queries, unbounded loops or growth, missing pagination, leaks |
| `C-API` | Breaking change to an exported signature, serialised format, or persisted shape |
| `C-GOLDEN` | Anything touching a byte-exact golden or a parity capture — does the change move a pinned output, and is that intended and re-pinned? |
| `C-WORKER` | Worker/main divergence: the same computation implemented or configured twice, drifting |
| `C-BUDGET` | Budget-estimator accuracy: does a cost model still match what the code actually does? |

`C-GOLDEN`, `C-WORKER` and `C-BUDGET` are repo-specific and earn their place: each maps to a
defect class this project has actually shipped.

## Required read scope

Reading only the diff misses compatibility breaks at the call sites. Reading everything is
unaffordable. So:

1. **Always in scope, before any cap** — every importer whose path matches a
   security-sensitive pattern: `auth`, `crypto`, `payment`, `permission`, `session`, `token`.
   A pure proximity-and-recency ordering can rank the most critical consumer out of scope: a
   stable payment service lands 26th behind 25 recently-churned low-risk ones, and a semantic
   change that preserves the exported signature makes its authorization fail open.
2. **Depth 1** — then up to **25** further direct importers.
3. **Depth 2** — only when an exported signature changes, up to **25** more consumers.
4. **Colocated tests** for everything in scope, uncapped.

**Ordering is deterministic**, because "proximity" and "recently changed" are not
self-explanatory and two compliant reviewers would otherwise inspect different sets:

1. fewest path segments between the changed file and the importer;
2. then most recent `git log -1 --format=%ct` on the importer;
3. then lexicographic path.

**Log truncation with its count and the ordering key used.** A silently capped scope reads as
full coverage.

The caps are arguable. Arguable and written down beats unarguable and absent — revisit them
against real truncation logs once this has run on real targets.

## Preferred invocation

The native `codex exec review` resolves the target itself, and `--uncommitted` includes
untracked files — a hand-written "staged and unstaged" description omits them, so a brand-new
source file gets no review.

But a target flag and a prompt cannot be passed together, and the engine requires a per-round
brief. So the brief wins: pass it on stdin with **no** target flag and name the target in the
brief itself, or use the general `codex exec` form and have the reviewer run `git status` and
`git diff` for itself. Either way, state in the brief that untracked files are in scope —
that is the one thing `--uncommitted` was buying, and describing the target by hand is exactly
where it gets dropped. See `invocation.md` for the measured command lines.
