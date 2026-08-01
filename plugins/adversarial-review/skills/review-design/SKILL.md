---
name: review-design
description: >
  Adversarially review an idea, architecture, design decision, spec or plan, using OpenAI
  Codex as a second, hostile reviewer. Trigger when the user asks to critique, evaluate,
  sanity-check, stress-test or debate any concept, design doc, RFC, proposal, specification,
  plan or requirements — even without mentioning Codex or "adversarial". Also applies to "is
  this a good idea?", "what are the risks of this approach?", "poke holes in this", "review
  this design", "review this spec", "what could go wrong?".
argument-hint: "<concept and/or file paths> [focus area]"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# Adversarial design and specification review

A front door. All mechanics live in the engine — read
[`../../engine/ENGINE.md`](../../engine/ENGINE.md) and follow it.

## Resolve the target

The user may give file paths, inline prose describing the idea, or both. Note the paths; you
will point codex at them by absolute path, never by pasting their contents.

If nothing was provided: `No concept provided. Pass a description, file paths, or both.`

If the concept is inline only, with no file to cite, say so in the output — findings cannot
carry verbatim citations against prose that exists only in the prompt, so the proof-of-work
citation check does not apply and the review is weaker for it. Prefer writing the concept to
a file first.

## Then

1. Load the engine, then **both** `rubric-architecture.md` and `rubric-document.md` unless
   the artefact is plainly only one. Most specs are both, and loading one because of which
   door fired gives the same artefact a different review.
2. Follow the engine: loop shape, scope gate, rounds, convergence, output.
3. Default to the **verdict loop**. Enter the fix loop only on an explicit grant to edit.

## Watch for

- **Right measurement, wrong quantity.** Both sides agreeing on a number that does not decide
  anything. Ask what observation would change the decision, then measure that.
- **Agreement by exhaustion.** Later rounds going quiet because the brief narrowed. The
  candidate-final round takes the whole artefact for exactly this reason.
- **A design's account of current behaviour** is the most commonly wrong part of it. Read the
  behaviour, do not trust the description.
