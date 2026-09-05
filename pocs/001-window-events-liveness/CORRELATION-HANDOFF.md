# POC-001 fixture--observer correlation gate

**Status: fixture and observer source/test slices implemented; one live
correlation smoke completed.** POC-001 remains a **Hypothesis**. The design
below records the pre-run boundary; the observed result and its narrow
conclusion are in the [canonical POC
result](../../docs/pocs/001-window-events-liveness.md). No further fixture or
observer live action is authorized. This document is also linked from the
[fixture handoff](README.md).

## Decision boundary

The prior draft was insufficient: a fixture that omitted its raw token from
IPC/trace while the observer accepted any `corr-…` AX value had no common join
between fixture and observer records. It merely recognized a token-shaped
value. That design is rejected.

**Target, pending approval:** generate one random 80-bit raw correlation token
in fixture memory; assign it to the fixture `NSWindow`'s public
`accessibilityIdentifier`; calculate the full SHA-256 alias below; and emit or
return only that alias from the fixture. The observer makes one targeted
`AXIdentifier` read on its delivered fixture create callback, calculates the
same alias from the raw AX value, emits only the alias, and clears its raw value
immediately. Later analysis joins fixture and observer records by **exact alias
equality only**, never timing, callback order, or another identity field.

The alias association is POC instrumentation only. It proves neither liveness,
readiness, ownership, admission, destruction, callback delivery, nor a
production identity mechanism. It causes no window effect.

## Verified API basis

