# POC-001 observer — operator guide

This is a **disposable, read-only comparison harness**, not 10bucks runtime code.
It does not import `10bucks.spoon`, request frames or focus, mutate windows, create
timers, or poll. It must be loaded only after the legacy 10bucks runtime has been
stopped in an isolated Hammerspoon Console session.

## Do not run live actions yet

This checkpoint implements **step 2A only**: install/start/trace/cleanup/export.
Do **not** create, focus, close, minimize, hide, fullscreen, move, quit, reload,
or otherwise manipulate an application for this harness yet. The guided action
matrix and any action driver belong to later POC-001 slices. In particular, do
not reload Hammerspoon for this checkpoint.

## Console commands

Run these exact commands in the Hammerspoon Console after confirming the legacy
10bucks watchers, timers, bar timer, and hotkeys are stopped. Adjust only the
absolute repository path and the explicitly chosen export destination.

```lua
local poc_root = "/Users/piotr/Git/10bucks/pocs/001-window-events-liveness"
package.path = poc_root .. "/?.lua;" .. package.path
poc001 = require("observer")
poc001:start()
poc001:status()
poc001:mark("sample-001", "observer_ready", "no_live_action")
poc001:stop()
poc001:export("/Users/piotr/Desktop/poc-001-redacted-trace.json")
```

`start()` and `stop()` are idempotent: repeated calls return `false` plus
`already_running` or `already_stopped`; they do not create a second observer.
A subsequent successful `start()` begins a new run with new aliases. `export()`
requires an absolute, operator-selected path and overwrites that file. Review
the export location before sharing it.

Use `poc001:status()` before stop to inspect the run ID, event total, callback
stack depth, counters by `bootstrap`/`steady` scope, active watcher counts,
active timers (expected `0`), and POC window effects (expected `0`).

## Trace and privacy contract

The in-memory trace is structured and monotonically timestamped in milliseconds.
Every event has `run_id`, `sample_id`, `sequence`, and `monotonic_ms`. Callback
entry/exit events carry source/event and callback sequence; query attempts carry
query kind, call site, scope, and current callback attribution.

No title, URL, path, raw AX text, app name, bundle ID, PID, or native window ID
is exported. Application/window aliases (`app-001`, `win-001`) are assigned only
in memory and reset per run. The export serializer whitelists safe event fields
and drops sensitive/unknown fields. Raw identifiers exist only as transient Lua
map keys while this process runs. A per-run native-window-ID cache correlates a
late filter destruction callback whose `window:application()` is unavailable;
it contains redacted aliases only as values, is never exported, is removed after
destruction correlation, and is reset for every new run.

`bootstrap.attach_existing_apps` is the sole intentional global application
scan. For each app returned there, `bootstrap.attach_existing_windows` performs
one narrow per-application `application:allWindows()` scan, counted as
`per_application_window_scan` with `bootstrap` scope, so existing windows get
their own direct `AXUIElementDestroyed` watcher. Neither scan runs from a
steady callback. Framework-internal behavior is not counted as POC-issued work;
it is reported separately in [`EVIDENCE.md`](EVIDENCE.md).

## Sources compared

- `hs.window.filter`: `windowCreated`, `windowFocused`, `windowDestroyed`.
  The observer constructs it with `hs.window.filter.new(true, ...)`: installed
  Hammerspoon source defines `true` as an empty allow-all filter, while `false`
  is reject-all and would suppress this comparison.
- `hs.application.watcher`: launch/termination (and recorded other app events).
- Direct per-application `hs.uielement.watcher`: `AXWindowCreated` and
  `AXFocusedWindowChanged`; each identified AX window gets an
  `AXUIElementDestroyed` watcher.

Direct attachment is attempted once for every application returned by the
explicit startup scan and for later `launched` apps. Bootstrap also attaches
per-window destruction watchers to that app's already-existing windows; an app
termination stops/removes all POC-owned app and window watchers for its PID.
Failure/unavailability is a trace fact, not a retry or an inference. There is
deliberately no readiness, minimize/hide/fullscreen/Space/liveness correlation,
target check, or permanent poll in this slice.

## Pure checks

```sh
lua pocs/001-window-events-liveness/run-tests.lua
luac -p pocs/001-window-events-liveness/trace.lua
luac -p pocs/001-window-events-liveness/observer.lua
```
