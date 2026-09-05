# humanize

humanize makes text readable for the person reading it, so they get it in one pass and can act on it. It classifies the text into one of three contexts, because each has a different idea of what readable means. A reply in this conversation needs the answer first and a decision the reader can make now. Documentation needs no fluff and one fact or instruction per sentence. Creative copy, such as marketing and blog posts, needs natural flow and none of the repeated patterns readers notice in generated text.

## Install

```bash
claude plugin marketplace add serenecotech/agent-skills
claude plugin install humanize@sereneco
```

Restart Claude Code after install. The SessionStart hook loads only at startup, resume, `/clear`, and compaction.

Needs only `sh`.

### If you already have the loose skills

This plugin replaces four standalone skills and one rules file that used to live in `~/.claude`: `skills/docs-voice`, `skills/simple-english`, `skills/writing-prose-like-a-human`, `skills/human-voice-writer`, and `rules/reply-clarity.md`. If those are still present, delete them after installing the plugin. A loose `docs-voice` matches documentation requests as well as `humanize` does, so the model picks either one, and a loose `reply-clarity.md` loads the reply rules a second time on every session.

## Using it

No commands to memorise. The skill triggers from ordinary phrasing, and it also runs as `/humanize`.

```text
write the docs
draft release notes
de-slop this
make this readable
plain english
make it sound human
match my voice
tighten this
```

## What it classifies

The humanize skill reads the text first. It decides which of four cases applies: a reply, documentation, creative copy, or an audit of existing text. Documentation splits again into procedural, descriptive, and reference sections. Each section type gets its own ruleset.

## Which ruleset applies

| Example phrasing | Classification | Ruleset | Direct invocation |
| --- | --- | --- | --- |
| "write the docs", "draft release notes" | Documentation, procedural section | procedural-writing | `/humanize:procedural-writing` |
| "explain how this works", "write the overview" | Documentation, descriptive section | descriptive-writing | `/humanize:descriptive-writing` |
| "make it sound human", "match my voice", "write the launch post" | Creative copy | creative-copy | `/humanize:creative-copy` |
| "tighten this", "make this readable" said about a chat reply | Reply | `rules/reply-clarity.md`, loaded by the SessionStart hook | not applicable |
| "check this doc against the rules" | Audit of existing text | procedural-writing check mode, reports by rule number | `/humanize:procedural-writing` |

## Why three separate skills

procedural-writing, descriptive-writing, and creative-copy are sibling skills with `disable-model-invocation: true`, so Claude cannot load them on its own. The humanize skill reads each one by file path when a section needs its full catalog, and picks which one applies.

procedural-writing holds 53 numbered controlled-language rules and a check mode that reports violations by rule number. descriptive-writing covers specific facts, plain verbs, and no significance inflation. creative-copy covers varied rhythm, no repeated lexical patterns, no assistant register, and voice matching from writing samples.

A user can invoke each ruleset directly: `/humanize:procedural-writing`, `/humanize:descriptive-writing`, `/humanize:creative-copy`. The router exists so the model sees one description instead of four overlapping ones, and cannot be bypassed by picking a ruleset on its own.

## The conflict it owns

Creative copy wants contractions, fragments, and sentences of varied length. Documentation bans all three. Inside documentation the docs rules win. Inside creative copy the copy rules win. The two rulesets never apply to one passage together.

## The reply hook

A SessionStart hook, `hooks/reply-clarity.sh`, prints `rules/reply-clarity.md` into the session at startup, resume, `/clear`, and compaction. Replies written for a person then follow the reply rules without the user asking.

The hook is POSIX `sh`, and it fails open: any error exits 0, and the session starts without the rules. The rules exclude code, tool input, commit messages, subagent prompts, and reports returned to another agent.

## Worth knowing

- Reference sections, such as API tables, config keys, and flag lists, stay structural. Neither the procedural nor the descriptive rules touch their wording.
- A task that mixes types, such as a launch post that links to a quickstart, gets split. The skill routes each part on its own, and it never applies one ruleset to both.
- Untouchables stay exact under every ruleset: code blocks, commands, file paths, quoted errors, product names, and UI labels.
- Tables are for data with two or more dimensions. A three-item list does not need one.
- No summary section closes a document. There is no "In summary" or "In conclusion", and no arc from a challenge to a promising future.
- A README itself is treated as both types: what it is as descriptive prose, install and first run as procedural steps, then configuration as reference.

## Limitations

The skill states its own limit plainly: "These rules govern how the text reads, not whether it is true." A compliant document can still be wrong. Check the facts separately, and say plainly which claims you could not verify.

## Portability

The three rulesets are plain `SKILL.md` files with `references/` Markdown, and no scripts. They port to any agent that reads skills from a directory.

Two parts stay Claude Code specific. The humanize skill finds its siblings through `${CLAUDE_PLUGIN_ROOT}` paths, and the hook is a Claude Code SessionStart hook. Adjust both when porting to another agent.
