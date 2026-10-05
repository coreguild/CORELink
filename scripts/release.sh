#!/usr/bin/env bash
# Release flow with two channels and automatic version numbers.
#
#   scripts/release.sh rc    [--bump auto|patch|minor|major] [--notes "text"] [--dry-run]
#   scripts/release.sh final [--notes "text"] [--no-rc [--bump ...]] [--dry-run]
#   scripts/release.sh site  [--dry-run]
#
# Nobody edits a version number. The TOCs in git carry "@project-version@"; the version is computed from the
# existing tags and stamped into the zip at build time (scripts/package.sh):
#   rc    : if an unreleased candidate series exists (v0.2.0-rc1 newer than the last final v0.1.1), the next rc of
#           that series (v0.2.0-rc2); otherwise bump the last final (--bump, default patch) and start rc1.
#           --bump minor/major on an existing series starts a new, higher series instead.
#   final : the version of the rc tag that points at this commit (required unless --no-rc, which bumps the last final).
# Release notes are built from the commits on main since the previous release (merge commits and wip/site noise
# skipped), put on the GitHub release and shown on the download page; --notes adds text on top.
# Downloads are published to the gh-pages branch at permanent URLs (see site/index.template.html).
# Normally run by the "release" GitHub Actions workflow (Run workflow button); works locally from a clean main.
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

preflight() {
  [ "$(git branch --show-current)" = main ] || { echo "release from main only (you are on $(git branch --show-current))"; exit 2; }
  [ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 2; }
  git fetch -q origin
  [ "$(git rev-parse origin/main)" = "$HEAD_SHA" ] || { echo "local main differs from origin/main; pull or push first"; exit 2; }
  scripts/check-game-version.sh
  VERSION="$VER" scripts/package.sh
  [ -f "dist/CORELink-$VER.zip" ] || { echo "dist/CORELink-$VER.zip missing"; exit 2; }
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
  if [ "$channel" != none ]; then
    cp "$zip" "$wt/$channel/CORELink.zip"
    echo "$VER" > "$wt/$channel/VERSION"
    date -u +%Y-%m-%d > "$wt/$channel/DATE"
    cp "$zip" "$wt/v/CORELink-$VER.zip"
    printf '%s\n' "$RELEASE_NOTES" > "$wt/notes/$VER.md"
    printf '%s\n' "$RELEASE_NOTES" > "$wt/$channel/NOTES.md"
  fi
  local stable rc stable_date rc_date rc_block=""
  stable=$(cat "$wt/latest/VERSION" 2>/dev/null || echo "none yet")
  rc=$(cat "$wt/rc/VERSION" 2>/dev/null || echo "none")
  stable_date=$(cat "$wt/latest/DATE" 2>/dev/null || echo "-")
  rc_date=$(cat "$wt/rc/DATE" 2>/dev/null || echo "-")
  if [ "$rc" != none ] && [ "$rc" != "$stable" ]; then rc_block="show"; fi
  local stable_notes rc_notes
  stable_notes=$(notes_html < "$wt/latest/NOTES.md" 2>/dev/null || true)
  rc_notes=$(notes_html < "$wt/rc/NOTES.md" 2>/dev/null || true)
  # Notes contain slashes and ampersands; use awk for a literal substitution of the two notes blocks.
  sed -e "s|{{STABLE_VERSION}}|$stable|g" -e "s|{{STABLE_DATE}}|$stable_date|g" \
      -e "s|{{RC_VERSION}}|$rc|g" -e "s|{{RC_DATE}}|$rc_date|g" -e "s|{{RC_CLASS}}|$rc_block|g" \
      -e "s|{{PAGES_URL}}|$PAGES_URL|g" -e "s|{{UPDATED}}|$(date -u +'%Y-%m-%d %H:%M UTC')|g" \
      site/index.template.html \
    | awk -v s="$stable_notes" -v r="$rc_notes" '{ gsub(/\{\{STABLE_NOTES\}\}/, s); gsub(/\{\{RC_NOTES\}\}/, r); print }' \
    > "$wt/index.html"
  cp site/style.css "$wt/style.css"
  printf '{"stable":"%s","rc":"%s","updated":"%s"}\n' "$stable" "$rc" "$(date -u +%FT%TZ)" > "$wt/channels.json"
  (cd "$wt" && git add -A && git commit -q -m "site: $channel -> $VER" && git push -q origin HEAD:gh-pages)
  git worktree remove --force "$wt"
  echo "site published: $PAGES_URL  (stable $stable, rc $rc)"
}

