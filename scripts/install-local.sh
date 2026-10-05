#!/usr/bin/env bash
# Link (or copy) the addon folder into a WoW client's Interface/AddOns so edits are live after /reload.
# Usage: scripts/install-local.sh [path-to-flavor-folder]   e.g. ".../World of Warcraft/_classic_beta_"
# With no argument it tries the default macOS and Windows locations for the Forever beta.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$(pwd)/CORELink"
FLAVOR="${1:-}"
if [ -z "$FLAVOR" ]; then
  for c in "/Applications/World of Warcraft/_classic_beta_" "/Applications/World of Warcraft/_classic_" \
           "/c/Program Files (x86)/World of Warcraft/_classic_beta_" "/c/Program Files (x86)/World of Warcraft/_classic_"; do
    [ -d "$c" ] && FLAVOR="$c" && break
  done
fi
[ -d "$FLAVOR" ] || { echo "WoW flavor folder not found. Pass it as the first argument."; exit 2; }
DEST="$FLAVOR/Interface/AddOns/CORELink"
mkdir -p "$FLAVOR/Interface/AddOns"
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  mv "$DEST" "$DEST.bak.$(date +%Y%m%d%H%M%S)"; echo "existing folder moved aside as $DEST.bak.*"
fi
rm -f "$DEST"
if ln -s "$SRC" "$DEST" 2>/dev/null; then
  echo "linked $DEST -> $SRC"
else
  cp -R "$SRC" "$DEST"; echo "copied to $DEST (symlink not permitted here; re-run after each change)"
fi
echo "In game: /reload"
