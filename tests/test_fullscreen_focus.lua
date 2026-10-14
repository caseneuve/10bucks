-- POC-010: native fullscreen is independently ready but has no regular slot.
-- Native focus can confirm before the Space callback; no callback is injected
-- inside enumeration. Fullscreen exit ordering is also recorded in POC-001/003.
local function setup(retained)
  local f = { fullscreen = not retained, activeSpace = retained and "regular" or "full", focuses = {}, frames = {}, watchers = {}, scans = 0, queries = 0, timers = {} }
  local function watcher(callback)
    return { callback = callback, start = function() end, stop = function(self) self.stopped = true end }
  end
  local app = { isHidden = function() return f.hidden == true end, pid = function() return 41 end, name = function() return "Fixture" end, bundleID = function() return "fixture" end }
  -- Dock owns only the topology boundary observer, never fixture AX windows.
  local dock = { pid = function() return 81 end, bundleID = function() return 'com.apple.dock' end,
    allWindows = function() return {} end }
  local dockElement = { attributeValue = function(_, name) if name == 'AXChildren' then return {} end end }
  local windows = {}
  local function owner(id) return id == 1 and f.fullscreen and "full" or "regular" end
  for id = 1, 2 do
    local window = { isMinimized = function() return f.minimized == true end, id = function() return id end, title = function() return "fixture" end,
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
      allSpaces = function() return { ["built-in"] = { "regular", "full" } } end,
      spaceType = function(id) return id == "full" and "fullscreen" or "user" end,
      windowsForSpace = function(space) local ids = {}; for id in ipairs(windows) do if owner(id) == space then ids[#ids + 1] = id end end; return ids end,
      windowSpaces = function(id) if f.ownerOverride then return f.ownerOverride end; return { owner(id) } end,
      watcher = { new = function(callback) f.contextWatcher = watcher(callback); return f.contextWatcher end } },
    axuielement = { applicationElement = function(application) assert(application == dock); return dockElement end,
      observer = { notifications = { AXUIElementDestroyed = 'AXUIElementDestroyed' }, new = function(pid)
        assert(pid == 81)
        local observer = {
          callback = function(self, callback) self.notification = callback; return self end,
          addWatcher = function(_, element, notification)
            assert(element == dockElement and notification == 'AXUIElementDestroyed'); return true
          end,
          start = function(self) self.running = true; return self end,
          stop = function(self) self.running = false; self.stopped = true end,
        }
        f.dockObserver = observer; return observer
      end }, windowElement = function(window) return {
      isValid = function() return true end,
      attributeValue = function() return false end,
      isAttributeSettable = function(_, attribute) return not (window == windows[1] and f.fullscreen and attribute == "AXPosition") end,
    } end },
    window = { focusedWindow = function() f.queries = f.queries + 1; return f.focused end,
      list = function() local rows = {}; for id in ipairs(windows) do if owner(id) == f.activeSpace then
        rows[#rows + 1] = { kCGWindowNumber = id, kCGWindowOwnerPID = 41 } end end; return rows end },
    application = { applicationsForBundleID = function(bundle) assert(bundle == 'com.apple.dock'); return { dock } end,
      runningApplications = function() return { app } end, applicationForPID = function(pid) return pid == 41 and app or nil end,
      watcher = { new = function(callback)
        local object = watcher(callback)
        if not f.life or f.life.stopped then f.life = object else f.dockLife = object end
        return object
      end,
        launched = 2, terminated = 3, hidden = 4, unhidden = 5, activated = 6 } },
    canvas = { new = canvas }, mouse = { absolutePosition = function() return { x = 50, y = 50 } end }, host = { interfaceStyle = function() return nil end },
    distributednotifications = { new = function() return { start = function() end, stop = function() end } end },
    timer = { secondsSinceEpoch = function() return 1 end, doAfter = function(delay, callback)
      local timer = barTimer(); timer.delay, timer.callback = delay, callback
      timer.stop = function(self) self.stopped = true end
      f.timers[#f.timers + 1] = timer; return timer
    end, doEvery = function() return barTimer() end },
    alert = { show = function(message) f.alert = message end },
    hotkey = { bind = function() return { delete = function() end } end },
  }
  local discovery = { inventory = function()
    local rows = {}; for id in ipairs(windows) do rows[#rows + 1] = { windowId = id, pid = 41, layer = 0 } end
    return rows
  end, create = function() error("all fixture windows exposed") end }
  local ten = dofile("10bucks.spoon/init.lua").new({create=function()return {set=function()end,poll=function()return {}end,stop=function()end}end}, discovery):configure({ builtInDisplayUUID = "built-in" }):start()
  f.ten, f.windows = ten, windows
  function f:activateRegular()
    self.activeSpace, self.focused = "regular", windows[2]
    self.contextWatcher.callback()
  end
  function f:previous()
    assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
  end
  function f:choose(id)
    for _, row in ipairs(ten.chooserRows) do if row.windowId == id then return ten:_chooseWindow(row) end end
    error("fixture chooser row missing")
  end
  return f, ten
end

return {
  ["CHOOSE-001 CHOOSE-003 FS-002 FS-005 STATE-002: chooser focuses retained and unplaced fullscreen without slot/frame/order changes"] = function()
    for _, retained in ipairs({ false, true }) do
      local f, ten = setup(retained)
      local core = ten.cores.regular
      local order = table.concat(core:state().manager.spaces.regular.memberIds, ",")
      if retained then
        f.fullscreen = true
        f.watchers[1].callback(nil, "AXWindowResized")
      end
      f:activateRegular()
      local layout = core:state().coordinators.regular.activeLayoutId
      local rows = table.concat({ ten.chooserRows[1].windowId, ten.chooserRows[2].windowId }, ",")
      f.onFocus = function(id) assert(ten.focusHistory:pending().windowId == id) end
      local queries, scans, effects = f.queries, f.scans, #f.focuses
      assert(f:choose(1))
      assert(#f.focuses == effects + 1, "chooser selection has exactly one focus effect")
      assert(f.activeSpace == "full" and f.focused == f.windows[1] and not ten.focusHistory:pending())
      assert(f.queries == queries + 1 and f.scans == scans)
      assert(table.concat(core:state().manager.spaces.regular.memberIds, ",") == order)
      assert(core:state().coordinators.regular.activeLayoutId == layout)
      assert(table.concat({ ten.chooserRows[1].windowId, ten.chooserRows[2].windowId }, ",") == rows)
      assert((core:state().manager.windows[1] ~= nil) == retained)
      if retained then assert(core:state().manager.windows[1].placementSpaceId == "regular") else assert(not f.frames[1]) end
      f.contextWatcher.callback()
      assert(f:choose(1) and not ten.focusHistory:pending(), "unchanged exact focus confirms without AX callback")
      ten:stop()
    end
  end,
  ["CHOOSE-001 STATE-008 FS-005: unplaced overlapping lifecycle rejects until each flag clears and readiness refreshes"] = function()
    local f, ten = setup(); f:activateRegular()
    f.minimized, f.hidden = true, true
    f.watchers[1].callback(nil, "AXWindowMiniaturized")
    f.life.callback(nil, hs.application.watcher.hidden, f.windows[1]:application())
    local effects = #f.focuses
    assert(not f:choose(1) and #f.focuses == effects)
    f.minimized = false; f.watchers[1].callback(nil, "AXWindowDeminiaturized")
    assert(not f:choose(1) and #f.focuses == effects)
    f.hidden = false
    ten.host:_ready(f.windows[1], "targetedReadiness", ten.host.windowCallback)
    assert(f:choose(1), "repeat independently confirmed readiness refreshes lifecycle")
    ten:stop()
  end,
  ["CHOOSE-001 STATE-005 FOCUS-003: uncertain/mismatched native owner rejects without admission or focus"] = function()
    for _, owners in ipairs({ {}, { "regular" }, { "full", "regular" }, { "other-full" } }) do
      local f, ten = setup(); f:activateRegular(); f.ownerOverride = owners
      local nativeType = hs.spaces.spaceType
      hs.spaces.spaceType = function(id) return id == "other-full" and "fullscreen" or nativeType(id) end
      local effects, scans = #f.focuses, f.scans
      assert(not f:choose(1) and #f.focuses == effects and not ten.focusHistory:pending())
      assert(ten.focusHistory:unplacedTarget(1) and not ten.core:state().manager.windows[1] and f.scans == scans)
      ten:stop()
    end
  end,
  ["CHOOSE-001 STATE-005 WIN-005: exact resource uncertainty replacement and destruction never focus numerical aliases"] = function()
    for _, kind in ipairs({ "uncertain", "invalid", "replaced", "app-retired", "destroyed" }) do
      local f, ten = setup(); f:activateRegular()
      local row
      for _, item in ipairs(ten.chooserRows) do if item.windowId == 1 then row = item end end
      local record = ten.host.handles[1]
      if kind == "uncertain" then record.element.isValid = function() return nil end
      elseif kind == "invalid" then record.element.isValid = function() return false end
      elseif kind == "replaced" then record.handle = { id = function() return 1 end }
      elseif kind == "app-retired" then ten.host.appResources[41].active = false
      else f.watchers[1].callback(nil, "AXUIElementDestroyed") end
      local effects, scans = #f.focuses, f.scans
      assert(not ten:_chooseWindow(row) and #f.focuses == effects and f.scans == scans)
      assert(not ten.focusHistory:pending())
      if kind == "uncertain" or kind == "replaced" then assert(ten.focusHistory:unplacedTarget(1)) end
      ten:stop()
    end
  end,
  ["CMD-006 CHOOSE-001: desktop operation gates fullscreen even when saved placement is active"] = function()
    for _, retained in ipairs({ false, true }) do
      local f, ten = setup(retained)
      if retained then f.fullscreen = true; f.watchers[1].callback(nil, "AXWindowResized") end
      f:activateRegular()
      local original = ten.workspace.state
      for _, creating in ipairs({ false, true }) do
        ten.workspace.state = function() return { switch = { inFlight = { creating = creating } } } end
        local effects = #f.focuses
        local ok, reason = f:choose(1)
        assert(not ok and reason == (creating and "desktop-creation-pending" or "desktop-switch-pending"))
        assert(#f.focuses == effects and not ten.focusHistory:pending())
      end
      ten.workspace.state = original
      ten:stop()
    end
  end,
  ["FOCUS-006 CMD-005: stale chooser confirmation cannot overwrite newer pending history or selection"] = function()
    local f, ten = setup(); f:activateRegular(); f.delayFocus = true
    assert(f:choose(1))
    f.focused = nil
    assert(f:choose(2) and ten.focusHistory:pending().windowId == 2)
    local core = ten.core
    f.focused = f.windows[1]; f.appWatcher.callback(f.windows[1], "AXFocusedWindowChanged")
    assert(ten.focusHistory:pending().windowId == 2)
    assert(core:state().manager.focus.desiredBySpace.regular.targetId == 2)
    assert(ten.focusHistory:snapshot()[2].windowId == 2)
    f.focused = f.windows[2]; f.appWatcher.callback(f.windows[2], "AXFocusedWindowChanged")
    assert(not ten.focusHistory:pending() and not core:state().manager.focus.desiredBySpace.regular.pending)
    ten:stop()
  end,
  ["FOCUS-006 CMD-005 CMD-006: chooser timeout supersession shutdown and late callbacks release only current authority"] = function()
    local f, ten = setup(); f:activateRegular(); f.delayFocus = true
    assert(f:choose(1)); local expired = ten.managedFocusTimer
    assert(expired and ten.focusHistory:pending().windowId == 1)
    assert(f:choose(2) and not ten.focusHistory:pending())
    expired.callback(); assert(not ten.focusHistory:pending() and not f.alert)
    assert(f:choose(1)); local timeout = ten.managedFocusTimer
    local effects = #f.focuses; timeout.callback()
    assert(not ten.focusHistory:pending() and #f.focuses == effects and f.alert)
    assert(not ten.core:state().manager.focus.desiredBySpace.regular.pending)
    assert(f:choose(1)); local stopped = ten.managedFocusTimer
    ten:stop(); stopped.callback(); assert(not ten.focusHistory:pending() and #f.focuses == effects + 1)
  end,
  ["FOCUS-006 CMD-005 FS-002: departed saved placement Space callback cannot cancel fullscreen chooser authority"] = function()
    local f, ten = setup(true); f.fullscreen = true; f.watchers[1].callback(nil, "AXWindowResized"); f:activateRegular()
    f.delayFocus = true; assert(f:choose(1))
    f.activeSpace = "full"; f.contextWatcher.callback()
    assert(ten.focusHistory:pending().windowId == 1)
    f.focused = f.windows[1]; f.appWatcher.callback(f.windows[1], "AXFocusedWindowChanged")
    assert(not ten.focusHistory:pending())
    ten:stop()
  end,
  ["FOCUS-006 STATE-002: same-Space chooser terminal native failure clears both authorities"] = function()
    local f, ten = setup(); f:activateRegular()
    f.windows[2].focus = function() error("fixture local focus failure") end
    local ok, reason = f:choose(2)
    assert(not ok and reason == "managed-focus-failed")
    assert(not ten.focusHistory:pending() and not ten.managedFocusTimer)
    assert(not ten.core:state().manager.focus.desiredBySpace.regular.pending)
    ten:stop()
  end,
  ["FOCUS-006 STATE-002: native focus exception clears chooser global and Core authority"] = function()
    for _, retained in ipairs({ false, true }) do
      local f, ten = setup(retained)
      if retained then f.fullscreen = true; f.watchers[1].callback(nil, "AXWindowResized") end
      f:activateRegular(); f.windows[1].focus = function() error("fixture focus failure") end
      assert(not f:choose(1) and not ten.focusHistory:pending())
      assert(not ten.core:state().manager.focus.desiredBySpace.regular.pending)
      ten:stop()
    end
  end,
  ["FS-004 FS-005 FOCUS-003: cold fullscreen is tracked without a Core, layout slot, frame, or focus request"] = function()
    local f, ten = setup()
    assert(ten.core == nil and ten.suspended)
    assert(ten.focusHistory:unplacedTarget(1) and #ten.focusHistory:snapshot() == 1)
    assert(ten.cores.regular and ten.cores.regular:state().manager.windows[2])
    assert(next(f.frames) == nil and #f.focuses == 0 and f.scans == 1)
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
