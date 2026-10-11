-- POC-010: native fullscreen is independently ready but has no regular slot.
-- Native focus can confirm before the Space callback; no callback is injected
-- inside enumeration. Fullscreen exit ordering is also recorded in POC-001/003.
local function setup()
  local f = { fullscreen = true, activeSpace = "full", focuses = {}, frames = {}, watchers = {}, scans = 0, queries = 0 }
  local function watcher(callback)
    return { callback = callback, start = function() end, stop = function(self) self.stopped = true end }
  end
  local app = { isHidden = function() return false end, pid = function() return 41 end, name = function() return "Fixture" end, bundleID = function() return "fixture" end }
  local windows = {}
  local function owner(id) return id == 1 and f.fullscreen and "full" or "regular" end
  for id = 1, 2 do
    local window = { isMinimized = function() return false end, id = function() return id end, title = function() return "fixture" end,
      application = function() return app end, role = function() return "AXWindow" end,
      subrole = function() return "AXStandardWindow" end,
      isFullScreen = function() return id == 1 and f.fullscreen end,
      newWatcher = function(_, callback) local w = watcher(callback); f.watchers[id] = w; return w end,
      frame = function() assert(not (id == 1 and f.fullscreen), "fullscreen must not receive frame queries"); return f.frames[id] or { x = 7, y = 0, w = 1, h = 1 } end,
      setFrame = function(_, frame) assert(not (id == 1 and f.fullscreen), "fullscreen must not receive frames"); f.frames[id] = frame end,
      focus = function()
        if f.onFocus then f.onFocus(id) end
        f.focuses[#f.focuses + 1] = id
        if not f.delayFocus then f.focused = windows[id]; f.activeSpace = owner(id) end
      end,
    }
    windows[id] = window
  end
  app.allWindows = function() f.scans = f.scans + 1; return windows end
  app.newWatcher = function(_, callback) f.appWatcher = watcher(callback); return f.appWatcher end
  f.focused = windows[1]
  local screen = { getUUID = function() return "built-in" end, frame = function() return { x = 0, y = 0, w = 100, h = 80 } end, fullFrame = function() return { x = 0, y = 0, w = 100, h = 80 } end }
  local function barTimer() return { stop = function() end } end
  local function canvas() return { level = function(self) return self end, behavior = function(self) return self end, clickActivating = function(self) return self end, canvasMouseEvents = function(self) return self end, mouseCallback = function(self) return self end, frame = function(self) return self end, replaceElements = function(self) return self end, show = function(self) return self end, hide = function(self) return self end, delete = function() end } end
  _G.hs = { processInfo = { processID = 99 }, screen = { allScreens = function() return { screen } end, watcher = { new = function(callback) return watcher(callback) end } },
    spaces = { activeSpaceOnScreen = function() return f.activeSpace end,
      data_managedDisplaySpaces = function() return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = f.activeSpace }, Spaces = { { ManagedSpaceID = "regular", type = 0 }, { ManagedSpaceID = "full", type = 4 } } } } end,
      spaceType = function(id) return id == "full" and "fullscreen" or "user" end,
      windowsForSpace = function(space) local ids = {}; for id in ipairs(windows) do if owner(id) == space then ids[#ids + 1] = id end end; return ids end,
      windowSpaces = function(id) return { owner(id) } end,
      watcher = { new = function(callback) f.contextWatcher = watcher(callback); return f.contextWatcher end } },
    axuielement = { windowElement = function(window) return {
      attributeValue = function() return false end,
      isAttributeSettable = function(_, attribute) return not (window == windows[1] and f.fullscreen and attribute == "AXPosition") end,
    } end },
    window = { focusedWindow = function() f.queries = f.queries + 1; return f.focused end,
      list = function() local rows = {}; for id in ipairs(windows) do if owner(id) == f.activeSpace then
        rows[#rows + 1] = { kCGWindowNumber = id, kCGWindowOwnerPID = 41 } end end; return rows end },
    application = { runningApplications = function() return { app } end, applicationForPID = function(pid) return pid == 41 and app or nil end,
      watcher = { new = function(callback) f.life = watcher(callback); return f.life end,
        launched = 2, terminated = 3, hidden = 4, unhidden = 5, activated = 6 } },
    canvas = { new = canvas }, mouse = { absolutePosition = function() return { x = 50, y = 50 } end }, host = { interfaceStyle = function() return nil end },
    distributednotifications = { new = function() return { start = function() end, stop = function() end } end },
    timer = { secondsSinceEpoch = function() return 1 end, doAfter = function() return barTimer() end, doEvery = function() return barTimer() end },
    hotkey = { bind = function() return { delete = function() end } end },
  }
  local ten = dofile("10bucks.spoon/init.lua"):configure({ builtInDisplayUUID = "built-in" }):start()
  f.ten, f.windows = ten, windows
  function f:activateRegular()
    self.activeSpace, self.focused = "regular", windows[2]
    self.contextWatcher.callback()
  end
  function f:previous()
    assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
  end
  return f, ten
end

return {
  ["FS-004 FS-005 FOCUS-003: cold fullscreen is tracked without a Core, layout slot, frame, or focus request"] = function()
    local f, ten = setup()
    assert(ten.core == nil and next(ten.cores) == nil and ten.suspended)
    assert(ten.focusHistory:unplacedTarget(1) and #ten.focusHistory:snapshot() == 1)
    assert(next(f.frames) == nil and #f.focuses == 0 and f.scans == 0)
    assert(not ten:_submitCommand({ type = "FocusNext" }))
    ten:stop()
  end,
  ["FOCUS-005 FOCUS-006 FS-005: previous toggles regular/fullscreen with pending committed before effects"] = function()
    local f, ten = setup(); f:activateRegular()
    local core = ten.core
    assert(#ten.focusHistory:snapshot() == 2 and core:state().manager.windows[1] == nil)
    f.onFocus = function(id)
      assert(ten.focusHistory:pending().windowId == id)
      if id == 2 then assert(core:state().manager.focus.desiredBySpace.regular.pending) end
    end
    f:previous(); assert(f.focuses[#f.focuses] == 1 and not ten.focusHistory:pending())
    f.contextWatcher.callback(); assert(ten.suspended)
    local queries, scans = f.queries, f.scans
    f:previous(); assert(f.focuses[#f.focuses] == 2 and not ten.focusHistory:pending())
    assert(f.queries == queries + 1 and f.scans == scans)
    assert(not core:state().manager.focus.desiredBySpace.regular.pending)
    f.contextWatcher.callback(); assert(ten.core == core and not ten.suspended)
    f:previous(); assert(f.focuses[#f.focuses] == 1)
    assert(core:state().manager.windows[1] == nil and f.frames[1] == nil)
    ten:stop()
  end,
  ["FOCUS-005 FOCUS-006: unconfirmed fullscreen previous repeats its target, not an older history entry"] = function()
    local f, ten = setup(); f:activateRegular(); f.delayFocus = true
    f:previous(); f:previous()
    assert(f.focuses[1] == 1 and f.focuses[2] == 1 and ten.focusHistory:pending().windowId == 1)
    assert(ten.focusHistory:snapshot()[2].windowId == 2)
    f.focused, f.activeSpace = f.windows[1], "full"
    f.appWatcher.callback(f.windows[1], "AXFocusedWindowChanged")
    assert(not ten.focusHistory:pending() and ten.focusHistory:snapshot()[2].windowId == 1)
    ten:stop()
  end,
  ["FOCUS-006: a newer local focus request supersedes pending global fullscreen focus"] = function()
    local f, ten = setup(); f:activateRegular(); f.delayFocus = true
    f:previous(); assert(ten.focusHistory:pending().windowId == 1)
    assert(ten:_submitCommand({ type = "FocusNext" })) -- already-actual regular target confirms immediately
    assert(not ten.focusHistory:pending(), "older global request must not outlive a newer confirmed local request")
    assert(not ten.core:state().manager.focus.desiredBySpace.regular.pending)
    ten:stop()
  end,
  ["FS-004 LIFE-003: exit promotes once to actual regular ownership without history insertion or reorder"] = function()
    local f, ten = setup(); f:activateRegular(); f:previous(); f.contextWatcher.callback()
    local before = ten.focusHistory:snapshot()
    f.fullscreen, f.activeSpace = false, "regular"
    f.watchers[1].callback(nil, "AXWindowResized")
    assert(not ten.focusHistory:unplacedTarget(1))
    local history = ten.focusHistory:snapshot()
    assert(#history == #before and history[1].windowId == before[1].windowId and history[2].windowId == before[2].windowId)
    assert(history[2].spaceId == "regular" and ten.core:state().manager.windows[1].placementSpaceId == "regular")
    f.contextWatcher.callback()
    assert(#ten.core:state().manager.spaces.regular.memberIds == 2)
    assert(not ten.core:state().manager.windows[1].lifecycle.nativeFullscreen)
    assert(not ten.core:state().manager.focus.desiredBySpace.regular.pending)
    assert(f.frames[1] and not ten.focusHistory:pending())
    ten:stop()
  end,
  ["FS-004 DISC-002: ordinary regular bootstrap admits a previously unplaced fullscreen window"] = function()
    local f, ten = setup()
    f.fullscreen = false -- regular bootstrap, not observer reattachment, observes the exit
    f:activateRegular()
    assert(not ten.focusHistory:unplacedTarget(1) and ten.core:state().manager.windows[1])
    ten:stop()
  end,
  ["WIN-005 FOCUS-005: destruction removes unplaced ownership and history"] = function()
    local f, ten = setup(); f:activateRegular()
    f.watchers[1].callback(nil, "AXUIElementDestroyed")
    assert(not ten.focusHistory:unplacedTarget(1) and not ten.handleRegistry:target(1))
    assert(#ten.focusHistory:snapshot() == 1 and not ten:_submitCommand({ type = "FocusManagedPrevious" }))
    ten:stop()
  end,
}
