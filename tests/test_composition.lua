local function fakeHs(options)
  options = options or {}
  local f = { deleted = 0, frames = 0, focuses = 0, bindings = {}, scans = 0,
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
    assert(ten.core:state().manager.windows[9] and f.frames == 1)
    ten.core:submit({ type = "Reflow" }); assert(f.frames == 1)
    f.actual = { x = 7, y = 0, w = 100, h = 80 }; ten.core:submit({ type = "Reflow" }); assert(f.frames == 2)
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
  ["FOCUS-005 global previous crosses retained Spaces, waits for confirmation, toggles, and ignores stale/unmanaged focus"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
    local firstCore = ten.core

    f.activeSpace, f.members, f.owners = "next-space", {}, { "next-space" }
    f.contextWatcher.callback()
    ten.core:submit({ type = "WindowReady", id = 10, title = "Other", displayId = "built-in", spaceId = "next-space", application = { pid = 10, name = "Other" } })
    local otherFocuses, otherHandle = 0
    otherHandle = { focus = function() otherFocuses = otherFocuses + 1 end,
      frame = function() return { x = 0, y = 0, w = 100, h = 80 } end,
      setFrame = function() end }
    ten.handleRegistry:remember(10, "next-space", otherHandle, 10)
    ten:_submitEvent({ type = "ActualFocusChanged", id = 10 })
    ten:_submitEvent({ type = "ActualFocusChanged", id = 99 }) -- unmanaged popup does not alter managed anchor

    local beforeCrossFocus = f.focuses
    assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
    assert(f.focuses == beforeCrossFocus + 1 and ten.pendingGlobalFocus.windowId == 9)
    ten:_submitEvent({ type = "ActualFocusChanged", id = 10 }) -- stale callback cannot alter target/history
    assert(ten.pendingGlobalFocus.windowId == 9)

    f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
    f.contextWatcher.callback()
    assert(ten.core == firstCore and ten.core:state().manager.focus.desiredBySpace.space.targetId == 9)
    ten:_submitEvent({ type = "ActualFocusChanged", id = 9 })
    assert(ten.pendingGlobalFocus == nil)
    assert(not ten.core:state().manager.focus.desiredBySpace.space.pending)
    assert(ten:_submitCommand({ type = "FocusManagedPrevious" }))
    assert(otherFocuses == 1 and ten.pendingGlobalFocus.windowId == 10)
    ten:stop()
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
