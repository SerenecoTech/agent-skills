# agent-skills

Agent plugins, skills and hooks. Built for real work rather than as demonstrations, which mostly
shows up in what they refuse to do: the review plugin will not let an agent mark its own homework,
the guards deny rather than advise, and every component states the guarantee it *cannot* make.

Packaged in Claude Code's plugin format because that is what carries hooks. The skills themselves
are plain Markdown and portable to any agent that reads skills from a directory — see
[Portability](#portability).

## Plugins

| Plugin | What it does | Ships |
|---|---|---|
| **[adversarial-review](plugins/adversarial-review/)** | Code, architecture and spec review with OpenAI Codex as a second, hostile reviewer. Codex finds; the agent adjudicates and fixes; Codex never writes to your repo. Four `PreToolUse` gates enforce what a skill cannot enforce on itself. | 2 skills, 4 hooks, 23 tests |
| **[handoff](plugins/handoff/)** | Session continuity. Write a `HANDOFF.md` that captures the goal, what's done, decisions with rationale and — most valuably — failed approaches; then resume from it with a drift check, so nobody explains the task twice. | 2 skills |
| **[guard-hooks](plugins/guard-hooks/)** | Security guardrails as hooks, not instructions. Denies dangerous shell commands, writes to credential files and system paths, and secrets in file content. Pre-approves provably-safe deletes, enforces the project's package manager, warns on destructive git. | 5 hooks, 266 tests |

## Install

Add the marketplace once, then install whichever plugins you want:

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
claude plugin install handoff@sereneco
claude plugin install guard-hooks@sereneco
```

Or browse interactively with `/plugin` inside Claude Code.

The two spellings are not a typo: `serenecotech` is the GitHub organisation, and the marketplace
registers itself as `sereneco`.

**Skills work immediately. Hooks load at session start** — so `adversarial-review` and
`guard-hooks` need a restart before they enforce anything. After restarting, confirm
`claude plugin list` shows `Status: ✔ enabled`: a hook that fails to load is reported there and
**not** by `claude plugin validate`.

### Requirements

| Plugin | Needs |
|---|---|
| adversarial-review | `codex` ≥ 0.146.0 (authenticated), `jq` ≥ 1.6, `bash` ≥ 4, `git`, coreutils, `shuf`; `gh` optional for PR targets |
| handoff | `git`. Optional: a file-based agent memory, `memsearch` |
| guard-hooks | `jq` ≥ 1.6, `bash` ≥ 4, coreutils |

Everything is bash and Markdown. There is no build step and no runtime to install.

## Design commitments

These are the rules the contents follow, and the reason they look the way they do.

**A rule in a prompt is a request; a hook is a refusal.** Anything an agent could plausibly
rationalise its way past — writing outside an authorised path, skipping a refutation it would
rather not read, padding a rubric to satisfy a convergence check — belongs in a hook, because a
hook is configured outside the model's control. This is the whole reason `adversarial-review`
ships as a plugin instead of as skills alone.

**Choose the failure direction deliberately, and say which you chose.** Security guards fail
*closed*: a broken guard denies. Convention checks and review gates fail *open*: a check that
blocks ordinary work when it breaks gets switched off, and a switched-off gate is worse than none,
because the report still claims the guarantee. Each hook documents its own direction.

**State the limits in the artifact, not just the README.** `adversarial-review` requires every
report it produces to carry its own caveats — proof of work proves access, not comprehension; the
reviewing agent is still sole writer, adjudicator and verifier. A limitation that only appears in
documentation nobody re-reads is not disclosed.

**Tests must be able to fail.** Two guard suites shipped here originally exited zero regardless of
result, which made their green meaningless. They now exit non-zero, and that was verified by
injecting a deliberate failure and confirming the runner caught it.

## Portability

The repository is deliberately not Claude-specific, though the packaging currently is:

- **`plugins/`** — Claude Code plugin format. Required for hooks, since `hooks.json` and
  `${CLAUDE_PLUGIN_ROOT}` are Claude Code contracts.
- **`skills/`** — standalone skills with no harness dependency, for tools that read skills from a
  directory rather than installing plugins.

Skills inside plugins are ordinary `SKILL.md` files with YAML frontmatter. Nothing stops you
symlinking one into another agent's skills directory; `handoff` and `handoff-resume` in particular
have no scripts, no hooks and no harness-specific tool calls.

## Contributing

Issues are open — bug reports, false positives from the guards, and portability reports from other
agent harnesses are all useful. A false positive in `guard-hooks` is a real bug: a guard that
blocks legitimate work gets disabled, which defeats it entirely.

For pull requests:

1. Run the relevant tests and include the output. `bash plugins/guard-hooks/tests/run-all.sh` and
   `bash plugins/adversarial-review/hooks/test-gates.sh`.
2. Add a test with any behaviour change. For a guard, add both the case that should be caught and
   the near-miss that should not.
3. Keep fail-open and fail-closed decisions explicit, and update the hook's table if you change one.
4. Don't add a rule to a skill that a hook should enforce, or a hook for something a skill states
   perfectly well.

## Licence

MIT. See [LICENSE](LICENSE).
