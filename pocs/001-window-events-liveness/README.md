# POC-001 observer — calibration operator guide

This is a **disposable, read-only comparison harness**, not 10bucks runtime
code. It never imports `10bucks.spoon`, requests frames or focus, mutates a
window, creates timers, or polls. This handoff authorizes one short,
orchestrator-guided **Terminal-only calibration**; it is not authorization to
run the full POC matrix.

## Scope, safety, and isolation

- The orchestrator runs the commands below and pauses for each human action.
  The only human test application is Terminal, using blank, non-sensitive
  windows. Do not open a shell prompt, tab, document, URL, title, or content
  that is sensitive: event exports are redacted, but the operator must not
  rely on redaction as permission to expose private material.
- Never run the observer and legacy 10bucks concurrently. The existing global
  `spoon["10bucks"]` is **verified present**. Stop it first and explicitly
  check `started == false` before loading the observer.
- Do **not** call `hs.reload`, edit `~/.hammerspoon/init.lua`, or reload the
  Hammerspoon configuration. Load the observer directly from the absolute
  repository path below.
- This calibration covers only creation, focus, destruction, and a covered
  live window. Do **not** proceed to minimize, hide/unhide, native fullscreen,
  moving a window between Spaces, quitting/relaunching, cold bootstrap/reload,
  rapid sequences, or the full application matrix. Those remain pending POC
  actions.
- The observer creates no window effects. Its candidate event sources run in
  parallel only to gather comparison evidence; this does not create a second
  production runtime.

The examples use this checked-out repository path and a private export
location. The directory command makes the export directory owner-only. Do not
share the export before reviewing it.

```sh
umask 077
mkdir -p /tmp/poc-001-piotr
chmod 700 /tmp/poc-001-piotr
```

The private export path used below is:

```text
/tmp/poc-001-piotr/terminal-calibration.json
```

## Orchestrator procedure

Run the **Console Lua** form in the Hammerspoon Console, or the equivalent
safely single-quoted `hs -c` form in a shell. `hs -c` requires the IPC support
already loaded by `~/.hammerspoon/init.lua`; it evaluates in the running
Hammerspoon Lua environment. Do not run both forms of the same step.

### 1. Stop and verify legacy

Console Lua:

```lua
spoon["10bucks"]:stop()
assert(spoon["10bucks"].started == false, "legacy 10bucks is still started; abort")
print("POC-001 legacy stopped")
```

Shell:

```sh
hs -c 'spoon["10bucks"]:stop(); assert(spoon["10bucks"].started == false, "legacy 10bucks is still started; abort"); print("POC-001 legacy stopped")'
```

Do not continue if the assertion fails. `stop()` removes legacy hotkey
bindings, which is why restoration below must call `bindHotkeys()` before
`start()`.

### 2. Clear a previous partial observer and manually load/start this POC

This cleanup is safe only after step 1 has verified legacy is stopped. It stops
an earlier `poc001` object if one exists, then discards only this POC module
cache entry. The global names deliberately persist between Console evaluations;
do not replace them with `local` variables.

Console Lua:

```lua
if poc001 ~= nil then pcall(function() poc001:stop() end) end
poc001 = nil
package.loaded["observer"] = nil
poc001_root = "/Users/piotr/Git/10bucks/pocs/001-window-events-liveness"
package.path = poc001_root .. "/?.lua;" .. package.path
poc001 = require("observer")
assert(poc001:start())
assert(poc001:status().lifecycle == "running", "POC observer did not start")
print(hs.inspect(poc001:status()))
```

Shell:

```sh
hs -c 'if poc001 ~= nil then pcall(function() poc001:stop() end) end; poc001 = nil; package.loaded["observer"] = nil; poc001_root = "/Users/piotr/Git/10bucks/pocs/001-window-events-liveness"; package.path = poc001_root .. "/?.lua;" .. package.path; poc001 = require("observer"); assert(poc001:start()); assert(poc001:status().lifecycle == "running", "POC observer did not start"); print(hs.inspect(poc001:status()))'
```

The printed status is the initial inspection: it must show `lifecycle =
"running"`, `active_timers = 0`, and `window_effects = 0`. The bootstrap scan
and watcher counts are expected observer instrumentation, not legacy runtime
activity.

### 3. Run exactly these named markers and Terminal actions

For every pause, the orchestrator issues the named marker first, the human
performs only the named Terminal action, then the orchestrator issues the
completion marker. All marker/action tokens are privacy-safe and must remain
exactly as shown.

1. **Create a blank Terminal window.** Leave it at an empty, non-sensitive
   prompt; do not type or display sensitive material.

   ```lua
   poc001:mark("terminal-cal-001", "action_begin", "terminal_create_blank")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "action_begin", "terminal_create_blank")'
   ```

   Human action: in Terminal, use **File → New Window** (or `Cmd-N`) once.
   Then issue:

   ```lua
   poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_create_blank")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_create_blank")'
   ```

