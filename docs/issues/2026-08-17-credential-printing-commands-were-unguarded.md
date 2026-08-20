---
id: agent-skills:ISSUE-002
status: resolved
---

# Commands whose stdout is a credential were unguarded

`guard-hooks` blocked reading a credential **file** (`bash-guard`'s `.aws/credentials`, `.ssh/id_`,
`.npmrc`, `.pypirc`, `.env` patterns) but nothing blocked a command whose **output** is a live
secret. `git credential fill`, a credential helper's own `get`, `gh auth token` and
`gh auth status --show-token` all passed every guard.

## How it was found

Not by review. An agent ran `git credential fill` against a stub helper to establish which fields a
credential helper receives from git. The stub returned nothing, so git fell through to the machine's
configured `osxkeychain` helper and printed a real GitHub OAuth token to stdout, into the
conversation transcript. The token carried `admin:org`, `admin:public_key`,
`admin:ssh_signing_key`, `repo` and `workflow`: organisation administration, and the ability to add
an SSH key that would survive the token's own revocation.

The command read as introspection. Nothing about it looked like credential access, which is exactly
why a pattern guard is the right place to catch it.

## Why stdout is the boundary that matters

An agent's stdout is conversation transcript. Transcripts are summarised into session memory, and in
some setups indexed by a project memory store that is mounted into containers. A secret printed there
cannot be deleted, only rotated.

## Resolution

`toolchain-guard.sh` section 6, with 34 assertions in `tests/test-toolchain-guard.sh`.

- **`git credential fill`** is denied unless the command resets the helper list first
  (`-c credential.helper=`). The reset is what makes inspecting one helper safe: without it, `fill`
  consults every configured helper and emits a real token even when the helper under test returns
  nothing.
- **A credential helper's `get`**, in both `git credential-<x> get` and `git-credential-<x> get`
  forms, is denied outright. There is no helper list to reset for a direct invocation, so there is no
  safe form.
- **`gh auth token`** and **`gh auth status --show-token`** are denied unless redirected to a file,
  which keeps the value out of stdout. A pipe is not an exemption: the receiving command's output is
  still transcript.
- **`git credential approve`** and **`reject`** stay allowed. They read stdin and print nothing.

## What the first implementation got wrong

The boundary character classes used only whitespace and shell operators, so `TOKEN=$(gh auth token)`
matched nothing and was allowed. A command substitution opens a command as much as a pipe does.
`$(`, a backtick and `)` are now boundary characters, and five assertions pin the substitution and
backtick forms specifically.

This is the same failure shape the guard exists to prevent: a rule that looks correct, passes its
tests, and does not fire on the form someone actually types.
