#!/usr/bin/env bash
# Release flow with two channels and automatic version numbers.
#
#   scripts/release.sh rc    [--bump auto|patch|minor|major] [--notes "text"] [--dry-run]
#   scripts/release.sh final [--notes "text"] [--no-rc [--bump ...]] [--dry-run]
#   scripts/release.sh site  [--dry-run]      re-renders the page; repairs rc/ and latest/ from the GitHub releases
#                                             when a run died after tagging (works from any branch)
#
# Nobody edits a version number. The TOCs in git carry "@project-version@"; the version is computed from the
# existing tags and stamped into the zip at build time (scripts/package.sh):
#   rc    : runs on a release branch, never on main. release/<version> (release/0.2.0) pins the version and the
#           next rc number of that series. Any other release/<name> computes it: the next rc of an open
#           series (v0.2.0-rc2), else bump the last final (--bump, default patch) and start rc1.
#   final : runs on main after the release branch was merged. Takes the newest unreleased rc tag merged into
#           main whose addon files (CORELink/) are identical to main's, and refuses when the addon changed since
#           that rc. --no-rc bumps the last final for a hotfix that had no rc.
# Release notes are a CHANGELOG section in the conventional-changelog format (Features / Bug Fixes / ... with
# commit links), built from the commits since the previous tag (rc: since rcN-1 or the last release; final: since
# the last release). They go on the GitHub release, are prepended to CHANGELOG.md on gh-pages, and are shown on the
# download page. --notes adds a paragraph on top.
# Downloads are published to the gh-pages branch at permanent URLs (see site/index.template.html).
# Normally run by the "release" GitHub Actions workflow (Run workflow, pick the branch); works locally from a
# clean, pushed branch.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"; shift || true
NOTES=""; NO_RC=0; BUMP=auto; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    --bump) BUMP="$2"; shift 2 ;;
    --no-rc) NO_RC=1; shift ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown argument $1"; exit 2 ;;
  esac
