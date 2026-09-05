#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../../" && pwd)
fixture="$root/pocs/001-window-events-liveness/fixture"
build="$fixture/build"
mkdir -p "$build"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swiftc -sdk "$SDKROOT" -target arm64-apple-macosx26.0 \
  "$fixture/Sources/Clock.swift" \
  "$fixture/Sources/Trace.swift" \
  "$fixture/Tests/TestSupport.swift" \
  "$fixture/Tests/ClockTests.swift" \
  "$fixture/Tests/TraceTests.swift" \
  "$fixture/Tests/run.swift" \
  -o "$build/pure-tests"
"$build/pure-tests"
