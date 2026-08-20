---
name: review-code
description: >
  Adversarially review code changes for bugs, security issues and correctness, using OpenAI
  Codex as a second, hostile reviewer. Trigger when the user asks for a code review, wants
  code checked for bugs or security issues, asks to review a PR, branch, commit, diff or
  working tree, or says things like "any issues with this?", "review before I push", "check
  my changes", "look at what I changed", or "review my PR". Tell it where the code is.
argument-hint: "[target] [focus area]  — target: PR number, branch, commit SHA, paths, or nothing for uncommitted"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

# Adversarial code review

A front door. All mechanics live in the engine — read
[`../../engine/ENGINE.md`](../../engine/ENGINE.md) and follow it.

## Resolve the target

Interpret the argument naturally, then hand the engine a target:

| Argument looks like | Target |
|---|---|
| nothing | uncommitted changes, untracked files included |
| a branch name (`git rev-parse` resolves it) | changes against that base |
| a commit SHA | the changes that commit introduced |
| a PR number or GitHub URL | verify with `gh pr view <n> --json number`, then review the checked-out branch |
| file paths that exist | those files |

If a token resolves to none of these, say so rather than guessing:
`Could not resolve '<token>': not a file, directory, branch, commit SHA, or PR number.`

For uncommitted targets, check `git status` first — if there is nothing, say so and stop.

**Name the target in the brief, not in a flag.** `codex exec review` refuses a target flag and
a prompt together, and the engine requires a per-round brief, so the target has to be described
in the brief itself — including that untracked files are in scope. `invocation.md` has the
measured command lines.

## Then

1. Load the engine and `rubric-code.md`. Load **other rubrics too** if the change includes
   design or specification content — the door does not decide the evidence bar.
2. Follow the engine: loop shape, scope gate, rounds, convergence, output.
3. Default to the **verdict loop**. Only enter the fix loop if the user explicitly authorised
   you to edit — "review my changes" does not.

## Do not

- Paste diffs or file contents into the codex prompt. Codex reads the files itself; give it
  paths and a target description.
- Substitute your own review when codex is slow. That is what the user already had.
