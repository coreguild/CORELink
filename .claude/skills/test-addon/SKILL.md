---
name: test-addon
description: Syntax-check CORELink and run the mock WoW API harness. Use before any commit or when asked whether a change works.
---

1. From the repo root run `tests/run.sh`.
2. If `lua` is missing, tell the user the install command for their OS (macOS `brew install lua`) and stop; do not try to work around it.
3. Read every `FAIL` line. Fix the addon or the mock, not the assertion, unless the assertion is wrong and you can say why.
4. When adding behaviour, add a `check("...", cond, detail)` to `tests/harness.lua` that would have failed before your change.
5. Report: number of checks, failures, and the sentence "not verified in game" unless a human has run the in-game steps in `agents/testing.md`.
