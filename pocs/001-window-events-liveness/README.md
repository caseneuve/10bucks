# POC-001 observer — manual regular-Space move operator handoff

This is a **human-gated, disposable, read-only comparison harness**, not
10bucks runtime code. It authorizes one Terminal-only manual regular-Space move
sample. It does not authorize the remaining POC matrix, a production change, or
a timing claim. Prior calibration history remains in
[`docs/pocs/001-window-events-liveness.md`](../../docs/pocs/001-window-events-liveness.md).

## Scope and fixed run setup

**Observed run setup, not a portable fact:** the read-only topology observation
on this machine found one display, three regular Spaces with the first active,
and three fullscreen Spaces. This handoff relies only on the human-visible
preconditions below; it does not infer future topology from that observation.

Before the orchestrator starts:

- Desktop 1/current regular Space has **two visible, blank Terminal windows**:
  the session window and a separate blank target window.
- Desktop 2 exists.
- Terminal is the only application involved.

The observer performs no frame, focus, fullscreen, Space, minimize, hide,
close, admission, or other window effect. It has no timer or controlled action
driver. The human alone uses Mission Control to move the target. Manual-action
timing is explicitly **unmeasurable**: do not state or imply a two-second (or
any other) action-to-detection result.

If the UI differs, the blank target cannot be identified, or Desktop 2 cannot
be identified, abort without improvising. Do not use fullscreen, hide,
minimize, another app, another Space action, or a replacement gesture. In
particular, do not use an operator `hs -c` or Hammerspoon Console command that
reads/changes focus to bind the target; the one-shot chord is the binding
boundary.

## Private export destination

Before loading the observer, the orchestrator creates this owner-private
directory:

```sh
umask 077
mkdir -p /tmp/poc-001-regular-space-move-005
chmod 700 /tmp/poc-001-regular-space-move-005
test "$(stat -f '%Sp' /tmp/poc-001-regular-space-move-005)" = "drwx------"
```

The private export path is:

```text
/tmp/poc-001-regular-space-move-005/terminal-regular-space-move-005.json
```

The exporter writes only to an explicitly selected owner-private directory,
enforces and verifies mode `0600` on a temporary file, atomically renames it,
and fails closed. Review locally and redact before sharing.

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
assert(poc001:status().target_binding_armed == false, "POC target binding unexpectedly armed")
```

Do not continue if an assertion fails.

## Keyboard chord notation

Before starting the sample, read this notation:

- `⌃` means the physical **Control** key.
- `⌥` means the physical **Option** key (also labelled **Alt** on some keyboards).
- `⌘` means the physical **Command** key.
- `⌃⌥⌘B` means: hold physical **Control**, **Option/Alt**, and **Command** together, then tap the letter **B** once. Do not press a function key.

## Exact move-only flow

Sample ID: `terminal-regular-space-move-005`.

1. The orchestrator arms the POC-only one-shot target binder; this is the only
   permitted preparatory call:

   ```lua
   assert(poc001:arm_target_action("terminal-regular-space-move-005", "manual_move_regular_space"))
   assert(poc001:status().target_binding_armed == true, "target binder did not arm")
   ```

   The fixed POC-only chord is **Control-Option-Command-B** (`⌃⌥⌘B`): hold
   physical Control, Option/Alt, and Command, then tap **B** once. Source
   inspection verified that no project legacy binding uses this exact chord;
   legacy is stopped throughout this POC in any event. The binder uses the
   verified local Hammerspoon 1.1.1 `hs.hotkey.new(...):enable()` API and
   deletes itself before reading focus. A second arm rejects. It does not focus,
   admit, or move a window.

2. The human clicks the **blank target Terminal** (not the session window) and
   presses **Control-Option-Command-B once**. The callback deletes/disarms
   itself first, then calls the existing read-only `begin_target_action` against
   that current focus. It records either a bound target with its expected source
   or a rejection. The orchestrator checks:

   ```lua
   assert(poc001:status().target_binding_armed == false, "one-shot target binder remained armed")
   ```

   If the binding rejected, or the human is not certain the blank target was
   clicked, abort; do not press the chord again or arm again.

3. The human opens Mission Control with **Control-Up**, drags **ONLY the blank
   target window thumbnail** to **Desktop 2**, then exits Mission Control.
   Do not move the session window or any other thumbnail.

4. The human switches to Desktop 2 and visually verifies the blank target
   there. The observer-derived ownership observation remains the destination
   evidence; the controlled action records only the target and expected source.
   It does not drive or assert a destination.

5. The human returns to Desktop 1/the session window and replies **only then**.
   Only after that reply does the orchestrator mark completion:

   ```lua
   poc001:mark("terminal-regular-space-move-005", "manual_visual_complete", "manual_move_regular_space")
   ```

Do not perform a fullscreen, hide, minimize, restore, close, or any action in
another application. If UI differs at any point, the target/destination cannot
be identified, or Mission Control cannot complete this exact move, use the
abort path below without improvisation.

## Stop, export, and restore

After the human has returned to Desktop 1/session and the completion marker has
been emitted, stop the observer, export only after it is stopped, then restore
legacy 10bucks:

```lua
print(hs.inspect(poc001:status()))
assert(poc001:stop())
assert(poc001:status().lifecycle == "stopped", "POC observer did not stop")
assert(poc001:status().target_binding_armed == false, "armed target binder survived stop")
local exported, export_error = pcall(function()
  return poc001:export("/tmp/poc-001-regular-space-move-005/terminal-regular-space-move-005.json")
end)
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
assert(exported, "private POC export failed: " .. tostring(export_error))
```

## Abort: no improvisation

If a precondition fails, binding rejects, or the human reports unexpected UI,
mark only the abort, stop (which deletes any armed target hotkey), export, and
restore. Do not add a replacement action, re-arm, press the chord again,
restart the observer, or call `hs.reload`.

```lua
if poc001 ~= nil and poc001:status().lifecycle == "running" then
  poc001:mark("terminal-regular-space-move-005", "sample_aborted", "operator_reported_unexpected_ui")
  pcall(function() poc001:stop() end)
end
assert(poc001 == nil or poc001:status().lifecycle == "stopped", "observer may still be running; do not restore legacy")
assert(poc001 == nil or poc001:status().target_binding_armed == false, "armed target binder survived abort")
local exported, export_error = true, nil
if poc001 ~= nil then
  exported, export_error = pcall(function()
    return poc001:export("/tmp/poc-001-regular-space-move-005/terminal-regular-space-move-005.json")
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
```
