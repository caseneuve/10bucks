# POC-001 API/source evidence (steps 2A–2B)

**Status:** source-inspection and pure-fake evidence only. No Hammerspoon
reload, live POC load, or live action was performed for this checkpoint.

## Verified local host/API facts

- **Verified:** `/Applications/Hammerspoon.app/Contents/Info.plist` reports
  Hammerspoon `1.1.1`.
- **Verified:** the installed
  `Resources/extensions/hs/window_filter.lua` documents and exposes
  `windowCreated`, `windowFocused`, `windowDestroyed`, and `windowMoved`. Its `subscribe`
  callback receives `(hs.window, appName, event)`. Its `windowfilter.new()`
  implementation defines `true` as an empty filter that allows every window
  and `false` as a default reject-all rule. The observer therefore uses
  `new(true, "poc001-window-events")`; `new(false, ...)` cannot collect the
  requested comparison events. The POC preserves a per-run raw-ID-to-redacted-
  alias cache for the **hypothesis** that a destruction callback can retain its
  native ID when a separate `window:application()` lookup is unavailable; this
  is harness correlation logic, not a claim about live callback ordering.
- **Verified:** installed `Resources/extensions/hs/window_filter.lua` exposes
  `windowMinimized`, `windowUnminimized`, `windowFullscreened`, and
  `windowUnfullscreened`. Its implementation derives fullscreen changes while
  handling a window move; this is source evidence for comparison only, not
  proof of live callback ordering.
- **Verified:** installed `Resources/extensions/hs/uielement.lua` documents
  application-level `windowCreated` (`AXWindowCreated`) and
  `focusedWindowChanged` (`AXFocusedWindowChanged`) events, and says those
  callbacks receive the relevant child element. It defines direct window
  notifications `windowMoved` (`AXWindowMoved`), `windowResized`
  (`AXWindowResized`), `windowMinimized` (`AXWindowMiniaturized`),
  `windowUnminimized` (`AXWindowDeminiaturized`), and `elementDestroyed`
  (`AXUIElementDestroyed`). It exposes no selected direct fullscreen
  notification.
- **Verified:** the inspected local Hammerspoon source at
  `/Users/piotr/Git/external/hammerspoon` commit `23e387e` has
  `extensions/application/libapplication_watcher.m`, whose watcher subscribes
  to NSWorkspace launch, termination, hide/unhide, activate/deactivate
  notifications and invokes Lua with `(appName, event, hs.application)`.
  Its in-source documentation warns that the terminated name can be `nil` and
  the application object may only be useful for its PID.

## POC-issued bootstrap queries

- **Verified:** `hs.application:allWindows()` is the available narrow
  per-application enumeration API in installed `hs/application.lua` (which
  uses it to build `visibleWindows()`). At explicit startup only, this POC
  records one `per_application_window_scan` / `bootstrap.attach_existing_windows`
  query per app returned by the separately labeled global
  `bootstrap.attach_existing_apps` scan, then attaches a direct destruction
  watcher to each identified existing window. It does not call either method
  from a steady callback.

## Step 2B correlation and metadata hypotheses

- **Target:** the pure `lifecycle.lua` correlator is keyed exclusively by
  per-run redacted `app-NNN`/`win-NNN` aliases. Every lifecycle fact is
  tri-state: absent is unknown, never false. `app_hidden` starts unknown and
  changes only from the shared attributed application hide/unhide source;
  no targeted app-hidden property read is selected at this checkpoint.
  Filter and direct-AX minimize/fullscreen facts live in isolated candidate
  records, so a late contradictory callback cannot overwrite the other. Each
  candidate derives availability false when any condition is true, true only
  when all three are explicitly false, and otherwise unknown. Conflicts are
  traced. The correlator has no removal, liveness, or admission operation.
  Fake sequence coverage includes both prescribed minimize/hide orderings,
  duplicates/stale facts, fullscreen overlap, and competing-source conflicts.
- **Superseded hypothesis:** direct callback objects support
  `attributeValue()` for `AXMinimized`, `AXFullScreen`, `AXRole`, `AXSubrole`,
  and `AXVisible`. The first calibration found no such method on all 72
  attempted reads, so the observer no longer depends on it.
