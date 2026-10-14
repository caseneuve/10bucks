#!/bin/bash
# Requires macOS clang and installed Hammerspoon LuaSkin development headers.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
headers="/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/Versions/A/Headers"
[[ -f "$headers/lua.h" && -f "$headers/lauxlib.h" ]] || { echo 'Hammerspoon LuaSkin headers required' >&2; exit 1; }
mkdir -p "$here/build"
for module in ax_validity regular_discovery; do
 clang -arch arm64 -std=gnu11 -fblocks -Wall -Wextra -Werror \
  -bundle -undefined dynamic_lookup -framework ApplicationServices -framework Foundation \
  -I "$headers" "$here/$module.m" -o "$here/build/$module.so"
done
