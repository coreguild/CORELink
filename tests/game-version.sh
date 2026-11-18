#!/usr/bin/env bash
# scripts/check-game-version.sh is a required check: it must fail on a mismatch and on a version file it cannot
# read, and pass an unreachable server only when asked to. The version file is a local one; no network.
set -uo pipefail
cd "$(dirname "$0")/.."
box=$(mktemp -d); trap 'rm -rf "$box"' EXIT
fail=0
listed=$(grep -m1 '^## Interface:' CORELink/CORELink_Camelot.toc | grep -oE '[0-9]{5,6}' | tail -1)
dotted="$((listed / 10000)).$((listed / 100 % 100)).$((listed % 100))"
row() { printf 'Region!STRING:0|BuildConfig|CDNConfig|KeyRing|BuildId|VersionsName|ProductConfig\nus|a|b|c|70938|%s|d\n' "$1"; }
expect() {   # expect <exit code> <what> <text the output must contain> <args...>
  local want=$1 what=$2 text=$3; shift 3
  local out got; out=$(VERSIONS_URL="file://$box/versions" scripts/check-game-version.sh "$@" 2>&1); got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$out" | grep -qF -- "$text"; then echo "PASS game version: $what exits $want"
  else echo "FAIL game version: $what exits $got, expected $want with '$text'"; printf '%s\n' "$out"; fail=1; fi
}
row "$dotted.70938" > "$box/versions"; expect 0 "the interface the TOCs list" "TOC interface matches"
row "9.87.6.11111" > "$box/versions";  expect 1 "an interface no TOC lists" "MISMATCH"
expect 1 "a mismatch with --outage-ok" "MISMATCH" --outage-ok
row "" > "$box/versions";              expect 2 "a row without a version" "ERROR: no version"
printf 'not a versions file\n' > "$box/versions"; expect 2 "a file without our region" "ERROR: no 'us' row"
rm -f "$box/versions";                 expect 2 "a version file that cannot be fetched" "ERROR: could not fetch"
expect 0 "the same with --outage-ok" "::warning::game version not checked" --outage-ok
exit $fail
