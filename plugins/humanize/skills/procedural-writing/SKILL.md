---
name: procedural-writing
description: Controlled-language rules for instructions a person has to act on. Quickstarts, how-to steps, runbooks, troubleshooting, error messages, breaking-change actions. 53 numbered rules plus a check mode that reports violations by rule number. Loaded by /humanize for procedural sections. Invoke directly for a numbered audit of existing text.
disable-model-invocation: true
---

# Procedural Writing: Controlled Language for Instructions

Write instructions so that a tired reader who is not a native English speaker cannot misread them. The rules below come from controlled-language practice in safety-critical documentation, where a misread instruction has a cost. They remove long sentences, synonym rotation, hedges, filler, and decorative clauses, which is also what makes text read as generated rather than written.

Write for that tired reader. Each sentence must survive one read.

Domain vocabulary is legal. Keep the words your project already uses: "idempotent", "webhook", "commit", "endpoint". The rules govern structure and consistency, not your technical terms.

## Your Task

When asked to write or rewrite technical text:

1. **Classify each passage** as procedural or descriptive. Every other rule depends on this.
2. **Pick your terms before you draft.** For each concept that has common synonyms, pick one word and use no other word for that concept in the whole document. The usual offenders: check/verify/confirm/ensure/validate, config/configuration/settings/options, run/execute, delete/remove/drop.
3. **Apply the rules** from the catalog that follows.
4. **Do the self-check** before you deliver. This step is not optional.
5. **Never touch code**, identifiers, commands, or quoted errors (see Untouchables).

When asked to CHECK text instead of writing it, report each violation as: rule number, the offending text, a compliant rewrite. Cite only rule numbers that exist in this file. Do not cite rule numbers from memory. The numbering is unintuitive and invented rule numbers are a known failure.

## Step 1: Classify the Text

|                | Procedural (instructions)          | Descriptive (explanations)                                           |
| -------------- | ---------------------------------- | -------------------------------------------------------------------- |
| Purpose        | Tell the reader what to do         | Explain what a thing is or does                                      |
| Verb form      | Imperative: "Install the pump."    | Simple present/past/future                                           |
| Sentence limit | **20 words** (Rule 5.1)            | **25 words** (Rule 6.3)                                              |
| Unit rule      | One instruction per sentence (5.2) | One topic per paragraph (6.5), max six sentences per paragraph (6.6) |

Do not mix the two in one passage. A "Getting started" section is procedural. An "Architecture" section is descriptive. A note inside a procedure is descriptive (25-word limit, no imperative).

## THE RULE CATALOG

53 rules in 9 sections, with software examples.

### Section 1 — Words (Rules 1.1-1.14)

| Rule | Instruction |
| --- | --- |
| 1.1 | Use plain, common words, technical nouns, or technical verbs. Prefer the shortest word that carries the fact. |
| 1.2 | Use a word as one part of speech only, through the whole document. |
| 1.3 | Give a word one meaning only. If it must carry a second meaning, pick a different word for the second. |
| 1.4 | Use simple verb and adjective forms (see Section 3). |
| 1.5 | You can use domain words as technical nouns ("webhook", "commit", "endpoint"). |
| 1.6 | Use an unusual, invented, or borrowed word only when it is a technical noun or part of one. |
| 1.7 | Do not use technical nouns as verbs. |
| 1.8 | Use the technical nouns of your project or industry. |
| 1.9 | When you pick a technical noun, pick a short and clear one. |
| 1.10 | No regional, slang, or jargon words as technical nouns. |
| 1.11 | One item, one name. Do not call it "config" here and "settings" there. |
| 1.12 | You can use domain verbs as technical verbs ("deploy", "compile", "merge"). Common computer verbs are legal, for example: click, press, enter, type, tap, copy, cut, paste, delete, save, scroll, sort, validate, boot, debug, download, install, load, process, reboot, update, upgrade, upload. When a plain verb does the same job, prefer it: "find" instead of "detect". |
| 1.13 | Do not use technical verbs as nouns. |
| 1.14 | Use American English spelling. |

Rules 1.5, 1.8, and 1.12 keep your domain vocabulary legal. The ones agents break are 1.2, 1.7, 1.11, and 1.13.

**Before:** You can webhook the event, then do a deploy. **After:** Send the event to the webhook. Then deploy the service.

### Section 2 — Multi-word nouns (Rules 2.1-2.2)

| Rule | Instruction                                                                                                              |
| ---- | ------------------------------------------------------------------------------------------------------------------------ |
| 2.1  | Write multi-word nouns of three words or fewer.                                                                          |
| 2.2  | When a technical noun needs more than three words, write it in full once, then give a short form or hyphenate the units. |

