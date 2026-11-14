#!/usr/bin/env bash
# Cross-version compatibility: the addon as released at the baseline tag and the working copy, each in its own
# fake game client, exchange lines, greetings and settings (tests/compat.lua). Exit code is non-zero on any failure.
# Without the tag the test cannot run: that fails in CI (CI=true) and is a loud skip on a developer's machine.
set -euo pipefail
cd "$(dirname "$0")/.."

# The oldest release that must keep working with the code in this tree. Not "the previous release": players
# who installed it never update on our schedule. Raise it only when that release is deliberately dropped.
BASELINE=${BASELINE:-v0.2.0}

LUA=${LUA:-lua}
if ! git rev-parse -q --verify "refs/tags/$BASELINE^{commit}" >/dev/null; then
  echo "compat: the tag $BASELINE is not in this clone. Fetch it with: git fetch origin tag $BASELINE"
  if [ "${CI:-}" = "true" ]; then
    echo "FAIL compat: the cross-version test did not run"
    exit 1
  fi
  echo "SKIPPED compat: the cross-version test did NOT run; CI runs it"
  exit 0
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git archive "$BASELINE" CORELink | tar -x -C "$tmp"
"$LUA" tests/compat.lua "$tmp/CORELink" CORELink "$BASELINE"
