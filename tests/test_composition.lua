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
  local element = { asHSWindow = function() return f.window end,
    attributeValue = function(_, _) return false end, isAttributeSettable = function() return true end,
    newWatcher = function(_, cb) f.windowWatcher = watcher(cb, "window"); return f.windowWatcher end }
  local app = { pid = function() return 8 end, name = function() return "App" end, bundleID = function() return "app" end,
    allWindows = function() f.scans = f.scans + 1; if options.bootstrapFails then error("bootstrap failed") end; return { f.window } end,
    newWatcher = function(_, cb) f.appWatcher = watcher(cb, "app"); return f.appWatcher end }
  f.window = { id = function() return 9 end, title = function() return "Window" end, application = function() return app end,
    role = function() return "AXWindow" end, subrole = function() return "AXStandardWindow" end,
    isFullScreen = function() return f.fullscreen end, frame = function() return f.actual end,
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
    f.appWatcher.callback(element, "AXWindowCreated"); assert(ten.core:state().manager.windows[9])
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
    f.windowWatcher.callback(nil, "AXUIElementDestroyed"); f.owners = { "other" }; f.appWatcher.callback(element, "AXWindowCreated"); assert(not ten.core:state().manager.windows[9])
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
  ["Canary A context A-to-B-to-A suspends non-destructively and resumes original Core"] = function()
    local f = fakeHs(); local ten = load(f); ten:start()
    local originalCore, oldWindowWatcher, oldSpaceWatcher = ten.core, f.windowWatcher.callback, f.contextWatcher.callback
    local before = ten.core:state().manager.spaces.space.memberIds[1]
    local scans, frames = f.scans, f.frames

    -- A duplicate confirmed activation does not rebuild, bootstrap, or emit effects.
    f.contextWatcher.callback()
    assert(ten.core == originalCore and f.scans == scans and f.frames == frames)

    f.activeSpace, f.members = "next-space", {}
    f.contextWatcher.callback()
    assert(ten.suspended and ten.core == originalCore and ten.context.regularSpaceId == "next-space")
    assert(ten.core:state().manager.spaces.space.memberIds[1] == before and f.frames == frames)
    oldWindowWatcher(nil, "AXWindowMiniaturized")
    assert(ten.core:state().manager.windows[9] and not ten.core:state().manager.windows[9].lifecycle.minimized)
    assert(f.bindings[1].callback() == false, "commands reject while context differs")

    f.activeSpace, f.members, f.owners = "space", { 9 }, { "space" }
    f.contextWatcher.callback()
    assert(not ten.suspended and ten.core == originalCore and ten.context.regularSpaceId == "space")
    assert(ten.core:state().manager.spaces.space.memberIds[1] == before)
    assert(f.windowWatcher, "resume starts a fresh host/adapter")
    f.windowWatcher.callback(nil, "AXWindowMiniaturized")
    assert(ten.core:state().manager.windows[9].lifecycle.minimized, "resumed callbacks reach original Core")
    ten:stop(); oldSpaceWatcher()
    assert(not ten.started)
  end,
}
