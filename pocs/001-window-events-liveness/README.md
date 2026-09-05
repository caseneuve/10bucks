# POC-001 observer — lifecycle calibration operator handoff

This is a **human-gated, disposable, read-only comparison harness**, not
10bucks runtime code. It authorizes exactly one Terminal-only lifecycle sample.
It does not authorize the full POC matrix or any production change. The first
Terminal calibration and its unplanned deviation remain recorded in
[`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md#first-terminal-calibration--calibration-only-observations);
this handoff does not replace that history.

## Scope and non-negotiable boundaries

- The orchestrator alone stops/loads the runtimes, emits all markers, stops and
  exports the trace, and restores legacy 10bucks. The human performs only the
  individually announced UI action (or the explicitly announced combined
  hide→wait→unhide action), then waits.
- Use **exactly two** blank, non-sensitive Terminal windows, named **A** and
  **B** by their on-screen positions before the sample starts. Both are on the
  current regular Space. A is frontmost and B is visible behind it. Terminal is
  the only application acted on; do not open, switch, quit, or operate another
  application.
- Do not move a Space, use Mission Control, reload Hammerspoon, cold reload the
  observer, run another sample, rapidly repeat an action, or make timing
  claims. This calibration has no timing result.
- Minimize, application hide, and native fullscreen are **independent
  observations**. The expected visible states below deliberately preserve that
  distinction; none implies another.
- If the user cannot perform an action, cannot identify the required Dock item,
  or sees unexpected UI/state, the user says so. The sample then stops. Do not
  improvise a substitute action, add a marker/action, or continue from a
  different state.
- The observer makes no frame, focus, minimize, hide, fullscreen, Space, or
  other window effects. Candidate sources are comparison instrumentation only.

The applicable hypothesis, environment observations, and acceptance thresholds
are in [`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md).

## Exact setup

Before stopping legacy or loading the observer, the human arranges the current
regular Space into this precondition: exactly two blank Terminal windows are
open; **A** is the front window; **B** remains visibly unminimized behind A;
and A's minimized-window item is identifiable in the Dock when minimized. This
setup is not a measured action and receives no marker. If that Dock item cannot
be identified, do not start the sample.

The orchestrator creates a new owner-private export directory and path:

```sh
umask 077
mkdir -p /tmp/poc-001-lifecycle-002
chmod 700 /tmp/poc-001-lifecycle-002
test "$(stat -f '%Sp' /tmp/poc-001-lifecycle-002)" = "drwx------"
```

The export path is new for this slice:

```text
/tmp/poc-001-lifecycle-002/terminal-lifecycle-calibration-002.json
```

The exporter is fail-closed: it accepts only an explicitly chosen absolute
path in an already-existing directory owned by the current user with no
group/other permissions; writes a temporary file in that directory; enforces
and verifies temporary-file mode `0600`; atomically renames only that verified
temporary file; and removes the temporary file if any step fails. Shell
`umask` is defense in depth only and does not control the already-running
Hammerspoon process. Do not share an export before local review.

## Orchestrator setup

Use either the Hammerspoon Console Lua forms below or their safely
single-quoted `hs -c` equivalents—not both for a step. Do not edit
`~/.hammerspoon/init.lua` or call `hs.reload`.

### Stop legacy and load the observer

```lua
spoon["10bucks"]:stop()
assert(spoon["10bucks"].started == false, "legacy 10bucks is still started; abort")

if poc001 ~= nil then pcall(function() poc001:stop() end) end
poc001 = nil
package.loaded["observer"] = nil
poc001_root = "/Users/piotr/Git/10bucks/pocs/001-window-events-liveness"
package.path = poc001_root .. "/?.lua;" .. package.path
poc001 = require("observer")
assert(poc001:start())
assert(poc001:status().lifecycle == "running", "POC observer did not start")
assert(poc001:status().active_timers == 0, "POC observer unexpectedly has timers")
assert(poc001:status().window_effects == 0, "POC observer issued a window effect")
print(hs.inspect(poc001:status()))
```

Do not continue if any assertion fails.

## Guided lifecycle sample

Use sample ID `terminal-lifecycle-002`. For each row, the orchestrator emits
`action_begin`, the human performs **only** the announced action, confirms the
listed visible state, and the orchestrator emits `manual_visual_complete`.
There is no prescribed wait or timing measurement.

Before the hide row begins, the orchestrator must announce the entire combined
operation: **hide Terminal → wait briefly → click Terminal in the Dock to
unhide it**. Because hiding Terminal also hides the communication terminal,
the human must not be asked to reply while Terminal is hidden; they reply only
after Terminal has returned. The combined operation has one begin/completion
marker and is not a claim about a clean hide/unhide marker sequence.

