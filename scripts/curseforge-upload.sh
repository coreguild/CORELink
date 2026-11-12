#!/usr/bin/env bash
# Upload a built zip to CurseForge, run by the release workflow after scripts/release.sh published an rc or a
# final. Reads the tag from dist/TAG (written by release.sh), the notes from the GitHub release, and the game
# versions from the TOC "## Interface:" numbers, matched by name against CurseForge's version list.
#
#   CURSEFORGE_API_KEY=... CURSEFORGE_PROJECT_ID=123456 scripts/curseforge-upload.sh [--dry-run|--check|--tag vX.Y.Z]
#
# --check talks to CurseForge with the key and reports whether the game versions match, without needing a
# release in dist/ and without uploading anything: the curseforge-check workflow button runs it, so a wrong key
# or version name shows up before the next rc instead of at the end of its job.
# --tag v0.2.0 uploads an existing GitHub release instead: its zip is downloaded into dist/ first. For a release
# that shipped before CurseForge was set up, or a release whose upload step failed. CurseForge keeps every
# upload, so running it twice for one tag lists the file twice.
# Optional: CURSEFORGE_GAME_VERSIONS="1.60.1,13.0.0" overrides the TOC-derived names when a flavour's name on
# CurseForge differs from the interface number convention (major*10000 + minor*100 + patch).
# Without the key or the project id the script prints why it skipped and exits 0, so a release never fails
# because CurseForge is not set up.
set -euo pipefail
set +x                      # never trace this script: the API key is in its environment
cd "$(dirname "$0")/.."
MODE=upload; TAG_ARG=""
case "${1:-}" in
  --dry-run) MODE=dry ;;
  --check)   MODE=check ;;
  --tag)     TAG_ARG=${2:-}
             [[ "$TAG_ARG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || { echo "usage: $0 --tag vX.Y.Z[-rcN]"; exit 2; } ;;
  "")        ;;
  *)         echo "usage: $0 [--dry-run|--check|--tag vX.Y.Z]"; exit 2 ;;
esac
API="https://wow.curseforge.com/api"

if [ -z "${CURSEFORGE_API_KEY:-}" ] || [ -z "${CURSEFORGE_PROJECT_ID:-}" ]; then
  echo "curseforge: skipped (CURSEFORGE_API_KEY secret or CURSEFORGE_PROJECT_ID variable not set)"
  if [ "$MODE" = check ] || [ -n "$TAG_ARG" ]; then exit 2; else exit 0; fi
fi
# The key goes to curl through a private header file, never on a command line (visible in ps and in traces)
# and never in anything this script prints. curl -s keeps its own output quiet; -f turns an HTTP error into
# a non-zero exit, which is the only thing reported about it.
HDR=$(umask 077 && mktemp); trap 'rm -f "$HDR"' EXIT
printf 'x-api-token: %s\n' "$CURSEFORGE_API_KEY" > "$HDR"
unset CURSEFORGE_API_KEY

# ---- game versions: TOC interface numbers -> "major.minor.patch" -> CurseForge ids ----------------------
names="${CURSEFORGE_GAME_VERSIONS:-}"
if [ -z "$names" ]; then
  names=$(cat CORELink/*.toc | grep '^## Interface:' | sed 's/^## Interface://' | tr ',' '\n' | tr -d ' ' \
    | grep . | sort -u | awk '{
        if ($0 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) print $0;
        else { n = $0 + 0; printf "%d.%d.%d\n", int(n / 10000), int(n / 100) % 100, n % 100 } }' | sort -u | paste -sd, -)
fi
versions=$(curl -fsS -m 30 -H "@$HDR" "$API/game/versions") \
  || { echo "curseforge: could not list game versions (the API key is wrong, or not an author token from legacy.curseforge.com)"; exit 2; }
ids=""; missing=""
for name in $(printf '%s' "$names" | tr ',' ' '); do
  found=$(printf '%s' "$versions" | python3 -c '
import json, sys
name = sys.argv[1]
print(",".join(str(v["id"]) for v in json.load(sys.stdin) if v.get("name") == name))' "$name")
  if [ -n "$found" ]; then ids="${ids:+$ids,}$found"; else missing="${missing:+$missing,}$name"; fi
done
if [ -n "$missing" ]; then
  echo "curseforge: no game version named $missing on CurseForge; set CURSEFORGE_GAME_VERSIONS to the names it uses"
  echo "curseforge: names it does use, newest first:"
  printf '%s' "$versions" | python3 -c '
import json, sys
vs = sorted(json.load(sys.stdin), key=lambda v: v.get("id", 0), reverse=True)[:40]
print("  " + ", ".join(v.get("name", "?") for v in vs))'
fi
[ -n "$ids" ] || { echo "curseforge: no game version matched; nothing uploaded"; exit 2; }
echo "curseforge: key accepted; game versions $names -> ids $ids; project $CURSEFORGE_PROJECT_ID"
[ "$MODE" = check ] && { [ -z "$missing" ] && exit 0 || exit 2; }

# ---- the file: tag from release.sh (or --tag), zip from dist/, notes from the GitHub release ---------------
if [ -n "$TAG_ARG" ]; then
  mkdir -p dist
  gh release download "$TAG_ARG" --pattern 'CORELink-*.zip' --dir dist --clobber \
    || { echo "curseforge: no GitHub release $TAG_ARG with a CORELink zip"; exit 2; }
  printf '%s\n' "$TAG_ARG" > dist/TAG
fi
[ -f dist/TAG ] || { echo "curseforge: dist/TAG missing; nothing was released in this run"; exit 0; }
TAG=$(tr -d '[:space:]' < dist/TAG)
VER=${TAG#v}; VER=${VER%-rc*}
ZIP="dist/CORELink-$VER.zip"
[ -f "$ZIP" ] || { echo "curseforge: $ZIP missing"; exit 2; }
case "$TAG" in
  *-rc*) TYPE=beta;    NAME="CORELink $VER rc${TAG##*-rc}" ;;
  *)     TYPE=release; NAME="CORELink $VER" ;;
esac
notes=$(gh release view "$TAG" --json body -q .body 2>/dev/null || echo "CORELink $TAG")
metadata=$(python3 -c '
import json, sys
print(json.dumps({"changelog": sys.argv[1], "changelogType": "markdown", "displayName": sys.argv[2],
                  "gameVersions": [int(i) for i in sys.argv[3].split(",")], "releaseType": sys.argv[4]}))' \
  "$notes" "$NAME" "$ids" "$TYPE")
echo "curseforge: $NAME ($TYPE)"
if [ "$MODE" = dry ]; then echo "[dry-run] would upload $ZIP to project $CURSEFORGE_PROJECT_ID"; exit 0; fi
out=$(curl -fsS -m 120 -H "@$HDR" -F "metadata=$metadata" -F "file=@$ZIP" \
  "$API/projects/$CURSEFORGE_PROJECT_ID/upload-files") || { echo "curseforge: upload failed"; exit 2; }
echo "curseforge: uploaded $ZIP, file id $(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id"))')"
