# adversarial-review

Code, architecture and specification review with OpenAI Codex as a second, hostile reviewer.

Codex finds problems. Claude adjudicates and fixes them. Codex never writes to your repository.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
```

**Restart Claude Code.** The skills work immediately, but the four hooks load only at session start
and enforce nothing until you restart. Then check `claude plugin list` says `Status: ✔ enabled`.

`codex` must be installed and authenticated. Full dependency list is [below](#requirements).

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

Expect minutes rather than seconds, and up to 40 `codex` calls. It runs multiple rounds and stops
when it converges.

## Clean up when a review ends

Delete `.claude/adversarial-review/state.json` when you are done. Leaving it in place with a narrow
allowlist blocks unrelated work in your next session.

Git-ignore that file.

## Requirements

| Dependency | Required | Used for |
|---|---|---|
| `codex` (codex-cli ≥ 0.146.0) | yes | the reviewer itself, including `codex exec review` and `--output-schema` |
| `jq` (≥ 1.6) | yes | hooks read their event and emit decisions as JSON; the verifier parses findings |
| `bash` (≥ 4) | yes | all hooks and the verifier |
| `git` | yes | target resolution, diffs, and the importer-ordering recency key |
| coreutils / POSIX text tools | yes | `sed`, `awk`, `grep`, `tr`, `wc`, `head`, `cut`, `sort`, `mktemp`, `date`, `basename` |
| `shuf` | yes | picking unpredictable echo-probe lines |
| `gh` | optional | only for PR-number targets in `review-code` |

Model choice is constrained by account type, so a review must not depend on `-m` selecting a
particular model unless you have confirmed that model is available to you.

**Check the sandbox mode before trusting it.** `engine/invocation.md` mandates
`-s danger-full-access`, the only mode that worked where this was built: every other mode fails at
bwrap because the container cannot create user namespaces. In a container that permits userns, a
restrictive mode is both available and preferable. Verify this for your environment.

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
| `write-path-gate` | No write outside the declared allowlist, and **no write at all** during a verdict review |
| `appendix-gate` | Codex cannot start while a prior refutation appendix is unread; the denial injects it |
| `rubric-gate` | Rejects near-duplicate probes that would satisfy the convergence rule without examining anything new |
| `verification-recorder` | Records which verification commands ran, and their real exit status |

**Every gate fails open** when `state.json` is absent, malformed, or `active` is not `true`. A gate
that breaks ordinary editing is a gate someone disables, and a disabled gate is worse than no gate,
because the report still claims the guarantee. Gates append to `gate-log.tsv` when they fire, so a
report can state what was actually enforced.

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
- The reviewing agent is still sole writer, adjudicator and verifier. The write-path gate constrains
  where it writes, but bias in what it confirms or refutes is **narrowed, not closed.**
- Prompt injection against an unsandboxed reviewer is out of scope. That belongs to the sandbox
  layer.

## Layout

```text
adversarial-review/
├── .claude-plugin/plugin.json
├── engine/                        # shared reference, deliberately not a skill
│   ├── ENGINE.md                  # loop shape, scope gate, rounds, convergence, output
│   ├── invocation.md              # the codex contract: flags, proof of work, budget
│   ├── rubric-{code,architecture,document}.md
│   ├── schema/findings.json       # enforced via codex --output-schema
│   └── verify-proof-of-work.sh
├── skills/
│   ├── review-code/SKILL.md       # door: PR, branch, commit, diff, "my changes"
│   └── review-design/SKILL.md     # door: architecture, RFC, spec, plan
└── hooks/
    ├── hooks.json
    ├── lib-state.sh               # shared helpers; every gate fails open
    ├── write-path-gate.sh         # PreToolUse  Edit|Write|MultiEdit|NotebookEdit
    ├── appendix-gate.sh           # PreToolUse  Bash (codex invocations only)
    ├── rubric-gate.sh             # PreToolUse  Bash (codex invocations only)
    ├── verification-recorder.sh   # PostToolUse Bash
    └── test-gates.sh
```

The engine sits outside `skills/` on purpose: it has no `SKILL.md` and no trigger of its own, and
the doors load it via `../../engine/`.
