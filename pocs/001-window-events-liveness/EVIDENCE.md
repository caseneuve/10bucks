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
- **Hypothesis:** on a relevant direct AX callback, the five per-window AX
  attributes `AXMinimized`, `AXFullScreen`, `AXRole`, `AXSubrole`, and
  `AXVisible` can be read cheaply and consistently enough to mark
  `metadata_ready`. Every unavailable attribute or read error is recorded as
  uncertainty; no live result has established availability or latency.
- **Hypothesis:** because the inspected direct event constants contain no
  fullscreen notification, a direct move/resize callback can trigger a
  targeted `AXFullScreen` observation. The trace labels this
  `targeted_observed_property`; it does not infer fullscreen from visibility,
  onscreen state, or Space membership.
- **Target:** `metadata_ready` requires all five privacy-safe fields. The
  harness does not emit `window_ready_eligible`; actual Space ownership is
  deliberately deferred to Step 2C.

## Framework-internal query/lifecycle caveats

- **Verified:** installed `hs/window_filter.lua` `startGlobalWatcher()` calls
  `window._orderedwinids()` and `application.runningApplications()` when its
  global watcher begins. This harness does **not** treat that framework work as
  POC-issued queries. It is a source-inspected candidate-framework fact, not a
  claim that it is zero.
- **Verified:** the same installed filter source’s Space-change path can call
  `getCurrentSpaceWindows()`; comments state it is inefficient because it
  relies on `hs.window.allWindows()`. This 2A harness subscribes only to
  create/focus/destroy and does not use a Space-aware filter, but source
  inspection alone does not prove that all relevant framework refreshes are
  absent. The eventual selection gate remains **unknown** pending instrumented
  live evidence.
- **Verified:** installed `hs/uielement.lua` creates and starts a module-global
  `hs.application.watcher` to stop UI-element watchers on app termination.
  `hs.uielement.watcher:start()` also automatically adds an element-destroyed
  watch for non-application elements unless requested. Therefore `stop()` in
  this POC stops every watcher it owns, but cannot unload the Hammerspoon
  module-global cleanup watcher; its host/module lifetime is an explicit
  framework-internal caveat, not a leaked POC-owned watcher.

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
  are unique reciprocal confirmations and differ. Its output is non-effecting.
  Safe metadata readiness from 2B plus current unique regular ownership emits
  one idempotent `window_ready_eligible`; focus itself does not admit.

## Implication

This observer is suitable only to collect comparison evidence. Step 2C adds no
production behavior, timer, action, reload, or live result. The pure fake
suite proves its bookkeeping and cleanup, not macOS behavior. It proves no
liveness/destruction authority, live lifecycle distinction, Space behavior,
metadata readiness, latency, or query-gate result. In particular, it must not
be used to claim zero framework-internal global refreshes.
