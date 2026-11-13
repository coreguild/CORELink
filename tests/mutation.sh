#!/usr/bin/env bash
# When the addon changed, the harness in the working tree must fail against the base's addon files: proof that at
# least one check depends on this change. It is not proof that every behaviour change has a check; the self-review
# walks the diff for that. Compares the working tree with the merge-base of HEAD and the base, so it means the
# same thing before a commit, on a branch behind main, and on the CI merge commit.
#   tests/mutation.sh [origin/main]
# Nothing to prove when every changed Lua file compiles to the same bytecode (luac -s strips comments, whitespace
# and local names), or when MUTATION_EXEMPT=true (CI sets it for PRs titled "refactor": a claim the author makes,
# and the self-review still walks the diff).
set -euo pipefail
cd "$(dirname "$0")/.."
base=${1:-origin/main}; LUA=${LUA:-lua}; LUAC=${LUAC:-luac}
mb=$(git merge-base "$base" HEAD)
if git diff --quiet "$mb" -- CORELink/; then echo "mutation: addon unchanged against $base; nothing to prove"; exit 0; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/base" "$tmp/run"
git archive "$mb" CORELink | tar -x -C "$tmp/base"

same_bytecode() {   # every changed Lua file compiles, stripped, to what the base compiled to
  local f
  for f in $(git diff --name-only "$mb" -- 'CORELink/*.lua'); do
    [ -f "$f" ] && [ -f "$tmp/base/$f" ] || return 1
    "$LUAC" -s -o "$tmp/a.out" "$tmp/base/$f" 2>/dev/null && "$LUAC" -s -o "$tmp/b.out" "$f" 2>/dev/null || return 1
    cmp -s "$tmp/a.out" "$tmp/b.out" || return 1
  done
}
if same_bytecode; then echo "mutation: the changed addon files compile to the same bytecode as $base; nothing to prove"; exit 0; fi
if [ "${MUTATION_EXEMPT:-}" = "true" ]; then
  echo "mutation: skipped, the PR is titled refactor: the author claims no behaviour change; the self-review walks the diff"; exit 0
fi

cp -R tests "$tmp/run/tests" && cp -R "$tmp/base/CORELink" "$tmp/run/CORELink"
if (cd "$tmp/run" && "$LUA" tests/harness.lua > "$tmp/harness.txt" 2>&1); then
  echo "FAIL mutation: the harness passes against $base's addon files, so no check fails without this change."
  echo "      Add a check(...) to tests/harness.lua that this change makes pass, or title the PR refactor if it changes no behaviour."
  exit 1
fi
n=$(grep -c '^FAIL' "$tmp/harness.txt" || true)
if [ "$n" -eq 0 ]; then
  echo "FAIL mutation: the harness errors against $base's addon files instead of failing a check:"
  tail -3 "$tmp/harness.txt" | sed 's/^/      /'
  echo "      Guard what the harness needs from this change (if NS.X then ... end, or pcall) so the check fails rather than crashes."
  exit 1
fi
echo "mutation ok: $n check(s) fail against $base's addon files:"; grep '^FAIL' "$tmp/harness.txt" | head -5 | sed 's/^/      /'
