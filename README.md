# agent-skills

Three Claude Code plugins: hostile code review, session handoff, and security guard hooks.

Bash and Markdown throughout. Nothing to build, nothing to compile.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
claude plugin install handoff@sereneco
claude plugin install guard-hooks@sereneco
```

Or run `/plugin` in Claude Code and browse.

**Restart Claude Code afterwards.** Skills work immediately, but hooks load only at session start,
so `adversarial-review` and `guard-hooks` sit inert until you do. Then run `claude plugin list` and
check each says `Status: ✔ enabled`. A hook that failed to load shows up there, and nowhere else.

Both spellings are correct: `serenecotech` is the GitHub organisation, `sereneco` is the
marketplace.

## What each one does

**[adversarial-review](plugins/adversarial-review/)** — say "review my changes" or "poke holes in
this spec" and OpenAI Codex reviews it as a hostile second opinion. Codex finds problems, Claude
fixes them, and Codex never writes to your repository.

**[handoff](plugins/handoff/)** — say "handoff" before `/clear` and it writes `HANDOFF.md`. Say
"resume" in a fresh session and it picks the work back up without you re-explaining anything.

**[guard-hooks](plugins/guard-hooks/)** — blocks dangerous shell commands, credential leaks, and
merges that skip a failing check. Enforced outside the conversation, so an agent cannot talk its way
past them.

Each plugin has its own README.

## Requirements

| Plugin | Needs |
|---|---|
| adversarial-review | `codex` ≥ 0.146.0 (authenticated), `jq` ≥ 1.6, `bash` ≥ 4, `git`, `shuf`, coreutils. `gh` only for reviewing a PR by number. |
| handoff | `git`. |
| guard-hooks | `jq` ≥ 1.6, `bash` ≥ 4, `git`, coreutils. `gh` for the GitHub merge rules. |

## Layout

```text
.claude-plugin/marketplace.json    marketplace manifest
plugins/                           Claude Code plugins; hooks require this format
skills/                            standalone skills, no harness dependency
```

Skills inside the plugins are ordinary `SKILL.md` files with YAML frontmatter, so you can symlink
one into another agent's skills directory instead of installing the plugin. `handoff` and
`handoff-resume` port cleanly, having no scripts or hooks at all. The Claude Code-specific pieces
are `hooks.json` and `${CLAUDE_PLUGIN_ROOT}`.

## Two conventions

These explain most of the design.

**Enforcement goes in hooks, not in prose.** A rule written into a skill is advice, and an agent can
reason its way past advice. Rules that matter go into a hook, which is configured where the model
cannot reach it.

**Every hook states which way it fails.** Security guards fail closed: if the guard itself errors,
the call is denied. Convention checks and review gates fail open, because a check that blocks
ordinary work when it breaks is a check someone switches off. Each plugin's hook table says which
applies where.

## Contributing

Issues are open. Bug reports, false positives from the guards, and portability reports from other
agent harnesses are all welcome.

Treat a `guard-hooks` false positive as a real bug rather than a nuisance. A guard that blocks
legitimate work is a guard someone will switch off, and then it protects nothing.

For pull requests:

1. Run the tests and paste the output.

   ```bash
   bash plugins/guard-hooks/tests/run-all.sh
   bash plugins/adversarial-review/hooks/test-gates.sh
   ```

2. Add a test for any behaviour change. For a guard, cover both the case that should be caught and
   the near-miss that should not.
3. If you add a hook, say which way it fails and add it to the plugin's hook table.

## Licence

MIT. See [LICENSE](LICENSE).
