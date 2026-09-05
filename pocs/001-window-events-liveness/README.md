# POC-001 observer — fullscreen-only calibration operator handoff

This is a **human-gated, disposable, read-only comparison harness**, not
10bucks runtime code. It authorizes one Terminal-only, fullscreen-only
calibration. It does not authorize the full POC matrix, a production change,
or a timing claim. Prior calibration history remains in
[`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md).

## Scope and precondition

- Before the orchestrator starts, arrange **exactly two visible, blank Terminal
  windows on the current regular Space**. The front window is A; the other
  visible window is B.
- Terminal is the only application acted on. Do not hide, minimize, restore,
  move windows or Spaces, use Mission Control, open or operate another app,
  reload Hammerspoon, or run another sample.
- The observer performs no frame, focus, fullscreen, Space, or other window
  effects. The human alone invokes the two fullscreen shortcuts.
- This calibration records no prescribed wait duration and makes no timing,
  source-authority, lifecycle-pass, or acceptance-threshold claim.

If the precondition is not true, or any UI is unexpected, abort; do not
improvise a substitute action or continue from a different state.

## Private export destination

The orchestrator creates this new owner-private directory before loading the
observer:

```sh
umask 077
mkdir -p /tmp/poc-001-fullscreen-003
chmod 700 /tmp/poc-001-fullscreen-003
test "$(stat -f '%Sp' /tmp/poc-001-fullscreen-003)" = "drwx------"
```

The private export path for this slice is:

```text
/tmp/poc-001-fullscreen-003/terminal-fullscreen-calibration-003.json
```

The exporter writes only to an explicitly selected owner-private directory,
enforces and verifies mode `0600` on a temporary file, atomically renames it,
and fails closed. Review the export locally; do not share it before redaction
review.

## Orchestrator: stop legacy and load the observer

Use the Hammerspoon Console Lua forms below (or safely single-quoted `hs -c`
equivalents), not both. Do not edit `~/.hammerspoon/init.lua` or call
`hs.reload`.

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
```

Do not continue if an assertion fails.

## Guided fullscreen calibration

Use sample ID `terminal-fullscreen-003`. For each action, the orchestrator
uses the read-only target-bound `begin_target_action` marker: it reads focus
once, resolves only a known in-memory redacted identity, and rejects uncertain
ownership without admission or effects. The human performs exactly the announced action, waits
for the stated visible state, then replies. Only after that reply does the
orchestrator emit `manual_visual_complete`.

1. The orchestrator announces `terminal_enter_native_fullscreen_A` and emits:

   ```lua
   assert(poc001:begin_target_action("terminal-fullscreen-003", "terminal_enter_native_fullscreen_A"))
   ```

   The human presses **Control-Command-F** once on front blank Terminal window
   A. The human waits until its dedicated native-fullscreen Space visibly
   settles, then replies. The orchestrator then emits:

   ```lua
   poc001:mark("terminal-fullscreen-003", "manual_visual_complete", "terminal_enter_native_fullscreen_A")
   ```

2. The orchestrator announces `terminal_exit_native_fullscreen_A` and emits:

   ```lua
   assert(poc001:begin_target_action("terminal-fullscreen-003", "terminal_exit_native_fullscreen_A"))
   ```

   The human presses **Control-Command-F** once to exit fullscreen on that same
   window A. The human waits until the regular Space visibly settles, then
   replies. The orchestrator then emits:

   ```lua
   poc001:mark("terminal-fullscreen-003", "manual_visual_complete", "terminal_exit_native_fullscreen_A")
   ```

B remains untouched. Do not perform any extra action between or after these
steps.

## Stop, export, and restore

After the second completion marker, the orchestrator stops the observer,
exports only after it is stopped, then restores legacy 10bucks:

```lua
print(hs.inspect(poc001:status()))
assert(poc001:stop())
assert(poc001:status().lifecycle == "stopped", "POC observer did not stop")
local exported, export_error = pcall(function()
  return poc001:export("/tmp/poc-001-fullscreen-003/terminal-fullscreen-calibration-003.json")
end)
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
assert(exported, "private POC export failed: " .. tostring(export_error))
```

The status and export are diagnostic-only and authorize no additional action.

## Abort: no improvisation

If the human cannot perform either action or sees unexpected UI, the
orchestrator marks only the abort, stops, exports, and restores. It does not
add a replacement action, restart the observer, emit another marker, or use
`hs.reload`.

```lua
if poc001 ~= nil and poc001:status().lifecycle == "running" then
  poc001:mark("terminal-fullscreen-003", "sample_aborted", "operator_reported_unexpected_ui")
  pcall(function() poc001:stop() end)
end
assert(poc001 == nil or poc001:status().lifecycle == "stopped", "observer may still be running; do not restore legacy")
local exported, export_error = true, nil
if poc001 ~= nil then
  exported, export_error = pcall(function()
    return poc001:export("/tmp/poc-001-fullscreen-003/terminal-fullscreen-calibration-003.json")
  end)
end
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
assert(exported, "private POC export failed: " .. tostring(export_error))
```

If stop fails, leave legacy stopped and report the Console output.

## Pure checks

```sh
lua pocs/001-window-events-liveness/run-tests.lua
luac -p pocs/001-window-events-liveness/trace.lua
luac -p pocs/001-window-events-liveness/lifecycle.lua
luac -p pocs/001-window-events-liveness/ownership.lua
luac -p pocs/001-window-events-liveness/private_export.lua
luac -p pocs/001-window-events-liveness/observer.lua

## Before a separately approved manual regular-Space move

The fullscreen calibration is diagnostic-only. A guided regular-Space move
remains blocked pending an explicit human handoff that fixes its target,
regular source/destination, controlled completion (or explicitly unmeasurable
manual timing), and pending-work hotkey procedure. That handoff must use
`begin_target_action`, retain generic `mark` only for completion/abort, and
review the redacted sweep/coalescing, reciprocal-ownership, `no_regular_move`,
and target/non-target destruction-candidate records. Do not treat this README
as authorization to perform that move.
```
