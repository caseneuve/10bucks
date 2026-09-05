# POC-001 observer — Chromium create/focus/destruction handoff

This is a **human-gated, disposable, read-only comparison harness**, not
10bucks runtime code. It authorizes only sample
`chromium-create-focus-destroy-006`; it does not authorize the remaining
POC-001 matrix, source selection, true last-window testing, or a latency claim.

## Safety and setup — unmeasured

**Do not touch existing Chrome windows or tabs.** Before the observer starts,
the human—not the harness—must create two new, visibly distinguishable blank
Incognito windows. If Incognito is unavailable, create two new, visibly
distinguishable blank temporary Chrome windows instead. Keep at least one
pre-existing Chrome window open and untouched, so neither temporary close is a
true Chromium last-window case. Abort if existing Chrome state cannot remain
untouched or the two temporary windows cannot be distinguished.

No setup action is measured. Do not quit Chrome; close an existing Chrome
window; test a true last-app-window; minimize, hide, fullscreen, or move a
window between Spaces; or use app hide. The observer issues no window effects.

Create the private destination before loading the observer:

```sh
umask 077
mkdir -p /tmp/poc-001-chromium-create-focus-destroy-006
chmod 700 /tmp/poc-001-chromium-create-focus-destroy-006
test "$(stat -f '%Sp' /tmp/poc-001-chromium-create-focus-destroy-006)" = "drwx------"
```

Export path:

```text
/tmp/poc-001-chromium-create-focus-destroy-006/chromium-create-focus-destroy-006.json
```

## Orchestrator start

Use Hammerspoon Console Lua. Do not edit `~/.hammerspoon/init.lua` or call
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
assert(poc001:status().lifecycle == "running", "observer did not start")
assert(poc001:status().active_timers == 0, "observer unexpectedly has timers")
assert(poc001:status().window_effects == 0, "observer issued a window effect")
assert(poc001:status().target_binding_armed == false, "binder unexpectedly armed")
```

`⌃⌥⌘B` means hold physical Control, Option/Alt, and Command, then tap **B**
once. The one-shot binder deletes itself before its one focus read. It can be
armed again only after the prior bound action is marked complete; it rejects
while armed or while a target action remains active.

## Exact measured actions — return to chat after each action

Sample ID: `chromium-create-focus-destroy-006`. The user returns to chat after
each numbered action. Do not improvise or combine steps.

1. **Bind front temporary blank (non-destructive).** The orchestrator runs:

   ```lua
   assert(poc001:arm_target_action("chromium-create-focus-destroy-006", "bind_front_temporary_blank"))
   ```

   The human clicks the front temporary blank Chrome window and presses
   `⌃⌥⌘B` once, then returns to chat. The orchestrator verifies disarm and marks
   that completed binding:

   ```lua
   assert(poc001:status().target_binding_armed == false, "binder remained armed")
   poc001:mark("chromium-create-focus-destroy-006", "manual_visual_complete", "bind_front_temporary_blank")
   ```

2. **Focus the other temporary blank.** The human focuses only the other
   temporary blank Chrome window, then returns to chat. The orchestrator marks:

   ```lua
   poc001:mark("chromium-create-focus-destroy-006", "manual_visual_complete", "focus_other_temporary_blank")
   ```

3. **Cover for five seconds.** Using only the two temporary blank windows,
   completely cover one with the other for five seconds. Do not minimize,
   hide, fullscreen, or move Spaces. Then return to chat. The orchestrator
   marks:

   ```lua
   poc001:mark("chromium-create-focus-destroy-006", "manual_visual_complete", "cover_temporary_blank_5s")
   ```

4. **Bind and close the front temporary blank.** This is destructive, so it
   requires a new target binding. The orchestrator arms:

   ```lua
   assert(poc001:arm_target_action("chromium-create-focus-destroy-006", "close_front_temporary_blank"))
   ```

   The human exposes/clicks only the front temporary blank, presses `⌃⌥⌘B`
   once, and returns to chat. After the orchestrator confirms the binder is
   disarmed, the human closes **that bound front temporary blank only**, then
   returns to chat. The orchestrator marks completion:

   ```lua
   assert(poc001:status().target_binding_armed == false, "binder remained armed")
   poc001:mark("chromium-create-focus-destroy-006", "manual_visual_complete", "close_front_temporary_blank")
   ```

5. **Bind and close the remaining temporary blank.** The pre-existing Chrome
   window remains untouched. The orchestrator arms:

   ```lua
   assert(poc001:arm_target_action("chromium-create-focus-destroy-006", "close_remaining_temporary_blank"))
   ```

   The human clicks only the remaining temporary blank, presses `⌃⌥⌘B` once,
   returns to chat, then closes that bound temporary blank and returns to chat.
   The orchestrator verifies disarm and marks:

   ```lua
   assert(poc001:status().target_binding_armed == false, "binder remained armed")
   poc001:mark("chromium-create-focus-destroy-006", "manual_visual_complete", "close_remaining_temporary_blank")
   ```

There is no controlled `native_action_completed` marker. This sample makes **no
latency or action-to-detection timing claim**. True Chromium last-window
behavior remains pending.

## Abort — no improvisation

Abort immediately for uncertain identity, unexpected Chrome UI, an existing
window/tab that cannot remain untouched, a binding rejection, or any accidental
forbidden action. Do not re-arm while armed/active, replace an action, hide an
app, call `hs.reload`, or continue with another POC action.

```lua
if poc001 ~= nil and poc001:status().lifecycle == "running" then
  poc001:mark("chromium-create-focus-destroy-006", "sample_aborted", "operator_reported_unexpected_ui")
  pcall(function() poc001:stop() end)
end
assert(poc001 == nil or poc001:status().lifecycle == "stopped", "observer may still be running")
assert(poc001 == nil or poc001:status().target_binding_armed == false, "binder survived abort")
```

## Stop, export, and restore

After action 5 (or abort), stop, export, then restart legacy:

```lua
assert(poc001:stop())
assert(poc001:status().lifecycle == "stopped", "observer did not stop")
local exported, export_error = pcall(function()
  return poc001:export("/tmp/poc-001-chromium-create-focus-destroy-006/chromium-create-focus-destroy-006.json")
end)
spoon["10bucks"]:bindHotkeys():start()
assert(spoon["10bucks"].started == true, "legacy 10bucks did not restart")
assert(exported, "private POC export failed: " .. tostring(export_error))
```

Review the private export locally; do not commit raw traces.

## Pure checks

```sh
lua pocs/001-window-events-liveness/run-tests.lua
luac -p pocs/001-window-events-liveness/trace.lua
luac -p pocs/001-window-events-liveness/lifecycle.lua
luac -p pocs/001-window-events-liveness/ownership.lua
luac -p pocs/001-window-events-liveness/private_export.lua
luac -p pocs/001-window-events-liveness/observer.lua
```
