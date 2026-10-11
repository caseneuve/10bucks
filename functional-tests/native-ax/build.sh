#!/bin/bash
# Source-only arm64 POC build; does not load the extension or perform AX queries.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
headers="/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/Versions/A/Headers"
[[ -f "$headers/lua.h" && -f "$headers/lauxlib.h" ]] || { echo 'LuaSkin headers unavailable' >&2; exit 1; }
mkdir -p "$here/build"
clang -arch arm64 -std=gnu11 -fblocks -Wall -Wextra -Werror \
  -bundle -undefined dynamic_lookup -framework ApplicationServices -framework Foundation \
  -I "$headers" "$here/ax_probe.m" -o "$here/build/ax_probe.so"
