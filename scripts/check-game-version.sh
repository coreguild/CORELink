#!/usr/bin/env bash
# Compare the addon's TOC "## Interface:" numbers with the live game client version from Blizzard's
# public version server. Exit 0 when the live interface number is listed in every TOC, 1 when not, 2 on error.
#
#   scripts/check-game-version.sh            # product from tests/game-product.txt (default wow_classic_beta)
#   PRODUCT=wow_classic scripts/check-game-version.sh
#
# Interface number convention: major*10000 + minor*100 + patch, e.g. 1.60.1 -> 16001, 1.15.7 -> 11507.
set -euo pipefail
cd "$(dirname "$0")/.."
PRODUCT="${PRODUCT:-$(tr -d '[:space:]' < tests/game-product.txt 2>/dev/null || echo wow_classic_beta)}"
REGION="${REGION:-us}"
URL="https://${REGION}.version.battle.net/${PRODUCT}/versions"
body=$(curl -fsS -m 20 "$URL") || { echo "ERROR: could not fetch $URL"; exit 2; }
row=$(printf '%s\n' "$body" | grep -m1 "^${REGION}|") || { echo "ERROR: no '${REGION}' row in versions file"; exit 2; }
version=$(printf '%s' "$row" | awk -F'|' '{print $6}')      # e.g. 1.60.1.70205
build=$(printf '%s' "$row" | awk -F'|' '{print $5}')
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
