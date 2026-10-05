#!/usr/bin/env bash
# Build dist/CORELink-<version>.zip from the TOC version. Run tests first.
set -euo pipefail
cd "$(dirname "$0")/.."
VER=$(grep -m1 '^## Version:' CORELink/CORELink.toc | awk '{print $3}')
[ -n "$VER" ] || { echo "no ## Version in CORELink/CORELink.toc"; exit 2; }
tests/run.sh
mkdir -p dist
OUT="dist/CORELink-$VER.zip"; rm -f "$OUT"
zip -rq -X "$OUT" CORELink -x '*.DS_Store'
echo "built $OUT"; unzip -l "$OUT"
