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
  "$fixture/Sources/FixtureControl.swift" \
  "$fixture/Sources/IPC.swift" \
  "$fixture/Sources/LifecycleHooks.swift" \
  "$fixture/Sources/PendingWork.swift" \
  "$fixture/Sources/Tokens.swift" \
  "$fixture/Tests/TestSupport.swift" \
  "$fixture/Tests/ClockTests.swift" \
  "$fixture/Tests/TraceTests.swift" \
  "$fixture/Tests/FixtureControlTests.swift" \
  "$fixture/Tests/LifecycleHookTests.swift" \
  "$fixture/Tests/PendingWorkTests.swift" \
  "$fixture/Tests/TokenTests.swift" \
  "$fixture/Tests/IPCTests.swift" \
  "$fixture/Tests/run.swift" \
  -o "$build/pure-tests"
"$build/pure-tests"
