# adversarial-review

Code, architecture and specification review with OpenAI Codex acting as a second, hostile reviewer.
Two front doors over one shared engine, plus four hooks that enforce the parts a skill can't enforce
on itself.

Codex finds problems. Claude adjudicates and fixes them. Codex never writes to your repository.

## Using it

Both skills trigger from ordinary phrasing:

```text
review my changes                        working tree, staged, or last commit
review PR 412
review this branch against main

poke holes in docs/plans/caching.md      a spec, RFC, plan or proposal
sanity-check this architecture
what could go wrong with this approach?
```

The first group opens `review-code`, the second `review-design`. You don't pick; the phrasing does.

Expect a review to take minutes rather than seconds, and to cost up to 40 `codex` calls. It runs
multiple rounds and stops when it converges.

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

Codex must be authenticated. Model choice is constrained by account type, so a review must not
depend on `-m` selecting a particular model unless you've confirmed that model is available to you.

**Check the sandbox mode before trusting it.** `engine/invocation.md` mandates
`-s danger-full-access`, which is the only mode that worked where this was built: every other mode
fails at bwrap because the container can't create user namespaces. In a container that permits
userns, a restrictive mode is both available and preferable, so verify this for your environment.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
```

Skills work immediately. **Hooks load at session start**, so restart before expecting the gates to
enforce anything. Then check `claude plugin list` shows `Status: ✔ enabled`; a hook that failed to
load is reported there and not by `claude plugin validate`.

## The two doors

| Door | Triggers on |
|---|---|
| `review-code` | PRs, branches, commits, diffs, working tree, "check my changes" |
| `review-design` | architecture, RFCs, proposals, specs, plans, "poke holes in this" |

Both load the engine and follow it. A door resolves the target and does nothing else — in particular
**it doesn't set the evidence bar.** The engine inspects the artefact and loads every rubric that
applies, so an API specification containing pseudocode gets the same treatment whichever door fired.

## Why hooks and not more instructions

A self-administered protocol can't make guarantees against its own administrator. Instructions can't
compel a later session to read a refutation it would rather skip. The agent that writes a fix also
chooses the verification command and interprets its output. A rubric can be padded by whoever writes
it. Each additional rule in a skill is one more instruction the same party both writes and follows.

A hook is different, being configured outside the model's control and able to refuse a call whatever
the intent behind it. That's why this ships as a plugin instead of skills alone: the gate arrives
with the instructions, rather than depending on someone remembering to wire it up.

| Gate | Enforces |
|---|---|
| `write-path-gate` | No write outside the declared allowlist, and **no write at all** during a verdict review |
| `appendix-gate` | Codex can't start while a prior refutation appendix is unread; the denial injects it |
| `rubric-gate` | Rejects near-duplicate probes that would satisfy the convergence rule without examining anything new |
| `verification-recorder` | Records which verification commands ran, and their real exit status |

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

Git-ignore it. **Every gate fails open** when the file is absent, malformed, or `active` isn't
`true`. A gate that breaks ordinary editing is a gate someone disables, and a disabled gate is worse
than no gate, because the report still claims the guarantee. Gates append to `gate-log.tsv` when
they fire, so a report can state what was actually enforced instead of assuming.

**Delete the state file when a review ends.** Leaving `active: true` with a narrow allowlist will
block unrelated work in your next session.

## Tests

```bash
bash hooks/test-gates.sh
```

23 tests covering fail-open behaviour, each gate's decisions, and that the appendix denial really
does carry the appendix. The fail-open cases matter most. Run them after touching any gate.

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
    └── test-gates.sh              # run after changing any gate
```

The engine sits outside `skills/` on purpose: it has no `SKILL.md` and no trigger of its own, and
the doors load it via `../../engine/`.

## Limitations

Every report the engine produces has to carry these, because none of them is solved:

- Proof of work proves **access, not comprehension.** A shallow read of every file passes.
- The reviewing agent is still sole writer, adjudicator and verifier. The write-path gate constrains
  where it writes, but bias in what it confirms or refutes is **narrowed, not closed.**
- Prompt injection against an unsandboxed reviewer is out of scope here. That belongs to the sandbox
  layer.

## Provenance

The design went through four rounds of adversarial review before anything was implemented. Round 2
produced seven fatal findings and forced a subtractive redesign. Rounds 3 and 4 closed with zero
fatal findings and declining counts, which is what "converged" meant here.

Three findings were declared **unfixable by design**, on the grounds that a self-administered
protocol can't guarantee anything against its own administrator. That conclusion is why the hooks
exist.

The spec and per-round materials stayed in the private repository this plugin was extracted from.
The load-bearing conclusions are restated in `engine/ENGINE.md` and in the limitations above, so
nothing you need in order to use the plugin depends on reading them.
