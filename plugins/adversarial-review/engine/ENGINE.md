# Adversarial review engine

Loaded by `review-code` and `review-design`. Not invoked directly.

Read [`invocation.md`](invocation.md) before the first reviewer call — it is the contract, and
the flags in it are not negotiable. The reviewer is Codex when it is available and a separate
Claude Opus process otherwise: `select-reviewer.sh` chooses, `run-reviewer.sh` runs every call.
[`../WORKFLOW.md`](../WORKFLOW.md) diagrams the process below.

## 1. Establish the loop shape

Mutation authority decides it, and **only an explicit grant counts**:

| | fix loop | verdict loop |
|---|---|---|
| when | the user explicitly authorised you to edit | **everything else — this is the default** |
| unit | the artefact | one finding |
| cap | 6 rounds | 5 rounds per substantive finding |
| ends with | work fixed, each fix carrying a named verification | a classified report |

Ownership is not authority. "Review my patch before I push" is owned work that authorises
review, not editing. Intent to act is not authority either — someone who says they will act
on findings may well mean they intend to make the edits themselves. **If in doubt, verdict
loop.** State which you chose and why.

**Snapshot the working tree when the review begins.** Straight after writing `state.json`,
run `bash engine/check-changes.sh start <repo-root>`. Before the report, and after each fix in
the fix loop, run `bash engine/check-changes.sh check <repo-root>`. It lists every path changed
since the snapshot, however it was changed, and flags any outside the allowed paths: none in
a verdict loop, the allowlist in a fix loop. The write gate stops the file tools early; this
check is what catches a change made any other way, such as through Bash.

## 2. Load the rubrics

Inspect the artefact and load **every** rubric that applies — not the one the front door
implies. An API spec containing pseudocode is both a document and an architecture; reviewing
it under one rubric because of which door fired gives the same artefact a different review.

- [`rubric-code.md`](rubric-code.md) — diffs, PRs, commits, source files
- [`rubric-architecture.md`](rubric-architecture.md) — designs, RFCs, system proposals
- [`rubric-document.md`](rubric-document.md) — specs, plans, requirements

Each supplies a probe list with stable ids, a definition of "confirmed", and a required read
scope. Nothing else. Probe ids come from the checked-in rubric — **never author probes per
run**.

## 3. Scope gate

Do not run for routine edits, copy changes, mechanical refactors, or work a green suite
already covers. The loop is expensive; spending it on simple work teaches everyone to ignore
it.

Record the answers to these rather than asking yourself "is this routine?" — discretionary
exclusion is the first thing reached for under release pressure, and it skips review exactly
when a green suite is providing false reassurance:

- Does it touch auth, crypto, payments, permissions, sessions or tokens?
- Does it change an exported signature or a serialised format?
- Does it touch a byte-exact golden or a parity capture?
- Is it numerics, concurrency, or geometry?
- Would a defect here be silent rather than loud?

Any yes → run. All no → say so and stop.

## 4. Each round

**Brief.** The reviewer has no memory between calls. State what the work claims, what would falsify
it, and which files to read — by absolute path, never pasted contents. Name what you are least
sure of; a vague brief returns vague findings. Full artefact on round 1 and on any
candidate-final round; changed sections plus affected invariants in between.

**Blind first.** Run the reviewer with no prior verdicts and no ledger. It must form findings
independently.

**Adjudicate, with evidence.** For each finding: **confirmed** (reproduce it — a failing test
is strongest), **refuted** (say why, from the source, in one or two sentences), or **out of
scope** (real but separate — record where it went). The reviewer is confidently wrong
sometimes.
Never accept a finding because it sounds authoritative, never dismiss one because it is
inconvenient.

**Grade, from the scenario.** Every finding is either **substantive** or a **nit**. It is
substantive when its scenario ends in a wrong outcome: incorrect behaviour, a security or data
exposure, a broken contract, or two readers of a spec building different things. Everything
else is a nit: naming, wording, formatting, style, or a preference with no failure scenario.
Severity does not decide it. A `low` finding with a wrong outcome is substantive, and a
`medium` style complaint is a nit.

**Only substantive findings earn another round.** Never start a round, a challenge or a
re-check because of a nit. Nits are fixed in passing or not at all: in the fix loop, fix a nit
only when it sits in code you are already changing for a substantive finding, and let that
fix's verification cover it. Every other nit goes in the report, unfixed. In the verdict loop,
report nits as found, with no challenge.

**Challenge second.** Put every substantive finding you intend to refute back to the reviewer —
full evidence for those findings, ids only for the rest — and require **DEFEND / RETRACT /
REVISE**. You may never convert a disagreement to "refuted" alone; unresolved disagreement
reaches the user as unresolved.

**If the reviewer returns nothing, reverse the roles.** A result of only nits is not empty: it closes
the loop (§5). An empty result is not evidence the artefact is sound — it is one reviewer
failing to find something. Generate 2–3 concerns of your own from the rubric probes, put each
to the reviewer, and require **DEFEND / CONCEDE / PARTIAL**. In this direction the semantics flip: a
convincing DEFEND dismisses your concern, a CONCEDE confirms a real finding, a PARTIAL means
keep going on the remaining gap. Only after that may you report "both reviewers agree: nothing
significant found".

