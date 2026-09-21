local Host = require("lib.macos.window_host")

local function fake()
  local f = { scans = 0, stops = 0, membershipQueries = 0, ownerQueries = 0, focusedWindowQueries = 0, focusRequests = 0, owners = { 9 }, members = { 9 } }
  local function watcher(callback) return { start = function(self) self.callback = callback; if f.failStart == self then error("start failed") end end, stop = function(self) if not self.stopped then self.stopped = true; f.stops = f.stops + 1 end end } end
  -- Installed Hammerspoon 1.1.1: docs.json describes hs.uielement:newWatcher,
  -- but axuielement.windowElement(window) is a different userdata with no watcher.
  local element = { asHSWindow = function() return f.window end, attributeValue = function(_, key) return key == "AXModal" and false end, isAttributeSettable = function() return true end }
  local function windowWatcher(callback) f.windowWatcher = watcher(callback); return f.windowWatcher end
  local app = { pid = function() return 7 end, name = function() return "App" end, bundleID = function() return "app" end, focusedWindow = function() return f.window end, allWindows = function() f.scans = f.scans + 1; return { f.window } end, newWatcher = function(_, callback) local w = watcher(callback); f.appWatchers[#f.appWatchers + 1] = w; return w end }
  f.appWatchers = {}
  f.actual = { x = 0, y = 0, w = 10, h = 10 }
  f.window = { id = function() return 9 end, title = function() return "Title" end, application = function() return app end, role = function() return "AXWindow" end, subrole = function() return "AXStandardWindow" end, isFullScreen = function() return f.fullscreen end, newWatcher = function(_, callback) return windowWatcher(callback) end, frame = function() return f.actual end, setFrame = function(_, frame, duration) f.duration = duration; f.writes = (f.writes or 0) + 1; f.actual = frame end, focus = function() f.focusRequests = f.focusRequests + 1 end }
  f.hs = { processInfo = { processID = 1 }, window = { focusedWindow = function() f.focusedWindowQueries = f.focusedWindowQueries + 1; if f.focusedWindowError then error("focused-window read failed") end; return f.focusedWindow end }, axuielement = { windowElement = function(value) assert(value == f.window, "reverse conversion forbidden"); return element end }, spaces = { windowsForSpace = function() f.membershipQueries = f.membershipQueries + 1; return f.members end, windowSpaces = function(id) assert(id == 9); f.ownerQueries = f.ownerQueries + 1; return f.owners end, spaceType = function(id) assert(id == 9); return f.spaceType or "user" end }, application = { runningApplications = function() return { app } end, watcher = { new = function(callback) f.lifecycle = watcher(callback); return f.lifecycle end, terminated = 3, hidden = 4, unhidden = 5, launched = 2, activated = 5 } } }
  return f, app, element
end
return {
  ["host bootstrap uses one active-Space snapshot and one app scan, deferring absent handles"] = function()
    local f, _, element = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:subscribeExistingWindows(function(e) events[#events + 1] = e end)
    assert(f.membershipQueries == 1 and f.scans == 1 and events[1].metadata.origin == "bootstrap")
    f.members = {}; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 2 and f.ownerQueries == 1)
    f.owners = { 99 }; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 2)
    f.owners = { 9, 10 }; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 2)
    f.owners = { 9 }; f.spaceType = "fullscreen"; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 2)
  end,
  ["nil/error app watcher and failed bootstrap defer only that app while peers still boot"] = function()
    local f, primary = fake()
    local peer = {}
    peer.pid = function() return 8 end
    peer.name = function() return "Peer" end
    peer.bundleID = function() return "peer" end
    peer.newWatcher = function() error("AX unavailable") end
    peer.allWindows = function() error("window enumeration unavailable") end
    f.hs.application.runningApplications = function() return { peer, primary } end
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local events = {}
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    assert(#events == 1 and events[1].metadata.application.pid == 7)
    assert(#f.appWatchers == 1, "working peer must retain its subscription")

    local f2, app2 = fake()
    app2.newWatcher = function() return nil end
    local host2 = Host.new(f2.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local booted = {}
    host2:subscribeExistingWindows(function(event) booted[#booted + 1] = event end)
    assert(#booted == 1 and f2.scans == 1, "nil watcher defers subscription but bootstrap remains available")
  end,
  ["each host watcher start failure stops its registered watcher before retry"] = function()
    local function failing(kind)
      local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
      if kind == "application" then
        f.hs.application.watcher.new = function(callback) return { start = function() error("start failed") end, stop = function() f.stops = f.stops + 1 end } end
        return f, function() host:subscribeApplications(function() end) end
      elseif kind == "appAX" then
        app.newWatcher = function() return { start = function() error("start failed") end, stop = function() f.stops = f.stops + 1 end } end
        return f, function() host:_attachApp(app, function() end) end
      end
      f.window.newWatcher = function() return { start = function() error("start failed") end, stop = function() f.stops = f.stops + 1 end } end
      return f, function() host:subscribeWindow(f.window, function() end) end
    end
    for _, kind in ipairs({ "application", "appAX", "windowAX" }) do
      local f, start = failing(kind); assert(not pcall(start)); assert(f.stops == 1, kind .. " watcher leaked after failed start")
    end
  end,
  ["host frame effects compare targeted actual frames and permit drift correction"] = function()
    local f = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local adapter = { handleForId = function() return f.window end }
    host:execute(adapter, { { kind = "frame", windowId = 9, frame = { x = 0, y = 0, w = 10, h = 10 } } }); assert(not f.writes)
    f.actual = { x = 3, y = 0, w = 10, h = 10 }
    host:execute(adapter, { { kind = "frame", windowId = 9, frame = { x = 0, y = 0, w = 10, h = 10 } } }); assert(f.writes == 1)
    host:execute(adapter, { { kind = "frame", windowId = 9, frame = { x = 0, y = 0, w = 10, h = 10 } } }); assert(f.writes == 1)
  end,
  ["POC-009 host focus confirms only a matching targeted read without an AX callback"] = function()
    local f = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    local baseline, scans, memberships, owners = #events, f.scans, f.membershipQueries, f.ownerQueries
    f.focusedWindow = f.window
    host:focus(f.window)
    assert(f.focusRequests == 1 and f.focusedWindowQueries == 1)
    assert(#events == baseline + 1 and events[#events].kind == "focus" and events[#events].id == 9)
    f.focusedWindow = { id = function() return 10 end }
    host:focus(f.window)
    f.focusedWindow = nil
    host:focus(f.window)
    f.focusedWindowError = true
    host:focus(f.window)
    assert(f.focusRequests == 4 and f.focusedWindowQueries == 4 and #events == baseline + 1)
    assert(f.scans == scans and f.membershipQueries == memberships and f.ownerQueries == owners)
    host:stop()
  end,
  ["host caches known handles, clears destruction/termination, and owns watchers once"] = function()
    local f, app, element = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:subscribeApplications(function(e) events[#events + 1] = e end); host:subscribeExistingWindows(function(e) events[#events + 1] = e end)
    local subscription = host:subscribeWindow(f.window, function(e) events[#events + 1] = e end)
    host:probeReadiness(9, function(metadata) assert(metadata and metadata.origin == "targetedReadiness") end); local scans = f.scans
    host:probeReadiness(99, function(metadata) assert(metadata == nil) end); assert(f.scans == scans)
    f.windowWatcher.callback(nil, "AXWindowMiniaturized"); f.fullscreen = true; f.windowWatcher.callback(nil, "AXWindowResized"); f.windowWatcher.callback(nil, "AXUIElementDestroyed")
    assert(events[#events].kind == "destroyed"); host:probeReadiness(9, function(metadata) assert(metadata == nil) end)
    local lifecycleCount, scansBeforeLaunch = #events, f.scans
    f.focusedWindow = f.window
    f.lifecycle.callback(nil, 5, app)
    assert(events[#events].kind == "focus" and events[#events].id == 9)
    lifecycleCount = #events
    f.lifecycle.callback(nil, 2, app)
    assert(#events == lifecycleCount + 1 and events[#events].kind == "ready")
    assert(events[#events].metadata.origin == "targetedReadiness")
    assert(f.scans == scansBeforeLaunch + 1, "launch must perform exactly one app-local readiness scan")
    f.appWatchers[#f.appWatchers].callback(f.window, "AXWindowCreated"); assert(events[#events].kind == "ready")
    local old = f.appWatchers[#f.appWatchers].callback
    f.lifecycle.callback(nil, 3, app); subscription.detach(); host:stop():stop(); assert(f.stops == 4)
    host:start(); old(element, "AXWindowCreated"); assert(events[#events].kind == "terminated")
  end,
}
