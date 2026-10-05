#!/usr/bin/env bash
# Release flow with two channels.
#
#   scripts/release.sh rc    [--notes "text"]   tag v<ver>-rcN (next free N), GitHub pre-release, RC download channel
#   scripts/release.sh final [--notes "text"] [--no-rc]
#                                              tag v<ver>, GitHub latest release, stable download channel.
#                                              Requires an rc tag on this exact commit unless --no-rc (small hotfixes).
#   scripts/release.sh site                    just re-render and publish the download page from current channels
#
# <ver> comes from "## Version:" in CORELink/CORELink.toc. The TOC never carries "rc"; the same zip that passed
# RC is what ships. Downloads are served from the gh-pages branch at permanent URLs (see site/index.template.html).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
PAGES_URL="https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)"
MODE="${1:-}"; shift || true
NOTES=""; NO_RC=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    --no-rc) NO_RC=1; shift ;;
    *) echo "unknown argument $1"; exit 2 ;;
  esac
done
[ "$MODE" = rc ] || [ "$MODE" = final ] || [ "$MODE" = site ] || { sed -n '2,12p' "$0"; exit 2; }

VER=$(grep -m1 '^## Version:' CORELink/CORELink.toc | awk '{print $3}')
[ -n "$VER" ] || { echo "no ## Version in CORELink/CORELink.toc"; exit 2; }
HEAD_SHA=$(git rev-parse HEAD)

preflight() {
  [ "$(git branch --show-current)" = main ] || { echo "release from main only (you are on $(git branch --show-current))"; exit 2; }
  [ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 2; }
  git fetch -q origin
  [ "$(git rev-parse origin/main)" = "$HEAD_SHA" ] || { echo "local main differs from origin/main; pull or push first"; exit 2; }
  scripts/check-game-version.sh
  scripts/package.sh
  [ -f "dist/CORELink-$VER.zip" ] || { echo "dist/CORELink-$VER.zip missing"; exit 2; }
}

# ---- publish the download site from a gh-pages worktree -------------------------------------------
publish_site() {   # $1 = channel to update (rc|latest|none), $2 = zip to copy for that channel
  local channel="$1" zip="${2:-}"
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
  if [ "$channel" != none ]; then
    cp "$zip" "$wt/$channel/CORELink.zip"
    echo "$VER" > "$wt/$channel/VERSION"
    cp "$zip" "$wt/v/CORELink-$VER.zip"
  fi
  local stable rc stable_date rc_date
  stable=$(cat "$wt/latest/VERSION" 2>/dev/null || echo "none yet")
  rc=$(cat "$wt/rc/VERSION" 2>/dev/null || echo "none")
  [ -f "$wt/latest/VERSION" ] && stable_date=$(date -r "$wt/latest/VERSION" +%Y-%m-%d) || stable_date="-"
  [ -f "$wt/rc/VERSION" ] && rc_date=$(date -r "$wt/rc/VERSION" +%Y-%m-%d) || rc_date="-"
  # RC newer than stable? show it; otherwise hide the RC card.
  local rc_block=""
  if [ "$rc" != none ] && [ "$rc" != "$stable" ]; then rc_block="show"; fi
  sed -e "s|{{STABLE_VERSION}}|$stable|g" -e "s|{{STABLE_DATE}}|$stable_date|g" \
      -e "s|{{RC_VERSION}}|$rc|g" -e "s|{{RC_DATE}}|$rc_date|g" -e "s|{{RC_CLASS}}|$rc_block|g" \
      -e "s|{{PAGES_URL}}|$PAGES_URL|g" -e "s|{{UPDATED}}|$(date -u +'%Y-%m-%d %H:%M UTC')|g" \
      site/index.template.html > "$wt/index.html"
  cp site/style.css "$wt/style.css"
  printf '{"stable":"%s","rc":"%s","updated":"%s"}\n' "$stable" "$rc" "$(date -u +%FT%TZ)" > "$wt/channels.json"
  (cd "$wt" && git add -A && git -c user.name="$(git config user.name)" -c user.email="$(git config user.email)" \
     commit -q -m "site: $channel -> $VER" && git push -q origin HEAD:gh-pages)
  git worktree remove --force "$wt"
  echo "site published: $PAGES_URL  (stable $stable, rc $rc)"
}

case "$MODE" in
  rc)
    preflight
    n=1; while git rev-parse -q --verify "refs/tags/v$VER-rc$n" >/dev/null 2>&1 || git ls-remote --exit-code --tags origin "v$VER-rc$n" >/dev/null 2>&1; do n=$((n+1)); done
    TAG="v$VER-rc$n"
    git tag -a "$TAG" -m "CORELink $VER release candidate $n" && git push -q origin "$TAG"
    gh release create "$TAG" "dist/CORELink-$VER.zip" --prerelease --title "CORELink $VER rc$n" \
      --notes "${NOTES:-Release candidate $n for $VER. Test build for guild leads; not yet for everyone. See CHANGELOG.md.}

Direct download (RC channel): $PAGES_URL/rc/CORELink.zip"
    publish_site rc "dist/CORELink-$VER.zip"
    echo "RC published: $TAG"
    ;;
  final)
    preflight
    if [ $NO_RC -eq 0 ]; then
      git fetch -q --tags origin
      if ! git tag --points-at "$HEAD_SHA" | grep -q "^v$VER-rc[0-9]*$"; then
        echo "no v$VER-rc* tag points at this commit. Cut an RC first (scripts/release.sh rc) or pass --no-rc for a small hotfix."; exit 2
      fi
    fi
    TAG="v$VER"
    git tag -a "$TAG" -m "CORELink $VER" && git push -q origin "$TAG"
    gh release create "$TAG" "dist/CORELink-$VER.zip" --latest --title "CORELink $VER" \
      --notes "${NOTES:-CORELink $VER. See CHANGELOG.md.}

Direct download: $PAGES_URL/latest/CORELink.zip"
    publish_site latest "dist/CORELink-$VER.zip"
    echo "Release published: $TAG"
    ;;
  site)
    publish_site none
    ;;
esac
