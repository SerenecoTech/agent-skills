# adversarial-review

Code, architecture and specification review with a second, hostile reviewer: OpenAI Codex when it
is available, otherwise a separate Claude Opus process.

The reviewer finds problems. Claude adjudicates and fixes them. The reviewer never writes to your
repository.

Codex is preferred because it is a different model family, with different blind spots. Without it
the review still runs the same workflow, and the report says the reviewer was the same family.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
```

**Restart Claude Code.** The skills work immediately, but the four hooks load only at session start
and enforce nothing until you restart. Then check `claude plugin list` says `Status: ✔ enabled`.

Install and log in to `codex` to get the cross-model review. Without it the Claude reviewer runs
instead. Full dependency list is [below](#requirements).

## Using it

Both skills trigger from ordinary phrasing. You do not pick one; the phrasing does.

```text
review my changes                        working tree, staged, or last commit
review PR 412
review this branch against main

poke holes in docs/plans/caching.md      a spec, RFC, plan or proposal
sanity-check this architecture
what could go wrong with this approach?
```

The first group opens `review-code`, the second `review-design`.

Expect minutes rather than seconds, and up to 40 reviewer calls. It runs multiple rounds and stops
when it converges.

## Which reviewer runs

The reviewer is a **provider**: Codex first, Claude as the fallback. `engine/select-reviewer.sh`
lists the providers that can run, in the order in `engine/providers/PRIORITY`.
`engine/run-reviewer.sh` runs the first. If a call fails partway through a review, for example
on a usage limit, the same round runs on the next provider instead of stopping, and the report
states the switch and the error. [`WORKFLOW.md`](WORKFLOW.md) diagrams this and the rest of the
review.

The Claude provider is `claude -p` on the latest Opus at high effort. It runs read-only, without
your CLAUDE.md, plugins or hooks, and without saving a session, so it never appears in your
session lists. Override the model or effort with `ADVERSARIAL_REVIEW_CLAUDE_MODEL` and
`ADVERSARIAL_REVIEW_CLAUDE_EFFORT`, and the order with `ADVERSARIAL_REVIEW_PROVIDERS`.

To add a provider, see [`engine/providers/README.md`](engine/providers/README.md).

## Clean up when a review ends

Delete `.claude/adversarial-review/state.json` when you are done. Leaving it in place with a narrow
allowlist blocks unrelated work in your next session.

Git-ignore the whole `.claude/adversarial-review/` folder. A review also leaves logs, the scope
snapshot and reviewer output there, and untracked files left behind would make the next PR review
stop at its clean-tree check.

## Requirements

| Dependency | Required | Used for |
|---|---|---|
| `codex` (codex-cli ≥ 0.146.0) | preferred | the cross-model reviewer, via `codex exec --output-schema` |
| `claude` (Claude Code) | yes, as fallback | the reviewer when Codex is missing or fails; needs `--json-schema` and `--no-session-persistence` |
| `jq` (≥ 1.6) | yes | hooks read their event and emit decisions as JSON; the verifier parses findings |
| `bash` (≥ 4) | yes | all hooks and the verifier |
| `git` | yes | target resolution, diffs, and the importer-ordering recency key |
| coreutils / POSIX text tools | yes | `sed`, `awk`, `grep`, `tr`, `wc`, `head`, `cut`, `sort`, `mktemp`, `date`, `basename` |
| `shuf` | yes | picking unpredictable echo-probe lines |
| `gh` | optional | only for PR-number targets in `review-code` |

Codex model choice is constrained by account type, so a review must not depend on `-m` selecting
a particular model unless you have confirmed that model is available to you.

**Check the Codex sandbox mode before trusting it.** The Codex provider passes
`-s danger-full-access`, because in a container that cannot create user namespaces every other
mode fails and Codex reads nothing. Where a restrictive mode works, it is preferable. See
[`engine/providers/codex/README.md`](engine/providers/codex/README.md).

## The two doors

| Door | Triggers on |
|---|---|
| `review-code` | PRs, branches, commits, diffs, working tree, "check my changes" |
| `review-design` | architecture, RFCs, proposals, specs, plans, "poke holes in this" |

Both load the same engine. A door resolves the target and does nothing else. In particular it does
not set the evidence bar: the engine inspects the artefact and loads every rubric that applies, so
an API specification containing pseudocode gets the same treatment whichever door fired.

## The four gates

A self-administered protocol cannot make guarantees against its own administrator. The agent that
writes a fix also chooses the verification command and interprets its output. Each additional rule
written into a skill is one more instruction the same party both writes and follows.

A hook is configured outside the model's control and can refuse a call whatever the intent behind
it. That is why this ships as a plugin rather than skills alone.

| Gate | Enforces |
|---|---|
| `write-path-gate` | No file-tool write to the repository outside the declared allowlist, and **no write at all** during a verdict review. Paths are resolved first, so `..` cannot climb out of an exempt folder |
| `appendix-gate` | No reviewer call while a prior refutation appendix is unread; the denial injects it |
| `rubric-gate` | Rejects near-duplicate probes that would satisfy the convergence rule without examining anything new |
| `verification-recorder` | Records which verification commands ran, and their real exit status |

The gates keep a review on its scope. They are not a security layer, and they do not repeat the
work of your permission rules or of security hooks such as `guard-hooks`. In particular, the write
gate does not try to predict what a Bash command writes. Instead, `engine/check-changes.sh`
snapshots the working tree when a review begins and, before the report, lists every path changed
since, however it was changed, flagging any outside the allowed paths.

**Every gate fails open** when `state.json` is absent, malformed, or `active` is not `true`. A gate
that breaks ordinary editing is a gate someone disables, and a disabled gate is worse than no gate,
because the report still claims the guarantee. Gates append to `gate-log.tsv` when they fire, so a
report can state what was actually enforced. `run-reviewer.sh` appends every call and fallback to
`reviewer-log.tsv` in the same directory.

## Runtime state

The gates read `.claude/adversarial-review/state.json`, which the skill writes:

```json
{
  "active": true,
  "slug": "creasewall-collar",
  "loop": "fix",
  "authorized_paths": ["lib/creaseWall.ts", "tests/unit/*.test.ts"],
  "appendix": "docs/reviews/creasewall-collar/appendix.md",
  "appendix_read": false,
  "probes_previous_round": ["C-LOGIC", "C-RACE"]
}
```

## Limitations

Every report the engine produces carries these, because none is solved:

- Proof of work proves **access, not comprehension.** A shallow read of every file passes.
- A round run by the Claude reviewer was reviewed by the same model family that adjudicates it.
- The reviewing agent is still sole writer, adjudicator and verifier. The write-path gate constrains
  where it writes, but bias in what it confirms or refutes is **narrowed, not closed.**
- Prompt injection against an unsandboxed reviewer is out of scope. That belongs to the sandbox
  layer.

## Layout

```text
adversarial-review/
├── .claude-plugin/plugin.json
├── WORKFLOW.md                    # diagrams: review lifecycle, one round, reviewer dispatch, gates
├── engine/                        # shared reference, deliberately not a skill
│   ├── ENGINE.md                  # loop shape, scope gate, rounds, convergence, output
│   ├── invocation.md              # the reviewer contract: choice, fallback, proof of work, budget
│   ├── select-reviewer.sh         # selection: providers that can run, best first
│   ├── run-reviewer.sh            # execution: runs a provider, falls back, logs
│   ├── providers/
│   │   ├── README.md              # the provider contract, and how to add one
│   │   ├── PRIORITY               # the order providers are tried
│   │   ├── codex/                 # provider.sh + README.md
│   │   └── claude/                # provider.sh + README.md
│   ├── rubric-{code,architecture,document}.md
│   ├── schema/findings.json       # enforced on every reviewer call
│   ├── schema/check-output.jq     # checks out.json against findings.json
│   ├── verify-proof-of-work.sh
│   ├── check-changes.sh           # snapshot at review start; list out-of-scope changes after
│   └── test-engine.sh             # selection, execution, proof of work and the scope check
├── skills/
│   ├── review-code/SKILL.md       # door: PR, branch, commit, diff, "my changes"
│   └── review-design/SKILL.md     # door: architecture, RFC, spec, plan
└── hooks/
    ├── hooks.json
    ├── lib-state.sh               # shared helpers; every gate fails open
    ├── write-path-gate.sh         # PreToolUse  Edit|Write|MultiEdit|NotebookEdit
    ├── appendix-gate.sh           # PreToolUse  Bash (reviewer calls only)
    ├── rubric-gate.sh             # PreToolUse  Bash (reviewer calls only)
    ├── verification-recorder.sh   # PostToolUse + PostToolUseFailure Bash
    └── test-gates.sh
```

The engine sits outside `skills/` on purpose: it has no `SKILL.md` and no trigger of its own, and
the doors load it via `../../engine/`.
