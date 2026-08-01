# adversarial-review

Adversarial code, architecture and specification review using OpenAI Codex as a second,
hostile reviewer. Two front doors over one shared engine, plus hooks that enforce the parts a
skill cannot enforce on itself.

Codex finds; Claude adjudicates and fixes. Codex never writes to the repository.

## Requirements

| Dependency | Required | Used for |
|---|---|---|
| `codex` (codex-cli ≥ 0.146.0) | yes | the reviewer itself, including `codex exec review` and `--output-schema` |
| `jq` (≥ 1.6) | yes | every hook reads its event and emits its decision as JSON; the verifier parses findings and traces |
| `bash` (≥ 4) | yes | all hooks and the verifier |
| `git` | yes | target resolution, diffs, and the importer-ordering recency key |
| coreutils / POSIX text tools | yes | `sed`, `awk`, `grep`, `tr`, `wc`, `head`, `cut`, `sort`, `mktemp`, `date`, `basename` |
| `shuf` | yes | selecting unpredictable echo-probe lines |
| `gh` | optional | only for PR-number targets in `review-code` |

Codex must be authenticated. Note that model choice is constrained by account type — a
review must not depend on `-m` selecting a specific model unless it has been confirmed
available.

**Sandbox mode is environment-specific.** `engine/invocation.md` mandates
`-s danger-full-access` because that is the only mode that functions where this was built:
every other mode fails at bwrap because the container cannot create user namespaces. Verify
this for your environment before trusting it — in a container that permits userns, a
restrictive mode is both available and preferable.

## Layout

```
adversarial-review/
├── .claude-plugin/plugin.json
├── engine/                        # shared reference, deliberately not a skill
│   ├── ENGINE.md                  # loop shape, scope gate, rounds, convergence, output
│   ├── invocation.md              # the codex contract — flags, proof of work, budget
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

The engine sits outside `skills/` deliberately: it has no `SKILL.md` and no trigger of its
own, and the doors load it via `../../engine/`.

## The two doors

Both load the engine and follow it. The door resolves the target and nothing else — in
particular **it does not set the evidence bar.** The engine inspects the artefact and loads
every rubric that applies, so an API specification containing pseudocode gets the same review
whichever door fired.

| Door | Triggers on |
|---|---|
| `review-code` | PRs, branches, commits, diffs, working tree, "check my changes" |
| `review-design` | architecture, RFCs, proposals, specs, plans, "poke holes in this" |

## Why the hooks exist

A self-administered protocol cannot make guarantees against its administrator. Instructions
cannot compel a later session to read a prior refutation; the agent that writes a fix is also
the one choosing the verification command and interpreting its output; a rubric can be padded
by whoever authors it. Each extra rule in a skill is another instruction the same party both
writes and follows.

A hook is different: it is configured outside the model's control and can refuse a call
regardless of intent. That is why this ships as a plugin rather than as skills alone — the
gate arrives with the instructions instead of depending on someone wiring it up.

| Gate | Enforces |
|---|---|
| `write-path-gate` | No write outside the declared allowlist, and **no write at all** during a verdict review |
| `appendix-gate` | Codex cannot start while a prior refutation appendix is unread — the denial injects it |
| `rubric-gate` | Rejects near-duplicate probes that would satisfy the convergence rule without examining anything new |
| `verification-recorder` | Records which verification commands ran and their real exit status |

## Runtime state

Gates read `.claude/adversarial-review/state.json` in the project, which the skill writes:

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

Git-ignore it. **Every gate fails open** when the file is absent, malformed, or `active` is
not `true`: a gate that breaks ordinary editing gets disabled, and a disabled gate is worse
than none because the report still claims the guarantee. Gates append to `gate-log.tsv` when
they fire, so a report can state what was actually enforced rather than assuming.

**Delete the state file when a review ends.** Leaving `active: true` with a narrow allowlist
blocks unrelated work in the following session.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@serenecotech
```

Skills are usable immediately. **Hooks load at session start**, so restart before expecting
the gates to enforce anything. After installing, check `claude plugin list` shows
`Status: ✔ enabled` — a hook loading failure is reported there, not by
`claude plugin validate`.

## Testing

```bash
bash hooks/test-gates.sh
```

Covers fail-open behaviour, each gate's decisions, and that the appendix denial actually
carries the appendix. The fail-open cases matter most; run them after touching any gate.

## Limits it states rather than hides

Every report the engine produces must carry these, because none of them is solved:

- Proof of work proves **access, not comprehension** — a shallow read of every file passes.
- The reviewing agent is sole writer, adjudicator and verifier. The write-path gate constrains
  where it writes; bias in what it confirms or refutes is **narrowed, not closed.**
- Prompt injection against an unsandboxed reviewer is out of scope here and belongs to the
  sandbox layer.

## Provenance

The design was itself put through four rounds of adversarial review before implementation.
Round 2 produced seven fatal findings and forced a subtractive redesign; rounds 3 and 4 closed
with zero fatal findings and declining counts, which is what "converged" meant here. Three
findings were declared **unfixable by design** — a self-administered protocol cannot guarantee
anything against its own administrator — and that conclusion is why the hooks exist.

The spec and per-round materials live in the private repository this plugin was extracted
from and are not published here. The load-bearing conclusions are restated in
`engine/ENGINE.md` and in the limits above, so nothing needed to read the plugin depends on
them.
