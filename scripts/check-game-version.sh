#!/usr/bin/env bash
# Compare the addon's TOC "## Interface:" numbers with the live game client version from Blizzard's
# public version server. Exit 0 when the live interface number is listed in every TOC, 1 when not, 2 on error.
#
#   scripts/check-game-version.sh            # product from tests/game-product.txt (default wowf, WoW: Forever)
#   PRODUCT=wow_classic scripts/check-game-version.sh
#   scripts/check-game-version.sh --outage-ok   # a version server that cannot be fetched is a warning and exit 0
#                                               # (pull requests: its outage must not block every merge)
# VERSIONS_URL replaces the address (tests/game-version.sh points it at a file).
#
# Interface number convention: major*10000 + minor*100 + patch, e.g. 1.60.1 -> 16001, 1.15.7 -> 11507.
set -euo pipefail
cd "$(dirname "$0")/.."
PRODUCT="${PRODUCT:-$(tr -d '[:space:]' < tests/game-product.txt 2>/dev/null || echo wowf)}"
REGION="${REGION:-us}"
URL="${VERSIONS_URL:-https://${REGION}.version.battle.net/${PRODUCT}/versions}"
OUTAGE_OK=0; [ "${1:-}" = "--outage-ok" ] && OUTAGE_OK=1
body=$(curl -fsS -m 20 --retry 2 "$URL") || {
  if [ $OUTAGE_OK -eq 1 ]; then echo "::warning::game version not checked: could not fetch $URL"; exit 0; fi
  echo "ERROR: could not fetch $URL"; exit 2
}
row=$(printf '%s\n' "$body" | grep -m1 "^${REGION}|") || { echo "ERROR: no '${REGION}' row in versions file"; exit 2; }
version=$(printf '%s' "$row" | awk -F'|' '{print $6}')      # e.g. 1.60.1.70205
build=$(printf '%s' "$row" | awk -F'|' '{print $5}')
# Anything but a version here means the file changed shape: an error, not "the game moved to interface 0".
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "ERROR: no version in the '${REGION}' row: $row"; exit 2; }
IFS=. read -r major minor patch _ <<< "$version"
live=$(( major * 10000 + minor * 100 + patch ))
echo "live client ($PRODUCT/$REGION): $version (build $build) -> interface $live"
status=0
for toc in CORELink/*.toc; do
  listed=$(grep -m1 '^## Interface:' "$toc" | sed 's/^## Interface://' | tr ',' ' ')
  if printf ' %s ' $listed | grep -q " $live "; then
    echo "ok       $toc lists $live"
  else
    echo "MISMATCH $toc lists [$(echo $listed)] but live client is $live"
    status=1
  fi
done
[ $status -eq 0 ] && echo "TOC interface matches the live client." || echo "Update '## Interface:' in the TOC(s) above (keep older numbers if players may still be on them)."
exit $status