done
case "$MODE" in rc|final|site) ;; *) sed -n '2,16p' "$0"; exit 2 ;; esac
case "$BUMP" in auto|patch|minor|major) ;; *) echo "--bump must be auto, patch, minor or major"; exit 2 ;; esac

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PAGES_URL="https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)"
GIT_NAME=$(git config user.name || true);  GIT_NAME=${GIT_NAME:-github-actions[bot]}
GIT_EMAIL=$(git config user.email || true); GIT_EMAIL=${GIT_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}
export GIT_COMMITTER_NAME="$GIT_NAME" GIT_COMMITTER_EMAIL="$GIT_EMAIL" GIT_AUTHOR_NAME="$GIT_NAME" GIT_AUTHOR_EMAIL="$GIT_EMAIL"
HEAD_SHA=$(git rev-parse HEAD)
BRANCH=$(git branch --show-current)
run() { if [ $DRY -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

# ---- versions from tags ---------------------------------------------------------------------------
git fetch -q --tags origin 2>/dev/null || true
last_final() { git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -vE -- '-rc[0-9]+$' | sed 's/^v//' | sort -V | tail -1; }
last_rc()    { git tag -l 'v[0-9]*.[0-9]*.[0-9]*-rc[0-9]*' | sed 's/^v//' | sort -V | tail -1; }   # e.g. 0.2.0-rc3
bump() {  # bump <version> <patch|minor|major>
  IFS=. read -r a b c <<< "$1"
  case "$2" in major) echo "$((a+1)).0.0" ;; minor) echo "$a.$((b+1)).0" ;; *) echo "$a.$b.$((c+1))" ;; esac
}
ver_gt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }
LAST_FINAL=$(last_final); LAST_FINAL=${LAST_FINAL:-0.0.0}
LAST_RC=$(last_rc)
RC_SERIES=""; RC_N=0
if [ -n "$LAST_RC" ]; then
  RC_SERIES=${LAST_RC%-rc*}; RC_N=${LAST_RC##*-rc}
  ver_gt "$RC_SERIES" "$LAST_FINAL" || { RC_SERIES=""; RC_N=0; }   # series already shipped
fi

# Which branch may run which channel: rc from release/* only, final from main, site from anywhere (it only renders
# the page and repairs the channels from the GitHub releases). Checked on --dry-run too.
check_branch() {
  case "$MODE" in
    rc)    [[ "$BRANCH" == release/* ]] || { echo "rc builds come from a release branch (release/<version> or release/<name>); you are on ${BRANCH:-a detached HEAD}. See skills/release/SKILL.md."; exit 2; } ;;
    final) [ "$BRANCH" = main ] || { echo "final runs from main only (you are on ${BRANCH:-a detached HEAD})"; exit 2; } ;;
  esac
}
preflight() {
  check_branch
  [ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 2; }
  git fetch -q origin
  [ "$(git rev-parse "origin/$BRANCH" 2>/dev/null)" = "$HEAD_SHA" ] || { echo "local $BRANCH differs from origin/$BRANCH; pull or push first"; exit 2; }
  scripts/check-game-version.sh
  VERSION="$VER" scripts/package.sh
  [ -f "dist/CORELink-$VER.zip" ] || { echo "dist/CORELink-$VER.zip missing"; exit 2; }
}

# ---- repair a channel from the GitHub release (a local run that died after tagging, see #27) ----------
# The GitHub release is the source of truth: when the channel's zip is not byte-for-byte the release's asset, the
# zip, notes and changelog section are written exactly as the rc/final run would have written them. A channel
# that already serves the release's zip is left alone (its notes may predate this script).
SYNCED=""
sync_channel() {  # $1 = rc|latest, $2 = tag (vX.Y.Z or vX.Y.Z-rcN), $3 = previous tag for the changelog ("" none)
  local channel="$1" tag="$2" prev="$3" ver; ver=${tag#v}; ver=${ver%-rc*}
  local tmp; tmp=$(mktemp -d)
  if ! gh release download "$tag" --pattern "CORELink-$ver.zip" --dir "$tmp" >/dev/null 2>&1; then
    echo "site: $tag has no GitHub release with CORELink-$ver.zip; $channel left as is"; rm -rf "$tmp"; return 0
  fi
  if cmp -s "$tmp/CORELink-$ver.zip" "$wt/$channel/CORELink.zip"; then rm -rf "$tmp"; return 0; fi
  echo "site: $channel <- $tag (recovered from the GitHub release)"
  cp "$tmp/CORELink-$ver.zip" "$wt/$channel/CORELink.zip"
  cp "$tmp/CORELink-$ver.zip" "$wt/v/CORELink-$ver.zip"
  echo "$ver" > "$wt/$channel/VERSION"
  git log -1 --format=%cs "$tag" > "$wt/$channel/DATE"
  gh release view "$tag" --json body -q .body > "$wt/notes/${tag#v}.md"
  cp "$wt/notes/${tag#v}.md" "$wt/$channel/NOTES.md"
  if ! grep -qE "^## (\[)?${tag#v}([]( ]|\$)" "$wt/CHANGELOG.md" 2>/dev/null; then
    prepend_changelog "$wt/CHANGELOG.md" "$(changelog_section "$tag" "$prev" "$tag")"
  fi
  SYNCED="$SYNCED $tag"
  rm -rf "$tmp"
}
sync_channels() {
  if [ "$LAST_FINAL" != 0.0.0 ]; then
    local prevf; prevf=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' | grep -vE -- '-rc[0-9]+$' | sort -V | grep -B1 -x "v$LAST_FINAL" | head -1)
    [ "$prevf" = "v$LAST_FINAL" ] && prevf=""
    sync_channel latest "v$LAST_FINAL" "$prevf"
  fi
  if [ -n "$RC_SERIES" ]; then
    local p="v$RC_SERIES-rc$((RC_N - 1))"; [ "$RC_N" -gt 1 ] || p="v$LAST_FINAL"
    git rev-parse -q --verify "refs/tags/$p" >/dev/null || p=""
    sync_channel rc "v$LAST_RC" "$p"
  fi
}

# ---- publish the download site from a gh-pages worktree -------------------------------------------
publish_site() {   # $1 = channel to update (rc|latest|none), $2 = zip to copy for that channel
  local channel="$1" zip="${2:-}"
  if [ $DRY -eq 1 ]; then echo "[dry-run] publish site: $channel <- ${zip:-no zip}"; return; fi
  local wt; wt=$(mktemp -d)
  if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
    git fetch -q origin gh-pages
    git worktree add -q "$wt" origin/gh-pages --detach
  else
    git worktree add -q --detach "$wt" HEAD
    (cd "$wt" && git checkout -q --orphan gh-pages && git rm -rfq . >/dev/null 2>&1 || true)
  fi
  mkdir -p "$wt/latest" "$wt/rc" "$wt/v"
  touch "$wt/.nojekyll"
  mkdir -p "$wt/notes"
  if [ "$channel" = none ]; then sync_channels; fi
  if [ "$channel" != none ]; then
    cp "$zip" "$wt/$channel/CORELink.zip"
    echo "$VER" > "$wt/$channel/VERSION"
    date -u +%Y-%m-%d > "$wt/$channel/DATE"
    cp "$zip" "$wt/v/CORELink-$VER.zip"
    printf '%s\n' "$RELEASE_NOTES" > "$wt/notes/${TAG#v}.md"
    printf '%s\n' "$RELEASE_NOTES" > "$wt/$channel/NOTES.md"
    prepend_changelog "$wt/CHANGELOG.md" "$CHANGELOG_SECTION"
  fi
  bash scripts/render-site.sh "$wt" "$PAGES_URL"
  (cd "$wt" && git add -A && { git diff --cached --quiet && echo "site: nothing to publish" || { git commit -q -m "site: $channel -> $VER${SYNCED:+ (recovered$SYNCED)}" && git push -q origin HEAD:gh-pages; }; })
  echo "site published: $PAGES_URL  (stable $(cat "$wt/latest/VERSION" 2>/dev/null || echo none), rc $(cat "$wt/rc/VERSION" 2>/dev/null || echo none)${SYNCED:+; recovered$SYNCED})"
  git worktree remove --force "$wt"
}

# ---- changelog from commits (conventional-changelog style) ------------------------------------------
# Commit subjects "type(scope)!: text" are grouped by type; everything else lands under "Other Changes".
changelog_section() {  # $1 = new tag, $2 = previous tag ("" for none), $3 = end ref (default HEAD) ; prints markdown
  local tag="$1" prev="$2" end="${3:-HEAD}" url="https://github.com/$REPO" today; today=$(date -u +%Y-%m-%d)
  if [ -n "$prev" ]; then printf '## [%s](%s/compare/%s...%s) (%s)\n' "${tag#v}" "$url" "$prev" "$tag" "$today"
  else printf '## %s (%s)\n' "${tag#v}" "$today"; fi
  git log --no-merges --reverse --pretty='%H%x1f%h%x1f%s' "${prev:+$prev..}$end" | awk -F'\037' -v url="$url" '
    {
      full = $1; short = $2; subj = $3
      if (subj ~ /^(wip|fixup!|squash!|site:|Merge )/) next
      type = ""; scope = ""; bang = 0; rest = subj
      if (match(subj, /^[A-Za-z]+(\([^)]*\))?!?: /)) {
        head = substr(subj, 1, RLENGTH); rest = substr(subj, RLENGTH + 1)
        type = head; sub(/[(!:].*$/, "", type); type = tolower(type)
        if (match(head, /\([^)]*\)/)) scope = substr(head, RSTART + 1, RLENGTH - 2)
        if (head ~ /!: $/) bang = 1
      }
      sec = "Other Changes"
      if (type == "feat") sec = "Features"
      else if (type == "fix") sec = "Bug Fixes"
      else if (type == "perf") sec = "Performance Improvements"
      else if (type == "revert") sec = "Reverts"
      else if (type == "docs") sec = "Documentation"
      else if (type ~ /^(chore|ci|build|test|refactor|style)$/) sec = "Maintenance"
      line = "* " (scope != "" ? "**" scope ":** " : "") rest " ([" short "](" url "/commit/" full "))"
      if (bang) brk[++nb] = line
      n[sec]++; items[sec, n[sec]] = line; total++
    }
    END {
      if (nb) { printf "\n\n### \342\232\240 BREAKING CHANGES\n\n"; for (i = 1; i <= nb; i++) print brk[i] }
      split("Features|Bug Fixes|Performance Improvements|Reverts|Documentation|Maintenance|Other Changes", o, "|")
      for (k = 1; k <= 7; k++) { s = o[k]; if (n[s]) { printf "\n\n### %s\n\n", s; for (i = 1; i <= n[s]; i++) print items[s, i] } }
      if (!total) printf "\n\n* No changes.\n"
    }'
}
build_notes() {  # $1 = new tag, $2 = previous tag, $3 = channel label, $4 = channel dir ; prints markdown
  [ -n "$NOTES" ] && printf '%s\n\n' "$NOTES"
  changelog_section "$1" "$2"
  printf '\nDirect download (%s): %s/%s/CORELink.zip\n' "$3" "$PAGES_URL" "$4"
}
prepend_changelog() {  # $1 = CHANGELOG.md path on gh-pages, $2 = section markdown
  local header body
  header=$(printf '%s\n' "# Changelog" "" "All notable changes to CORELink are documented in this file. It is generated at release time from the commit history; commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/) (\`feat:\`, \`fix:\`, \`feat(scope)!:\` ...)." "")
  body=""
  [ -f "$1" ] && body=$(awk 'f{print} /^## /{if(!f){f=1; print}}' "$1")
  printf '%s\n\n%s\n\n%s\n' "$header" "$2" "$body" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$1"
}

case "$MODE" in
  rc)
    check_branch
    PINNED=$(printf '%s' "$BRANCH" | sed -nE 's#^release/([0-9]+\.[0-9]+\.[0-9]+)$#\1#p')
    if [ -n "$PINNED" ]; then
      ver_gt "$PINNED" "$LAST_FINAL" || { echo "branch $BRANCH names version $PINNED but $LAST_FINAL is already released; name the branch after a higher version"; exit 2; }
      VER="$PINNED"
      LAST_N=$(git tag -l "v$VER-rc[0-9]*" | sed 's/.*-rc//' | sort -n | tail -1); N=$(( ${LAST_N:-0} + 1 ))
    elif [ -n "$RC_SERIES" ] && { [ "$BUMP" = auto ] || [ "$BUMP" = patch ]; }; then
      VER="$RC_SERIES"; N=$((RC_N + 1))
    else
      VER=$(bump "$LAST_FINAL" "$([ "$BUMP" = auto ] && echo patch || echo "$BUMP")"); N=1
      if [ -n "$RC_SERIES" ] && ! ver_gt "$VER" "$RC_SERIES"; then VER="$RC_SERIES"; N=$((RC_N + 1)); fi
    fi
    TAG="v$VER-rc$N"
    echo "branch: $BRANCH | last final: $LAST_FINAL | open rc series: ${RC_SERIES:-none} | this: $TAG"
    PREV_TAG="v$VER-rc$((N-1))"; [ "$N" -gt 1 ] || PREV_TAG="v$LAST_FINAL"
    git rev-parse -q --verify "refs/tags/$PREV_TAG" >/dev/null || PREV_TAG=""
    CHANGELOG_SECTION=$(changelog_section "$TAG" "$PREV_TAG")
    RELEASE_NOTES=$(build_notes "$TAG" "$PREV_TAG" "RC channel" rc)
    [ $DRY -eq 1 ] && { printf '%s\n' "--- notes ---" "$RELEASE_NOTES" "-------------"; }
    [ $DRY -eq 1 ] || preflight
    run git tag -a "$TAG" -m "CORELink $VER release candidate $N"
    run git push -q origin "$TAG"
    run gh release create "$TAG" "dist/CORELink-$VER.zip" --prerelease --title "CORELink $VER rc$N" --notes "$RELEASE_NOTES"
    [ $DRY -eq 1 ] || printf '%s\n' "$TAG" > dist/TAG     # for scripts/curseforge-upload.sh
    publish_site rc "dist/CORELink-$VER.zip"
    echo "RC published: $TAG"
    ;;
  final)
    check_branch
    # The rc that was tested: the newest unreleased rc tag merged into main whose addon files equal main's.
    RC_HERE=""; RC_STALE=""
    for t in $(git tag -l 'v[0-9]*.[0-9]*.[0-9]*-rc[0-9]*' | sort -rV); do
      s=${t#v}; s=${s%-rc*}
      ver_gt "$s" "$LAST_FINAL" || continue
      git merge-base --is-ancestor "$t" "$HEAD_SHA" 2>/dev/null || continue
      if git diff --quiet "$t" "$HEAD_SHA" -- CORELink/; then RC_HERE=${t#v}; break; else RC_STALE=${RC_STALE:-$t}; fi
    done
    if [ -n "$RC_HERE" ]; then
      VER=${RC_HERE%-rc*}
    elif [ $NO_RC -eq 1 ]; then
      VER=$(bump "$LAST_FINAL" "$([ "$BUMP" = auto ] && echo patch || echo "$BUMP")")
      echo "no tested rc on main; --no-rc given, releasing $VER directly"
    elif [ -n "$RC_STALE" ]; then
      echo "the addon on main differs from $RC_STALE (CORELink/ changed since that rc was tested). Cut a new rc from the release branch, test it, merge it, then final."; exit 2
    else
      echo "no unreleased rc tag is merged into main. Cut an rc from a release branch, test it, merge the branch, then final (or --no-rc for a small hotfix)."; exit 2
    fi
    TAG="v$VER"
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists; nothing to do"; exit 2; }
    echo "last final: $LAST_FINAL | promoting ${RC_HERE:-(no rc)} -> $TAG"
    PREV_TAG="v$LAST_FINAL"; git rev-parse -q --verify "refs/tags/$PREV_TAG" >/dev/null || PREV_TAG=""
    CHANGELOG_SECTION=$(changelog_section "$TAG" "$PREV_TAG")
    RELEASE_NOTES=$(build_notes "$TAG" "$PREV_TAG" "stable" latest)
    [ $DRY -eq 1 ] && { printf '%s\n' "--- notes ---" "$RELEASE_NOTES" "-------------"; }
    [ $DRY -eq 1 ] || preflight
    run git tag -a "$TAG" -m "CORELink $VER"
    run git push -q origin "$TAG"
    run gh release create "$TAG" "dist/CORELink-$VER.zip" --latest --title "CORELink $VER" --notes "$RELEASE_NOTES"
    [ $DRY -eq 1 ] || printf '%s\n' "$TAG" > dist/TAG     # for scripts/curseforge-upload.sh
    publish_site latest "dist/CORELink-$VER.zip"
    echo "Release published: $TAG"
    ;;
  site)
    check_branch
    VER="$LAST_FINAL"; TAG="v$VER"; RELEASE_NOTES=""; CHANGELOG_SECTION=""
    publish_site none
    ;;
esac
