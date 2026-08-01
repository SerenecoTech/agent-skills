# skills

Standalone skills that are not part of any plugin — plain `SKILL.md` files with no hooks, no
scripts and no harness-specific tool calls, for agents that read skills from a directory rather
than installing plugins.

Empty for now. Everything currently in this repository is bundled with a plugin because it either
ships hooks or pairs with a sibling skill:

| Skill | Lives in | Why it's bundled |
|---|---|---|
| `review-code`, `review-design` | [adversarial-review](../plugins/adversarial-review/) | Depend on the plugin's `PreToolUse` gates for the guarantees they claim |
| `handoff`, `handoff-resume` | [handoff](../plugins/handoff/) | Two halves of one contract — the `▶ Resume This Work` block |

`handoff` and `handoff-resume` are portable as-is; symlink them out of the plugin if you want them
in another agent. This directory is for skills that have no plugin to belong to in the first place.

## Adding one

```
skills/<name>/SKILL.md
```

With frontmatter:

```yaml
---
name: <name>
description: Use when <the situation that should trigger this>...
---
```

Write the `description` as a trigger condition, not a summary — it is what an agent matches
against to decide whether to load the skill at all.
