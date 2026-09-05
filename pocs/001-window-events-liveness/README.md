# POC-001 — AppKit timing fixture implementation handoff

**Status: approved implementation handoff; POC-001 remains `hypothesis`.** This
is the separately gated handoff requested by
[`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md).
The source/test checkpoint is complete. One separately human-gated
[fixture-only live calibration](fixture/LIVE-CALIBRATION.md) has been completed
and recorded as a one-sample observation. It did **not** authorize Hammerspoon,
an observer, or fixture--observer correlation, and it authorizes no repeat.
The correlation handoff records an implemented but approval-pending
fixture-only source/test/build slice; it does **not** authorize a fixture
launch, IPC request against the app, Hammerspoon action, observer
implementation, or any live correlation action. The
[correlation handoff](CORRELATION-HANDOFF.md) records the public-AX/SHA-256-
alias fixture seam and the remaining unapproved observer/live gates. The
[proposed one-sample live-correlation guide](LIVE-CORRELATION.md) requires a
separate explicit human approval and authorizes nothing by itself.

## Decision boundary

The fixture will make only this later measurement possible: timestamps for its
own AppKit create/close lifecycle and its own main-run-loop pending work. It
cannot select a Hammerspoon source, establish destruction authority, prove
another app's liveness/callback delivery, or authorize a native replacement.
The existing Chromium result remains candidate-only evidence.

## Verified implementation basis

- **Verified (local toolchain, 2026-08-29):** Command Line Tools is active at
  `/Library/Developer/CommandLineTools`; `swiftc` is available as Apple Swift
  6.3.3 targeting `arm64-apple-macosx26.0`; the macOS SDK is
  `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. `xcodebuild` is not
  available because full Xcode is not selected. This handoff deliberately uses
  `swiftc`, not Xcode, SwiftPM, or an Xcode project.
- **Verified (installed SDK `mach/mach_time.h`):** `mach_absolute_time()` and
  `mach_timebase_info()` are declared; `mach_continuous_time()` is public and
  available on macOS 10.12 and later. The header says continuous time advances
  during sleep. [Apple's `mach_continuous_time` documentation](https://developer.apple.com/documentation/kernel/1646199-mach_continuous_time)
  describes a monotonic, arbitrary-origin tick clock.
- **Verified (installed SDK `AppKit/NSWindow.h` and Apple AppKit
  documentation):** [`NSWindowDelegate.windowWillClose(_:)`](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowwillclose(_:)),
  [`NSWindowDelegate.windowDidChangeOcclusionState(_:)`](https://developer.apple.com/documentation/appkit/nswindowdelegate/windowdidchangeocclusionstate(_:)),
  and `NSWindow.occlusionState` with its public `.visible` bit are public
  AppKit APIs. They are fixture-local observation hooks, not Accessibility or
  liveness authorities.
- **Hypothesis:** the specified hooks will arrive consistently enough on this
  host to meet the thresholds below. That requires the later live gate; source
  declarations and documentation do not establish delivery, ordering, or
  latency.

## Frozen source, bundle, and build layout

The future implementation creates only this POC-local tree (generated paths
are ignored/not committed):

```text
pocs/001-window-events-liveness/fixture/
  README.md                         # optional fixture-only operator notes
  Sources/
    POC001FixtureApp.swift          # @main AppKit app/delegate and window registry
    Clock.swift                     # public mach clock wrapper and conversion
    Trace.swift                     # strict NDJSON schema/redaction writer
    IPC.swift                       # owner-local Unix-domain IPC server
    FixtureControl.swift            # command parser/state machine
    fixturectl.swift                # one-request IPC client
  Tests/
    ClockTests.swift
    TraceTests.swift
    FixtureControlTests.swift
    LifecycleHookTests.swift
  Resources/Info.plist
  scripts/build-fixture.sh
  build/                            # generated only; never committed
    POC001Fixture.app/
      Contents/Info.plist
      Contents/MacOS/POC001Fixture
      Contents/MacOS/poc001-fixturectl
```

`Resources/Info.plist` is copied verbatim to the bundle and contains
`CFBundlePackageType=APPL`, `CFBundleExecutable=POC001Fixture`, a fixture-only
identifier `local.poc001.fixture`, and `LSBackgroundOnly=false`. The future
build script is frozen to use:

```sh
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swiftc -sdk "$SDKROOT" -target arm64-apple-macosx26.0 -framework AppKit \
  -o fixture/build/POC001Fixture.app/Contents/MacOS/POC001Fixture \
  fixture/Sources/POC001FixtureApp.swift fixture/Sources/Clock.swift \
  fixture/Sources/Trace.swift fixture/Sources/IPC.swift fixture/Sources/FixtureControl.swift
```

It compiles the control client with `swiftc` into the same `Contents/MacOS`
directory. No signing, notarization, quarantine bypass, installer, login item,
agent, `open`, or `codesign --deep` is in scope. **Hypothesis:** this unsigned,
local bundle can be launched normally on the supported host; the future build
and live gates must record any Gatekeeper/quarantine result rather than alter
security settings. The fixture must use public AppKit/Foundation/Darwin APIs;
no `hs`, AX APIs, private Spaces APIs, polling, privileged helper, or
non-fixture window operation is permitted.

### Build-only integration corrections (2026-09-05)

- **Verified narrow revision:** the public macOS SDK exposes
  `NSWindowDelegate.windowDidChangeOcclusionState(_:)` and
  `NSWindow.occlusionState`, including its `.visible` bit. The fixture uses
  that delegate callback—not focus/key state—to emit
  `fixture_create_visible_completed` only for the first callback whose exact
  registered fixture window has `occlusionState.contains(.visible)`. This
  fact means only that AppKit reports at least partial visibility. It does
  **not** mean liveness, unobscured pixels, AX readiness, regular-Space
  ownership, admission, or Hammerspoon observation, and it is never used for
  destruction.
- **Verified integration mismatch:** the frozen build command named only five
  sources, but the checked-in pure implementation intentionally factors the
  lifecycle, pending-work, token, and coordinator seams into additional source
  files. `build-fixture.sh` compiles that closed dependency set and compiles
  `fixturectl` with the token protocol source. Build products remain only under
  ignored `fixture/build`; no execution, signing, or security behavior changed.

## Exact fixture contract

### Public lifecycle hooks

All AppKit object creation, window mutation, delegate calls, and notification
handling run on the main thread.

1. On `create`, the fixture allocates one `NSWindow`, assigns itself as that
   window's delegate, emits `create_requested`, and calls
   `orderFrontRegardless()`, which does not make key/focus status part of the
   measurement.
2. `windowDidChangeOcclusionState(_:)` checks the callback object's identity
   against the exact registered fixture window and checks
   `occlusionState.contains(.visible)`. Only the first matching visible
   callback for that active generation emits
   `fixture_create_visible_completed`. A non-visible callback, another window,
   or a duplicate callback is ignored/rejected by the identity/generation
   guards. The trace fact is narrowly **AppKit reporting at least partial
   visibility**. It MUST NOT imply liveness, unobscured pixels, AX readiness,
   Space ownership, admission, or Hammerspoon observation; it MUST NOT be used
   for destruction.
3. On `close`, it emits `close_requested` and invokes only that fixture
   window's `performClose(nil)`. It does not close a window if the registry has
   no matching fixture token.
4. In `windowWillClose(_:)`, after checking notification/window identity and
   generation, it emits exactly one `native_close_completed`, removes the
   fixture's strong registry reference, and cancels that generation's bounded
   work. This means AppKit has entered its public will-close delegate hook. It
   is **not** proof that the process exited, memory was deallocated, pixels
   disappeared, an AX destroy event happened, or another observer received a
   destruction callback. A user-close follows the same hook and is emitted as
   `native_close_completed` with `origin=user`, never silently attributed to an
   IPC close.
5. `applicationShouldTerminateAfterLastWindowClosed` returns `false`; a close
   never terminates the fixture. Only `shutdown` may terminate it.

No lifecycle hook is used as a production authority. Duplicate notifications,
wrong object, and duplicate generation are safe rejected/duplicate outcomes.
If the registered window's `windowWillClose(_:)` arrives before its visible
completion, that hook clears both lifecycle/control generation state and cancels
work for cleanup but emits no `native_close_completed`; it is an anomalous
 discarded ordering, never a completion.

### Clock and trace

`Clock.nowTicks()` uses `mach_continuous_time()` when the deployment/runtime
availability supports macOS 10.12+; otherwise it uses `mach_absolute_time()`.
The `run_started` record freezes `clock_kind` (`mach_continuous` or
`mach_absolute`), `timebase_numer`, `timebase_denom`, and raw `ticks`. All
elapsed fixture timings are first calculated by checked unsigned tick
subtraction (`end >= start`) and retained as `elapsed_ticks`.

For a display-only integer-nanosecond conversion, use the overflow-safe
identity:

```text
q = ticks / denom; r = ticks % denom
nanoseconds = q * numer + (r * numer) / denom
```

The implementation must use checked arithmetic for both products/addition and
emit `conversion_overflow` rather than wrapping. `monotonic_ms` is
`nanoseconds / 1_000_000` (integer floor), alongside ticks/timebase; it is not
an epoch time and must never be correlated with wall-clock time. The fallback
is compatibility only: absolute time may not advance during sleep, so a trace
with `clock_kind=mach_absolute` is not comparable to a continuous-clock sleep
sample. The supported local host is macOS 26.5, where the continuous branch is
expected but remains **Hypothesis** until a later run records it.

Every NDJSON record has exactly: `schema`, `run_id`, `sample_id`, `sequence`,
`event`, `clock_kind`, `ticks`, `monotonic_ms`, and only approved scalar fields.
Fixture tokens have the form `fixture-win-<random-base32>` and correlation
tokens `corr-<random-base32>`; both are generated with `SecRandomCopyBytes`.
No PID, native window number, title, path, URL, AX value, app name, or command
argument is written to the trace.

### IPC and operator sequence

The fixture serves one owner-local Unix-domain socket at
`<approved-private-run-dir>/poc001-fixture.sock`. Startup requires a preexisting
owner directory with mode `0700`; it refuses symlinks, a non-owner directory,
or a socket/output mode other than `0600`. `fixturectl` connects to that exact
path, sends one newline-delimited JSON request, reads one response, and exits.
The server never accepts a network socket and serializes commands on the main
queue. Requests are exact:

```json
{"request_id":"req-001","command":"create","sample_id":"fixture-create-warm-001"}
{"request_id":"req-002","command":"probe_pending_work","sample_id":"fixture-probe-warm-001"}
{"request_id":"req-003","command":"close","sample_id":"fixture-close-warm-001","fixture_token":"fixture-win-…"}
{"request_id":"req-004","command":"shutdown","sample_id":"fixture-cleanup-001"}
```

`request_id`, `sample_id`, and tokens accept only `[A-Za-z0-9._-]` with the
fixture token prefix above. The response repeats only request/sample IDs,
accepted/rejected status, and the generated fixture/correlation tokens. The
operator sequence for the later run is fixed: validate private output
location → launch one fixture instance → wait for `run_started`/socket-ready →
`create` → await its response and `fixture_create_visible_completed` (or the
fixed create timeout) → `probe_pending_work` → await `pending_work_serviced` or timeout → `close` using
that response token → await `native_close_completed` or timeout → repeat only
the declared class → `shutdown` → verify cleanup. No command is automatic, and
no command in this handoff is authorized now.

### Pending-work and observer correlation boundaries

The [unapproved correlation research handoff](CORRELATION-HANDOFF.md) records
the proposed public Accessibility identifier plus SHA-256 alias join, precise
observer read, tests, privacy/query limits, and stop rule. It is not normative
implementation approval and this fixture handoff does not authorize that source
slice or a live run.

`probe_pending_work` emits `pending_work_requested` then enqueues one
`DispatchQueue.main.async` closure. That closure emits
`pending_work_serviced`; it schedules no timer, recurring work, polling, or
secondary queue. This measures service of this fixture's main dispatch queue
only, not Hammerspoon hotkey service or general OS responsiveness.

The checked-in fixture source now keeps the raw correlation token only in its
active in-memory generation and the live AppKit accessibility identifier;
fixture IPC/trace emit only the full SHA-256 `correlation_alias`. The observer
is not implemented or authorized: a future approved slice would read the raw
AX value once, calculate the same alias, clear the raw value, and emit only the
alias. Later analysis requires exact alias equality, never title, PID, window
number, focus, visibility, or timing proximity. Correlation remains a
**Hypothesis** and the fixture has no Hammerspoon dependency.

## Fixed measurements, counts, and stop rules

These thresholds are inherited without relaxation from POC-001's readiness,
destruction, and next-key service gates:

| Class | Samples | Fixed measure and threshold |
| --- | ---: | --- |
| Warm create | 30 | `fixture_create_visible_completed - create_requested`: p95 <= 100 ms |
| Cold create (first create after fresh fixture launch) | 5 | `fixture_create_visible_completed - create_requested`: every successful sample <= 3,000 ms; timeout is recorded, not inferred complete |
| Warm close | 10 | `native_close_completed - close_requested`: every successful sample <= 1,000 ms |
| Pending-work (first after create, no other fixture work pending) | 30 warm + 5 cold | `pending_work_serviced - pending_work_requested`: p95 <= 50 ms and max <= 100 ms |

The create measure is only the fixture-local time until AppKit reports at
least partial visibility for its exact window. It does not satisfy POC-001
readiness, liveness, ownership, admission, Hammerspoon-observation, or
destruction gates. A close is counted as the inherited reduced destructive
class even though it only destroys a disposable fixture window. Cold close is not a separate class:
the cold creation sample's resulting window is closed under the warm-close
class. Report every raw sample, count, median, nearest-rank p95, maximum,
timeouts, duplicates, late completions, clock kind/timebase, and zero active
pending-work items at shutdown. These are fixture measurements only; the
1,000-ms close threshold is a diagnostic proxy for POC-001's controlled
*destruction-confirmed* deadline, not satisfaction of that observer gate.

Stop the affected class immediately on timeout, late/duplicate completion,
clock-conversion overflow, unsafe file permission, invalid IPC input accepted,
trace write failure, non-fixture-window interaction, unexpected timer/poll,
or any privacy leak. Preserve only owner-private diagnostics, mark the class
failed/unresolved, and do not tune/retry ad hoc. Stop the entire fixture on
process-level cleanup failure.

## Tests to write before implementation logic

Write these pure tests first; they must not launch AppKit or create a window:

1. `ClockTests`: continuous selection/fallback metadata, checked tick
   subtraction, exact quotient/remainder conversion, and overflow rejection.
2. `TraceTests`: required fields/sequence ordering; rejection/redaction of
   raw IDs, title-like values, spaces, paths, URLs, and invalid tokens; `0600`
   output failure handling.
3. `FixtureControlTests`: only the four exact commands/states; one active
   window per token; invalid/duplicate/wrong-token rejection; serial command
   ordering; no implicit create/close/shutdown.
4. `LifecycleHookTests`: a fake notification gateway proves one completion per
   generation, wrong-object/duplicate rejection, user-close attribution, and
   registry removal only at the specified close hook.
5. `PendingWorkTests`: exactly one queued closure, one service record, and
   cancellation/rejection after close or shutdown; no timer/poll API in the
   control path.

Only after these tests exist may the separately authorized implementation add
the AppKit/IPC adapters. Build/test execution itself remains a later gate.

## Cleanup and authorization boundary

At each future run, close every registered fixture window, reject further IPC,
cancel outstanding bounded work, unlink the socket, flush/close the `0600`
trace, terminate the fixture, and verify no fixture process, socket, build
output outside `fixture/build`, login item, agent, watcher, or service remains.
Raw traces stay in the approved `0700` directory; only redacted aggregates may
be committed. At POC conclusion remove fixture source, build products, and
traces unless a result document names a POC-only diagnostic owner, use, and
negligible idle cost.

**Current authorized action: none.** The [live-calibration guide](fixture/LIVE-CALIBRATION.md)
records the completed one-sample observation and does not authorize a repeat
or any other live action. It did not authorize a Hammerspoon action, observer,
or fixture--observer correlation experiment. The proposed
[live-correlation guide](LIVE-CORRELATION.md) likewise requires separate
explicit human approval before any live action.