Break long noun chains with prepositions (of, on, in, for):

**Before:** the connection pool timeout configuration value **After:** the timeout value for the connection pool

### Section 3 — Verbs (Rules 3.1-3.7)

| Rule | Instruction |
| --- | --- |
| 3.1 | Use plain, common verbs. Prefer a common verb over an unusual one: "find" not "detect", "show" not "render". |
| 3.2 | Use only: infinitive, imperative, simple present, simple past, simple future, past participle as adjective. |
| 3.3 | Use the past participle only as an adjective ("the cached response"). |
| 3.4 | No auxiliary verbs for complex constructions. No present perfect, no "is to be installed". |
| 3.5 | Use an "-ing" form only as a technical noun or inside one ("logging", "the mounting bracket") — never as a verb. |
| 3.6 | Active voice. In descriptive text, passive is legal only when the agent is unknown. To repair an agentless passive, use "you" (the reader) or "we" (your company) as the subject: "Indexes are not used on this table" → "We do not use indexes on this table." |
| 3.7 | Describe an action with a verb, not a noun ("compress the file", not "perform compression of the file"). |

**Approved modals: can, will, must. Banned: should, would, may, might, could.** Write "an explosion can occur", never "could occur". For "should": a requirement becomes "must". A suggestion is stated as fact or deleted. This matters double for agent instructions — models read "should" as optional.

**Before:** The migration has completed and the table is being rebuilt. **After:** The migration completed. The database rebuilds the table.

**Before:** The flag can be set in the config file, making restarts unnecessary. **After:** You can set the flag in the config file. Then a restart is not necessary.

**Before:** The temperature must be adjusted. **After:** Adjust the temperature.

### Section 4 — Sentences (Rules 4.1-4.5)

| Rule | Instruction |
| --- | --- |
| 4.1 | Write short and clear sentences. |
| 4.2 | Do not omit words or use contractions to shorten sentences. Keep articles, keep "that". |
| 4.3 | Use a vertical list for complex text. Put a colon at the end of the lead-in. Start each item with an uppercase letter. An item gets a period only if it is a full sentence — never a comma or a semicolon. The last item gets a period. Do not mix instructions and facts in one list. Do not nest lists. |
| 4.4 | Use connecting words between sentences on related topics ("Then", "As a result"). |
| 4.5 | Put an article (the, a, an) or a demonstrative adjective (this, these) before nouns where applicable. Exception: no article before a noun when an identifier follows it — "Restart pod web-7f9b2", not "Restart the pod web-7f9b2". |

Rule 4.2 is the anti-terseness rule. This is short sentences with complete grammar, not telegraph style:

**Wrong shortening:** Ensure file exists before running. **Correct:** Make sure that the file exists before you run the command.

### Section 5 — Procedural writing (Rules 5.1-5.5)

| Rule | Instruction |
| --- | --- |
| 5.1 | Maximum 20 words per sentence. Warnings and cautions included. |
| 5.2 | One instruction per sentence, unless two actions happen at the same time. A step can have a second sentence for an immediate result or limit: "Run the migration. The migration must take less than 5 minutes." |
| 5.3 | Write instructions in the imperative: "Run the migration." |
| 5.4 | Put a required condition before the command, divided by a comma: "If the build fails, read the log." |
| 5.5 | Notes give information, never instructions, requirements, or limits. A limit belongs with its action in the work step. Notes get the 25-word limit. Notes-test: the procedure must still work for a reader who deletes all notes. |

**Before:** You'll want to grab the API key from the dashboard before configuring the client, which you can do under Settings. **After:** Get the API key from the dashboard, under Settings. Then configure the client with this key.

### Section 6 — Descriptive writing (Rules 6.1-6.6)

| Rule | Instruction                                                     |
| ---- | --------------------------------------------------------------- |
| 6.1  | Give information gradually: one new fact per sentence.          |
| 6.2  | Use key words and phrases to give the text a logical structure. |
| 6.3  | Maximum 25 words per sentence.                                  |
| 6.4  | Group related information in paragraphs.                        |
| 6.5  | One topic per paragraph.                                        |
| 6.6  | Maximum six sentences per paragraph.                            |

No imperative in descriptive text. Descriptions explain. Procedures instruct.

### Section 7 — Safety instructions (Rules 7.1-7.3)

| Rule | Instruction                                                                                                                    |
| ---- | ------------------------------------------------------------------------------------------------------------------------------ |
| 7.1  | Use a word that shows the risk level ("WARNING" = injury, "CAUTION" = damage). If the two risks occur together, use "WARNING". |
| 7.2  | Start with a clear command or condition.                                                                                       |
| 7.3  | Then give the risk or the possible result.                                                                                     |

