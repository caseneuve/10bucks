#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../../" && pwd)
fixture="$root/pocs/001-window-events-liveness/fixture"
app="$fixture/build/POC001Fixture.app"

# Source-level checks keep the build scope frozen: CLT swiftc, arm64/macOS 26,
# copied fixed plist, and no signing/open/security commands.
grep -F -- '-target arm64-apple-macosx26.0' "$fixture/scripts/build-fixture.sh" >/dev/null
grep -F -- 'cp "$fixture/Resources/Info.plist" "$app/Contents/Info.plist"' "$fixture/scripts/build-fixture.sh" >/dev/null
! grep -E 'codesign|xattr|spctl|[[:space:]]open[[:space:]]|security[[:space:]]' "$fixture/scripts/build-fixture.sh" >/dev/null
plutil -extract CFBundlePackageType raw "$fixture/Resources/Info.plist" | grep -Fx APPL >/dev/null
plutil -extract CFBundleExecutable raw "$fixture/Resources/Info.plist" | grep -Fx POC001Fixture >/dev/null
plutil -extract CFBundleIdentifier raw "$fixture/Resources/Info.plist" | grep -Fx local.poc001.fixture >/dev/null
plutil -extract LSBackgroundOnly raw "$fixture/Resources/Info.plist" | grep -Fx false >/dev/null

# These inspect only already-built files; they never launch either executable.
test -x "$app/Contents/MacOS/POC001Fixture"
test -x "$app/Contents/MacOS/poc001-fixturectl"
cmp "$fixture/Resources/Info.plist" "$app/Contents/Info.plist"
file "$app/Contents/MacOS/POC001Fixture" | grep -F 'arm64' >/dev/null
file "$app/Contents/MacOS/poc001-fixturectl" | grep -F 'arm64' >/dev/null

# The public occlusion callback measures only AppKit-reported partial visibility.
grep -F 'windowDidChangeOcclusionState' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
grep -F 'occlusionState.contains(.visible)' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
grep -F 'fixture_create_visible_completed' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
! grep -F 'windowDidBecomeKey' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
! grep -F 'makeKeyAndOrderFront' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
! grep -F 'native_create_completed' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
# Coordinator cleanup makes state terminal before asking AppKit to close.
grep -F 'guard let active = lifecycle.active else { return }' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
grep -F '_ = lifecycle.discardForShutdown()' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
grep -F '_ = control.completeClose(token: active.token, generation: active.generation)' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null

# Correlation is public AXIdentifier instrumentation only: the exact raw token
# is assigned before the create trace/order, while every emitted schema exports
# only the frozen full SHA-256 alias.
grep -F 'setAccessibilityIdentifier' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
grep -F 'setAccessibilityIdentifier(nil)' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
grep -F 'clearCorrelationToken(objectID: objectID)' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
grep -F 'abortCreatedWindow(objectID: objectID)' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
grep -F 'assignAccessibilityIdentifier' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
grep -F 'import CommonCrypto' "$fixture/Sources/Tokens.swift" >/dev/null
grep -F 'CC_SHA256' "$fixture/Sources/Tokens.swift" >/dev/null
grep -F 'correlation_alias' "$fixture/Sources/IPC.swift" >/dev/null
grep -F 'correlation_alias' "$fixture/Sources/Trace.swift" >/dev/null
! grep -F '"correlation_token"' "$fixture/Sources/IPC.swift" "$fixture/Sources/Trace.swift" >/dev/null
! grep -E '\.title|NSWindow\.identifier' "$fixture/Sources/POC001FixtureApp.swift" "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
printf '%s\n' 'PASS fixture bundle/build static checks'