**Fix, if authorised.** Each confirmed substantive finding gets a fix and a **named
verification**: an executable test for code, a rehearsal or simulation for architecture, a
recorded manual check where neither is possible. A manual check needs steps, observed result,
evidence pointer, who, and an expiry — "manually inspected, looks fine" is not a verification
and is recorded as **unverified**.

Before claiming any fix: review your own `git diff`, include the diff stat in the output, and
capture the actual command output of each verification. This is auditable, not enforced —
you are sole writer, adjudicator and verifier, so say "reduced, not eliminated" rather than
implying a guarantee.

## 5. Convergence

**A round whose findings are all nits closes the loop**, provided it re-ran every probe whose
substantive findings were fixed since that probe last ran. Stop there: no further round runs,
and its nits go in the report unfixed. A nits-only round that skipped one of those probes has
not checked the fixes, so the next round re-runs them, and it is the last unless it confirms
something substantive.

**Converged** means a round that meets every condition below returned no findings, and role
reversal then left none of your own concerns conceded. Stop there.

An empty round is not convergence on its own — a reviewer can fixate on a known defect and
return nothing new while independent defects remain. A round can decide convergence only if
it:

- uses **at least one probe id unused in the immediately preceding round**. *Exception:* if
  that round already used every id in the rubric, a full-artefact candidate-final pass counts
  without one; **and**
- **re-runs every probe whose substantive findings were fixed** since it last ran; **and**
- covers the full artefact, if it is candidate-final.

**Candidate-final, not final.** Finality is only knowable after the result. Any round you
intend to be convergence-deciding is *candidate-final* and gets the full artefact; if it finds
something it was not final, and the next one gets the full artefact again.

Finding identity is **yours to assign** — `file:line-span:category` canonicalised from
evidence, never the reviewer's own ids, which are unstable across rounds and not one-to-one with
defects. Ambiguous identity resolves toward **new**: fail toward more review.

**Stop and escalate on oscillation** — a fix in round N challenged in N+1 whose remedy reopens
N's issue. That is a design problem the loop cannot resolve. Do not burn the remaining rounds.

**Stop to fix first, when more rounds would only rework a larger issue.** Stop before
convergence when either holds:

- most of the latest round's findings re-report confirmed findings that are still unfixed, so
  another blind round against the same artefact would mostly repeat itself; or
- the confirmed findings share one cause, and fixing or re-reviewing them one at a time would
  only make small adjustments around it.

This stop hands the work back for a fix. It is never a way past a real issue, so it is allowed
only when:

- every finding raised so far is adjudicated and in the report. Nothing is skipped, downgraded
  to a nit, or left unchallenged to make the stop possible;
- the report gives the stop reason as **fix first**, says plainly that the review did not
  converge, and names the larger issue or the unfixed findings that the next round would have
  repeated;
- the next step is fixing them, then a fresh review. A fix-first stop is never sign-off.

In the fix loop, decide this before fixing, straight after the challenge: if the round's
confirmed findings share one cause, stop instead of applying a point fix to each.

## 6. Output

- Rounds run, and why it stopped: converged / nits only / fix first / cap / thrash-escalated / budget.
- The scope check: the last `check-changes.sh check` output, and every out-of-scope change
  it listed with how it happened.
- Which reviewer ran each round, as its `REVIEWER:` label gives it. If it fell back from one
  provider to another, say in which round and quote the error from the `FALLBACK:` line.
- Per substantive finding: confirmed with its reproduction; refuted with reason and falsifier;
  unresolved; or deferred with a destination. **Nothing is dropped silently** — the reasoning
  that killed a finding is the most reusable output of a review.
- Nits in one list, each marked fixed in passing, not fixed, or refuted with a one-line reason.
- Unverified assumptions with named owners. If any is load-bearing the verdict is
  **CONDITIONAL**: name the owner, name the observation that would clear it, and state that
  the review is not sign-off while it stands.
- Proof-of-work summary: citations verified, probes echoed, trace depth, reviewed path.
- Scope actually covered, including truncation counts and the ordering key used.
- Claims that survived unchallenged — **with their evidence basis**, labelled where unverified.
  Absence of a successful challenge is not proof.
- A **refutation-and-falsifier appendix** for the next reviewer.
- The standing limitations, stated plainly rather than implied away — see below.

## Limitations to state in every report

Do not imply rigour that is not present:

- Proof of work proves **access, not comprehension**.
- If any round used the Claude reviewer, that round was reviewed by the **same model family**
  that adjudicated it. It ran blind and passed proof of work, but it shares your blind spots;
  agreement between the two is weaker evidence than agreement with Codex.
- You are sole writer, adjudicator and verifier. Bias is **narrowed, not closed** — the same
  party writes both briefs, performs the fixes, and interprets the verification.
- The refutation appendix is a **convention, not a mechanism** unless the plugin's
  `appendix-gate` hook is active. Without it, nothing compels a later session to read the
  appendix; say which gates were actually enforcing rather than assuming they were.
- Prompt injection against a reviewer running without a sandbox is **out of scope here**. It
  belongs to whoever administers the execution environment, because any mitigation written
  into these instructions would be an assumption about model behaviour — the same class of
  control being questioned.
