#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Fixture.app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
# Caller must impose a <=120-second command bound. Never launches the result.
xcrun swiftc -swift-version 5 -warnings-as-errors -framework AppKit main.swift -o "$app/Contents/MacOS/Fixture"
printf '%s\n' "$app"
