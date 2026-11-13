---
name: unslop
description: Cut AI tells from prose. README, docs, agent rules, skills, PR bodies, commit subjects, changelog lines and code comments, not code. Manual only (/unslop); the self-review reads this file and applies it to changed prose.
disable-model-invocation: true
---

# Unslop

Edit prose to remove the patterns below. Keep the meaning and the author's tone; change nothing else. Work on the
changed lines of the diff, not the whole file, unless asked for the whole file. Report what you changed and why,
by rule number, so the author can push back.

In scope: `README.md`, `docs/`, `agents/`, `.claude/skills/`, `CONTRIBUTING.md`, `ONBOARDING.md`, PR bodies,
commit subjects, changelog lines, and comments in Lua and shell. Out of scope: code, command output, error text,
quoted game messages, and anything inside a code fence.

Kept as they are, because the repository uses them on purpose:

* UI navigation paths with arrows and bold names: `GitHub -> Actions -> **release** -> **Run workflow**`.
* The labelled fields of `.github/pull_request_template.md` ("**Commands added/changed:** ...") in a PR body.
* The `* path - description` lists in `AGENTS.md` and the tables in `docs/`.
* File header comments and the comment on every `NS` key, which `CONTRIBUTING.md` requires.
* Limits stated in a rule ("a file under 400 lines, a function under 40").

The rule numbers are the ids of the general unslop skill this copy was trimmed from, which already skipped 1, 2,
4, 6 and 21; this copy also drops 5 and 12. The numbers stay so that "rule 27" means the same thing in both, and a
self-review report can cite them. Rules of this project start at 40.

## Words of this project that are not tells

harness (`tests/harness.lua`), courier, relay, mirror, echo, fan-out, lockdown, hardware event, Guild Info, channel,
whisper, feature (the PR template's "Feature notes"). They name things in the addon. Leave them, and add to this
list rather than fighting the rule below each time.

## Content

3. **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...". Delete, or
   replace with the fact.

## Language

7. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate,
   landscape (abstract), pivotal, showcase, tapestry, testament, underscore, vibrant. Replace with plain words.
8. **Fancy ways to say "is".** "serves as", "stands as", "boasts". Say "is" or "has".
9. **"Not just X, but Y."** State the point directly.
10. **Rule of three.** Use the natural number of items, not three.
11. **Synonym cycling.** One name per thing, repeated. The addon's names are the project list above; use them.

## Style

13. **Em dashes.** None. End the sentence or use a comma. No parentheses or hyphens standing in for a dash.
14. **Colons as connectors.** A colon introduces a list or an example. Mid-sentence, rewrite without it.
15. **Boldface.** Not on every proper noun or acronym.
16. **Inline-header lists.** A bold label and colon that restates the line ("**Tests:** tests pass") becomes
    prose. A bold lead-in ending in a period, followed by new detail, is fine. The PR template's fields stay.
17. **Headings in sentence case.**
18. **Emoji.** None in headings or bullets. The PR footer line is the one exception.
19. **Straight quotes.**

## Communication artifacts

20. **Chatbot phrases.** "I hope this helps", "Let me know if", "Certainly", "Found the smoking gun". Remove.
22. **Sycophancy.** "Great question", "You're absolutely right". Remove.

## Filler

23. **Filler phrases.** "In order to" is "To". "Due to the fact that" is "Because". "It is important to note
    that" goes.
24. **Hedging stacks.** "could potentially possibly" is "may".
25. **Generic conclusions.** "The future looks bright." Replace with the plan or the fact, or cut.

## Jargon

26. **Metaphor nouns.** Substrate, wedge, vector (as "way"), locus, nexus, primitive (as a noun), surface (as in
    "API surface"), bedrock, scaffolding, paradigm, north star, flywheel. Use the concrete word. "Harness" is on
    the project list above; it is the real name of the test file.

## Plain speech

27. **Say what it does, not how it feels.** "the relay stays out of your way" names a feeling. Name the
    mechanism or the number: "the relay sends at most one message a second". If a sentence could sit unchanged
    in another addon's README, it says nothing about this one. Cut it.
28. **One idea per sentence.** If the reader has to backtrack, split it.
29. **Active voice.** "messages are queued" is "the relay queues messages". Passive only when the actor is
    unknown or does not matter.
30. **Adverbs.** "runs quickly" is "is fast" or the number. "Significantly improves" is the measured change.
31. **The plain word.** utilize and leverage are "use"; facilitate is "help"; numerous is "many"; "in the event
    that" is "if".
32. **Mannered prose.** Aphorisms, rhetorical fragments, personified code, figurative verbs. Say what you mean.
    The addon's own metaphors (courier, relay, mirror) are names, not flourish.
33. **Over-compression.** Dropped articles, verbless fragments, arrows, unexplained abbreviations. Write whole
    sentences, spell out the arrow, expand the abbreviation the first time.

## Rules of this project

40. **Commit subjects are changelog lines.** Players read them. The form is `CONTRIBUTING.md`'s
    (`type(scope): what changed`); the content is the behaviour, not the file: no "various fixes", no "update
    X". Fix the wording before the push; a pushed subject stays, since merge commits keep every one.
41. **Comments say why, not what.** A comment that restates the line below it goes. The exceptions are listed at
    the top: file headers and `NS` key comments are documentation, not narration. Rule 27 applies to comments.