| Item | Status | Evidence and conclusion |
| --- | --- | --- |
| `NSWindow.accessibilityIdentifier` is a public setter candidate | **Verified** | The installed macOS SDK `AppKit/NSWindow.h` declares `NSWindow` conformant to `NSAccessibilityElement` and `NSAccessibility`. `NSAccessibilityProtocols.h` declares nullable/copy `accessibilityIdentifier`, serving `NSAccessibilityIdentifierAttribute`, available from macOS 10.10. |
| AX attribute spelling | **Verified** | Installed SDK `ApplicationServices/.../AXAttributeConstants.h` declares `kAXIdentifierAttribute` as `CFSTR("AXIdentifier")`. |
| `NSWindow.identifier` | **Verified but rejected** | `NSWindow` also conforms to public `NSUserInterfaceItemIdentification`, whose `identifier` property may identify a programmatically created window. The inspected headers do not state it propagates to `AXIdentifier`; it is not a fallback. |
| AppKit setter propagates to the remote callback AX object | **Hypothesis** | Headers prove neither cross-process propagation nor availability timing nor equivalence to Hammerspoon's AX object. The later smoke gate must establish this. |
| Hammerspoon can obtain/read an AX object for a delivered `hs.window` | **Verified** | Installed Hammerspoon 1.1.1 `hs/axuielement.lua` wraps `hs.axuielement.windowElement(obj)` and passes an `hs.window` through to its native constructor. Its docs specify formal `object:attributeValue(attribute)` for error-aware reads and warn that AX attributes depend on what an application exposes. |
| Hammerspoon SHA-256 | **Verified** | Installed Hammerspoon 1.1.1 `hs/hash.lua` documents `hs.hash.SHA256(data)` as returning the hexadecimal SHA-256 digest and says it is equivalent to `hs.hash.new("SHA256"):append(data):finish():value()`. `hs.hash.types` lists `SHA256` as a 256-bit cryptographic hash. The future observer uses the non-HMAC SHA-256 operation; there is no shared secret. |
| Public Swift SHA-256 | **Verified** | The installed macOS SDK has public `usr/include/CommonCrypto/module.modulemap` defining system module `CommonCrypto`, whose umbrella includes `CommonDigest.h`. That header declares `CC_SHA256_DIGEST_LENGTH` (32), `CC_SHA256_Init`/`Update`/`Final`, and one-shot `CC_SHA256`, available on macOS 10.4+. A future Swift fixture may `import CommonCrypto` and use this public API; CryptoKit was not relied on because it was not found in this Command Line Tools SDK. |
| Identical runtime output | **Hypothesis until tests run** | Both APIs document SHA-256/hex output, but the fixture and observer implementations must pass the same fixed vectors before any live gate. |
| Cross-process absolute-time basis | **Verified** | Hammerspoon [1.1.1 tag `extensions/timer/libtimer.m`](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/timer/libtimer.m) implements `hs.timer.absoluteTime` with `mach_absolute_time()` and `mach_timebase_info()`. Installed [`hs.timer` docs](https://www.hammerspoon.org/docs/hs.timer.html#absoluteTime) specify nanoseconds since boot, excluding sleep. This differs from the fixture's default `mach_continuous_time()` clock, so its old run-relative milliseconds could not support a direct close-candidate comparison. |

## Frozen alias format and security scope

For raw ASCII token `T` with the existing grammar `corr-` followed by exactly
16 uppercase RFC 4648 base32 characters, define:

```text
alias(T) = "poc001-corr-sha256-" + lowercase-hex(SHA-256(UTF-8 bytes of T))
```

The digest is the **full** 32-byte/64-lowercase-hex-character SHA-256 output;
it is never truncated. The explicit `poc001-corr-sha256-` prefix is part of the
emitted alias, not part of the hash input. No newline, NUL, JSON quoting, token
prefix normalization, or other bytes are included in the input.

Fixed cross-language vectors:

| Raw test token (test-only) | Required alias |
| --- | --- |
| `corr-AAAAAAAAAAAAAAAA` | `poc001-corr-sha256-83687efb86d2554f0547e44f7790efc5cc14b07af1ad8447ebb2d270cc6d7eac` |
| `corr-7777777777777777` | `poc001-corr-sha256-5e5f2182c2728604b072539a13264b2ed227582defd4deaa220f8ed8cb7e178b` |

SHA-256 is a public, unkeyed hash: **the alias is not a secret, MAC, or proof
that an untrusted app is the fixture.** The raw token is generated from 80 bits
of `SecRandomCopyBytes` output and is disposable POC data. Given a full alias,
that random 80-bit input makes practical reversal by brute force infeasible for
this scope; it does not prevent an accessibility client that reads the live
window's `AXIdentifier` from computing the alias. The gate relies on the
fixture-specific controlled experiment and exact alias equality, not on
adversarial authentication.

## Explicitly prohibited correlation inputs

An accepted join, fallback, or failure diagnosis must not use:

- title, `AXTitle`, subtitle, document name, URL, or user content;
- focus/key state, visibility/occlusion, z-order, Space, frame, PID or bundle
  identity alone, or callback/timing proximity;
- native window ID/number in fixture IPC/trace, observer export, logs, or git;
- `NSWindow.identifier` as an assumed AX bridge;
- global application/window/AX enumeration, `hs.window.find`, all-window
  snapshots, element scans, child traversal, `attributeNames`, or
  `allAttributeValues`; or
- retries, deferred reads, timers, polling, or production state/effects.

Missing/unavailable/malformed AX data, an alias calculation error, or an alias
mismatch is unresolved/failed evidence, never permission to use a prohibited
input.

## Implemented fixture source/test/build slice

The implemented, approval-pending fixture-only portion is limited to source,
pure tests, static checks, and build verification:

1. **Fixture:** generates `T` only in active fixture memory, calculates
   `alias(T)` with public CommonCrypto, and calls public
   `setAccessibilityIdentifier(T)` on the main thread before
   `create_requested` and `orderFrontRegardless()`. It clears the raw active
   token on matching close, shutdown, and create-error cleanup. Fixture trace
   and IPC records emit only `correlation_alias`; they omit
   `correlation_token`, raw AX values, PID, and native ID. The existing
   `fixture_token` remains the separate private close-control capability.
2. **Observer source/test slice (implemented; not live-authorized):** an
   explicit one-generation arm scopes only an already-delivered `windowCreated`
   callback from the exact fixture bundle. The bundle check is not association
   evidence and is not exported. That callback calls
   `hs.axuielement.windowElement(callback_window)` once and
   `:attributeValue("AXIdentifier")` once. It validates the exact raw-token
   grammar, computes `alias(T)` with `hs.hash.SHA256`, emits the alias, retains
   only `native-window-id -> correlation_alias` in memory, and immediately
   clears its raw Lua value/reference. It emits neither the raw token nor AX
   value.
3. **Join:** later local analysis accepts exactly one fixture record and one
   observer record only when their full aliases are byte-for-byte equal and
   have the frozen prefix/length. A missing peer, duplicate alias, malformed
   alias, or unequal aliases is a failure. Timing is reported only as a
   separate performance observation and cannot form or repair a join.
4. **Cleanup:** destruction callbacks remain candidate-only and do not clear
   correlation mappings. After close analysis, explicit observer sample
   cleanup (and observer stop/startup failure) clears raw token/value
   references, alias/native mappings, armed generation, and the callback
   subscription. There is no timer, poll, global scan, or production state.

**Hypothesis:** the public AppKit identifier appears as the same callback
window's `AXIdentifier`, allowing the two independently calculated aliases to
match. Source/header/doc evidence does not prove it.

## Build-only clock prerequisite — implemented, not live-authorized

**Verified:** the fixture now accepts only `POC001_FIXTURE_CLOCK_KIND` values
`mach_continuous` (the standalone default) and `mach_absolute`; any other value
fails closed before the fixture creates its trace/socket state. A separately
approved correlation smoke must explicitly select `mach_absolute`. Every fixture
trace record records `clock_kind`, raw `ticks`, `timebase_numer`, and
`timebase_denom`. The observer retains its run-relative `monotonic_ms` and now
records an independently sampled `absolute_ns` from `hs.timer.absoluteTime()`
on every event. `absolute_ns` is whitelisted scalar telemetry only; it carries
no raw AX value, native ID, PID, title, or other identity.

**Frozen comparison (Target for a later authorized smoke only):** with no sleep
during the sample, convert the fixture's `native_close_completed` raw ticks
using its record's frozen timebase:

```text
fixture_absolute_ns = (ticks / denom) * numer + ((ticks % denom) * numer) / denom
latency_ns = observer_destruction_candidate.absolute_ns - fixture_absolute_ns
```

The fixture clock kind must be `mach_absolute`; missing/invalid fields, a zero
or invalid timebase, observed sleep, or a negative/order-invalid latency fails
the sample. This comparison is diagnostic timing only: exact correlation alias
equality remains the sole join and no timing result may repair a failed join.
Pure fixture/Lua tests cover explicit mode selection, fail-closed invalid mode,
raw tick/timebase preservation, independent observer `absolute_ns`, redaction,
and negative/order failure.

**Prerequisite status:** source/test/build prerequisite complete; no smoke,
fixture launch, IPC, Hammerspoon load/action, authorization, or POC-001 result
has occurred. POC-001 remains a **Hypothesis**.

## Aborted research command

A research command accidentally started a second Hammerspoon process. It was
aborted; that process exited. It made no sample or configuration change and
produced no evidence. It is not a POC run and does not alter the authorization
boundary above.

## Fixed pass/fail, privacy, and query limits

- **Pass for the separately approved smoke sample:** exactly one fixture window
  and one create callback; one identifier assignment before ordering; one
  `windowElement` construction and one `AXIdentifier` read; valid raw grammar;
  one complete alias on each side; exact alias equality; no raw value export;
  one in-memory mapping only; and verified cleanup.
- **Fail:** no callback by the fixed timeout; AX object/read/hash error;
  missing/non-string/malformed raw value; malformed/unequal/duplicate alias;
  more than one targeted read; retry/timer/poll; enumeration/snapshot;
  prohibited input; raw token/native ID/PID/AX value leak; or cleanup failure.
  Do not retry a failed smoke sample ad hoc.
- **Timing/query:** correlation is equality-based, not timing-based. Record
  callback processing and the one read/hash duration separately; retain the
  POC-001 p95 <= 50 ms and maximum <= 100 ms callback limits. The strict query
  budget is one `AXIdentifier` read per armed generation, zero reads for a
  duplicate/unresolved generation, zero global AX/app/window enumerations and
  snapshots, and zero polling.
- **Privacy:** raw values exist only in fixture memory and transiently in the
  observer callback. Owner-private diagnostics remain `0700`/`0600`; committed
  evidence includes aliases, counts, durations, environment, and outcomes only.
  The live AX identifier remains readable by accessibility clients while the
  disposable window exists; its random input is not user data.

## Required tests before any live gate

These future tests are pure/source tests; they do not prove propagation:

1. Fixture tests verify raw 80-bit token generation, the two vectors using
   CommonCrypto, full lowercase-hex/prefix format, assignment before
   trace/order, alias-only IPC/trace schema, and raw-token clearing on
   close/shutdown.
2. Observer tests verify the same two vectors through `hs.hash.SHA256`, exact
   one-read behavior, raw grammar rejection, immediate raw-reference clearing,
   alias-only export, in-memory-only native mapping, and cleanup on every exit.
3. Cross-language fixture/observer fixtures exchange each fixed vector's
   **alias only** and require byte-for-byte equality. An intentionally altered
   one-hex-character observer alias must fail the join (`alias_mismatch`), with
   no title/focus/PID/timing fallback.
4. Discipline fakes/spies prove no `attributeNames`, `allAttributeValues`,
   child traversal, `hs.window.find`, global enumeration, title/focus/
   visibility/PID/native-ID correlation input, timer, poll, or effect.
5. Static documentation tests keep this draft linked from the canonical result
   and fixture handoff, retain both vectors, alias mismatch failure, the smoke
   gate before volume, and the no-authorization statement.

If either runtime cannot pass the fixed vectors with the frozen bytes and
format, stop and record the unresolved compatibility result. Do not substitute
a private hashing API, a different encoding, a raw-token export, or a rejected
correlation input without a new handoff.

## Later live sequencing (not authorized now)

The one-sample correlation smoke completed under the
[live-correlation guide](LIVE-CORRELATION.md). The separately approved volume
attempt is recorded in the canonical POC result: the warm class stopped during
sample 2 and the five cold samples completed but missed the readiness bound.
No further correlation volume is authorized. Neither the completed smoke nor
the partial/failing volume alone passes POC-001's liveness, readiness,
destruction, or source-selection gates.

## Alternatives, stop rule, and authorization

`NSWindow.identifier` is not an AX propagation guarantee; custom AX children
would not prove the callback's `hs.window` is that child; and all title/scan
alternatives are prohibited. If `accessibilityIdentifier` cannot be applied to
`NSWindow`, AX propagation fails, hashing compatibility fails, or aliases do
not exactly match, record failure and **stop**. Do not invent a private AX
attribute, bridge `NSWindow.identifier`, expose raw correlation data through
IPC/trace, or add a fallback.

**Current authorized action: source, pure-test, and recorded-result review
only.** No app launch, IPC request, Hammerspoon observer load, or further live
action is authorized by this handoff.
