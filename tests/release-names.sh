#!/usr/bin/env bash
# A release candidate carries its rc number (#19): 0.3.0-rc1 in the TOC, CORELink-0.3.0-rc1.zip, its own path on
# the site; the final keeps 0.3.0. Checked here without the network: the names derived from a tag, what
# scripts/package.sh stamps, and what scripts/release.sh --dry-run says it would build. git and gh see a
# throwaway repository and a stand-in; nothing is tagged, released or pushed anywhere real.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd); fail=0
box=$(mktemp -d); trap 'rm -rf "$box"' EXIT
pass() { echo "PASS release names: $1"; }
flop() { echo "FAIL release names: $1"; fail=1; }
is()    { if [ "$2" = "$3" ]; then pass "$1"; else flop "$1: got '$2', expected '$3'"; fi; }  # label got expected
says()  { if printf '%s' "$2" | grep -qF -- "$3"; then pass "$1"; else flop "$1: no '$3'"; fi; }  # label text part
quiet() { if printf '%s' "$2" | grep -qF -- "$3"; then flop "$1: has '$3'"; else pass "$1"; fi; }

# ---- names from a tag ------------------------------------------------------------------------------------
. scripts/release-names.sh
is "a candidate is stamped with its rc number" "$(stamp_of v0.3.0-rc1)" 0.3.0-rc1
is "a final is stamped with the plain version" "$(stamp_of v0.3.0)" 0.3.0
is "a candidate's asset: its own name, then the name from before #19" \
   "$(asset_names v0.3.0-rc1 | paste -sd' ' -)" "CORELink-0.3.0-rc1.zip CORELink-0.3.0.zip"
is "an old candidate's asset is found under the bare version" \
   "$(asset_names v0.2.0-rc3 | paste -sd' ' -)" "CORELink-0.2.0-rc3.zip CORELink-0.2.0.zip"
is "two-digit rc numbers" "$(asset_names v0.1.1-rc10 | head -1)" CORELink-0.1.1-rc10.zip
is "a final's asset has one name" "$(asset_names v0.3.0 | paste -sd' ' -)" CORELink-0.3.0.zip
is "what a new candidate's asset says inside" "$(asset_stamp CORELink-0.3.0-rc1.zip)" 0.3.0-rc1
is "what an old candidate's asset says inside" "$(asset_stamp CORELink-0.2.0.zip)" 0.2.0

# fetch_asset against a stand-in gh that serves the files under $FAKE_RELEASES/<tag>/
mkdir -p "$box/bin" "$box/rel/v0.3.0-rc1" "$box/rel/v0.2.0-rc3" "$box/rel/v0.3.0" "$box/rel/v0.4.0-rc1"
cat > "$box/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo coreguild/CORELink ;;
  "release download")
    tag=$3; shift 3; pattern=""; dir=.
    while [ $# -gt 0 ]; do case "$1" in --pattern) pattern=$2; shift ;; --dir) dir=$2; shift ;; esac; shift; done
    [ -f "$FAKE_RELEASES/$tag/$pattern" ] || { echo "no assets match the file pattern" >&2; exit 1; }
    cp "$FAKE_RELEASES/$tag/$pattern" "$dir/" ;;
  *) echo "the stand-in gh was asked: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$box/bin/gh"
echo new > "$box/rel/v0.3.0-rc1/CORELink-0.3.0-rc1.zip"
echo old > "$box/rel/v0.2.0-rc3/CORELink-0.2.0.zip"
echo fin > "$box/rel/v0.3.0/CORELink-0.3.0.zip"
fetch() {  # fetch <tag>: prints "<name found>:<its content>", or "none"
  local d name; d=$(mktemp -d "$box/dl.XXXXXX")
  if name=$(PATH="$box/bin:$PATH" FAKE_RELEASES="$box/rel" fetch_asset "$1" "$d"); then
    echo "$name:$(cat "$d/$name")"
  else echo none; fi
}
is "repair finds a new candidate's asset"       "$(fetch v0.3.0-rc1)" "CORELink-0.3.0-rc1.zip:new"
is "repair finds a candidate from before #19"   "$(fetch v0.2.0-rc3)" "CORELink-0.2.0.zip:old"
is "repair finds a final's asset"               "$(fetch v0.3.0)"     "CORELink-0.3.0.zip:fin"
is "repair reports a release without a zip"     "$(fetch v0.4.0-rc1)" none

