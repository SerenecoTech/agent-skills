---
name: humanize
description: Write or rewrite documentation, copy, or a reply so the person reading it understands it in one pass. Use for any README, quickstart, how-to, guide, runbook, release notes, changelog, error message, API or concept page, or PR description, and for any marketing, landing page, launch post, blog, newsletter, social post, pitch, personal email, or matching someone's voice from samples. Also use to audit existing text for readability. Triggers include "write the docs", "write a README", "quickstart", "document this", "draft release notes", "de-slop", "make this readable", "plain english", "simple english", "tighten this", "less wordy", "make it sound human", "match my voice", "in my tone of voice", "humanize". Use it even when the user asks for the text only, with no mention of style.
---

# Humanize

One entry point for text a person will read. The goal is the same every time: the reader understands the text in one pass and can act on it. The mechanics differ by who is reading and why, so this skill classifies the context first and then applies one of three rulesets.

| The reader is | They need | Ruleset |
| --- | --- | --- |
| A person reading a reply in this conversation | The answer first, short sentences, a decision they can make now | Step 2, reply rules |
| A person following or learning from documentation | No fluff, one fact or instruction per sentence, a predictable shape | Step 3, procedural and descriptive rules |
| A person reading copy (marketing, blog, email, pitch) | Natural flow, a voice, none of the repeated patterns readers notice in generated text | Step 4, creative copy rules |

The three rulesets live in sibling skills with model invocation disabled, so the Skill tool cannot load them. Read them from the paths given below. A user can still invoke them directly as `/humanize:procedural-writing`, `/humanize:descriptive-writing` and `/humanize:creative-copy`.

## Step 1: Classify the context

Classify before writing a word. Pick by what the text is, not by what the user called it.

| The text | Route |
| --- | --- |
| Is the answer in this conversation, or a summary or status the user reads here | Step 2 |
| Will live in a repository, a docs site, a release, a UI string, or an error path | Step 3 |
| Exists to persuade, announce, or carry a specific person's or brand's voice, or the user supplied samples to match | Step 4 |
| Is existing text the user handed over to check or fix | Classify it by the three rows above, then use that step's checklist. For a procedural audit, use the check mode in `procedural-writing`, which reports violations by rule number. |

If a task mixes types (a launch post that links to a quickstart), split it and route each part. Do not apply one ruleset to both.

## Step 2: Replies

Read `${CLAUDE_PLUGIN_ROOT}/rules/reply-clarity.md` and apply it to the reply. If a block headed "REPLY CLARITY (humanize plugin)" is already in this session's context, the plugin's SessionStart hook loaded it. Do not read it again.

The rules that carry most of the effect: one idea per sentence with a 25-word cap, condition before instruction, one word per concept, modals that carry meaning (`must`, `can`, `will`), no hedge without a real uncertainty, and no specific (number, path, error string) that does not trace to something read or run in the session.

## Step 3: Documentation

### 3a. Split the document by section type

| Type | Contains | Rules |
| --- | --- | --- |
| **Procedural** | Setup, quickstart, how-to steps, runbook steps, troubleshooting, breaking-change actions, error messages | 3b |
| **Descriptive** | Overview, concepts, architecture, "what's new" narrative, announcement intro, rationale | 3c |
| **Reference** | API tables, config keys, flag lists, schema fields | Leave structural. Apply 3d only. |

Do not mix procedural and descriptive in one passage. A note inside a procedure is descriptive: 25-word limit, no imperative.

### 3b. Procedural sections

1. Imperative mood. One instruction per sentence. "Run the migration."
2. Maximum 20 words per sentence, warnings included.
3. Condition before command, split by a comma. "If the build fails, read the log." Never the reverse.
4. No contractions. Keep articles, keep "that". Short sentences with complete grammar, not telegraph style.
5. One term per concept, held for the whole document. Never rotate check/verify/confirm/ensure, config/settings, run/execute, delete/remove.
6. Modals: `can`, `will`, `must`. Never should, would, may, might, could. A requirement is "must". A suggestion is stated as fact or deleted.
7. Warnings and cautions: command or condition first, risk second. "CAUTION: Do not use `--force` against production. The flag deletes rows that do not match the source."
8. Notes give information only, never requirements or limits. A limit belongs with its action in the step. Test it: delete every note, then check that the procedure still works.

Read `${CLAUDE_PLUGIN_ROOT}/skills/procedural-writing/SKILL.md` when the section runs past ten steps, when the user asks for a compliance check on existing text, when the docs get localised, or when the user asks for plain or simple English. It holds the full 53-rule catalog, the check mode, and the word-swap and use-case references.

### 3c. Descriptive sections

1. **Be specific, not significant.** State the fact, skip the commentary about why it matters. Cut pivotal, crucial, vital, key (adjective), testament, watershed, indelible, deeply rooted, lasting legacy, evolving landscape.
2. **Use plain verbs.** "is", "are", "has", not "serves as", "stands as", "represents", "showcases", "underscores", "boasts". Better still, find the verb hiding in the noun phrase: "the tool serves as a validation mechanism" becomes "the tool validates inputs".
3. **End sentences at the fact.** No trailing "-ing" commentary. "The population grew 12%" says more than "The population grew 12%, reflecting broader demographic trends."
4. **Earn every adjective.** If deleting it does not change the meaning, delete it. Cut vibrant, rich, robust, seamless, comprehensive, meticulous, multifaceted, intricate, dynamic.
5. **Maximum 25 words per sentence, one new fact per sentence, six sentences per paragraph, one topic per paragraph.**

