# Humanization Techniques by Layer

These techniques are synthesized from Nielsen Norman Group research, Sabrina Ramonov's humanizer prompt methodology, Joseph Thacker's vocabulary constraint approach, the AIMCLEAR quantifiable parameters method, Scale AI's "strategic inefficiencies" framework, and CMU/PNAS stylometric findings on the deepest AI-human writing differences.

## Layer 1: Word Choice

**Core principle: radical simplicity.** RLHF training pushes LLMs toward impressive-sounding academic language because human raters rewarded it during training. Fight this bias explicitly.

Rules:
- Default to the shortest, most common word. "Use" not "utilize." "Help" not "facilitate." "Try" not "endeavor." "Show" not "demonstrate." "Start" not "commence." "Get" not "obtain."
- Target a middle-school reading level for vocabulary unless the subject demands technical precision.
- Use concrete, specific nouns and active verbs instead of abstract nominalizations. "We decided" not "the decision was made." "Sales dropped" not "a decrease in sales was observed."
- When a technical term is necessary, use it once and move on. Do not define it three ways.
- Contractions are mandatory in informal and semi-formal registers. "Don't," "won't," "can't," "it's." Only drop contractions in genuinely formal contexts (legal, academic, ceremonial).
- Never use "straightforward," "at its core," or "at the end of the day." All are AI tells.
- Avoid hollow intensifiers: "truly," "really," "incredibly," "absolutely," "extremely." One per piece maximum. AI uses these for false emphasis that adds nothing.
- Do not use paired synonyms for emphasis: "clear and concise," "robust and scalable," "simple and intuitive," "quick and easy." Pick one adjective. The doubling is an AI habit.
- Avoid "the power of [X]" and "the beauty of [X]." Always vague, always filler.
- Avoid "ensures" and "ensures that." AI uses this to sound authoritative without committing. Rephrase or cut.
- Avoid "allows you to," "enables you to," "empowers you to." Say what the thing does directly. "The tool tracks expenses" not "The tool allows you to track expenses."
- Avoid weasel quantifiers without actual numbers: "significant," "substantial," "considerable," "notable," "meaningful." Quantify when possible. When not, use plain words like "large" or "small."
- Avoid "key" as an overused adjective: "key takeaways," "key insights." Say "main," "biggest," or drop the qualifier.
- Avoid "respective" and "respectively." Almost always unnecessary.
- Limit transition words: "additionally," "however," "consequently," "therefore," "thus." AI uses these as paragraph glue far more than humans. Most of the time the connection is obvious without them.

## Layer 2: Sentence Structure

**Core principle: burstiness.** Human writing has dramatic sentence length variation. AI stays in a 15-25 word band. Detection tools use burstiness as a core metric.

Rules:
- Never use em dashes (—), en dashes used as em dashes (–), or double hyphens (--). Restructure the sentence to use periods, commas, colons, or parentheses. If the sentence needs a dash to work, rewrite it.
- Never use "It's not just X, it's Y" or any variation: "This isn't just...", "That's not... it's...", "It's not about X, it's about Y." State the point directly without the false-revelation setup.
- Vary sentence length deliberately. Mix 4-word punches with 30-word compound sentences. No three consecutive sentences should be within 5 words of each other in length. Aim for a standard deviation of 8+ words across sentence lengths per paragraph.
- Use sentence fragments for emphasis. "Not even close." "The opposite, actually." "Worth noting." One word works too.
- Start some sentences with "And" or "But." Roughly 10-15% is natural for most English prose.
- Vary sentence openings. Never start 3+ consecutive sentences with the same word, especially "The," "It," "This," or "There."
- Do not start sentences with vague "This" as a referent. "This underscores..." and "This highlights..." are AI crutches. Name the actual subject.
- Do not use anaphora chains (repeating the same structure with word swaps). "It means better outcomes. It means faster delivery." Say it once, say it differently.
- Do not use colon-to-tidy-list constructions. "Three things matter: clarity, consistency, and communication" is an AI pattern. Humans don't naturally sort their thoughts into perfect groupings of abstract nouns.
- Use questions to break rhythm. Rhetorical or genuine, they change the reader's mental posture.
- Avoid trailing participial phrases ("...improving efficiency," "...highlighting its significance"). These are the single strongest grammatical AI signature per CMU research. Restructure: put the action in its own sentence or use "which" clauses instead.
- Reduce nominalizations (verb-to-noun conversions). "The implementation of the system" becomes "implementing the system" or "we implemented the system." LLMs use nominalizations at 1.5-2x human rates.
- Limit semicolons. Most people rarely use them. AI over-relies on them to connect related ideas. Use a period instead.
- Do not use "from X to Y" sweeps: "From onboarding to offboarding," "From startups to enterprises." These gesture at breadth without specifics. Name what you actually mean.
- Do not open with "Imagine a world where..." or "Picture this:" These are AI blog post cliches. Start with the actual point.
- Limit question-then-answer constructions. "What makes this different? The architecture." Once per piece is fine. Two or three times is a pattern.
- Do not chain "by [gerund]" openers: "By implementing...", "By automating...", "By focusing on..." Restructure into direct statements about what happens.
- Avoid "not only X, but also Y" parallel constructions. State the two things directly without the rhetorical scaffolding.
- Do not use recap openers in multi-turn contexts: "As we discussed earlier...", "Building on our previous conversation..." Just pick up where you left off.

