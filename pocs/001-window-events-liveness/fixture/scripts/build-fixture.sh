#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../../" && pwd)
fixture="$root/pocs/001-window-events-liveness/fixture"
build="$fixture/build"
app="$build/POC001Fixture.app"
macos="$app/Contents/MacOS"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
rm -rf "$app"
mkdir -p "$macos"

swiftc -sdk "$SDKROOT" -target arm64-apple-macosx26.0 -framework AppKit -framework Security \
  -o "$macos/POC001Fixture" \
  "$fixture/Sources/POC001FixtureApp.swift" \
  "$fixture/Sources/Clock.swift" \
  "$fixture/Sources/Trace.swift" \
  "$fixture/Sources/IPC.swift" \
  "$fixture/Sources/FixtureControl.swift" \
  "$fixture/Sources/FixtureCoordinator.swift" \
  "$fixture/Sources/LifecycleHooks.swift" \
  "$fixture/Sources/PendingWork.swift" \
  "$fixture/Sources/Tokens.swift"

swiftc -sdk "$SDKROOT" -target arm64-apple-macosx26.0 -framework Security \
  -o "$macos/poc001-fixturectl" \
  "$fixture/Sources/fixturectl.swift" \
  "$fixture/Sources/IPC.swift" \
  "$fixture/Sources/FixtureControl.swift" \
  "$fixture/Sources/Tokens.swift"

cp "$fixture/Resources/Info.plist" "$app/Contents/Info.plist"
