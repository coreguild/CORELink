#!/usr/bin/env bash
# Every behaviour change needs a harness check that fails without it. This proves the second half: when the
# addon differs from the base branch, the branch's harness is run against the base branch's addon files and
# must fail there. CI runs it on every pull request; locally: tests/mutation.sh origin/main
# MUTATION_EXEMPT=true skips it (refactor, chore, docs and style PRs: the title decides in CI).
set -euo pipefail
cd "$(dirname "$0")/.."
base=${1:-origin/main}
LUA=${LUA:-lua}
if git diff --quiet "$base" -- CORELink/; then echo "mutation: addon unchanged against $base; nothing to prove"; exit 0; fi
if [ "${MUTATION_EXEMPT:-}" = "true" ]; then echo "mutation: skipped, the PR is exempt (no behaviour change claimed)"; exit 0; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git archive HEAD | tar -x -C "$tmp"
rm -rf "$tmp/CORELink"
git archive "$base" CORELink | tar -x -C "$tmp"
if (cd "$tmp" && "$LUA" tests/harness.lua > "$tmp/harness.txt" 2>&1); then
  echo "FAIL mutation: the harness passes against $base's addon files, so no check fails without this change."
  echo "      Add a check(...) to tests/harness.lua that this change makes pass, or mark the PR refactor/chore."
  exit 1
fi
n=$(grep -c '^FAIL' "$tmp/harness.txt" || true)
if [ "$n" -eq 0 ]; then
  echo "mutation ok: the harness cannot run against $base's addon files (it errors), so it depends on this change"
else
  echo "mutation ok: $n check(s) fail against $base's addon files:"; grep '^FAIL' "$tmp/harness.txt" | head -5 | sed 's/^/      /'
fi