2. **Focus the other blank Terminal window.** Keep both windows open. The
   action is a focus comparison only, not a layout action.

   ```lua
   poc001:mark("terminal-cal-001", "action_begin", "terminal_focus_other_blank")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "action_begin", "terminal_focus_other_blank")'
   ```

   Human action: click the other blank Terminal window's title bar once. Then
   issue:

   ```lua
   poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_focus_other_blank")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_focus_other_blank")'
   ```

3. **Cover, but do not close, one blank Terminal window.** Bring the focused
   blank window fully over the other blank Terminal window and leave the
   covered window open for five seconds. Do not minimize either window.

   ```lua
   poc001:mark("terminal-cal-001", "action_begin", "terminal_cover_live_window")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "action_begin", "terminal_cover_live_window")'
   ```

   Human action: arrange the two blank Terminal windows so one completely
   covers the other; wait five seconds. Then issue:

   ```lua
   poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_cover_live_window")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_cover_live_window")'
   ```

4. **Destroy the front blank Terminal window.** This is the only destructive
   action in this calibration. Close the front window with **File → Close
   Window** (or `Cmd-W`); do not quit Terminal.

   ```lua
   poc001:mark("terminal-cal-001", "action_begin", "terminal_close_front_blank")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "action_begin", "terminal_close_front_blank")'
   ```

   Human action: close only the front blank Terminal window. Then issue:

   ```lua
   poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_close_front_blank")
   ```

   ```sh
   hs -c 'poc001:mark("terminal-cal-001", "manual_visual_complete", "terminal_close_front_blank")'
   ```

Do not invent extra markers or actions in this calibration.

### 4. Inspect, stop, export, and restore legacy

Inspect before stopping:

```lua
print(hs.inspect(poc001:status()))
```

```sh
hs -c 'print(hs.inspect(poc001:status()))'
```

Record the displayed status for the later result write-up. It is diagnostic
only: do not interpret it as a pass/fail result during this handoff.

Stop, verify the observer stopped, and export to the owner-only `/tmp` path:

```lua
assert(poc001:stop())
assert(poc001:status().lifecycle == "stopped", "POC observer did not stop")
poc001:export("/tmp/poc-001-piotr/terminal-calibration.json")
```

```sh
hs -c 'assert(poc001:stop()); assert(poc001:status().lifecycle == "stopped", "POC observer did not stop"); poc001:export("/tmp/poc-001-piotr/terminal-calibration.json")'
```

Only after the stop assertion succeeds, restore the single legacy runtime.
`bindHotkeys()` is mandatory because legacy `stop()` deletes the bindings.

```lua
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
```

```sh
hs -c 'spoon["10bucks"]:bindHotkeys():start(); assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")'
```

## Abort and partial-load cleanup

If loading, starting, marking, or a human action goes wrong, **do not** reload
Hammerspoon and do not start legacy while the observer might still be running.
Run this cleanup, inspect its status, then restore legacy only if the observer
reports `stopped`:

```lua
if poc001 ~= nil then pcall(function() poc001:stop() end) end
if poc001 ~= nil then print(hs.inspect(poc001:status())) end
assert(poc001 == nil or poc001:status().lifecycle == "stopped", "observer may still be running; do not restore legacy")
poc001 = nil
package.loaded["observer"] = nil
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
```

```sh
hs -c 'if poc001 ~= nil then pcall(function() poc001:stop() end) end; if poc001 ~= nil then print(hs.inspect(poc001:status())) end; assert(poc001 == nil or poc001:status().lifecycle == "stopped", "observer may still be running; do not restore legacy"); poc001 = nil; package.loaded["observer"] = nil; spoon["10bucks"]:bindHotkeys():start(); assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")'
```

If that assertion fails, leave legacy stopped and escalate with the Console
output; do not use `hs.reload` as cleanup.

## Trace and observer contract

The in-memory trace is structured and monotonically timestamped in
milliseconds. Every event has `run_id`, `sample_id`, `sequence`, and
`monotonic_ms`. Export redacts titles, URLs, paths, AX text, app names, bundle
IDs, PIDs, and raw native window IDs. Application/window aliases are in-memory
only and reset per run. Review the local export before sharing it.

`poc001:status()` reports the run ID, event count, open callback depth, query
counters, active watcher counts, active timers (expected `0`), and POC window
effects (expected `0`). The observer's only deliberate broad work is the
labeled startup bootstrap scan. It makes no frame/focus/window effects and no
permanent poll. See [`EVIDENCE.md`](EVIDENCE.md) for source-inspection caveats
and [`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md)
for the hypothesis, thresholds, and deferred matrix.

## Pure checks

```sh
lua pocs/001-window-events-liveness/run-tests.lua
luac -p pocs/001-window-events-liveness/trace.lua
luac -p pocs/001-window-events-liveness/lifecycle.lua
luac -p pocs/001-window-events-liveness/ownership.lua
luac -p pocs/001-window-events-liveness/observer.lua
```
