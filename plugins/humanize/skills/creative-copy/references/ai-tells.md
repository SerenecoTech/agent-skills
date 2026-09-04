# AI Writing Tells: What to Avoid

These patterns are drawn from Wikipedia's AI Cleanup project (24 documented patterns), Pangram Labs' detection guide, CMU/PNAS stylometric research, and GPTZero/Binoculars detection methodology. They represent the most statistically significant markers of AI-generated text.

## Tier 1: Strongest Signals (Ban Unconditionally)

### Punctuation

Never use em dashes (—), en dashes used as em dashes (–), or double hyphens (--). These are among the most recognizable AI writing markers. Restructure sentences to use periods, commas, colons, or parentheses instead. If a sentence requires a dash to function, rewrite it so it doesn't.

### Rhetorical Constructions

**False-revelation pattern:** "It's not just X, it's Y" and all variations: "This isn't just..., it's...", "That's not... it's...", "It's not about X, it's about Y", "It's more than just X, it's Y." These create a false sense of insight. Just state the point.

**False-choice framings:** "Whether you're a beginner or a seasoned pro...", "Whether you're looking to X or Y..." Pure filler. Cut them.

**Over-signposting:** "Let's break this down," "Here's the thing," "Let me explain," "Let's dive in," "Let's unpack this." Real writers don't announce that they're about to write. They just write.

**Negation-assertion patterns:** AI constantly uses negation to manufacture dramatic tension. This includes: short dramatic negations as punchlines ("That's not speculation." "That's not a coincidence."), negation-correction pairs across sentences ("They aren't junior employees. They're senior engineers." "This wasn't luck. It was strategy."), and saying what something *isn't* before what it *is* ("Remote work stopped being a perk. It's infrastructure now."). Humans do this occasionally; AI does it in nearly every paragraph because it's an easy way to sound authoritative. State the positive claim directly instead.

**Tidy trinities:** "Three things matter: clarity, consistency, and communication." AI loves grouping ideas into neat sets of three abstract nouns separated by a colon. Humans don't naturally organize their thoughts this way.

**"Imagine" openings:** "Imagine a world where...", "Picture this:", "Imagine if you could..." AI blog post staples. Just start with the actual point.

**Hollow intensifiers:** "truly," "really," "incredibly," "absolutely," "extremely." AI scatters these for false emphasis. Use one per piece at most, or skip them.

**"From X to Y" sweeps:** "From onboarding to offboarding," "From startups to enterprises," "From design to deployment." Gestures at breadth without saying anything specific. Name what you actually mean.

**Paired synonyms:** "clear and concise," "robust and scalable," "simple and intuitive," "quick and easy." AI doubles up adjectives constantly. Pick one.

**"The power/beauty of" constructions:** "The power of collaboration," "The beauty of this approach." Always vague, always filler.

**Overused question-then-answer:** "What makes this different? It's the approach." Once per piece is fine. More than that is a tell.

**"By [gerund]" chains:** "By implementing this framework, teams can..." or "By leveraging AI, organizations can..." AI uses these to sound procedural without adding information. Restructure into direct statements.

**"Allows/enables/empowers you to":** Product-copy AI defaults. Say what the thing does. "The tool tracks expenses" not "The tool allows you to track expenses."

**"Ensures" and "ensures that":** AI uses this to sound authoritative without committing. "This ensures alignment across teams." Humans say "so everyone's on the same page" or just cut the sentence.

**Recap openers:** "As we discussed earlier...", "Building on our previous conversation..." AI does this to establish continuity. A person just picks up where they left off.

### Vocabulary

These words appear on virtually every AI detection list. A PNAS study found some used 50-150x more often by LLMs than by humans in the same genre:

delve, tapestry (metaphorical), landscape (especially "digital landscape"), navigate (metaphorical), leverage, foster, robust, utilize, nuanced, multifaceted, pivotal, underscores, aforementioned, commendable, noteworthy, intricate, beacon, realm, embark, spearheading, holistic, synergy, paradigm, transformative, groundbreaking, cutting-edge, game-changer, unlock (metaphorical), harness, streamline, cornerstone, underpinning, overarching, encompasses, facilitates, catalyze, bolster, augment, elucidate, meticulous, discerning, burgeoning, bustling, moreover, furthermore, nevertheless, notwithstanding, hitherto, myriad, plethora, juxtaposition, dichotomy, crucible, straightforward, ensures/ensures that, respective/respectively, at the forefront, at the heart of, in the realm of, at its core, at the end of the day, serves as a testament to, it's important/worth noting that, the importance of X cannot be overstated

