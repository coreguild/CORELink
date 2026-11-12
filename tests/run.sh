#!/usr/bin/env bash
# Syntax-check the addon and run the mock-API harness. Exit code is non-zero on any failure.
# Requires a Lua 5.x interpreter: macOS `brew install lua`, Windows `winget install DEVCOM.Lua` or scoop/choco, Linux apt `lua5.4`.
set -euo pipefail
cd "$(dirname "$0")/.."
LUA=${LUA:-lua}; LUAC=${LUAC:-luac}
command -v "$LUA" >/dev/null || { echo "lua not found. macOS: brew install lua"; exit 2; }
for f in CORELink/*.lua; do "$LUAC" -p "$f" && echo "syntax ok: $f"; done
if command -v luacheck >/dev/null; then
  luacheck --no-color -q CORELink/
  luacheck --no-color -q --no-max-line-length tests/harness.lua   # one check per line, however long
elif [ "${CI:-}" = "true" ]; then
  echo "luacheck is required in CI"; exit 2
else
  echo "note: luacheck not installed (brew install luacheck); CI will run it"
fi
bash tests/size.sh
"$LUA" tests/load-order.lua
"$LUA" tests/harness.lua
bash tests/site-render.sh
bash tests/secrets.sh
