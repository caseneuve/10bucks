# POC-001 fixture--observer correlation gate

**Status: separately gated research/implementation handoff; no implementation or
live action is authorized.** POC-001 remains a **Hypothesis**. This document
freezes the only candidate for associating one fixture correlation token with
exactly the `hs.window`/AX window object delivered by that fixture's own create
callback. It is linked from the [canonical POC result](../../docs/pocs/001-window-events-liveness.md)
and the [fixture handoff](README.md).

This is not an authorization to build, launch, call IPC, load/reload
Hammerspoon, call an Hammerspoon API, or run a live experiment. It is a
research/documentation gate only.

## Decision boundary

**Target:** before a later, separately approved experiment, the fixture may
expose its random `correlation_token` **only** as public, fixture-local
Accessibility metadata. It is not included in fixture IPC responses or fixture
trace records for this experiment. On the observer's *own fixture create
callback*, it may perform exactly one targeted read of that callback's AX
window element. A well-formed token returned by that exact read is associated
with that callback's window. The observer retains the native mapping in memory
only and emits a redacted token alias.

This association is POC instrumentation only. It does not establish liveness,
readiness, ownership, admission, destruction, callback delivery, or a
production window identity mechanism. It causes no window effect and makes no
production behavior change.

## Evidence and proposed public interface

| Item | Status | Evidence and conclusion |
| --- | --- | --- |
| `NSWindow` can receive an AppKit accessibility identifier | **Verified** | The installed macOS SDK's `AppKit/NSWindow.h` declares `NSWindow` conformant to `NSAccessibilityElement` and `NSAccessibility`. `NSAccessibilityProtocols.h` declares the nullable, copyable `accessibilityIdentifier` property, documented there as serving `NSAccessibilityIdentifierAttribute`; it is available from macOS 10.10. `NSAccessibilityConstants.h` declares `NSAccessibilityIdentifierAttribute` as an `NSString` attribute. Therefore `window.accessibilityIdentifier = correlationToken` is a public fixture-local setter candidate. |
| AX name for that attribute | **Verified** | The installed SDK's `ApplicationServices/.../AXAttributeConstants.h` declares `kAXIdentifierAttribute` as `CFSTR("AXIdentifier")`. The candidate reader asks for exactly `"AXIdentifier"`; it does not invent a private name. |
| `NSWindow.identifier` can be set | **Verified, but rejected as the experiment interface** | `NSWindow` also conforms to `NSUserInterfaceItemIdentification`; that public protocol declares `identifier`, and its header explicitly says a programmatically created window may be assigned one. But the inspected headers do not document that this property is exported as `AXIdentifier`. It is not a substitute for `accessibilityIdentifier` and will not be tested as a fallback. |
| A remote client sees the setter as the callback window's `AXIdentifier` | **Hypothesis** | The declarations show a setter and the AX attribute name, but do not prove cross-process propagation, availability timing, or that AppKit's AX window is the same object Hammerspoon exposes. This must pass the frozen experiment below. |
| Hammerspoon can get an AX object for an existing `hs.window` | **Verified** | Installed Hammerspoon 1.1.1 `hs/axuielement.lua` wraps `hs.axuielement.windowElement(obj)` and passes an `hs.window` object through to its native constructor. Its module documentation says AX objects only support data application developers make available. |
| Hammerspoon can perform a targeted formal AX attribute read | **Verified** | The same installed module documents `object:attributeValue(attribute)` and says to use this formal method when AX errors matter. It also documents that dynamic attributes depend on the element. The candidate uses only `element:attributeValue("AXIdentifier")`; it does not enumerate `attributeNames`, `allAttributeValues`, children, applications, or windows. |
| The existing observer callback object is suitable for `attributeValue` | **Rejected for this experiment** | The canonical POC's first calibration observed that its direct callback/window objects did not support the assumed `attributeValue` method. The current observer correctly relies on its narrow public methods for existing metadata. This gate therefore does **not** reuse that object for the identifier read: it obtains the AX object from the already-delivered `hs.window` with `hs.axuielement.windowElement(window)`. |

The chosen candidate is consequently:

```swift
// Fixture, before the window is ordered front; future gated implementation only.
window.accessibilityIdentifier = correlationToken
```

```lua
-- Observer, in the delivered fixture create callback; future gated implementation only.
local ax = hs.axuielement.windowElement(callback_window)
local value, err = ax:attributeValue("AXIdentifier")
```

