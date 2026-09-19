# skills

Standalone skills: plain `SKILL.md` files with no hooks and no scripts, for agents that read skills
from a directory instead of installing plugins.

| Skill | Does |
|---|---|
| [`mac-design-explore`](mac-design-explore/) | Builds several native macOS interfaces for one task, captures real screenshots, walks the same task through each, and reports only what it observed. Also refines a single view, or checks whether the machine is set up for either |

Everything else in this repository ships inside a plugin, because it either needs hooks or pairs
with a sibling skill:

| Skill | Ships in | Why it's bundled |
|---|---|---|
| `review-code`, `review-design` | [adversarial-review](../plugins/adversarial-review/) | They depend on the plugin's `PreToolUse` gates for the guarantees they claim |
| `handoff`, `handoff-resume` | [handoff](../plugins/handoff/) | Two halves of one contract, the `▶ Resume This Work` block |
| `humanize`, `procedural-writing`, `descriptive-writing`, `creative-copy` | [humanize](../plugins/humanize/) | The router reads its siblings through `${CLAUDE_PLUGIN_ROOT}`, and a SessionStart hook loads the reply rules |

`handoff` and `handoff-resume` are portable as they stand, so symlink them out of the plugin if you
want them elsewhere. This directory is for skills with no plugin to belong to in the first place.

## Installing one

```bash
npx skills add serenecotech/agent-skills --skill mac-design-explore
```

The [skills CLI](https://github.com/vercel-labs/skills) finds this directory without any
configuration, because `skills/` is one of the locations it searches. It reads the plugins too:
`npx skills add serenecotech/agent-skills --list` returns the standalone skills and the
plugin-bundled ones in one list. Installing a plugin skill this way copies the `SKILL.md` alone,
without the hooks it depends on, so prefer `claude plugin install` for those.

## Adding one

```text
skills/<name>/SKILL.md
```

With frontmatter:

```yaml
---
name: <name>
description: Use when <the situation that should trigger this>...
---
```

Write the `description` as a trigger condition rather than a summary. It's what an agent matches
against when deciding whether to load the skill at all, so "Use when the user asks to X" beats
"A skill for Xing".

A skill with more than one file gets a `README.md` beside `SKILL.md`, saying what it needs, what it
does not do, and which of its claims are unverified.

Keep the directory to what an installer needs. `npx skills add` copies every file in it, so review
records, evaluation plans and scratch notes do not belong here.