# ---- changelog from commits ---------------------------------------------------------------------
commit_list() {  # $1 = range, e.g. v0.1.0..HEAD ; one "- subject (sha)" per commit, noise removed, oldest first
  git log --no-merges --reverse --pretty='%s (%h)' "$1" 2>/dev/null \
    | grep -viE '^(wip|fixup!|squash!|site:|merge |release:)' \
    | awk '!seen[$0]++' | sed 's/^/- /'
}
build_notes() {  # $1 = tag being created, $2 = channel label, $3 = channel dir ; prints markdown
  local since="v$LAST_FINAL"; git rev-parse -q --verify "refs/tags/$since" >/dev/null || since=""
  local all; all=$(commit_list "${since:+$since..}HEAD")
  [ -n "$NOTES" ] && printf '%s\n\n' "$NOTES"
  printf '## Changes since %s\n\n%s\n' "${since:-the beginning}" "${all:-- (no commits found)}"
  if [ "$MODE" = rc ] && [ "${N:-1}" -gt 1 ]; then
    local prev="v$VER-rc$((N-1))" delta
    delta=$(commit_list "$prev..HEAD")
    printf '\n## Since %s\n\n%s\n' "$prev" "${delta:-- (no new commits)}"
  fi
  printf '\nDirect download (%s): %s/%s/CORELink.zip\n' "$2" "$PAGES_URL" "$3"
}
notes_html() {  # stdin markdown -> minimal HTML (headings, bullet lists, paragraphs), escaped
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | awk '
    function closelist() { if (inlist) { print "</ul>"; inlist=0 } }
    /^## / { closelist(); sub(/^## /, ""); print "<h3>" $0 "</h3>"; next }
    /^- /  { if (!inlist) { print "<ul>"; inlist=1 } sub(/^- /, ""); print "<li>" $0 "</li>"; next }
    /^Direct download/ { closelist(); next }
    /^[[:space:]]*$/ { closelist(); next }
    { closelist(); print "<p>" $0 "</p>" }
    END { closelist() }'
}

case "$MODE" in
  rc)
    if [ -n "$RC_SERIES" ] && { [ "$BUMP" = auto ] || [ "$BUMP" = patch ]; }; then
      VER="$RC_SERIES"; N=$((RC_N + 1))
    else
      VER=$(bump "$LAST_FINAL" "$([ "$BUMP" = auto ] && echo patch || echo "$BUMP")"); N=1
      if [ -n "$RC_SERIES" ] && ! ver_gt "$VER" "$RC_SERIES"; then VER="$RC_SERIES"; N=$((RC_N + 1)); fi
    fi
    TAG="v$VER-rc$N"
    echo "last final: $LAST_FINAL | open rc series: ${RC_SERIES:-none} | this: $TAG"
    RELEASE_NOTES=$(build_notes "$TAG" "RC channel" rc)
    [ $DRY -eq 1 ] && { printf '%s\n' "--- notes ---" "$RELEASE_NOTES" "-------------"; }
    [ $DRY -eq 1 ] || preflight
    run git tag -a "$TAG" -m "CORELink $VER release candidate $N"
    run git push -q origin "$TAG"
    run gh release create "$TAG" "dist/CORELink-$VER.zip" --prerelease --title "CORELink $VER rc$N" --notes "$RELEASE_NOTES"
    publish_site rc "dist/CORELink-$VER.zip"
    echo "RC published: $TAG"
    ;;
  final)
    RC_HERE=$(git tag --points-at "$HEAD_SHA" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-rc[0-9]+$' | sed 's/^v//' | sort -V | tail -1 || true)
    if [ -n "$RC_HERE" ]; then
      VER=${RC_HERE%-rc*}
    elif [ $NO_RC -eq 1 ]; then
      VER=$(bump "$LAST_FINAL" "$([ "$BUMP" = auto ] && echo patch || echo "$BUMP")")
      echo "no rc on this commit; --no-rc given, releasing $VER directly"
    else
      echo "no v*-rc* tag points at this commit. Cut an RC first (scripts/release.sh rc) or pass --no-rc for a small hotfix."; exit 2
    fi
    TAG="v$VER"
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists; nothing to do"; exit 2; }
    echo "last final: $LAST_FINAL | promoting ${RC_HERE:-(no rc)} -> $TAG"
    RELEASE_NOTES=$(build_notes "$TAG" "stable" latest)
    [ $DRY -eq 1 ] && { printf '%s\n' "--- notes ---" "$RELEASE_NOTES" "-------------"; }
    [ $DRY -eq 1 ] || preflight
    run git tag -a "$TAG" -m "CORELink $VER"
    run git push -q origin "$TAG"
    run gh release create "$TAG" "dist/CORELink-$VER.zip" --latest --title "CORELink $VER" --notes "$RELEASE_NOTES"
    publish_site latest "dist/CORELink-$VER.zip"
    echo "Release published: $TAG"
    ;;
  site)
    VER="$LAST_FINAL"; RELEASE_NOTES=""
    publish_site none
    ;;
esac
