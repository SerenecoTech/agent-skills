# How a review runs

Four views of the same process, from the outside in. The rules behind each step are in
[`engine/ENGINE.md`](engine/ENGINE.md) (the review loop) and
[`engine/invocation.md`](engine/invocation.md) (the reviewer call). These diagrams describe
those files; where the two disagree, the engine files win.

Three roles appear throughout:

- **The adjudicator** is the Claude session the user is talking to. It writes the briefs,
  judges every finding, makes any fixes, and writes the report.
- **The reviewer** is a separate process that reads the work blind and returns findings. It
  is a **provider**: Codex first, a separate Claude process as the fallback.
- **The gates** are hooks. They run outside the adjudicator's control and can refuse a call.

## 1. The review, end to end

```mermaid
flowchart TD
    A["User: 'review my changes' or 'poke holes in this spec'"] --> B{"Which door?"}
    B -->|code, PR, branch, diff| C["review-code"]
    B -->|design, RFC, spec, plan| D["review-design"]
    C --> E["Resolve the target"]
    D --> E
    E --> F["Load every rubric that applies"]
    F --> G{"Scope gate: auth, exported signature, golden file,<br/>numerics or concurrency, or a silent failure mode?"}
    G -->|all no| H["Say so and stop"]
    G -->|any yes| I{"Did the user explicitly allow edits?"}
    I -->|no, the default| J["Verdict loop: report only,<br/>up to 5 rounds per substantive finding"]
    I -->|yes| K["Fix loop: fix and verify,<br/>up to 6 rounds"]
    J --> L["Write state.json: the gates turn on.<br/>check-changes.sh start: snapshot the tree"]
    K --> L
    L --> M["Rounds, see diagram 2"]
    M --> SC["check-changes.sh check: list every change<br/>since the snapshot, flag any out of scope"]
    SC --> N["Report"]
    N --> O["Delete state.json: the gates turn off"]
```

The report states how many rounds ran and why they stopped (converged, nits only, fix first,
cap, thrash-escalated or budget), which reviewer ran each round
and any fallback, every substantive finding with its outcome, the nits, unverified
assumptions, proof-of-work results, and the standing limitations.

## 2. One round

```mermaid
flowchart TD
    A["Write the brief: claim, falsifier,<br/>files by absolute path"] --> B["run-reviewer.sh auto, see diagram 3"]
    B --> C["Proof of work: reviewed path, echo probe,<br/>citations, trace audit"]
    C -->|fails| Q["Quarantine: the user accepts or rejects"]
    C -->|passes| D{"What came back?"}
    Q -->|accepted| D
    D -->|no findings at all| R["Reverse roles: put 2-3 of your own<br/>concerns to the reviewer"]
    R -->|a concern conceded<br/>or partly conceded| E
    R -->|every concern defended| X
    D -->|only nits, and every fixed<br/>probe was re-run| N["Loop closed: report the nits, stop"]
    D -->|only nits, but a fixed<br/>probe was skipped| A
    D -->|substantive findings| E["Adjudicate each: confirmed with a reproduction,<br/>refuted with a reason, or out of scope"]
    E --> F["Challenge every refutation:<br/>DEFEND, RETRACT or REVISE"]
    F --> G{"Fix loop?"}
    G -->|yes, but the findings<br/>share one cause| U
    G -->|yes| H["Fix each confirmed finding,<br/>with a named verification"]
    G -->|no| X
    H --> X{"Converged? An empty round that used a new probe id,<br/>re-ran fixed probes and covered the full artefact,<br/>and role reversal conceded nothing"}
    X -->|yes| S["Stop"]
    X -->|no, under the cap| A
    X -->|cap reached, or a fix reopened<br/>an earlier issue| T["Stop and escalate"]
    X -->|next round would mostly repeat unfixed<br/>findings, or they share one cause| U["Stop: fix first.<br/>Not converged, not sign-off"]
```

**Substantive or nit** is decided from the finding's scenario, not its severity. A finding is
substantive when the scenario ends in a wrong outcome: a bug, an exposure, a broken contract,
or two readers of a spec building different things. Everything else is a nit. Nits never
start a round. In the fix loop a nit is fixed only when it sits in code already being changed
for a substantive finding.