| Order | Marker action token | Human action | Expected visible state before completion marker |
|---:|---|---|---|
| 1 | `terminal_minimize_front_A` | Minimize front window **A** once using its yellow window control. | A is minimized. B is still visible, unminimized, and frontmost on the current regular Space. |
| 2 | `terminal_hide_wait_unhide_via_Dock` | With B visible and unminimized, perform the pre-announced combined operation: choose **Terminal → Hide Terminal** once, wait briefly, then click the Terminal application icon in the Dock once to unhide it. Reply only after Terminal returns. | B is visible and frontmost on the current regular Space. A remains minimized. |
| 3 | `terminal_restore_A_via_Dock` | Click **A's minimized-window item** in the Dock once. Do not click B or use a Terminal menu. | A is restored and visible on the current regular Space. B remains visible. |
| 4 | `terminal_enter_native_fullscreen_A` | With A frontmost, press **Control-Command-F** once to enter Terminal's native fullscreen. | A is in its native fullscreen Space. B remains on the original regular Space. |
| 5 | `terminal_exit_native_fullscreen_A` | In A's native fullscreen Space, press **Control-Command-F** once to exit native fullscreen. | A has exited native fullscreen and is visible again on the regular Space; B remains visible there. |

For every row, the orchestrator uses exactly these marker calls, replacing only
`ACTION` with that row's token:

```lua
poc001:mark("terminal-lifecycle-002", "action_begin", "ACTION")
-- Human performs the one announced action and confirms the expected visible state.
poc001:mark("terminal-lifecycle-002", "manual_visual_complete", "ACTION")
```

## Stop, export, and restore

After row 5, the orchestrator inspects the status, stops the observer, exports
only after it is stopped, then restores legacy bindings and runtime:

```lua
print(hs.inspect(poc001:status()))
assert(poc001:stop())
assert(poc001:status().lifecycle == "stopped", "POC observer did not stop")
local exported, export_error = pcall(function()
  return poc001:export("/tmp/poc-001-lifecycle-002/terminal-lifecycle-calibration-002.json")
end)
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
assert(exported, "private POC export failed: " .. tostring(export_error))
```

The status and local export are diagnostic-only. They are not a pass/fail
result and do not authorize another POC action.

### Recovery export of an already-stopped in-memory trace

If export failed after the observer was confirmed stopped, do **not** restart
it, call `start`, emit a marker, or reload the runtime. With `poc001` still in
Hammerspoon memory and its original `poc001_root`/`package.path` intact, load
only the corrected pure exporter and serialize the existing trace directly:

```lua
assert(poc001 ~= nil and poc001:status().lifecycle == "stopped", "trace is not safely stopped")
local load_exporter, load_error = loadfile(poc001_root .. "/private_export.lua")
assert(load_exporter, load_error)
local CorrectedPrivateExport = load_exporter()
local Trace = require("trace")
local path = "/tmp/poc-001-lifecycle-002/terminal-lifecycle-calibration-002.json"
local exported = CorrectedPrivateExport.write(
  path,
  Trace.encode_json(poc001.trace:export_table()),
  poc001.export_ops
)
print(exported)
```

This reads the stopped trace via `export_table()` and invokes only the
corrected file-writing module; it neither restarts the observer nor changes
POC/runtime state. Review the resulting local private export before sharing.

## Cancellation and abort

On the user's statement that an action cannot be completed or UI is unexpected,
the orchestrator marks the sample aborted (without a replacement action), then
stops, exports, and restores only if the observer is confirmed stopped:

```lua
if poc001 ~= nil and poc001:status().lifecycle == "running" then
  poc001:mark("terminal-lifecycle-002", "sample_aborted", "operator_reported_unexpected_ui")
  pcall(function() poc001:stop() end)
end
if poc001 ~= nil then print(hs.inspect(poc001:status())) end
assert(poc001 == nil or poc001:status().lifecycle == "stopped", "observer may still be running; do not restore legacy")
local exported, export_error = true, nil
if poc001 ~= nil then
  exported, export_error = pcall(function()
    return poc001:export("/tmp/poc-001-lifecycle-002/terminal-lifecycle-calibration-002.json")
  end)
end
poc001 = nil
package.loaded["observer"] = nil
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
assert(exported, "private POC export failed: " .. tostring(export_error))
```

If the stop assertion fails, leave legacy stopped and report the Console output.
Do not use `hs.reload` as cleanup.

## Trace contract and pure checks

The in-memory trace has monotonic millisecond timestamps and redacts titles,
URLs, paths, AX text, app names, bundle IDs, PIDs, and native IDs. Review the
local export before sharing it. `poc001:status()` reports lifecycle, event and
query counters, watcher counts, active timers (expected `0`), and POC window
effects (expected `0`).

```sh
lua pocs/001-window-events-liveness/run-tests.lua
luac -p pocs/001-window-events-liveness/trace.lua
luac -p pocs/001-window-events-liveness/lifecycle.lua
luac -p pocs/001-window-events-liveness/ownership.lua
luac -p pocs/001-window-events-liveness/private_export.lua
luac -p pocs/001-window-events-liveness/observer.lua
```
