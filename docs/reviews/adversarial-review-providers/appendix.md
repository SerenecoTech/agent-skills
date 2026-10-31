# Refutation appendix: adversarial-review provider restructure

Review of the uncommitted provider-selection restructure of `plugins/adversarial-review`, 2026-10-30, verdict loop, Codex reviewer for every round. A refutation holds only while its falsifier holds. Re-check each one before treating it as settled.

## Git external helpers can write through the Claude reviewer's allowed `git diff`

Raised three times (round 1 `R1-git-helper-writes`, round 2 `R2-04`, round 3 `F06`). Codex **RETRACTED** it under challenge.

**Refuted because:** the Claude reviewer cannot introduce or change a helper. `git config`, environment changes and every command outside the allowlist are denied (`--restricted`, `--permission-mode dontAsk`, the allowlist in `engine/providers/claude/provider.sh`). The only helper that can run is one the user configured, through `GIT_EXTERNAL_DIFF` or `diff.external`, and already runs on every `git diff` they type. The reviewer gains no write capability the user has not given their own git.

**Falsifier:** a path by which the reviewer itself, or committed content in the reviewed repository, causes a helper to run that the user did not configure. For example, a committed `.gitattributes` diff or textconv driver that executes without a matching entry in the user's git config. If that is found, the Claude provider must disable external diff and textconv helpers, for example with `GIT_EXTERNAL_DIFF` unset and `--no-ext-diff --no-textconv` enforced.
