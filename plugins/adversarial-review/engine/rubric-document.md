# Rubric: document

Applies to specs, plans, requirements, and proposals — anything someone will build to.
Frequently loads alongside `rubric-architecture.md`.

## Confirmed means

One of:

- an **ambiguity two competent readers resolve differently** — state both readings, and show
  they lead to different implementations;
- an **untestable acceptance criterion** — nobody can say whether it was met;
- a **missing case** — an input, state, or actor the document never addresses.

"Could be clearer" is not a finding. The bar is that following the document as written
produces divergent or unverifiable work.

## Probes

| id | probe |
|---|---|
| `D-AMBIG` | Ambiguity: two readings, two implementations |
| `D-TEST` | Testability: is every acceptance criterion observable, and by what? |
| `D-MISSING` | Missing cases: unhandled inputs, states, actors, error paths, empty and boundary conditions |
| `D-CONTRA` | Internal contradiction: two statements that cannot both hold |
| `D-DECISION` | Conflict with the recorded decisions in `docs/roadmap/` (D1–D13) — a plan that quietly reverses one |
| `D-SCOPE` | Scope creep, and its inverse: work implied but never scoped |
| `D-OWNER` | Unowned work: a step with no actor, or a dependency with no owner |
| `D-NUMBERS` | Numbers asserted without derivation — thresholds, caps, budgets that nobody can check |

`D-NUMBERS` earns its place: an unexplained constant is where two implementers diverge
silently, and where a cap excludes exactly the case that mattered.

## Required read scope

The document, everything it references by path, and the decision record it must not
contradict (`docs/roadmap/`). Where the document describes existing behaviour, read that
behaviour rather than trusting the description.

## A note on this rubric's own bar

The temptation with documents is to produce many low-value findings, because prose always
admits improvement. Resist it. A round returning three real ambiguities is worth more than
one returning twenty style notes, and padding trains the reader to skim the report — which
costs more than the review gained.
