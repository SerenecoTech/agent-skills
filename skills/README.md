# skills

Standalone skills: plain `SKILL.md` files with no hooks and no scripts, for agents that read skills
from a directory instead of installing plugins.

Empty for now. Everything in this repository currently ships inside a plugin, because it either
needs hooks or pairs with a sibling skill:

| Skill | Ships in | Why it's bundled |
|---|---|---|
| `review-code`, `review-design` | [adversarial-review](../plugins/adversarial-review/) | They depend on the plugin's `PreToolUse` gates for the guarantees they claim |
| `handoff`, `handoff-resume` | [handoff](../plugins/handoff/) | Two halves of one contract, the `▶ Resume This Work` block |

`handoff` and `handoff-resume` are portable as they stand, so symlink them out of the plugin if you
want them elsewhere. This directory is for skills with no plugin to belong to in the first place.

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