- **Verified (first calibration):** the observed callback/window shape exposes
  the narrow public methods `isMinimized`, `isFullScreen`, `role`, `subrole`,
  and `isVisible`. The observer queries a method only when present, attributes
  each field separately, and records missing/failed methods as uncertainty.
  Local source inspection did not establish an equivalent AX-element fallback,
  so none is used. Visibility remains readiness metadata only and is never
  liveness evidence.
- **Hypothesis:** because the inspected direct event constants contain no
  fullscreen notification, a direct move/resize callback can trigger a
  targeted `AXFullScreen` observation. The trace labels this
  `targeted_observed_property`; it does not infer fullscreen from visibility,
  onscreen state, or Space membership.
- **Target:** `metadata_ready` requires all five privacy-safe fields. Complete
  readiness fields are read on bootstrap/create/focus; move/resize reads only
  minimize/fullscreen. Cached safe fields merge monotonically, so a lifecycle
  callback need not return every readiness field. Step 2C emits the
  non-effecting `window_ready_eligible` marker only when safe metadata and one
  confirmed regular owner intersect; focus itself does not admit.

## Framework-internal query/lifecycle caveats

- **Verified:** installed `hs/window_filter.lua` `startGlobalWatcher()` calls
  `window._orderedwinids()` and `application.runningApplications()` **when its
  global watcher begins**, before ordinary filter callbacks while that watcher
  remains active. Tag-matched Hammerspoon 1.1.1 source implements the former
  with an on-screen CoreGraphics window-list snapshot and the latter by
  enumerating `NSWorkspace` running applications. This harness does **not**
  treat that startup framework work as POC-issued queries. It is a
  source-inspected candidate-framework fact, not a claim that it is zero.
- **Verified:** the same installed filter source’s Space-refresh path can call
  `getCurrentSpaceWindows()`, which calls `hs.application:allWindows()` once
  for every tracked application; it does **not** call public
  `hs.window.allWindows()`. Tag-matched Hammerspoon 1.1.1 source implements
  that per-application enumeration with
  `AXUIElementCopyAttributeValues(..., kAXWindowsAttribute, 0, 100, ...)`.
  Space-aware filter rules/subscriptions, or
  `forceRefreshOnSpaceChange == true`, can therefore cause broad
  per-application AX enumeration on an active-Space refresh; with a
  Space-aware filter, visible creation/unhide paths can also refresh that
  application. The POC filter's `new(true, ...)` configuration and selected
  events do not independently enable this path, but the filter module's
  Space-aware instance state is shared, so another active filter is an
  unresolved host-state condition. The selection gate remains **unknown**
  pending the required isolation/instrumented evidence.
- **Verified:** loading installed `hs/window_filter.lua` unconditionally
  constructs and starts an `hs.spaces.watcher`. Tag-matched Hammerspoon 1.1.1
  watcher source registers for `NSWorkspaceActiveSpaceDidChangeNotification`
  and, before Lua dispatch, calls
  `CGWindowListCopyWindowInfo(kCGWindowListOptionAll |
  kCGWindowListOptionOnScreenOnly, ...)` to scan for
  `kCGWindowWorkspace`. This is a broad WindowServer/CoreGraphics scan, not an
  AX enumeration and not `hs.window.allWindows()`. The POC separately starts a
  second direct `hs.spaces.watcher`, so both watcher registrations have this
  source-level scan path. Source establishes neither installed-binary
  provenance beyond the observed Hammerspoon version nor callback delivery
  frequency/coalescing, scan cost/main-thread effect, or reliable workspace
  availability on this host; those are **unknown** C/framework behavior, not
  zero framework refresh.
- **Verified (provenance limited):** the installed Hammerspoon **1.1.1** Lua
  wrapper `Resources/extensions/hs/uielement.lua` byte-matches the inspected
  retained source `extensions/uielement/uielement.lua`; the retained native
  sources were inspected with it. This verifies the installed Lua wrapper plus
  the stated retained-source behavior, **not** compiled-binary source
  provenance. The wrapper creates and starts a module-global
  `hs.application.watcher` which, on a usable matching-PID termination
  callback, native-stops registered UI-element watchers. It cannot be unloaded
  by POC-owned `stop()`; its host/module lifetime is a framework-internal
  caveat, not a leaked POC-owned watcher.
- **Verified (same provenance limit):** starting a non-application
  `hs.uielement.watcher` automatically subscribes it to
  `AXUIElementDestroyed`. The wrapper forwards that event only when it was
  explicitly requested; otherwise it uses it for cleanup and does not call the
  client callback. On delivery it may use the retained watched element because
  the dead-element wrapper can lack PID/ID fields, then stops the watcher.
  Native `AXObserverAddNotification` results are ignored, so source does not
  prove every requested notification registered successfully.
