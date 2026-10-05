#!/usr/bin/env bash
# Build dist/CORELink-<version>.zip. The TOCs in git carry the placeholder "@project-version@";
# the version is stamped in at build time. Run tests first.
#
#   scripts/package.sh                 # version "dev" (local builds)
#   VERSION=0.2.0 scripts/package.sh   # what scripts/release.sh does
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-dev}"
tests/run.sh
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -R CORELink "$STAGE/CORELink"
for toc in "$STAGE"/CORELink/*.toc; do
  sed -i.bak "s/@project-version@/$VERSION/g" "$toc" && rm -f "$toc.bak"
done
grep -q "^## Version: $VERSION\$" "$STAGE/CORELink/CORELink.toc" || { echo "version stamping failed"; exit 2; }
mkdir -p dist
OUT="$(pwd)/dist/CORELink-$VERSION.zip"; rm -f "$OUT"
(cd "$STAGE" && zip -rq -X "$OUT" CORELink -x '*.DS_Store')
echo "built $OUT (version $VERSION)"; unzip -l "$OUT" | tail -n +2 | head -6
