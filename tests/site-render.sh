#!/usr/bin/env bash
# Render the download page from a fixture whose notes contain & < > and several lines (#27) and check the page.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/latest" "$T/rc"
echo 1.2.3 > "$T/latest/VERSION"; echo 2026-01-01 > "$T/latest/DATE"
printf '%s\n' '## [1.2.3](https://x/compare/v1.2.2...v1.2.3) (2026-01-01)' '' '### Bug Fixes' '' \
  '* **setup:** /cl setup <channel> & password ([abc1234](https://x/commit/abc))' '' \
  'Direct download (stable): https://example.test/CORELink/latest/CORELink.zip' > "$T/latest/NOTES.md"
echo 1.3.0 > "$T/rc/VERSION"; echo 2026-02-02 > "$T/rc/DATE"
printf '%s\n' '## 1.3.0-rc1 (2026-02-02)' '' '### Features' '' '* line one' '* line "two" with $dollar and \backslash' > "$T/rc/NOTES.md"
bash scripts/render-site.sh "$T" https://example.test/CORELink
fail=0
has()  { if grep -qF -- "$2" "$T/index.html"; then echo "PASS site: $1"; else echo "FAIL site: $1"; fail=1; fi; }
lacks() { if grep -qF -- "$2" "$T/index.html"; then echo "FAIL site: $1"; fail=1; else echo "PASS site: $1"; fi; }
has   "entities in a commit subject survive"        "/cl setup &lt;channel&gt; &amp; password"
has   "commit link is rendered"                      '<a href="https://x/commit/abc">abc1234</a>'
has   "scope is bold"                                "<strong>setup:</strong>"
has   "stable version on the page"                   "1.2.3"
has   "rc version on the page"                       "1.3.0"
has   "rc notes keep every line"                     '<li>line "two" with $dollar and \backslash</li>'
has   "pages url substituted"                        "https://example.test/CORELink"
lacks "no template placeholder left"                 "{{"
lacks "download line is not shown as a paragraph"    "<p>Direct download"
if grep -q '"stable":"1.2.3","rc":"1.3.0"' "$T/channels.json"; then echo "PASS site: channels.json"; else echo "FAIL site: channels.json"; fail=1; fi
[ -f "$T/style.css" ] && echo "PASS site: style.css copied" || { echo "FAIL site: style.css copied"; fail=1; }
# The candidate card: shown while the candidate is ahead of stable, hidden once its version shipped. A candidate
# says its rc number (0.3.0-rc1, #19); the ones before that said the bare version.
card() {  # card <stable> <rc> <shown|hidden>
  echo "$1" > "$T/latest/VERSION"; echo "$2" > "$T/rc/VERSION"
  bash scripts/render-site.sh "$T" https://example.test/CORELink
  local got=hidden; if grep -qF 'class="card rc show"' "$T/index.html"; then got=shown; fi
  if [ "$got" = "$3" ] && grep -qF "Version $2<" "$T/index.html"; then echo "PASS site: stable $1, rc $2: card $3"
  else echo "FAIL site: stable $1, rc $2: card $got, expected $3"; fail=1; fi
}
card 0.2.0 0.3.0-rc1 shown
card 0.3.0 0.3.0-rc2 hidden
card 0.3.0 0.3.1-rc1 shown
card 0.2.0 0.2.0     hidden
card 0.2.0 0.3.0     shown
card 0.3.1 0.3.0-rc2 hidden      # a hotfix without a candidate went out after 0.3.0
card 0.10.0 0.9.1-rc1 hidden     # compared as versions, not as text
rm "$T/latest/VERSION"; bash scripts/render-site.sh "$T" https://example.test/CORELink
if grep -qF 'class="card rc show"' "$T/index.html"; then echo "PASS site: no stable yet: candidate card shown"
else echo "FAIL site: no stable yet: candidate card shown"; fail=1; fi
exit $fail
