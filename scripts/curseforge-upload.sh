#!/usr/bin/env bash
# Upload a built zip to CurseForge, run by the release workflow after scripts/release.sh published an rc or a
# final. Reads the tag from dist/TAG (written by release.sh), the notes from the GitHub release, and the game
# versions from the TOC "## Interface:" numbers, matched by name against CurseForge's version list.
#
#   CURSEFORGE_API_KEY=... CURSEFORGE_PROJECT_ID=123456 scripts/curseforge-upload.sh [--check] [--tag vX.Y.Z] [--dry-run]
#
# --check talks to CurseForge with the key and reports whether the game versions match, without needing a
# release in dist/ and without uploading anything: the curseforge-check workflow button runs it, so a wrong key
# or version name shows up before the next rc instead of at the end of its job.
# --tag v0.2.0 uploads an existing GitHub release instead: its zip is downloaded into dist/ first and the game
# versions come from the TOCs inside that zip. For a release that shipped before CurseForge was set up, or a
# release whose upload step failed. CurseForge keeps every upload, so running it twice for one tag lists the file
# twice. --dry-run combines with either and stops before the upload.
# Optional: CURSEFORGE_GAME_VERSIONS="1.60.1,13.0.0" overrides the TOC-derived names when a flavour's name on
# CurseForge differs from the interface number convention (major*10000 + minor*100 + patch). A name CurseForge
# does not know fails the script: nothing is uploaded with a partial list.
# Without the key or the project id a release run prints why it skipped and exits 0, so a release never fails
# because CurseForge is not set up; --check and --tag exit 2 instead, so their button goes red.
set -euo pipefail
set +x                      # never trace this script: the API key is in its environment
cd "$(dirname "$0")/.."
MODE=upload; TAG_ARG=""; DRY=0
usage() { echo "usage: $0 [--check] [--tag vX.Y.Z[-rcN]] [--dry-run]"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --check)   MODE=check ;;
    --tag)     TAG_ARG=$(printf '%s' "${2:-}" | tr -d '[:space:]'); shift
               [[ "$TAG_ARG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || usage ;;
    *)         usage ;;
  esac
  shift
done
[ "$MODE" = check ] && [ -n "$TAG_ARG" ] && usage
API="https://wow.curseforge.com/api"

if [ -z "${CURSEFORGE_API_KEY:-}" ] || [ -z "${CURSEFORGE_PROJECT_ID:-}" ]; then
  echo "curseforge: skipped (CURSEFORGE_API_KEY secret or CURSEFORGE_PROJECT_ID variable not set)"
  if [ "$MODE" = check ] || [ -n "$TAG_ARG" ]; then exit 2; else exit 0; fi
fi
# The key goes to curl through a private header file, never on a command line (visible in ps and in traces)
# and never in anything this script prints. Every call records the HTTP status and the answer; an answer is
# shown only when it is JSON, which is what the API speaks, and with the key blanked out, because the API echoes
# a refused token back in its error message and a proxy page may echo headers.
HDR=$(umask 077 && mktemp); RESP=$(mktemp); META=$(mktemp); trap 'rm -f "$HDR" "$RESP" "$META"' EXIT
printf 'x-api-token: %s\n' "$CURSEFORGE_API_KEY" > "$HDR"
unset CURSEFORGE_API_KEY
call() {   # call <curl args...>: the answer lands in $RESP; prints "<HTTP status> <curl exit code>"
  local rc=0   # curl itself prints 000 as the status when it got no answer, and says why in its exit code
  curl -sS -m 120 -o "$RESP" -w '%{http_code}' -H "@$HDR" "$@" || rc=$?
  printf ' %s' "$rc"
}
json_answer() {   # the answer, if it is JSON (at most 400 characters) with the key blanked out, else what it was
  python3 -c '
import json, sys
raw = open(sys.argv[1], "rb").read()
key = open(sys.argv[2]).read().split(": ", 1)[1].strip()   # the API echoes a refused token back in its message
try: json.loads(raw); print(raw.decode("utf-8", "replace").replace(key, "<key>")[:400])
except Exception: print("(the answer was not JSON: %d bytes)" % len(raw))' "$RESP" "$HDR"
}

# ---- --tag: the zip of an existing GitHub release stands in for what release.sh would have built ------------
if [ -n "$TAG_ARG" ]; then
  mkdir -p dist
  gh release download "$TAG_ARG" --pattern 'CORELink-*.zip' --dir dist --clobber \
    || { echo "curseforge: could not download the CORELink zip of release $TAG_ARG (see gh's message above)"; exit 2; }
  printf '%s\n' "$TAG_ARG" > dist/TAG
fi
tocs() {   # the TOCs that describe the file being uploaded: inside the tag's zip, else the working tree's
  if [ -n "$TAG_ARG" ]; then v=${TAG_ARG#v}; unzip -p "dist/CORELink-${v%-rc*}.zip" 'CORELink/*.toc'; else cat CORELink/*.toc; fi
}

# ---- game versions: TOC interface numbers -> "major.minor.patch" -> CurseForge ids ----------------------
names="${CURSEFORGE_GAME_VERSIONS:-}"
if [ -z "$names" ]; then
  names=$(tocs | grep '^## Interface:' | sed 's/^## Interface://' | tr ',' '\n' | tr -d ' ' \
    | grep . | sort -u | awk '{
        if ($0 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) print $0;
        else { n = $0 + 0; printf "%d.%d.%d\n", int(n / 10000), int(n / 100) % 100, n % 100 } }' | sort -u | paste -sd, -)
fi
read -r status _ <<< "$(call "$API/game/versions")"
versions=$(python3 -c '
import json, sys
try:
    vs = json.load(open(sys.argv[1])); print(json.dumps(vs) if isinstance(vs, list) else "")
except Exception: print("")' "$RESP")
if [ -z "$versions" ]; then
  echo "curseforge: could not list game versions (HTTP $status; the API key is wrong, or not an author token from legacy.curseforge.com)"
  json_answer; exit 2
fi
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
[ -z "$missing" ] && [ -n "$ids" ] || { echo "curseforge: not every game version matched; nothing uploaded"; exit 2; }
echo "curseforge: key accepted; game versions $names -> ids $ids; project $CURSEFORGE_PROJECT_ID"
[ "$MODE" = check ] && exit 0

# ---- the file: tag from release.sh (or --tag), zip from dist/, notes from the GitHub release ---------------
[ -f dist/TAG ] || { echo "curseforge: dist/TAG missing; nothing was released in this run"; exit 0; }
TAG=$(tr -d '[:space:]' < dist/TAG)
VER=${TAG#v}; VER=${VER%-rc*}
ZIP="dist/CORELink-$VER.zip"
[ -f "$ZIP" ] || { echo "curseforge: $ZIP missing"; exit 2; }
case "$TAG" in
  *-rc*) TYPE=beta;    NAME="CORELink $VER rc${TAG##*-rc}" ;;
  *)     TYPE=release; NAME="CORELink $VER" ;;
esac
notes=$(gh release view "$TAG" --json body -q .body 2>/dev/null || true)
# CurseForge requires a changelog; a release whose notes are empty (or only whitespace, GitHub bodies end in CRLF)
# gets its name
[[ "$notes" =~ [^[:space:]] ]] || notes="CORELink $TAG"
# The metadata goes through a file, into python on stdin and into curl as "metadata=<file": notes can be longer
# than one argument may be (128 KB on Linux), and a value curl reads from a file is sent as it is, with no
# option parsing at a ";" (what -F does to a value on its command line; seen live on 2026-11-12).
printf '%s' "$notes" | python3 -c '
import json, sys
try:
    with open(sys.argv[4], "w") as f:
        json.dump({"changelog": sys.stdin.read(), "changelogType": "markdown", "displayName": sys.argv[1],
                   "gameVersions": [int(i) for i in sys.argv[2].split(",")], "releaseType": sys.argv[3]}, f)
except Exception as e:
    print("curseforge: could not build the metadata (%s); nothing uploaded" % e); sys.exit(2)' \
  "$NAME" "$ids" "$TYPE" "$META"
echo "curseforge: $NAME ($TYPE)"
if [ $DRY -eq 1 ]; then echo "[dry-run] would upload $ZIP to project $CURSEFORGE_PROJECT_ID"; exit 0; fi
# Success is a 2xx whose JSON answer carries the file id: a wrong path answers with a redirect or a page, and a
# status alone would call that fine.
read -r status rc <<< "$(call -F "metadata=<$META" -F "file=@$ZIP" "$API/projects/$CURSEFORGE_PROJECT_ID/upload-file")"
id=$(python3 -c '
import json, sys
try: print(json.load(open(sys.argv[1])).get("id") or "")
except Exception: print("")' "$RESP")
case "$status" in
  2??) [ -n "$id" ] || { echo "curseforge: upload failed: HTTP $status but no file id in the answer; nothing is listed."; json_answer; exit 2; } ;;
  4??) echo "curseforge: upload failed: HTTP $status; nothing is listed."; json_answer; exit 2 ;;
  000) case "$rc" in   # no answer: only a failure to connect proves the file never left
         6|7|35) echo "curseforge: upload failed: could not connect to CurseForge (curl exit $rc); nothing was sent." ;;
         *)      echo "curseforge: upload failed: no answer (curl exit $rc). The file may still have landed:" \
                      "check the project's files page before pressing curseforge-upload again." ;;
       esac; exit 2 ;;
  *)   echo "curseforge: upload failed: HTTP $status. The file may still have landed:" \
            "check the project's files page before pressing curseforge-upload again."; json_answer; exit 2 ;;
esac
echo "curseforge: uploaded $ZIP as file $id"
