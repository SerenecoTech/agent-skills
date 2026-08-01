# Rubric: architecture

Applies to designs, RFCs, system proposals, and any document that asserts how parts fit
together. Frequently loads alongside `rubric-document.md` — most specs are both.

## Confirmed means

A **concrete scenario that violates a stated invariant** — specific inputs or state, the
sequence, and the wrong outcome — or a **cost/benefit that does not close** when the numbers
are worked through. "This seems complex" is not a finding.

## Probes

| id | probe |
|---|---|
| `A-BOUND` | Module boundaries: does responsibility land in one place, or is the same decision made twice? |
| `A-FLOW` | Data flow: where does state live, who may write it, and what reads stale copies? |
| `A-FAIL` | Failure modes: what happens on partial failure, timeout, retry, duplicate delivery? |
| `A-ROLLBACK` | Migration and rollback: can this be reversed, at what cost, and has the reverse path been walked? |
| `A-ASSUME` | Unstated assumptions the design depends on but never names |
| `A-SCALE` | Behaviour at 10×: what breaks first, and is that acceptable or silent? |
| `A-CONTRACT` | External contracts: which invariants depend on something outside this repository? |
| `A-COST` | Does the claimed benefit actually exceed the cost, with the numbers written down? |

## Required read scope

The design document, everything it references by path, and the code implementing any
invariant it asserts. Where the design claims current behaviour, **read the current
behaviour** — a design's description of the system it is changing is the most commonly wrong
part of it.

## External contracts and CONDITIONAL

Every invariant must name the external contract it depends on. Where that contract cannot be
verified from the repository — a production admission controller, a vendor durability
guarantee, a third-party rate limit — record it as an **unverified assumption with a named
owner**, and the review's verdict becomes **CONDITIONAL**.

CONDITIONAL must do work, not label. It requires:

- a **named owner** — a person or team, not "the team";
- **the specific observation that would clear it** — what to measure, not "confirm with
  vendor";
- an explicit statement that **the review is not sign-off** while any load-bearing assumption
  stands.

Deadlines and approval authority are beyond a review's power. Refusing to report CONDITIONAL
as a clean pass is not. The failure this prevents is real: a review's inability to run a check
quietly becoming permission for the engineering process not to require it.
