# agent-skills

Five Claude Code plugins: hostile code review, session handoff, security guard hooks, fewer
permission prompts for compound shell commands, and writing skills for text that does not read as
AI-generated. Plus one standalone skill, `mac-design-explore`, which compares native macOS
interfaces by building and screenshotting them.

Bash and Markdown throughout. Nothing to build, nothing to compile.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install adversarial-review@sereneco
claude plugin install handoff@sereneco
claude plugin install guard-hooks@sereneco
claude plugin install check-compound-bash@sereneco
claude plugin install humanize@sereneco
```

Or run `/plugin` in Claude Code and browse.

The standalone skill is not a plugin, so it installs with the
[skills CLI](https://github.com/vercel-labs/skills) instead:

```bash
npx skills add serenecotech/agent-skills --skill mac-design-explore
```

Add `-g` to install into `~/.claude/skills/` rather than the current project, and `-a claude-code -y`
to skip the prompts. `npx skills add serenecotech/agent-skills --list` shows everything in this
repository, the plugin-bundled skills included, and `--skill` takes any name from that list.

**Restart Claude Code afterwards.** Skills work immediately, but hooks load only at session start,
so `adversarial-review`, `guard-hooks`, `check-compound-bash` and the `humanize` reply rules sit
inert until you do. Then run `claude plugin list` and
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

**[check-compound-bash](plugins/check-compound-bash/)** — splits `a && b | c` into its parts and
checks each one against your `Bash(...)` allow and deny rules. When every part is already allowed,
the permission prompt is skipped. When any part is denied, the command is blocked. Anything else
falls through to the normal prompt.

**[humanize](plugins/humanize/)** — one skill for anything a person will read. Say "write the
docs", "de-slop this" or "make it sound human" and `humanize` classifies the text as a reply,
documentation or creative copy, then applies the matching ruleset so the reader gets it in one pass.
A session-start hook loads the reply rules, so answers in the conversation follow them too.

Each plugin has its own README.

## The standalone skill

**[mac-design-explore](skills/mac-design-explore/)** — say "explore alternatives for this sidebar"
and it builds several SwiftUI or AppKit versions of the same screen, runs them, captures real
screenshots, and walks the same task through each. It reports build, render, inspection and
interaction as four separate states, so a compiled direction nobody looked at is never presented as
verified. Install it with `npx skills add serenecotech/agent-skills --skill mac-design-explore`, or
copy the folder into `~/.claude/skills/`. There is no plugin to install.

## Requirements

| Plugin | Needs |
|---|---|
| adversarial-review | `codex` ≥ 0.146.0 (authenticated), `jq` ≥ 1.6, `bash` ≥ 4, `git`, `shuf`, coreutils. `gh` only for reviewing a PR by number. |
| handoff | `git`. |
| guard-hooks | `jq` ≥ 1.6, `bash` ≥ 4, `git`, coreutils. `gh` for the GitHub merge rules. |
| check-compound-bash | `shfmt`, `jq` ≥ 1.6, `bash` ≥ 4.3. Without `shfmt` or `jq` it does nothing and the normal prompt appears. |
| humanize | `sh`. The skills need nothing. |
| mac-design-explore (skill) | macOS with a Swift toolchain, `swift` or `xcodebuild`. A window capture tool such as `peek`, and an image-reading tool, for the visual checks. Without those it compiles and reports capture as blocked. |

## Layout

```text
.claude-plugin/marketplace.json    marketplace manifest
plugins/                           Claude Code plugins; hooks require this format
skills/                            standalone skills, no harness dependency
skills/mac-design-explore/         SKILL.md, README.md, references/peek.md
```

`npx skills add` copies a skill directory wholesale, so a skill directory holds only what an
installer needs.

Skills inside the plugins are ordinary `SKILL.md` files with YAML frontmatter, so you can symlink
one into another agent's skills directory instead of installing the plugin. `handoff`,
`handoff-resume` and the three `humanize` rulesets port cleanly, having no scripts or hooks at all.
The `humanize` router reads its siblings through `${CLAUDE_PLUGIN_ROOT}`, so fix those paths when
porting it. The Claude Code-specific pieces
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