**Fix first** stops a review that has found a larger issue, rather than spending rounds on
small adjustments around it. It is not a way past a real issue: every finding must already be
adjudicated and reported, and the report must say the review did not converge. The next step
is a fix, then a fresh review.

## 3. Choosing and running the reviewer

Selection and execution are separate, so a new provider is one directory and one line in
`PRIORITY`. See [`engine/providers/README.md`](engine/providers/README.md).

```mermaid
flowchart TD
    subgraph SEL["select-reviewer.sh: selection"]
        P["Order from ADVERSARIAL_REVIEW_PROVIDERS,<br/>else providers/PRIORITY"] --> Q["For each provider:<br/>provider_available"]
        Q --> R["List the ones that can run, best first"]
    end
    subgraph RUN["run-reviewer.sh: execution"]
        S["Take the next provider on the list"] --> T["provider_run: the CLI call,<br/>inside with_timeout"]
        T --> U{"Exit 0 and out.json<br/>matches the schema?"}
        U -->|yes| V["Print REVIEWER: label<br/>Log ok"]
        U -->|no| W{"Another provider<br/>on the list?"}
        W -->|yes| B2{"Calls left under<br/>--max-calls?"}
        B2 -->|yes| Y["Print FALLBACK: error<br/>Log it"]
        Y --> S
        B2 -->|no| Z2["Exit 5: budget used.<br/>Report it"]
        W -->|no| Z["Exit 4: every provider failed.<br/>Surface the errors, ask about a retry"]
    end
    R --> S
    subgraph PROV["providers/name/provider.sh"]
        C1["codex: codex exec --ephemeral,<br/>schema enforced, JSON trace, no saved session"]
        C2["claude: claude -p on Opus, read-only,<br/>no saved session, schema enforced"]
    end
    T -.-> PROV
```

After a fallback the adjudicator passes the provider that succeeded for the remaining
rounds, so one reviewer covers the rest of the review, and records the switch in the report.

## 4. Where the gates fire

```mermaid
sequenceDiagram
    participant A as Adjudicator
    participant G as Gates (hooks)
    participant W as run-reviewer.sh
    participant R as Reviewer CLI

    A->>G: Bash: run-reviewer.sh
    Note over G: appendix-gate: a prior refutation appendix must be read first<br/>rubric-gate: no near-duplicate probe ids
    G-->>A: deny, with the reason
    G->>W: allow
    W->>R: brief on stdin
    R-->>W: out.json and trace.jsonl
    W-->>A: REVIEWER or FALLBACK, and the files
    A->>A: verify-proof-of-work.sh
    A->>G: Edit or Write
    Note over G: write-path-gate: no write to the repository in a verdict loop,<br/>only allowlisted paths in a fix loop, paths resolved first
    A->>G: Bash: a test or lint command
    Note over G: verification-recorder logs the real exit status
```

The gates keep a review on its scope; they guide rather than police. The Bash gates recognise
one form of reviewer call, `run-reviewer.sh`, which the skill sends every call through; a
reviewer CLI called directly, against the skill, is not detected. Keeping Claude reviewer
calls out of the session list is likewise done by the wrapper, which always passes
`--no-session-persistence`, not by a gate. Writes made through Bash are not predicted:
`check-changes.sh` catches them afterwards by comparing the working tree with the snapshot
taken when the review began.

The gates find `state.json` in the session's directory or the nearest directory above it, so
changing into a subdirectory mid-review does not switch them off.

Every gate **fails open**: with no `state.json`, or `active` not `true`, it allows the call.
A gate that blocks ordinary work gets disabled, and a disabled gate is worse than none.

## Files a review leaves

All under `.claude/adversarial-review/` in the repository:

| File | Written by | Holds |
|---|---|---|
| `state.json` | the adjudicator | whether a review is active, the loop, the write allowlist, the appendix path |
| `gate-log.tsv` | the gates | every time a gate fired, and what it decided |
| `reviewer-log.tsv` | `run-reviewer.sh` | every reviewer call, which provider ran, and every fallback |
| `verifications.jsonl` | `verification-recorder` | each verification command and its real exit status |
| `baseline-tree` | `check-changes.sh start` | the git tree of the working tree when the review began |
