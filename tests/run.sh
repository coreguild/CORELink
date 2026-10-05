#!/usr/bin/env bash
# Syntax-check the addon and run the mock-API harness. Exit code is non-zero on any failure.
# Requires a Lua 5.x interpreter: macOS `brew install lua`, Windows `winget install DEVCOM.Lua` or scoop/choco, Linux apt `lua5.4`.
set -euo pipefail
cd "$(dirname "$0")/.."
LUA=${LUA:-lua}; LUAC=${LUAC:-luac}
command -v "$LUA" >/dev/null || { echo "lua not found. macOS: brew install lua"; exit 2; }
for f in CORELink/*.lua; do "$LUAC" -p "$f" && echo "syntax ok: $f"; done
"$LUA" tests/harness.lua