# ---- scripts/package.sh stamps what it is given (its own tests/run.sh is a stand-in here: this is run by it) --
mkdir -p "$box/pkg/scripts" "$box/pkg/tests"
cp scripts/package.sh "$box/pkg/scripts/"; cp -R CORELink "$box/pkg/CORELink"
printf '#!/usr/bin/env bash\nexit 0\n' > "$box/pkg/tests/run.sh"; chmod +x "$box/pkg/tests/run.sh"
for v in 0.3.0-rc1 0.3.0; do
  VERSION=$v bash "$box/pkg/scripts/package.sh" > /dev/null 2>&1
  zip="$box/pkg/dist/CORELink-$v.zip"
  if [ -f "$zip" ]; then pass "version $v builds CORELink-$v.zip"
  else flop "version $v builds CORELink-$v.zip"; continue; fi
  for toc in CORELink.toc CORELink_Camelot.toc; do
    is "$toc in CORELink-$v.zip says $v" "$(unzip -p "$zip" "CORELink/$toc" | grep '^## Version:')" "## Version: $v"
  done
done

# ---- scripts/release.sh --dry-run in a throwaway repository: last release v0.2.0, branch release/0.3.0 --------
repo="$box/repo"; mkdir -p "$repo/scripts"
cp scripts/release.sh scripts/release-names.sh "$repo/scripts/"
g() {
  git -C "$repo" -c user.name=test -c user.email=test@example.test -c commit.gpgsign=false -c tag.gpgsign=false "$@"
}
g init -q && g symbolic-ref HEAD refs/heads/main && g add -A && g commit -q -m "chore: fixture"
g tag v0.2.0
g checkout -q -b release/0.3.0 && g commit -q --allow-empty -m "feat: something new"
dry() { (cd "$repo" && PATH="$box/bin:$PATH" bash scripts/release.sh "$@" --dry-run 2>&1); }
out=$(dry rc)
says  "rc dry run names the tag" \
      "$out" "branch: release/0.3.0 | last final: 0.2.0 | open rc series: none | this: v0.3.0-rc1"
says  "rc dry run shows the stamped version"         "$out" "stamped version: 0.3.0-rc1 | zip: CORELink-0.3.0-rc1.zip"
says  "rc release would carry the rc-numbered zip" \
      "$out" 'gh release create v0.3.0-rc1 dist/CORELink-0.3.0-rc1.zip --prerelease --title CORELink 0.3.0 rc1'
says  "rc channel would get the rc-numbered zip"     "$out" "publish site: rc <- dist/CORELink-0.3.0-rc1.zip"
quiet "rc dry run never names the final's zip"       "$out" "CORELink-0.3.0.zip"
is    "a dry run creates no tag"                     "$(g tag -l | paste -sd' ' -)" v0.2.0
g tag v0.3.0-rc1
out=$(dry rc)
says  "the next candidate gets the next number"      "$out" "stamped version: 0.3.0-rc2 | zip: CORELink-0.3.0-rc2.zip"
g checkout -q main && g merge -q --ff-only release/0.3.0
out=$(dry final)
says  "final promotes the candidate merged into main" "$out" "promoting 0.3.0-rc1 -> v0.3.0"
says  "final dry run shows the plain version"        "$out" "stamped version: 0.3.0 | zip: CORELink-0.3.0.zip"
says  "final release would carry the plain zip" \
      "$out" 'gh release create v0.3.0 dist/CORELink-0.3.0.zip --latest --title CORELink 0.3.0'
says  "stable channel would get the plain zip"       "$out" "publish site: latest <- dist/CORELink-0.3.0.zip"
quiet "final dry run never names a candidate's zip"  "$out" "-rc1.zip"
exit $fail
