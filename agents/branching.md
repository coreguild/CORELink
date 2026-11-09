# Branching and commits

1. `git fetch origin && git switch -c <type>/<short-name> origin/main`
   where type is `feat`, `fix`, `docs` or `chore`. One change per branch.
2. Commit in small steps with imperative subjects. Mention the agent in a `Co-Authored-By:` trailer.
3. Before pushing: `tests/run.sh` must pass. Do not push with failing tests.
4. Push and open a PR into `main` with: what changed, why, how it was tested (harness + in game or "not verified in game").
   Commit subjects become changelog lines and must follow Conventional Commits: `feat(scope): ...`, `fix: ...`,
   `docs: ...`, `chore: ...`, with `!` for breaking changes. Avoid `wip` commits; squash them locally.
5. Never push to `main`. Never force-push a shared branch. Never rewrite history on `main`.
6. If the user asks to "just commit", still create a branch.
7. Never merge. Not with `gh pr merge`, not with auto-merge, not by pushing to `main`. Report "PR #n is ready to
   merge: CI green, review posted" and stop. A human presses the button. If the user says "merge it", point them
   at the button; do not do it for them.
8. Release branches are the one place an agent merges: `release/<version>` is created from `main`, feature
   branches are merged into it (`git merge origin/feat/x`), and release candidates are cut from it. It reaches
   `main` through a PR like any other branch. See `skills/release/SKILL.md`.