Never bury the instruction after the explanation. The pattern transfers directly to destructive CLI flags, irreversible migrations, and dangerous API options.

**Before:** Note that data loss may occur in some circumstances if the destructive flag happens to be enabled when running against production. **After:** CAUTION: Do not use the `--force` flag against production. The flag deletes rows that do not match the source.

### Section 8 — Punctuation and word count (Rules 8.1-8.7)

| Rule | Instruction |
| --- | --- |
| 8.1 | All standard punctuation is legal except the semicolon. Write two sentences instead. |
| 8.2 | Use hyphens to connect words that act as one unit. |
| 8.3 | Parentheses are legal for references, item numbers, abbreviations, plural forms, explanations, alternatives. |
| 8.4 | In a vertical list, the lead-in colon ends a sentence for word count. Each item after the colon counts as a new sentence and gets its own 20/25-word budget. |
| 8.5 | Text inside parentheses counts as one word. |
| 8.6 | Count as one word each: numbers, numbers with units, abbreviations, alphanumeric identifiers, quoted text, titles, labels, proper nouns. |
| 8.7 | A hyphenated word counts as one word. |

Rule 8.6 matters for software text: `sqlpipe run --config sqlpipe.yaml` in backticks is quoted text and counts as one word. Long identifiers do not blow your sentence budget.

### Section 9 — Writing practices (Rules 9.1-9.4, GR-1 to GR-8)

| Rule | Instruction                                                                               |
| ---- | ----------------------------------------------------------------------------------------- |
| 9.1  | When a word-for-word replacement does not work, restructure the sentence.                 |
| 9.2  | Use each word with one meaning and one part of speech, everywhere in the document.        |
| 9.3  | Do not build phrasal verbs ("go down" → "decrease", "set up" → "install" or "configure"). |
| 9.4  | Keep one consistent style and terminology through the whole document.                     |

General recommendations GR-1 to GR-8: keep the conjunction "that", be careful with "with", give pronouns clear referents, prefer "this + noun" over bare "this", avoid false friends, avoid Latin abbreviations, use inclusive language, and use the possessive apostrophe form only when you are sure it is correct (GR-8: if unsure, do not use it — non-native readers find it hard). GR-2 also kills a common habit: keep the primary verb first and the tool after "with" — "Fetch the URL with curl", not "Use curl to fetch the URL".

GR-6 for software docs: "e.g." → "for example", "i.e." → "that is", and delete "etc." — name the items or write "and more".

## VOCABULARY DISCIPLINE

The mechanic is one rule: **one word, one meaning, one part of speech.**

You do not need a controlled dictionary to apply it. You need a decision per concept, made once, then held for the whole document.

Useful part-of-speech patterns:

| Word | Ruling |
| --- | --- |
| follow | "To come after" only, never "obey". Write "obey the instructions". |
| above, below | Physical positions only. For limits write "more than", "less than". For cross-references, name the target: "the example that follows". |
| fall | Physical movement downward only: "Make sure that the tools do not fall into the engine." For a reduction in value write "decrease". |
| complete | Use "completed" as the adjective: "the completed migration", not "the migration is complete". |

### The modal ladder

| You wrote                                               | Write instead                                            |
| ------------------------------------------------------- | -------------------------------------------------------- |
| should (requirement)                                    | must                                                     |
| should (recommendation)                                 | Delete it, or state it as fact: "X is better because Y." |
| should (inverted conditional: "should a failure occur") | if: "If a failure occurs"                                |
| may / might / could (possibility)                       | can                                                      |
| may (permission)                                        | can                                                      |
| would (hypothetical)                                    | can, or restructure: "If X occurs, Y occurs."            |

### Slop-to-simple substitutions

AI-generated docs overuse a known set of words. `references/word-swaps.md` maps each one to a plain replacement. Read it when you rewrite existing text. If a word carries no fact, delete it instead of replacing it.

### Consistency pass

Collapse synonym rotations to one term each (Rules 1.11, 9.4). Pick one word per concept and use no other. The recommendation in brackets is a default, not a requirement — consistency matters more than which word you pick.

| Concept | Rotation to collapse | Default |
| --- | --- | --- |
| Confirming a state | check / verify / confirm / ensure / validate | `make sure that` for a state, `examine` to look for faults, `measure` to get a value |
| Configuration data | config / configuration / settings / options | pick one and keep it |
| Starting a process | run / execute / invoke / launch | `run` |
| Destroying data | delete / drop / destroy / erase | `delete` for data, `remove` for items in a list |
| Putting text on screen | display / render / present / show | `show` |
| Something wrong | issue / problem / error / fault / failure | `error` for a machine fault, `problem` for a human-facing one |

