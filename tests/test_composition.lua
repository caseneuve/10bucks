local function fakeHs(options)
  options = options or {}
  local f = { deleted = 0, frames = 0, focuses = 0, bindings = {}, scans = 0, focusedWindowQueries = 0,
    actual = { x = 99, y = 99, w = 1, h = 1 }, owners = { "space" }, members = { 9 } }
  local function watcher(callback, label)
    return { callback = callback, label = label, start = function() end,
      stop = function(self) if not self.stopped then self.stopped = true; f.deleted = f.deleted + 1 end end }
  end
  local function contextWatcher(callback)
    local watcher = watcher(callback, "space")
    f.contextWatcher = watcher
    return watcher
  end
  local screen = { getUUID = function() return "built-in" end, frame = function() return { x = 0, y = 0, w = 100, h = 80 } end }
  -- Evidence-derived boundary: AX conversion provides metadata/asHSWindow only;
  -- the per-window watcher is constructed by hs.window:newWatcher(handler).
  local element = { asHSWindow = function() return f.window end,
    attributeValue = function(_, _) return false end, isAttributeSettable = function() return true end }
  local app = { pid = function() return 8 end, name = function() return "App" end, bundleID = function() return "app" end,
    allWindows = function() f.scans = f.scans + 1; if options.bootstrapFails then error("bootstrap failed") end; return { f.window } end,
    newWatcher = function(_, cb) f.appWatcher = watcher(cb, "app"); return f.appWatcher end }
  f.window = { id = function() return 9 end, title = function() return "Window" end, application = function() return app end,
    role = function() return "AXWindow" end, subrole = function() return "AXStandardWindow" end,
    isFullScreen = function() return f.fullscreen end, newWatcher = function(_, cb) f.windowWatcher = watcher(cb, "window"); return f.windowWatcher end, frame = function() return f.actual end,
    setFrame = function(_, frame, duration) assert(duration == 0); f.frames = f.frames + 1; f.actual = frame end,
    focus = function() f.focuses = f.focuses + 1 end }
  local bindCount = 0
  _G.hs = { processInfo = { processID = 1 }, screen = { allScreens = function() return { screen } end },
    spaces = { activeSpaceOnScreen = function() return f.activeSpace or "space" end, spaceType = function() return "user" end,
      windowsForSpace = function() return f.members end, windowSpaces = function() return f.owners end,
      watcher = { new = contextWatcher } },
    axuielement = { windowElement = function(x) assert(x == f.window); return element end },
    application = { runningApplications = function() return { app } end, watcher = { new = function(cb) f.life = watcher(cb, "life"); return f.life end, terminated = 3, hidden = 4, unhidden = 5, launched = 2 } },
    window = { focusedWindow = function() f.focusedWindowQueries = f.focusedWindowQueries + 1; if f.focusedWindowError then error("focused-window read failed") end; return f.focusedWindow end },
    hotkey = { bind = function(_, _, cb) bindCount = bindCount + 1; if options.failBind == bindCount then error("bind failed") end; local h = { delete = function(self) if not self.deleted then self.deleted = true; f.deleted = f.deleted + 1 end end }; f.bindings[#f.bindings + 1] = { callback = cb, handle = h }; return h end }, }
  return f, element
end

local function load(f)
  package.loaded["init"] = nil
  local ten = dofile("10bucks.spoon/init.lua")
  ten:configure({ builtInDisplayUUID = "built-in" })
  return ten
end

local function loadConfiguredFile(f, config)
  package.loaded["init"] = nil
  local Config = require("lib.config")
  local original = Config.loadFile
  Config.loadFile = function(path) assert(path == "test-config.lua"); return config end
  local ten = dofile("10bucks.spoon/init.lua")
  local ok, err = pcall(function() ten:configureFile("test-config.lua"):bindHotkeys():start() end)
  Config.loadFile = original
  assert(ok, err)
  return ten
end

return {
  ["composition bootstrap and reflow deduplicate actual frames then correct drift"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    assert(ten.core:state().manager.windows[9] and f.frames == 1 and f.focuses == 0,
      "cold bootstrap must tile without stealing native focus")
    ten.core:submit({ type = "Reflow" }); assert(f.frames == 1 and f.focuses == 0)
    f.actual = { x = 7, y = 0, w = 100, h = 80 }; ten.core:submit({ type = "Reflow" }); assert(f.frames == 2)
    ten:stop()
  end,
  ["POC-009 FOCUS-006: no-callback unchanged focus confirms through one targeted read"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
    local scans, queries = f.scans, f.focusedWindowQueries
    f.focusedWindow = f.window
    ten.core:submit({ type = "FocusNext" })
    local desired = ten.core:state().manager.focus.desiredBySpace.space
    assert(f.focuses == 1 and f.focusedWindowQueries == queries + 1 and f.scans == scans)
    assert(desired.targetId == 9 and not desired.pending)
    ten:stop()
  end,
  ["POC-009 FOCUS-006: nonmatching read awaits a later ordinary focus callback"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
    local scans, queries = f.scans, f.focusedWindowQueries
    f.focusedWindow = { id = function() return 10 end }
    ten.core:submit({ type = "FocusNext" })
    assert(f.focuses == 1 and f.focusedWindowQueries == queries + 1 and f.scans == scans)
    assert(ten.core:state().manager.focus.desiredBySpace.space.pending)
    ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
    assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
    ten:stop()
  end,
  ["FOCUS-001 FOCUS-006: bootstrap samples actual managed focus after readiness without requesting focus"] = function()
    local f = fakeHs(); f.focusedWindow = f.window
    local ten = load(f); ten:start()
    local state = ten.core:state().manager
    local desired = state.focus.desiredBySpace.space
    assert(state.focus.actualWindow.id == 9 and desired.targetId == 9 and not desired.pending)
    assert(#ten.focusHistory:snapshot() == 1 and ten.focusHistory:snapshot()[1].windowId == 9)
    assert(f.focuses == 0 and f.focusedWindowQueries == 1)
    ten:stop()
  end,
  ["FOCUS-001 FOCUS-006: stale AX payload normalizes the current native focus, not its payload"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    f.focusedWindow = f.window
    local queries = f.focusedWindowQueries
    f.appWatcher.callback({ id = function() return 99 end }, "AXFocusedWindowChanged")
    assert(f.focusedWindowQueries == queries + 1)
    assert(ten.core:state().manager.focus.actualWindow.id == 9)
    ten:stop()
  end,
  ["FOCUS-001 FOCUS-003 FOCUS-006: cold Space bootstrap observes an earlier focus after independent admission"] = function()
    local f = fakeHs(); f.members = {}
    local ten = load(f); ten:start()
    f.owners, f.focusedWindow = { "next-space" }, f.window
    local beforeRaw = f.focusedWindowQueries
    f.appWatcher.callback({ id = function() return 9 end }, "AXFocusedWindowChanged") -- old host, before Space activation
    assert(f.focusedWindowQueries == beforeRaw + 1)
    assert(ten.core:state().manager.windows[9] == nil and #ten.focusHistory:snapshot() == 0 and f.focuses == 0)
    f.activeSpace, f.members = "next-space", { 9 }
    local queries, focuses = f.focusedWindowQueries, f.focuses
    f.contextWatcher.callback()
    local state = ten.core:state().manager
    local desired = state.focus.desiredBySpace["next-space"]
    assert(state.focus.actualWindow.id == 9 and desired.targetId == 9 and not desired.pending)
    assert(#ten.focusHistory:snapshot() == 1 and ten.focusHistory:snapshot()[1].windowId == 9)
    assert(f.focusedWindowQueries == queries + 1 and f.focuses == focuses)
    ten:stop()
  end,
  ["composition created/destroyed and availability callbacks update replacement Core only"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start()
    f.appWatcher.callback(f.window, "AXWindowCreated"); assert(ten.core:state().manager.windows[9])
    f.windowWatcher.callback(nil, "AXWindowMiniaturized"); assert(ten.core:state().manager.windows[9] and f.frames == 1)
    f.actual = { x = 5, y = 0, w = 1, h = 1 }; f.windowWatcher.callback(nil, "AXWindowDeminiaturized"); assert(f.frames == 2)
    f.life.callback(nil, _G.hs.application.watcher.hidden, f.window:application()); assert(ten.core:state().manager.windows[9])
    f.life.callback(nil, _G.hs.application.watcher.unhidden, f.window:application()); assert(ten.core:state().manager.windows[9])
    f.windowWatcher.callback(nil, "AXUIElementDestroyed"); assert(not ten.core:state().manager.windows[9] and not ten.host.handles[9])
    ten:stop()
  end,
  ["composition unknown focus never admits or scans and inactive creation defers"] = function()
    local f, element = fakeHs(); local ten = load(f); ten:start(); local scans = f.scans
    ten.windows:_window({ kind = "focus", id = 99 }, ten.windows.generation); assert(not ten.core:state().manager.windows[99] and f.scans == scans)
    f.windowWatcher.callback(nil, "AXUIElementDestroyed"); f.owners = { "other" }; f.appWatcher.callback(f.window, "AXWindowCreated"); assert(not ten.core:state().manager.windows[9])
    ten:stop()
  end,
  ["composition rolls back bind and bootstrap failures exactly once then retries"] = function()
    local f = fakeHs({ failBind = 2 }); local ten = load(f); assert(not pcall(function() ten:start() end)); assert(not ten.started and ten.host == nil and f.deleted == 4, "expected owned host watchers and first binding rollback")
    _G.hs.hotkey.bind = function(_, _, cb) local h = { delete = function(self) if not self.deleted then self.deleted = true; f.deleted = f.deleted + 1 end end }; f.bindings[#f.bindings + 1] = { callback = cb, handle = h }; return h end
    ten:start(); assert(ten.started); ten:stop()
    f = fakeHs({ bootstrapFails = true }); ten = load(f); ten:start()
    assert(ten.started and ten.host and not ten.core:state().manager.windows[9], "one app bootstrap failure must defer rather than abort startup")
    ten:stop()
  end,
  ["configureFile then bindHotkeys then start retains canary instrumentation"] = function()
    local f = fakeHs()
    local ten = loadConfiguredFile(f, { builtInDisplayUUID = "built-in", canaryInstrumentation = true })
    local status = ten:canaryStatus()
    assert(ten.config.canaryInstrumentation == true)
    assert(status.enabled and status.started and not status.suspended and status.memberCount == 1 and status.activeTimers == 0)
    ten:stop(); assert(ten:canaryStatus().started == false)
  end,
  ["Canary A instrumentation exposes only aggregate runtime status"] = function()
    local f = fakeHs(); local ten = load(f)
    ten:configure({ builtInDisplayUUID = "built-in", canaryInstrumentation = true })
    ten:start()
    local status = ten:canaryStatus()
    assert(status.enabled and status.started and not status.suspended and status.memberCount == 1 and status.activeTimers == 0)
    assert(status.counts["event.WindowReady"] == 1 and status.counts.reducerCommitVersions == 1)
    ten:stop(); assert(ten:canaryStatus().started == false)
  end,
  ["FOCUS-001 FOCUS-005 FOCUS-006 CMD-005 COL-007: global previous confirmation routes by retained Core for every callback/activation order"] = function()
    local function crossSpaceSetup(confirmImmediately, withColumns)
      local f = fakeHs(); local ten = load(f); ten:start()
      ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
      local firstCore = ten.core
      local columnHandle
      if withColumns then
        firstCore:submit({ type = "WindowReady", id = 11, title = "Column", displayId = "built-in", spaceId = "space", application = { pid = 11, name = "Column" } })
        columnHandle = { id = function() return 11 end, title = function() return "Column" end,
          application = function() return { name = function() return "Column" end } end, focus = function() end,
          frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }
        ten.handleRegistry:remember(11, "space", columnHandle, 11)
        firstCore:submit({ type = "CycleLayout" })
        ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
      end
      f.activeSpace, f.members, f.owners = "next-space", {}, { "next-space" }
      f.contextWatcher.callback()
      ten.core:submit({ type = "WindowReady", id = 10, title = "Other", displayId = "built-in", spaceId = "next-space", application = { pid = 10, name = "Other" } })
      local otherFocuses = 0
      local otherHandle = { id = function() return 10 end, title = function() return "Other" end,
        application = function() return { name = function() return "Other" end } end,
        focus = function() otherFocuses = otherFocuses + 1 end,
        frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }
      ten.handleRegistry:remember(10, "next-space", otherHandle, 10)
      ten:_submitEvent({ type = "ActualFocusChanged", id = 10 })
      if confirmImmediately then f.focusedWindow = f.window end
      assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
      if not confirmImmediately then
        local targetDesired = firstCore:state().manager.focus.desiredBySpace.space
        assert(targetDesired.pending and targetDesired.targetId == 9) -- committed before the native cross-Space effect
        ten:_submitEvent({ type = "ActualFocusChanged", id = 99 }) -- unmanaged focus preserves the managed anchor
        ten:_submitEvent({ type = "ActualFocusChanged", id = 10 }) -- stale managed callback cannot replace the request
        targetDesired = firstCore:state().manager.focus.desiredBySpace.space
        assert(ten.focusHistory:pending().windowId == 9 and targetDesired.pending and targetDesired.targetId == 9)
      end
      return f, ten, firstCore, function() return otherFocuses end, otherHandle, columnHandle
    end

    local cases = {
      {
        name = "POC-009 matching cross-Space read confirms pending, later callback is harmless, and mouse h/l works",
        run = function()
          local f, ten, firstCore, otherFocuses, otherHandle, columnHandle = crossSpaceSetup(true, true)
          assert(ten.focusHistory:pending() == nil and not firstCore:state().manager.focus.desiredBySpace.space.pending)
          f.appWatcher.callback(f.window, "AXFocusedWindowChanged") -- later real callback
          assert(ten.focusHistory:pending() == nil and not firstCore:state().manager.focus.desiredBySpace.space.pending)
          f.focusedWindow = otherHandle
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(otherFocuses() == 1 and ten.focusHistory:pending() == nil)
          f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
          f.contextWatcher.callback()
          ten:_submitEvent({ type = "ActualFocusChanged", id = 11 }) -- native mouse focus
          assert(ten.core == firstCore and ten.core:state().coordinators.space.layouts.columns.activeStack == 2)
          f.focusedWindow = f.window
          ten.core:submit({ type = "FocusLeftGroup" })
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          f.focusedWindow = columnHandle
          ten.core:submit({ type = "FocusRightGroup" })
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          ten:stop()
        end,
      },
      {
        name = "managed focus callback before Space activation",
        run = function()
          local f, ten, firstCore, otherFocuses = crossSpaceSetup()
          -- The old host receives the target focus while its context still says
          -- next-space. Its descriptor must retain the confirmed source Space.
          f.owners, f.focusedWindow = { "space" }, f.window
          f.appWatcher.callback(f.window, "AXFocusedWindowChanged")
          assert(ten.handleRegistry:resolve({ windowId = 9, spaceId = "space" }) == f.window)
          assert(ten.focusHistory:pending() == nil)
          assert(not firstCore:state().manager.focus.desiredBySpace.space.pending)
          f.activeSpace, f.members = "space", { 9 }
          f.contextWatcher.callback()
          assert(ten.core == firstCore and not ten.core:state().manager.focus.desiredBySpace.space.pending)
          local queries = f.focusedWindowQueries
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(otherFocuses() == 1 and f.focusedWindowQueries == queries + 1 and ten.focusHistory:pending().windowId == 10)
          ten:stop()
        end,
      },
      {
        name = "Space activation before managed focus callback",
        run = function()
          local f, ten, firstCore, otherFocuses = crossSpaceSetup()
          f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
          f.contextWatcher.callback()
          assert(ten.core == firstCore and ten.core:state().manager.focus.desiredBySpace.space.pending)
          f.focusedWindow = f.window
          f.appWatcher.callback(f.window, "AXFocusedWindowChanged")
          assert(ten.focusHistory:pending() == nil)
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(otherFocuses() == 1 and ten.focusHistory:pending().windowId == 10)
          ten:stop()
        end,
      },
      {
        name = "same-Space A to B to previous A confirmation to previous B",
        run = function()
          local f = fakeHs(); local ten = load(f); ten:start()
          ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
          ten.core:submit({ type = "WindowReady", id = 10, title = "B", displayId = "built-in", spaceId = "space", application = { pid = 10, name = "B" } })
          ten.handleRegistry:remember(10, "space", { id = function() return 10 end, title = function() return "B" end,
            application = function() return { name = function() return "B" end } end, focus = function() end,
            frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }, 10)
          ten:_submitEvent({ type = "ActualFocusChanged", id = 10 })
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(ten.core:state().manager.focus.desiredBySpace.space.targetId == 9)
          ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
          assert(ten.focusHistory:pending() == nil and not ten.core:state().manager.focus.desiredBySpace.space.pending)
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          assert(ten.core:state().manager.focus.desiredBySpace.space.targetId == 10)
          ten:stop()
        end,
      },
      {
        name = "mouse focus after previous confirmation enables first directional command",
        run = function()
          local f = fakeHs(); local ten = load(f); ten:start()
          ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
          ten.core:submit({ type = "WindowReady", id = 10, title = "B", displayId = "built-in", spaceId = "space", application = { pid = 10, name = "B" } })
          ten.handleRegistry:remember(10, "space", { id = function() return 10 end, title = function() return "B" end,
            application = function() return { name = function() return "B" end } end, focus = function() end,
            frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, setFrame = function() end }, 10)
          ten:_submitEvent({ type = "ActualFocusChanged", id = 10 })
          ten.core:submit({ type = "CycleLayout" })
          assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
          ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
          ten:_submitEvent({ type = "ActualFocusChanged", id = 10 }) -- mouse/native focus
          assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
          assert(ten.core:state().coordinators.space.layouts.columns.activeStack == 2)
          ten.core:submit({ type = "FocusLeftGroup" })
          local desired = ten.core:state().manager.focus.desiredBySpace.space
          assert(desired.pending and desired.targetId == 9)
          ten:stop()
        end,
      },
    }
    for _, case in ipairs(cases) do case.run() end
  end,
  ["FOCUS-005 destroyed global previous target is skipped without native focus or scan"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
    local stale = { focus = function() error("destroyed handle focused") end }
    ten.focusHistory:observe({ windowId = 10, spaceId = "other" })
    ten.handleRegistry:remember(10, "other", stale, 10)
    local scans = f.scans
    local accepted, reason = ten:_submitCommand({ type = "FocusManagedPrevious" })
    assert(not accepted and reason == "no-previous-managed-window" and f.scans == scans)
    assert(#ten.focusHistory:snapshot() == 1)
    ten:stop()
  end,
  ["regular Spaces retain independent Core state across A-to-B-to-A activation"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local firstCore, oldWindowWatcher, oldSpaceWatcher = ten.core, f.windowWatcher.callback, f.contextWatcher.callback
    local firstMember = firstCore:state().manager.spaces.space.memberIds[1]
    local scans, frames = f.scans, f.frames

    f.contextWatcher.callback()
    assert(ten.core == firstCore and f.scans == scans and f.frames == frames)

    f.activeSpace, f.members, f.owners = "next-space", {}, { "next-space" }
    f.contextWatcher.callback()
    local secondCore = ten.core
    assert(secondCore ~= firstCore and ten.context.regularSpaceId == "next-space")
    assert(#secondCore:state().manager.spaces["next-space"].memberIds == 0)
    oldWindowWatcher(nil, "AXWindowMiniaturized")
    assert(firstCore:state().manager.windows[9] and not firstCore:state().manager.windows[9].lifecycle.minimized)

    f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
    f.contextWatcher.callback()
    assert(ten.core == firstCore and ten.context.regularSpaceId == "space")
    assert(firstCore:state().manager.spaces.space.memberIds[1] == firstMember)
    f.windowWatcher.callback(nil, "AXWindowMiniaturized")
    assert(firstCore:state().manager.windows[9].lifecycle.minimized)
    assert(ten.cores["next-space"] == secondCore)
    ten:stop(); oldSpaceWatcher(); assert(not ten.started)
  end,
}