**Weasel quantifiers (ban when used without actual numbers):** significant, substantial, considerable, notable, meaningful. If you can quantify it, use a number. If you can't, use plain language like "large" or "small."

**Overused modifiers:** "key" (as in "key takeaways," "key insights," "key benefits"). Say "main," "biggest," or drop the qualifier.

**Transition word overuse:** additionally, however, consequently, therefore, thus. AI uses these as paragraph glue far more than humans do. Most of the time you can just start the next sentence and the connection is clear.

### Structural Phrases

Opening crutches: "In today's rapidly evolving...", "In the realm of...", "In an era where...", "When it comes to...", "In a world where...", "Imagine a world where...", "Picture this:"

Hedging fillers: "It's important to note that...", "It's worth mentioning...", "Based on the information provided...", "As we can see...", "It goes without saying..."

Closing patterns: "In conclusion" followed by full restatement, "Embrace the power of...", "The journey of X is...", generic calls to action

## Tier 2: Structural Patterns (Ban Unless User Specifically Does These)

### Sentence-Level

- Uniform sentence length (low burstiness). Human text varies wildly; AI stays in a 15-25 word band.
- Every sentence begins with "The," "It," or "This" in sequence.
- Sentences starting with vague "This" as a referent: "This underscores...", "This highlights...", "This reflects broader trends." Name the actual subject instead.
- Trailing participial phrases used for false analytical weight: "...improving efficiency," "...highlighting its significance," "...reflecting broader trends."
- "Not only X, but also Y" parallel constructions used repeatedly.
- Anaphora chains: repeating the same sentence structure with slight word swaps. "It means better outcomes. It means faster delivery. It means less waste." Say it once, differently.
- Excessive nominalization (turning verbs into nouns): "the implementation of" instead of "implementing," "the utilization of" instead of "using."
- Semicolon overuse. AI stitches related ideas together with semicolons far more often than most human writers. Use a period and start a new sentence.
- "By [gerund]" chains used to open sentences repeatedly: "By implementing...", "By automating...", "By focusing on..." Restructure into direct statements.
- "Allows you to" / "enables you to" / "empowers you to" used as default phrasing. Say what the thing does directly.

### Paragraph-Level

- Every paragraph leads with a topic sentence, follows with elaboration, ends with a summary or transition. Every. Single. Time.
- Every paragraph opens the same way (with a claim, a noun phrase, a subject-verb). Vary paragraph openings the same way you vary sentence openings.
- Uniform paragraph length (3-5 sentences, never 1, never 8).
- Predictable intro-body-conclusion structure even in short pieces.
- Excessive use of numbered lists and bullet points where prose would be more natural.

### Document-Level

- Preamble restating the question before answering it: "Great question! Let me break this down..."
- Sycophantic openings: "That's an excellent point!", "What a great question!"
- Summary paragraphs that restate everything already said.
- Excessive section headers for short content.
- Perfectly balanced "on the one hand / on the other hand" structures that avoid taking a position.
- Over-writing: producing three paragraphs when one sentence would do. AI defaults to more words. Humans writing emails, Slack messages, and quick notes keep them short.

## Tier 3: Statistical Deep Patterns (Hardest to Fix via Prompting)

These are identified by academic detection research and represent the deepest AI signatures:

- **Low perplexity**: AI text scores 5-10 on perplexity metrics where human text scores 20-50. AI is too "expected" token by token.
- **Present participial clauses at 2-5x human rates** (CMU/PNAS finding).
- **Nominalizations at 1.5-2x human rates** (CMU/PNAS finding).
- **Genre insensitivity**: Writing the same way regardless of whether context calls for casual conversation or formal prose.
- **Probability curvature**: AI text sits near local maxima of probability space in ways human text does not (Stanford DetectGPT finding).

The best defense against Tier 3 patterns: vary sentence structure deliberately, use active voice with concrete verbs, match register to context, and include genuine authorial choices (positions, preferences, specific details) rather than safe generalizations.