The snippets specify the public API boundary only; they are not approved code.
No fallback reads a title, content child, or another window.

## Explicitly rejected association inputs

The following are prohibited both for an accepted association and for a
fallback after an unavailable or malformed identifier:

- title, `AXTitle`, subtitle, document name, URL, or other user content;
- focus/key state, visibility/occlusion, z-order, Space, frame, or event order;
- PID or bundle identity **alone** (they may scope a fixture watcher but never
  prove which fixture window/token is involved);
- a native window ID/number in committed output, fixture IPC/trace output, or
  exported observer trace;
- `NSWindow.identifier` as an assumed `AXIdentifier` bridge;
- global application/window/AX enumeration, `hs.window.find`, all-window
  snapshots, or scanning elements for a token; and
- timing proximity between create response, callback arrival, or any other
  marker.

A missing, malformed, unavailable, erroring, or non-equal `AXIdentifier` is a
failed/unresolved sample, not permission to use one of these inputs.

## Frozen minimal implementation experiment

A later approval may authorize this *separate POC-only source slice*, and no
more:

1. **Fixture:** after `createWindow()` constructs the sole registered
   `NSWindow`, assign its generated `corr-…` token to
   `accessibilityIdentifier` on the main thread **before** `create_requested`
   and `orderFrontRegardless()`. In this experiment, remove
   `correlation_token` from the fixture IPC response and trace schema: public
   Accessibility metadata is the token's only exposure. (The separate
   `fixture_token` remains the private close-control capability.) It must not
   put the correlation token in the title, a view, user-defaults, a native ID,
   or any new IPC command.
2. **Observer:** arm one fixture-specific create subscription before the
   controlled fixture create. When that subscription delivers its `hs.window`,
   call `hs.axuielement.windowElement(callback_window)` once and make one
   formal `attributeValue("AXIdentifier")` call on the result. Do not first
   call `attributeNames`; do not retry, defer, schedule a timer, or search.
3. **Association:** accept only a returned string matching the frozen
   `corr-<base32>` grammar, allocate a per-run redacted alias (for example
   `fixture-token-001`), retain `native-window-id -> fixture-token-alias` only
   in the observer's in-memory map, and emit `fixture_correlation_matched`
   containing the alias, sample/generation alias, source, and targeted-read
   count. The raw token, PID, native ID, and AX value never leave memory.
4. **Unresolved:** emit one redacted `fixture_correlation_unresolved` reason
   (`ax_object_unavailable`, `attribute_error`, `missing`, `malformed`, or
   `duplicate_callback`), retain no association, and perform no additional
   query. A duplicate callback after a match is a redacted duplicate with zero
   reads; a callback after an unresolved result does not retry that generation.
5. **Cleanup:** clear the armed generation, the alias/native map entry,
   and the callback subscription at fixture close, observer stop, any timeout,
   and startup failure. The experiment owns no timer, poll, global watcher
   beyond its bounded create subscription, or production state.

**Hypothesis:** AppKit will expose the token as the exact `AXIdentifier` of the
same AX object constructed from that callback's `hs.window`, early enough for
this single read. No source/header/doc result upgrades this hypothesis.

## Fixed pass/fail and privacy/query limits

A future authorization must use these limits unchanged:

- **Pass per sample:** exactly one fixture window; one public identifier
  assignment before ordering; one delivered fixture create callback; exactly
  one `windowElement` construction and one `AXIdentifier` read; returned value
  matches the frozen `corr-<base32>` grammar; exactly one token alias is
  emitted; one
  in-memory-only native mapping is present until cleanup; and cleanup removes
  it. No prohibited input is read or logged for correlation.
- **Fail per sample:** no callback by the fixed sample timeout; unavailable AX
  object; AX error; absent/non-string/malformed value; duplicate
  match; more than one targeted identifier read; a retry; any timer/poll;
  global enumeration/snapshot; leaked raw token/native ID/PID/AX value; or
  cleanup failure. A failed sample is not retried ad hoc.
- **Timing:** association is equality-based, never timing-based. Record
  callback processing duration and the one targeted-read duration separately;
  do not calculate or claim create-to-callback correlation latency from them.
  Existing POC-001 callback processing limits remain p95 <= 50 ms and maximum
  <= 100 ms. The one identifier read is included in that callback duration.
