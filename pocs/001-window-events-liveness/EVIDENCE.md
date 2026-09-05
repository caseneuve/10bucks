# POC-001 API/source evidence (step 2A)

**Status:** source-inspection evidence only. No Hammerspoon reload, live POC
load, or live action was performed for this checkpoint.

## Verified local host/API facts

- **Verified:** `/Applications/Hammerspoon.app/Contents/Info.plist` reports
  Hammerspoon `1.1.1`.
- **Verified:** the installed
  `Resources/extensions/hs/window_filter.lua` documents and exposes
  `windowCreated`, `windowFocused`, and `windowDestroyed`. Its `subscribe`
  callback receives `(hs.window, appName, event)`. Its `windowfilter.new()`
  implementation defines `true` as an empty filter that allows every window
  and `false` as a default reject-all rule. The observer therefore uses
  `new(true, "poc001-window-events")`; `new(false, ...)` cannot collect the
  requested comparison events. The POC preserves a per-run raw-ID-to-redacted-
  alias cache for the **hypothesis** that a destruction callback can retain its
  native ID when a separate `window:application()` lookup is unavailable; this
  is harness correlation logic, not a claim about live callback ordering.
- **Verified:** installed `Resources/extensions/hs/uielement.lua` documents
  application-level `windowCreated` (`AXWindowCreated`) and
  `focusedWindowChanged` (`AXFocusedWindowChanged`) events, and says those
  callbacks receive the relevant child element. It documents
  `elementDestroyed` (`AXUIElementDestroyed`) for a window-level watcher.
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

## Implication

This observer is suitable only to collect comparison evidence. It proves no
liveness/destruction authority, lifecycle distinction, Space behavior, latency,
or query-gate result. In particular, it must not be used to claim zero
framework-internal global refreshes.