- **Verified (same provenance limit):** direct AX callback payload conversion
  synchronously performs per-element role/minimized checks and, for a window
  wrapper, PID/private native-window-ID conversion before Lua callback
  dispatch. The inspected direct UI-element watcher, module-global termination
  cleanup, and direct application-watcher start/callback paths contain no
  source-visible running-application enumeration, all-window snapshot, or
  `AXWindows` enumeration. This does not establish lower-level framework/OS
  work, runtime callback frequency/cost/main-thread impact, notification
  delivery, ordering, duplication, or latency; all remain **unknown**, not
  zero.
- **Verified (same provenance limit):** the direct application watcher uses
  NSWorkspace termination notifications, whose documented termination payload
  may have a nil name and an application object useful only for PID. Neither
  that event nor `AXUIElementDestroyed` is declared authoritative by inspected
  source. Both remain independently recorded destruction candidates only, not
  `destruction_confirmed` or a selected authority. POC-001 remains a
  **hypothesis** pending its controlled live/correlation and query-gate
  evidence.

## Step 2C Space ownership/readiness source findings

- **Verified:** installed `hs.spaces.lua` implements `spaceType(id)` by calling
  `data_managedDisplaySpaces()` and walking every managed display/Space on each
  invocation. The Step 2C observer instead issues one attributed
  `data_managedDisplaySpaces()` topology snapshot per ownership observation and
  classifies all returned IDs (`type == 0` regular; `type == 4` fullscreen;
  other/missing type unknown). It intentionally makes no repeated `spaceType()`
  calls.
- **Verified:** the same local source wraps `windowsForSpace()` to inspect
  Hammerspoon's own AX application windows and prune some non-window canvases.
  This is a private/global-cost caveat: each POC-issued reciprocal query is
  timed and counted, but source inspection cannot establish its live cost or
  prove full semantic reliability. A missing/failed reciprocal result becomes
  ownership uncertainty, never death.
- **Verified:** `activeSpaceOnScreen()` and `spaceType()` each obtain managed
  display data in the installed Lua source. The observer records the active
  query separately and does not mistake it for a free read.
- **Hypothesis:** `hs.spaces.watcher` active-Space callbacks and direct AX
  move/resize, filter move, creation, and focus callbacks provide sufficiently bounded
  triggers for the selected observations. The observer compares them only; no
  live ordering, latency, or ownership fact is established.
- **Target:** the pure `ownership.lua` accepts redacted aliases only, retains
  prior confirmed regular membership across fullscreen/unknown/ambiguous
  observations, and emits a move only when both prior and new regular owners
  are unique reciprocal confirmations and differ. It records membership count,
  reciprocal-confirmed count, `unique_regular`/`fullscreen`/`ambiguous`/
  `query_error`/`missing` reason, and retained prior owner; fullscreen,
  unknown, and same-regular outcomes emit non-effecting `no_regular_move`.
  Safe metadata readiness from 2B plus current unique regular ownership emits
  one idempotent `window_ready_eligible`; focus itself does not admit.
- **Target (instrumentation correction before manual move):** one active-Space
  callback reads active Space once and, when not a same-generation/value
  duplicate, obtains one topology snapshot for its complete known-window sweep.
  Every ownership probe reuses that snapshot. A duplicate emits an explicit
  coalesced outcome and performs no sweep; there is no timer. Sweep traces
  record exact POC-issued query attempts and unique known-window count.
- **Target (operator correlation):** `begin_target_action` performs one
  read-only focused-window query, resolves only the existing in-memory identity
  cache, and records redacted target/regular-owner evidence in `action_begin`.
  Missing or uncertain target/ownership rejects the binding. It cannot admit or
  effect a window. While bound, destruction candidates are classified as target
  or non-target and remain candidates only.

## Chromium sample 006 — redacted result

**Observed, narrow only:** the private, schema-valid
`chromium-create-focus-destroy-006` export was analyzed locally and is not
committed. It contains no raw IDs, titles, URLs, or AX values in this document.
The observer stopped cleanly, no callbacks remained open, and its final
`cleanup_complete` count was zero.

