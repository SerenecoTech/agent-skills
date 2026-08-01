# agent-skills

Three plugins for Claude Code: adversarial code review, session handoff, and security guard hooks.

Bash and Markdown throughout. No build step, no runtime, nothing to compile.

## What's here

| Plugin | Use it to | Contents |
|---|---|---|
| **[adversarial-review](plugins/adversarial-review/)** | Review code, architecture or specs with OpenAI Codex as a hostile second reviewer. Codex finds problems, your agent fixes them, and Codex never writes to your repo. | 2 skills, 4 hooks, 23 tests |
| **[handoff](plugins/handoff/)** | Survive context limits. Write a `HANDOFF.md` before `/clear`, then resume from it in a fresh session without re-explaining the task. | 2 skills |
| **[guard-hooks](plugins/guard-hooks/)** | Block dangerous shell commands, writes to credential files, and secrets in file content. Enforced by hooks, so the agent can't talk its way past them. | 5 hooks, 266 tests |

Each plugin has its own README with the detail.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
claude plugin install handoff@sereneco
claude plugin install guard-hooks@sereneco
```

Or run `/plugin` in Claude Code and browse.

Both spellings are correct: `serenecotech` is the GitHub organisation, `sereneco` is the marketplace.

**Restart Claude Code after installing anything with hooks.** Skills load immediately; hooks load only at session start, so `adversarial-review` and `guard-hooks` sit inert until you restart. Then check that `claude plugin list` reports `Status: ✔ enabled`. That's where a hook that failed to load shows up — `claude plugin validate` won't tell you.

### Requirements

| Plugin | Needs |
|---|---|
| adversarial-review | `codex` ≥ 0.146.0 (authenticated), `jq` ≥ 1.6, `bash` ≥ 4, `git`, `shuf`, coreutils. `gh` only if you review a PR by number. |
| handoff | `git`. Optionally an agent memory directory and [memsearch](https://github.com/zilliztech/memsearch). |
| guard-hooks | `jq` ≥ 1.6, `bash` ≥ 4, coreutils. |

## Layout

```text
.claude-plugin/marketplace.json    marketplace manifest
plugins/                           Claude Code plugins; hooks require this format
skills/                            standalone skills, no harness dependency
```

Skills inside the plugins are ordinary `SKILL.md` files with YAML frontmatter, so you can symlink
one into a different agent's skills directory instead of installing the plugin. `handoff` and
`handoff-resume` port cleanly, having no scripts or hooks at all. The genuinely Claude Code-specific
pieces are `hooks.json` and `${CLAUDE_PLUGIN_ROOT}`.

## Two conventions

Worth knowing before you send a patch, because they explain most of the design.

**Enforcement goes in hooks, not in prose.** A rule written into a skill is advice, and an agent
can reason its way past advice. Constraints that actually matter — don't write outside these paths,
don't skip this file — go into a hook, which is configured where the model can't reach it. The
[adversarial-review README](plugins/adversarial-review/#why-hooks-and-not-more-instructions) works
through why that plugin needs four of them.

**Every hook states which way it fails.** Security guards fail closed: if the guard itself errors,
the call is denied. Convention checks and review gates fail open, because a check that blocks
ordinary work when it breaks gets switched off, and a switched-off check is worse than no check at
all — the report still claims the guarantee. Each hook table says which applies.

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
   the near-miss that shouldn't.
3. If you add a hook, say which way it fails and add it to the plugin's hook table.

## Licence

MIT. See [LICENSE](LICENSE).