- **Query limit:** one targeted AX attribute read for one fixture create
  callback/generation; zero reads for duplicate/unresolved callbacks; zero
  global AX/app/window enumerations and zero all-window snapshots in every
  experiment callback; zero permanent or bounded polling.
- **Privacy:** raw correlation tokens, native IDs, PIDs, titles, AX values,
  responses, and raw traces stay owner-private (`0700` directory/`0600`
  files). Commit only redacted aliases, counts, durations, OS/Hammerspoon
  versions, and aggregate pass/fail. The public AX identifier is intentionally
  readable by accessibility clients while the disposable fixture window lives;
  it is a random 80-bit token, never user data, and is cleared with fixture
  teardown.

## Required tests before any live gate

These are future pure/source tests, not evidence of macOS propagation:

1. **Fixture ordering test:** a fake window port receives the correlation token
   and records `accessibilityIdentifier` assignment before
   `create_requested`/`orderFront`; no title or `identifier` setter is used.
2. **Fixture lifecycle/privacy tests:** only the active generation's random
   `corr-` token is assigned; close/shutdown clears the fixture-held token;
   the experiment's trace/IPC schemas omit `correlation_token` and contain no
   native ID/PID or exported AX value.
3. **Observer exact-match test:** one fake create callback produces one
   `windowElement` call, one `attributeValue("AXIdentifier")` call, one alias,
   and an in-memory native mapping only.
4. **Observer rejection tests:** unavailable AX object, AX error, nil,
   malformed, duplicate callback, startup failure, observer stop,
   and fixture close each produce no mapping/retry/effect and clear state.
5. **Observer discipline test:** fakes/spies prove no `attributeNames`,
   `allAttributeValues`, child traversal, `hs.window.find`, global enumeration,
   title/focus/visibility/PID/native-ID correlation input, timer, or poll.
   Exported event fixtures must contain aliases only.
6. **Static handoff test:** assert this document remains linked by the
   canonical result and fixture handoff, and that its pass/fail/query limits
   remain present.

## Later live procedure (not authorized now)

After the source tests are green, a new explicit human approval must freeze the
exact commit and permit one fixture--observer experiment. Its procedure is:

1. Start from a clean tree and fresh owner-private `0700` run directory; record
   OS, Hammerspoon 1.1.1, commit, and supported display/settings facts locally.
2. Stop legacy 10bucks, load only the POC observer, and arm one fixture create
   generation before a single controlled fixture create. Do not bootstrap scan,
   enumerate, focus, or manually select a window.
3. Create the sole fixture window. Capture only redacted observer counters and
   aliases. The observer makes the frozen single targeted read in its own
   delivered fixture create callback.
4. Evaluate the fixed per-sample criteria. Do not use callback order or elapsed
   time to repair an unresolved sample.
5. Close and shut down the fixture using the existing controlled cleanup,
   stop the observer, clear maps/subscriptions, verify zero active timers and
   no fixture process/socket, and retain raw material privately.

The volume is 30 warm and 5 cold fresh-fixture-create samples, with every
sample retained (including failures/timeouts). Stop the entire path on the
first privacy, query, prohibited-input, or cleanup violation. A result must
report each sample's one-read count, callback/read durations, outcome reason,
map cleanup, and aggregate median/p95/maximum; it must not commit raw
correlation data. Passing this correlation gate still does not pass POC-001's
liveness, destruction, readiness, or source-selection gates.

## Alternatives and stop rule

`NSWindow.identifier` remains a documented AppKit identifier but is not an AX
propagation guarantee, so it is rejected rather than used as a fallback. A
custom AX child/view would require a different object-to-window relation and
would not prove that the observer callback's `hs.window` is that child; it is
outside this minimal gate. Titles and all discovery scans are prohibited.

If the public `accessibilityIdentifier` setter cannot be compiled/applied to
`NSWindow`, or the live gate fails to return the exact token from the callback
window's `AXIdentifier`, record the failure and **stop**. Do not invent a
private AX attribute, bridge `NSWindow.identifier`, add IPC identity export,
or substitute any rejected correlation input. Any different public alternative
requires new SDK research and a new separately approved handoff.

## Authorization and cleanup

**Current authorized action: documentation review only.** No code change,
build, app launch, IPC request, Hammerspoon call, observer load, or live action
is authorized by this handoff. Any future source slice remains POC-only and is
removed with its artifacts after the result unless a later result names a
retained diagnostic owner, use, and negligible idle cost.
