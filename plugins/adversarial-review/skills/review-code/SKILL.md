---
name: review-code
description: >
  Adversarially review code changes for bugs, security issues and correctness, using a second,
  hostile reviewer: OpenAI Codex when it is available, otherwise a separate Claude Opus
  process. Trigger when the user asks for a code review, wants
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
| a PR number or GitHub URL | the PR's changes, once the local code is confirmed to be the PR (below) |
| file paths that exist | those files |

If a token resolves to none of these, say so rather than guessing:
`Could not resolve '<token>': not a file, directory, branch, commit SHA, or PR number.`

**A PR target must be the code checked out here.** Otherwise the review describes whatever
branch happens to be checked out while the report names the PR.

1. Run `gh pr view <n> --json headRefOid,headRefName,baseRefName`.
2. Compare `headRefOid` with `git rev-parse HEAD`. If they differ, stop:
   `Local HEAD <sha> is not PR <n>'s head <headRefOid>. Run 'gh pr checkout <n>' and pull, then
   ask again.` Do not check it out yourself: switching branches is the user's call.
3. If `git status --porcelain -- . ':(exclude).claude/adversarial-review'` shows uncommitted
   changes, stop and say so. They are not part of the PR, and the review would include them.
   The review's own bookkeeping folder is not part of the code, so it is left out.
4. Review exactly the change `gh pr diff <n>` shows: GitHub computes it against the PR's real
   base, so a stale local `origin/<baseRefName>` cannot add or hide commits. Name the PR, its
   head SHA and its base in the brief, and tell the reviewer to run `gh pr diff <n>` for the
   change and read the files in the checkout for context.
5. **Before every later round, repeat step 1 and 2.** If someone pushed to the PR meanwhile,
   `gh pr diff` now shows a change the checkout does not hold. Stop, tell the user the head
   moved from the reviewed SHA to the new one, and let them choose: check out the new head and
   restart, or finish on the reviewed SHA.

For uncommitted targets, check `git status` first — if there is nothing, say so and stop.

**Name the target in the brief.** The engine requires a per-round brief, and the reviewer runs
`git status` and `git diff` itself, so describe the target there — including that untracked
files are in scope. `invocation.md` has how the call is made.

## Then

1. Load the engine and `rubric-code.md`. Load **other rubrics too** if the change includes
   design or specification content — the door does not decide the evidence bar.
2. Follow the engine: loop shape, scope gate, rounds, convergence, output.
3. Default to the **verdict loop**. Only enter the fix loop if the user explicitly authorised
   you to edit — "review my changes" does not.

## Do not

- Paste diffs or file contents into the brief. The reviewer reads the files itself; give it
  paths and a target description.
- Substitute your own review when the reviewer is slow. That is what the user already had.
- Call `codex` or `claude -p` directly. Use `run-reviewer.sh`, which runs the provider
  `select-reviewer.sh` chooses, with flags that keep a Claude call out of the session list.
