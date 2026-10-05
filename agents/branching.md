# Branching and commits

1. `git fetch origin && git switch -c <type>/<short-name> origin/main`
   where type is `feat`, `fix`, `docs` or `chore`. One change per branch.
2. Commit in small steps with imperative subjects. Mention the agent in a `Co-Authored-By:` trailer.
3. Before pushing: `tests/run.sh` must pass. Do not push with failing tests.
4. Push and open a PR into `main` with: what changed, why, how it was tested (harness + in game or "not verified in game").
5. Never push to `main`. Never force-push a shared branch. Never rewrite history on `main`.
6. If the user asks to "just commit", still create a branch; ask before merging anything.
