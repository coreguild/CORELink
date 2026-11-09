#!/usr/bin/env bash
# Keep the addon readable without an editor: no file over MAX_FILE lines, no function over MAX_FUNC lines
# (luacheck caps line length at 120). A function is counted from the line that opens it ("function" that does
# not close on the same line) to the "end" at the same indentation. Exit 1 on any breach, listing them.
set -euo pipefail
cd "$(dirname "$0")/.."
MAX_FILE=${MAX_FILE:-400}
MAX_FUNC=${MAX_FUNC:-40}
status=0
for f in CORELink/*.lua; do
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$MAX_FILE" ]; then echo "TOO LONG  $f: $lines lines (max $MAX_FILE)"; status=1; fi
  long=$(awk -v max="$MAX_FUNC" '
    function indent_of(s) { match(s, /^[ \t]*/); return substr(s, 1, RLENGTH) }
    {
      ind = indent_of($0)
      opens = ($0 ~ /(^|[^A-Za-z0-9_])function[ (]/) && ($0 !~ /end[ )]*,?[ )]*$/)
      if (depth > 0 && ind == inds[depth] && $0 ~ ("^" inds[depth] "end([^A-Za-z0-9_]|$)")) {
        len = NR - starts[depth] + 1
        if (len > max) printf "TOO LONG  %s:%d: %d-line function (max %d): %s\n", FILENAME, starts[depth], len, max, texts[depth]
        depth--
      }
      if (opens) { depth++; starts[depth] = NR; inds[depth] = ind; texts[depth] = $0 }
    }' "$f")
  if [ -n "$long" ]; then echo "$long"; status=1; fi
done
[ $status -eq 0 ] && echo "size ok: every file under $MAX_FILE lines, every function under $MAX_FUNC"
exit $status
