## What this changes

<!-- One or two sentences a guild member would understand. -->

## Feature notes

<!-- Required for any user-visible change. Delete this section for pure refactors/docs. -->
- **Player-facing behaviour:** what someone sees or types that is new or different
- **Commands added/changed:** `/cl ...` (also update the table in README.md)
- **Config / Guild Info line impact:** none | new optional field | breaking
- **Wire protocol impact:** none | new field, PROTO bumped to CLx, older versions still readable
- **Size of change for the release:** patch (fix) | minor (feature) | major (players must all update together)

(The PR title becomes a line in the auto-generated release notes. Write it for a player.)

## Tests

- [ ] `tests/run.sh` passes locally
- [ ] New or changed behaviour has a `check(...)` in `tests/harness.lua` that fails without this change
- [ ] In-game test done (who, which two guilds, what was typed and seen), or "not verified in game"

## Gameplay impact review

<!-- Reviewer (human or agent) walks agents/review-checklist.md and posts the verdict as a PR comment. -->
- [ ] No protected chat calls outside a hardware event; all outgoing traffic goes through the rate-limited queue
- [ ] No new Print/chat spam on timers or per event; no unbounded tables
- [ ] Works when not in a guild / not configured / channel not joined / lockdown; older protocol versions still readable
- [ ] `game-version` CI check is green (TOC interface matches the live client)

## Open questions

<!-- Anything you were unsure about and how you decided. If the request was ambiguous, list the clarifying questions you asked and the answers. -->
