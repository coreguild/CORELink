# Handling a feature request

Vague requests produce code nobody asked for. Before writing any Lua for a new feature:

1. **Restate it** in two or three lines: what the player sees or types, who it affects (members, GM, linked
   guilds), and whether anything travels over the wire.
2. **Ask** about anything that changes the design and is not stated. Typical gaps: Should it be on by default?
   Per client or shared via the Guild Info line? Does it need to reach other guilds (protocol change) or only this
   client (display only)? What happens for members on an older version?
   Ask these before coding, not after. If the user is unavailable, state your assumptions explicitly in the PR
   under "Open questions" and pick the least-invasive option.
3. **Write the acceptance checks first** as `check(...)` lines in `tests/harness.lua`. They must fail before your
   change and pass after. A feature without a harness check is not done.
4. **Implement**, keeping the WoW constraints in `wow-api-gotchas.md` in mind.
5. **Document**: README command table and the PR template's "Feature notes" section filled in completely. Do not
   touch `## Version:` in the TOCs (it stays `@project-version@`); say in the PR whether the change is patch, minor
   or major so whoever presses the release button picks the right bump.

The PR template is the contract. A PR with an empty "Feature notes" or unchecked "Tests" boxes is not ready.