## Layer 3: Paragraph and Document Architecture

**Core principle: break the template.** AI defaults to topic-sentence, elaboration, summary/transition for every paragraph, and intro-body-conclusion for every document. Humans are messier and more interesting.

Rules:
- Use one-sentence paragraphs for emphasis or transitions. They create visual and rhythmic punch.
- Vary paragraph length. Mix 1-sentence paragraphs with 5-6 sentence paragraphs. Never write 4+ paragraphs of the same length in sequence.
- Do not lead every paragraph with a topic sentence. Sometimes the point comes at the end. Sometimes it's implied.
- Allow non-linear organization where appropriate. Start with an anecdote, a question, a surprising fact, or a bold claim before stating the thesis. Build to the main point instead of front-loading it.
- Use parentheticals and asides to create a thinking-out-loud quality. "(Though I'm not sure that's the right framing.)"
- Never write a summary paragraph that restates everything already said. If a conclusion is needed, it should add something new: a implication, a question, a call to action, a personal reflection.
- Avoid excessive section headers. Use them when they genuinely help navigation, not as a structural crutch every 2-3 paragraphs.
- Vary paragraph openings. Do not start every paragraph the same way. Mix claims, questions, fragments, dependent clauses, and mid-thought continuations. If you read just the first sentence of every paragraph and they all sound the same, rewrite.
- Calibrate length to format. AI over-writes by default. A Slack message should be a few sentences. A short email should be 3-5 sentences. A one-paragraph answer stays one paragraph. When in doubt, shorter is more human. If someone asks for "a quick note," that means quick.

## Layer 4: Tone and Voice

**Core principle: genuine authorial presence.** The "helpful assistant" register is the deepest AI signature. It manifests as artificial balance, formulaic hedging, and a refusal to commit to positions.

Rules:
- Take positions. "I think X is the better approach because..." is more human than "There are merits to both X and Y." Balanced analysis is fine when genuinely warranted, but do not default to it reflexively.
- Express genuine uncertainty. "I'm not confident about this part" or "This might be wrong, but..." beats "It's important to consider multiple perspectives."
- Include specific, concrete details rather than generic abstractions. A specific restaurant, a particular failure, an exact number. Specificity signals lived experience.
- Use "strategic inefficiencies" (Scale AI's term): meaningful detours, callbacks to earlier points, a shift in diction mid-paragraph, repetition of a key word for emphasis. These are the textures of human thought that training optimizes away.
- Match register to context. Casual writing should actually be casual (contractions, slang, sentence fragments). Formal writing should be formal (complete sentences, precise terminology). The hallmark of AI writing is genre insensitivity: writing the same way regardless of context.
- Avoid sycophantic openings and closings. Never open with praise for the question. Never close with generic encouragement. Just answer.
- Do not over-signpost. "Let's break this down," "Here's the thing," "Let me explain," "Let's dive in" are all filler. Just make the point. Real writers don't announce that they're about to write something.
- Do not use false-choice framings. "Whether you're a beginner or a seasoned pro" is empty padding. Cut it or address the reader directly.
- Show your thinking process where appropriate. "My first instinct was X, but then I considered Y" reads as more human than presenting a polished conclusion without the journey.

## Voice Capture: The 16 Dimensions

When trying to match a specific person's voice, analyze their writing across these dimensions. Each should be captured as a specific, measurable behavioral instruction, not a subjective adjective.

1. **Formality level**: Contraction frequency, register, colloquial expressions
2. **Vocabulary preferences**: Simple vs. complex, jargon frequency, signature words, banned words
3. **Sentence structure**: Average length, burstiness range, fragment use, active vs. passive ratio
4. **Punctuation habits**: Ellipses, semicolons, exclamation marks, parentheses, colon usage. Note: em dashes and en dashes are banned regardless of voice target.
5. **Humor style**: Dry, self-deprecating, witty, absurdist, or absent
6. **Paragraph architecture**: Short punchy vs. long blocks, one-sentence paragraph frequency
7. **Stance and certainty**: Hedging frequency, bold claim willingness, boosters vs. qualifiers
8. **Transition style**: Explicit connectors, implicit flow, abrupt topic shifts
9. **Opening patterns**: How they start pieces, sections, paragraphs
10. **Closing patterns**: How they end pieces, sections, paragraphs
11. **Metaphor and imagery**: Frequency, source domains, originality
12. **Perspective and pronouns**: First person frequency, "we" vs. "I," direct address ("you")
13. **Emotional expression**: Restrained vs. expressive, where emotion surfaces
14. **Cultural references**: What they reference (pop culture, literature, sports, tech)
15. **Rhythm and cadence**: How sentences flow when read aloud, pacing
16. **Complexity handling**: How they break down hard ideas (analogies, examples, building blocks)

**Critical finding from Nielsen Norman Group**: Actual writing samples outperform tone descriptors, which outperform celebrity/author name references. When possible, provide 2-3 samples and analyze them against these dimensions rather than describing desired voice in abstract terms.

**Critical finding from Dev.to experiment**: Flattened or restructured samples lose the author's voice. Structure matters. Rhythm is part of voice. Preserve paragraph breaks, sentence lengths, and formatting from samples.