### Common swaps

These are the words writers get wrong most often in technical text.

| You wrote                            | Write instead                                                                    |
| ------------------------------------ | -------------------------------------------------------------------------------- |
| however                              | but                                                                              |
| therefore                            | thus, as a result                                                                |
| since (= because)                    | because                                                                          |
| any                                  | Delete it, or restructure: "if you have any questions" → "if you have questions" |
| now                                  | Delete it: "now start the service" → "start the service"                         |
| need to, have to                     | Imperative in procedures ("install"); "it is necessary to" in descriptive text   |
| perform                              | do                                                                               |
| insert                               | put (but SQL `INSERT` stays: it is quoted text)                                  |
| reach                                | get, get to                                                                      |
| avoid                                | prevent                                                                          |
| repeat                               | do … again                                                                       |
| acceptable                           | Give the limit: "a latency of less than 200 ms"                                  |
| the example below, the section above | Name the target, or put the reference after it: "the example that follows"       |

## Untouchables

These are technical names (Rules 1.5, 8.6). Leave them exact, even when they break vocabulary rules:

- Code blocks, inline code, identifiers, CLI commands, flags, file paths
- Quoted error messages and log lines
- Product names, API endpoint names, config keys
- UI labels and button names ("click the **Save** button" — quoted text, counts as one word)
- Numbers with units — each counts as one word in the sentence limit

Facts are untouchable too. Rewrite the style, not the content. When the source does not give a number, a cause, or an exact term, keep the general statement. Do not invent specifics to look concrete.

## Beyond Documentation

The same rules apply to error messages, runbooks, incident reports, release notes, commit messages, agent instructions, support macros, UI copy, and translation prep. Read `references/use-cases.md` when the task is one of these. It gives the pattern for each.

## Self-Check Before You Deliver

This step is not optional. Run these five checks on your draft:

1. Count words in your three longest sentences. Over the 20/25 limit → split them.
2. Search your draft for: `'ll`, `'re`, `'s` (contraction), `has been`, `have been`, `should`, `shall`, `however`, `therefore`, `-ing` verbs after a comma, semicolons.
3. Search for every `if` and `when`. Each one stands at the START of its sentence, before the command. "Increase the timeout if the network is slow" → "If the network is slow, increase the timeout."
4. Search for the terms you did NOT pick in step 2 of Your Task. Replace each hit with your chosen term. The usual survivors are check, verify, confirm, ensure, settings, execute.
5. Check each vertical list: colon on the lead-in, items start with an uppercase letter, no comma or semicolon at the end of an item, no procedural and descriptive items mixed.

Fix what you find, then deliver. For a full audit, run `references/checklist.md`.

## Full Example

**Before (real unedited AI output):**

> **Connection timeouts.** If sqlpipe hangs or fails with `dial tcp: i/o timeout`, check that the host running sqlpipe can reach the Postgres port (usually 5432) — this is often a security group or firewall rule blocking the connection. If you're connecting to a managed database (RDS, Cloud SQL, etc.), confirm the instance allows connections from sqlpipe's IP. You can also try increasing `source.connect_timeout_seconds` in your config, since a slow network path can trip the default timeout even when the connection eventually succeeds.

**After (classified procedural, verb = "make sure", conditions first, one instruction per sentence):**

> **Connection timeouts.** sqlpipe stops with `dial tcp: i/o timeout` when it cannot connect to the Postgres port (5432 by default).
>
> 1. Make sure that the host that runs sqlpipe can connect to the Postgres port. A firewall or security group usually blocks it.
> 2. If the database is managed (RDS, Cloud SQL), make sure that the instance accepts connections from the IP of sqlpipe.
> 3. If the network is slow, increase `source.connect_timeout_seconds` in the configuration.

What changed: 40-word sentences split under 20. "you're" expanded. "check/confirm" collapsed to "make sure that". Every condition moved before its command. "etc." removed. Code and error strings untouched.

## Limits

These rules are for technical facts and instructions. They delete persuasion by design, so they are wrong for marketing copy, blog voice, or brand writing. The `humanize` skill decides which text gets this ruleset. Do not re-route from here.

The rules govern how the text reads, not whether it is true. A compliant document can still be wrong. Check the facts separately.

## References

- `references/checklist.md` — full verification pass with searchable patterns, for check mode and final audits
- `references/word-swaps.md` — slop-to-simple word map, for rewriting existing text
- `references/use-cases.md` — long-form adaptations: error messages, runbooks, incident reports, commits, UI copy, i18n
