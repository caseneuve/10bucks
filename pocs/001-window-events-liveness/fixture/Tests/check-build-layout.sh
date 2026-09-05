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

# The unavailable visible hook is never disguised as completion evidence.
grep -F 'fixture_key_became_candidate' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
! grep -F 'native_create_completed' "$fixture/Sources/POC001FixtureApp.swift" >/dev/null
# Coordinator cleanup makes state terminal before asking AppKit to close.
grep -F 'guard let active = lifecycle.discardForShutdown()' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
grep -F '_ = control.completeClose(token: active.token, generation: active.generation)' "$fixture/Sources/FixtureCoordinator.swift" >/dev/null
printf '%s\n' 'PASS fixture bundle/build static checks'