- The two destructive binds resolved two distinct temporary-window aliases
  (called **first bound temporary window** and **second bound temporary
  window** here). The retained regular owner at each bind was confirmed. No
  application alias is retained in this result.
- Both temporary closes produced one filter `windowDestroyed` candidate and
  one direct `AXUIElementDestroyed` candidate for the bound target. Filter was
  first in both pairs; direct followed by **0.278 ms** and **0.507 ms**,
  respectively. The filter missed neither observed close. These remain paired
  candidates only: there was no `destruction_confirmed`, authority selection,
  or general delivery guarantee.
- The protocol's covered-window marker did not name an alias. For the eventual
  first bound close target, no destruction candidate appeared before its close
  pair. That is no false-destruction observation for this eventual target, not
  proof that every covered window is safe.
- There is no controlled native-close completion marker, so there is no
  confirmation/latency result. The sample intentionally excluded a true
  last-Chromium-window close.
- Completed callback processing duration was **n=230**, median **3.862 ms**,
  nearest-rank p95 **33.013 ms**, maximum **91.586 ms**. These are harness
  processing durations, not callback-arrival or next-key-service latency.
- The 130-callback `AXWindowResized` burst produced 650 direct-window query
  attempts (five per callback). Fourteen non-coalesced active-Space,
  known-window-only sweeps occurred on the prescribed chat-switch path; each
  covered 6–8 known aliases and used 10–14 ownership queries (181 total).
- The export reports zero POC-issued steady global queries; it contains no
  timer creation/cancellation/fire, permanent poll, or POC window effect.
  This does not settle the separately recorded framework-internal filter
  refresh caveat.

**Target instrumentation correction, evidence-driven:** the observed resize
amplification justifies narrowing only the direct `AXWindowResized` ownership
path. Resize still reads targeted minimized/fullscreen properties. It probes
Space ownership only when `native_fullscreen` is newly known or changes from
its cached value; unchanged successful reads emit
`ownership_check_skipped` with `reason=resize_fullscreen_unchanged`.
`AXWindowMoved` continues to probe ownership on every event. If the fullscreen
method is unavailable, the observer records `metadata_uncertain` and an
explicit non-effecting skipped record (the same reason with
`fullscreen_status=unavailable`); it intentionally retains prior confirmed
ownership rather than inferring a move, liveness change, or destruction. This
is POC instrumentation only, not a production adapter decision. Pure-fake
coverage verifies repeated same-fullscreen resize skips, both fullscreen
transitions probe, moved always probes, and unavailable resize is
non-destructive.

## Fixture-only one-sample smoke/calibration — recorded result

**Observed, fixture-only:** one approved warm fixture smoke/calibration sample
completed. All eight expected markers occurred exactly once and in order.
Redacted timing aggregates were **52.508 ms** for create-visible, **0.115 ms**
for pending work, and **0.419 ms** for close.

- Trace/schema validation, marker order/counts, and owner-only `0600`
  permissions passed. Cleanup passed: the socket and process were absent, and
  the tree was clean.
- The delegated runner first reported **FAILED** because its ad hoc evaluator
  incorrectly required `elapsed_ticks` on request records and subtracted
  completion metadata. No rerun occurred. The orchestrator performed a bounded
  local review against the documented schema: each completion record already
  carries `elapsed_ticks` for its request-to-completion interval, with the
  timebase frozen by `run_started`.
- The one close value satisfies the fixture-local **<= 1,000 ms** one-sample
  diagnostic limit, and the one pending-work value satisfies its **<= 100 ms**
  maximum diagnostic limit. The create value is below 100 ms only as a
  diagnostic. This sample cannot establish a warm p95 or a warm-create pass.

Classify this as a successful fixture-only smoke/calibration observation only.
It is not a POC-001 pass, not warm-p95 evidence, and does not prove observer,
liveness, readiness, destruction-authority, Hammerspoon, or
representative-app behavior.

## Implication

The observer also records direct-AX and filter destruction candidates
independently and emits an idempotent paired-candidate diagnostic only when
both sources report one alias. It never emits `destruction_confirmed` and
selects no authority.

This observer is suitable only to collect comparison evidence. Step 2C adds no
production behavior, timer, action, reload, or live result. The pure fake
suite proves its bookkeeping and cleanup, not macOS behavior. It proves no
liveness/destruction authority, live lifecycle distinction, Space behavior,
metadata readiness, latency, or query-gate result. In particular, it must not
be used to claim zero framework-internal global refreshes.
