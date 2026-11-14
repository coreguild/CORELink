#!/usr/bin/env bash
# Render the download page from a gh-pages checkout: index.html, channels.json and style.css.
#
#   scripts/render-site.sh <gh-pages dir> <pages url>
#
# Reads <dir>/latest/{VERSION,DATE,NOTES.md} and <dir>/rc/{VERSION,DATE,NOTES.md}. NOTES.md is the markdown
# changelog section the release wrote; it is converted to minimal escaped HTML and inserted into
# site/index.template.html by plain-text substitution, so & < > and newlines in commit messages are safe (#27).
# Called by scripts/release.sh; tests/site-render.sh runs it on a fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
WT="${1:?gh-pages dir}"; PAGES_URL="${2:?pages url}"
command -v perl >/dev/null || { echo "perl is required to render the site"; exit 2; }

notes_html() {  # stdin markdown (changelog section) -> minimal HTML, escaped
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
      -E -e 's/\[([^]]+)\]\(([^)]+)\)/<a href="\2">\1<\/a>/g' -e 's/\*\*([^*]+)\*\*/<strong>\1<\/strong>/g' \
  | awk '
    function closelist() { if (inlist) { print "</ul>"; inlist = 0 } }
    /^### / { closelist(); sub(/^### /, ""); print "<h3>" $0 "</h3>"; next }
    /^## /  { closelist(); sub(/^## /, ""); print "<h3>" $0 "</h3>"; next }
    /^[*-] / { if (!inlist) { print "<ul>"; inlist = 1 } sub(/^[*-] /, ""); print "<li>" $0 "</li>"; next }
    /^Direct download/ { closelist(); next }
    /^[[:space:]]*$/ { closelist(); next }
    { closelist(); print "<p>" $0 "</p>" }
    END { closelist() }'
}
read_or() { if [ -f "$1" ]; then cat "$1"; else echo "$2"; fi; }

STABLE_VERSION=$(read_or "$WT/latest/VERSION" "none yet")
RC_VERSION=$(read_or "$WT/rc/VERSION" "none")
STABLE_DATE=$(read_or "$WT/latest/DATE" "-")
RC_DATE=$(read_or "$WT/rc/DATE" "-")
RC_CLASS=""
# The candidate card is hidden once its version shipped: rc/VERSION 0.3.0-rc2 (0.3.0 before #19), stable 0.3.0.
if [ "$RC_VERSION" != none ] && [ "${RC_VERSION%-rc*}" != "$STABLE_VERSION" ]; then RC_CLASS="show"; fi
STABLE_NOTES=""; if [ -f "$WT/latest/NOTES.md" ]; then STABLE_NOTES=$(notes_html < "$WT/latest/NOTES.md"); fi
RC_NOTES="";     if [ -f "$WT/rc/NOTES.md" ];     then RC_NOTES=$(notes_html < "$WT/rc/NOTES.md"); fi
UPDATED=$(date -u +'%Y-%m-%d %H:%M UTC')
export STABLE_VERSION RC_VERSION STABLE_DATE RC_DATE RC_CLASS STABLE_NOTES RC_NOTES UPDATED PAGES_URL

# {{NAME}} -> the environment variable of that name, inserted literally (no pattern or & semantics).
perl -pe 's/\{\{([A-Z_]+)\}\}/exists $ENV{$1} ? $ENV{$1} : "{{$1}}"/ge' site/index.template.html > "$WT/index.html"
cp site/style.css "$WT/style.css"
printf '{"stable":"%s","rc":"%s","updated":"%s"}\n' "$STABLE_VERSION" "$RC_VERSION" "$(date -u +%FT%TZ)" > "$WT/channels.json"