Rules 1 to 4 keep the prose honest. Rule 5 keeps it scannable. Inflated prose that scans well is still empty.

Read `${CLAUDE_PLUGIN_ROOT}/skills/descriptive-writing/SKILL.md` as a second pass when rewriting existing prose that is heavy in inflated vocabulary, or when you need the full watchlist and the attribution and structural-pattern tables. The five rules above are the engine. That skill is the filter.

### 3d. Rules for every section

- **Never invent a specific to sound concrete.** If the source gives no number, cause, or exact term, keep the general statement. A fabricated metric is worse than a vague sentence.
- **Untouchables.** Code blocks, inline code, identifiers, CLI commands, flags, file paths, quoted errors and log lines, product names, API endpoint names, config keys, UI labels. Leave them exact even when they break the rules above.
- **Sentence case headings.** No title case unless a style guide requires it.
- **Bullets only for list-shaped content.** If the items have a flow or a cause, write prose. Never build `**Scalability:** the system scales well` inventory lists.
- **Tables only for data with two or more dimensions.** Three items in a one-column table belong in a sentence.
- **No summary section.** No "In summary", "In conclusion", "Overall". No "despite challenges, the future looks promising" arc. If the section made its point, stop.
- **Delete filler rather than replacing it.** If the word carries no fact, cut it. The word-swap table in `procedural-writing/references/word-swaps.md` covers the rest.
- **Em dashes: one or two per page at most.** Prefer commas, parentheses, or colons.
- **Straight quotes and apostrophes.** No curly variants.
- **No semicolons.** Write two sentences.

### 3e. Self-check before you deliver

Not optional. Run all seven.

1. **Length.** Count words in your three longest sentences. Over 20 (procedural) or 25 (descriptive), split.
2. **Grep for banned forms:** `'ll`, `'re`, `n't`, `it's`, `has been`, `have been`, `should`, `may`, `might`, `could`, `however`, `therefore`, `;`
3. **Grep every `if` and `when`.** Each stands at the start of its sentence, before the command.
4. **Grep the synonyms you did not pick.** The usual survivors: check, verify, confirm, ensure, settings, execute.
5. **Grep trailing participials:** `, making`, `, allowing`, `, enabling`, `, ensuring`, `, highlighting`, `, underscoring`, `, reflecting`, `, solidifying`. Each becomes its own sentence or gets cut.
6. **Grep filler:** pivotal, crucial, vital, robust, seamless, comprehensive, leverage, utilize, delve, showcase, foster, streamline, simply, easily, effortlessly, powerful.
7. **Check every specific you added.** Each number, date, name, and source must trace to the source material. Remove anything you cannot trace.

### Format patterns

| Format | Classification | Pattern |
| --- | --- | --- |
| Release note entry | Descriptive | One entry, one change, one sentence. Say what changed, not that it is exciting. |
| Breaking change | Procedural | Action first, reason second: "Update your calls to `v2/users`. The `name` field split into `first_name` and `last_name`." |
| Quickstart / how-to | Procedural | Numbered steps, one instruction each, conditions first, expected result after the action. |
| Concept / architecture page | Descriptive | One new fact per sentence. No significance claims. Name the trade-off instead of calling it "a delicate balance". |
| README | Both | What it is (descriptive, 3 sentences), then install and first run (procedural), then configuration (reference). |
| Error message | Procedural | What happened (past simple), cause if known, then the command or condition to fix it. |
| Changelog | Descriptive | Group by category. No narrative arc across entries. |
| Announcement intro | Descriptive | Two or three sentences of plain fact. If it needs persuasion, it is creative copy (Step 4), not documentation. |

`procedural-writing/references/use-cases.md` has the long-form pattern for runbooks, incident reports, commit messages, support macros, UI copy, and localisation prep.

## Step 4: Creative copy

Read `${CLAUDE_PLUGIN_ROOT}/skills/creative-copy/SKILL.md` and follow it in full. It is not summarised here because its effect comes from the whole catalog: varied sentence length, no repeated sentence structures, no stock vocabulary, no assistant register, a position taken, and length matched to the format. Readers notice these patterns in copy before they notice anything else.

Three of its rules contradict the documentation rules. The context decides which wins:

| Rule | Creative copy (Step 4) | Documentation (Step 3) |
| --- | --- | --- |
| Contractions | Use them below formal register | Expand them |
| Fragments, "And"/"But" openers | Encouraged | Not used |
| Sentence length | Vary it widely | Cap at 20/25 words, one fact per sentence |

Inside documentation, Step 3 wins. Inside copy, Step 4 wins. Never apply both rulesets to one passage.

## Limits

These rules govern how the text reads, not whether it is true. A compliant document can still be wrong. Check the facts separately, and say plainly which claims you could not verify.
