local NativeHost = require("lib.macos.window_host")
local Host = { new = function(hs, context, instrumentation, registry, validity, discovery)
  return NativeHost.new(hs, context, instrumentation, registry, validity, discovery or {
    inventory = function()
      local rows = {}; for _, id in ipairs(hs.spaces.windowsForSpace(context.regularSpaceId or 9)) do
        rows[#rows + 1] = { windowId = id, pid = 7, layer = 0 }
      end
      return rows
    end,
    create = function() return { poll = function() return { done = true, results = {} } end, cancel = function() end } end,
  })
end }
local Registry = require("lib.macos.handle_registry")
local Windows = require("lib.macos.windows")

local function ownedCount(host)
  local count = 0; for _ in pairs(host.owned) do count = count + 1 end; return count
end

local function fake()
  local f = { scans = 0, stops = 0, membershipQueries = 0, ownerQueries = 0, focusedWindowQueries = 0, focusRequests = 0, owners = { 9 }, members = { 9 } }
  local function watcher(callback) return { start = function(self) self.callback = callback; if f.failStart == self then error("start failed") end end, stop = function(self) if not self.stopped then self.stopped = true; f.stops = f.stops + 1 end end } end
  -- Installed Hammerspoon 1.1.1: docs.json describes hs.uielement:newWatcher,
  -- but axuielement.windowElement(window) is a different userdata with no watcher.
  local element = { asHSWindow = function() return f.window end, attributeValue = function(_, key) return key == "AXModal" and false end, isAttributeSettable = function() return true end }
  local function windowWatcher(callback) f.windowWatcher = watcher(callback); return f.windowWatcher end
  local app = { isHidden = function() return false end, pid = function() return 7 end, name = function() return "App" end, bundleID = function() return "app" end, focusedWindow = function() return f.window end, allWindows = function() f.scans = f.scans + 1; return { f.window } end, newWatcher = function(_, callback) local w = watcher(callback); f.appWatchers[#f.appWatchers + 1] = w; return w end }
  f.appWatchers = {}
  f.actual = { x = 0, y = 0, w = 10, h = 10 }
  f.window = { isMinimized = function() return false end, id = function() return 9 end, title = function() return "Title" end, application = function() return app end, role = function() return "AXWindow" end, subrole = function() return "AXStandardWindow" end, isFullScreen = function() return f.fullscreen end, newWatcher = function(_, callback) return windowWatcher(callback) end, frame = function() f.frameReads = (f.frameReads or 0) + 1; return f.actual end, setFrame = function(_, frame, duration) f.duration = duration; f.writes = (f.writes or 0) + 1; f.actual = frame end, focus = function() f.focusRequests = f.focusRequests + 1 end }
  f.hs = { processInfo = { processID = 1 }, window = { focusedWindow = function() f.focusedWindowQueries = f.focusedWindowQueries + 1; if f.focusedWindowError then error("focused-window read failed") end; return f.focusedWindow end }, axuielement = { windowElement = function() return element end }, spaces = { windowsForSpace = function() f.membershipQueries = f.membershipQueries + 1; return f.members end, windowSpaces = function() f.ownerQueries = f.ownerQueries + 1; return f.owners end, spaceType = function() return f.spaceType or "user" end }, application = { runningApplications = function() return { app } end, watcher = { new = function(callback) f.lifecycle = watcher(callback); return f.lifecycle end, terminated = 3, hidden = 4, unhidden = 5, launched = 2, activated = 5 } } }
  f.hs.spaces.allSpaces = function() return { d = { 9 } } end
  return f, app, element
end
local function readinessFixture()
  local f, app, element = fake()
  f.members, f.owners = {}, {}
  local timers, events = {}, {}
  f.hs.timer = { doAfter = function(delay, callback)
    assert(delay == 0.1)
    local timer = { callback = callback, stop = function(self) self.stopped = true end }
    timers[#timers + 1] = timer; return timer
  end }
  local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
  host:subscribeApplications(function(event) events[#events + 1] = event end)
  host:subscribeExistingWindows(function(event) events[#events + 1] = event; return true end)
  local function create(window) f.appWatchers[1].callback(window or f.window, "AXWindowCreated") end
  return f, host, timers, events, create, app, element
end

local function discoveryFixture()
  local f, app = fake(); f.window.isFullScreen = function() return false end
  local b = {}; for key, value in pairs(f.window) do b[key] = value end
  b.id = function() return 10 end
  f.hs.spaces.allSpaces = function() return { d = { 9, 11 } } end
  f.hs.spaces.windowsForSpace = function(space) return space == 9 and { 9 } or { 10 } end
  f.hs.spaces.windowSpaces = function(id) return { id == 9 and 9 or 11 } end
  local timers, events, job = {}, {}, { done = false, cancelled = false }
  f.hs.timer = { absoluteTime = function() return (f.clock or 0) * 1e9 end,
    doAfter = function(_, callback)
      local timer = { callback = callback, stop = function(self) self.stopped = true end }
      timers[#timers + 1] = timer; return timer
    end }
  function job:poll() return { done = self.done, results = self.results } end
  function job:cancel() self.cancelled = true end
  local factory = { inventory = function() return { { windowId = 9, pid = 7, layer = 0 },
    { windowId = 10, pid = 7, layer = 8 } } end,
    create = function(targets) assert(#targets == 1 and targets[1].windowId == 10); return job end }
  local host = NativeHost.new(f.hs, { displayId = "d", regularSpaceId = 9 }, nil, nil, nil, factory):start()
  host:subscribeApplications(function() end)
  local function callback(event) events[#events + 1] = event; if f.reject then error("sink failed") end; return f.disposition end
  local function complete()
    job.done = true; job.results = { { pid = 7, windowId = 10, ax = { asHSWindow = function() return b end } } }
    timers[#timers].callback()
  end
  return f, host, job, events, timers, complete, b, callback
end

return {
  ["DISC-001 CHOOSE-002: finite startup admits inactive regular resource without focus or repeated enumeration"] = function()
    local f, host, job, events, _, complete, _, callback = discoveryFixture()
    host:subscribeExistingWindows(callback)
    assert(host:discoveryStatus().pending and #events == 1)
    complete()
    assert(host:discoveryStatus().complete and events[2].metadata.spaceId == 11)
    assert(events[2].metadata.origin == "bootstrap" and f.focusRequests == 0 and f.scans == 1)
    assert(f.focusedWindowQueries == 1 and job.cancelled)
    local status = host:discoveryStatus(); status.complete = false; assert(host:discoveryStatus().complete)
    host:stop()
  end,
  ["DISC-001: terminal exclusion settles while unknown ownership and sink failures remain incomplete"] = function()
    for _, mode in ipairs({ "exclude", "owner", "sink", "poll", "timer", "deadline" }) do
      local f, host, job, _, timers, complete, _, callback = discoveryFixture()
      host:subscribeExistingWindows(callback)
      if mode == "exclude" then f.disposition = "excluded"
      elseif mode == "owner" then f.hs.spaces.windowSpaces = function() return nil end
      elseif mode == "sink" then f.reject = true
      elseif mode == "poll" then job.poll = function() error("poll failed") end
      elseif mode == "timer" then f.hs.timer.doAfter = function() error("allocation failed") end
      elseif mode == "deadline" then f.clock = 2 end
      if mode == "timer" then timers[#timers].callback() else complete() end
      local status = host:discoveryStatus()
      assert(not status.pending and status.complete == (mode == "exclude"), mode)
      assert(job.cancelled and f.focusRequests == 0)
      host:stop()
    end
  end,
  ["DISC-001: finite job prioritizes normal level without discarding higher-level candidates"] = function()
    local f, host, _, _, _, _, _, callback = discoveryFixture()
    f.hs.spaces.windowsForSpace = function() return { 10, 12, 13, 14 } end
    host.nativeDiscovery.inventory = function() return {
      { windowId = 10, pid = 3, layer = 8 },
      { windowId = 14, pid = 7, layer = 0 },
      { windowId = 13, pid = 4, layer = 0 },
      { windowId = 12, pid = 7, layer = 0 },
    } end
    local submitted
    host.nativeDiscovery.create = function(targets)
      submitted = targets
      return { poll = function() return { done = true, results = {} } end, cancel = function() end }
    end
    host:subscribeExistingWindows(callback)
    assert(#submitted == 4 and submitted[1].windowId == 13 and submitted[2].windowId == 12)
    assert(submitted[3].windowId == 14 and submitted[4].windowId == 10)
    assert(not host:discoveryStatus().complete and host:discoveryStatus().unresolvedCount == 4)
    host:stop()
  end,
  ["DISC-001 LIFE-004: allocation reentry cancels returned stale job before installation"] = function()
    local f, host, job, events, _, _, _, callback = discoveryFixture()
    local factory = host.nativeDiscovery
    factory.create = function()
      host:stop(); host:start()
      return job
    end
    host:subscribeExistingWindows(callback)
    assert(job.cancelled and #events == 1 and not host:discoveryStatus().pending)
    assert(not host:discoveryStatus().complete and f.focusRequests == 0)
    host:stop()
  end,
  ["DISC-001: unknown Space type is explicitly incomplete, not an empty success"] = function()
    local f, host, _, events, _, _, _, callback = discoveryFixture()
    f.hs.spaces.spaceType = function() return nil end
    host:subscribeExistingWindows(callback)
    local status = host:discoveryStatus()
    assert(not status.pending and not status.complete and status.reason == "ownership-unavailable")
    assert(#events == 0 and f.focusRequests == 0)
    host:stop()
  end,
  ["DISC-001 LIFE-004: reentrant stop and restart cannot finish or cancel a replacement job"] = function()
    local f, host, job, _, _, complete, _, callback = discoveryFixture()
    host:subscribeExistingWindows(function(event)
      if event.metadata.id == 10 then host:stop(); host:start() end
      return callback(event)
    end)
    complete()
    assert(not host:discoveryStatus().complete and job.cancelled and f.focusRequests == 0)
    host:stop()
  end,
  ["DISC-001 LIFE-004: stale app resource ID reuse and stop reject late discovery publication"] = function()
    for _, mode in ipairs({ "stop", "terminate", "reuse" }) do
      local f, host, job, events, _, complete, b, callback = discoveryFixture()
      host:subscribeExistingWindows(callback)
      if mode == "stop" then host:stop()
      elseif mode == "terminate" then f.lifecycle.callback(nil, 3, f.window:application()); host:releaseApplication(7, host.appResources[7].lease)
      else b.id = function() return 999 end end
      complete()
      assert(#events == 1 and not host:discoveryStatus().complete and f.focusRequests == 0)
      if mode == "stop" then assert(job.cancelled) end
      host:stop()
    end
  end,
  ["LIFE-004: stop during multi-application bootstrap cannot attach later applications or leak returned watcher"] = function()
    local f, app = fake()
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local secondCalls, returnedStopped = 0, false
    local second = { pid = function() return 8 end, newWatcher = function() secondCalls = secondCalls + 1 end }
    f.hs.application.runningApplications = function() return { app, second } end
    app.newWatcher = function()
      host:stop()
      return { start = function() error("stopped watcher must not start") end, stop = function() returnedStopped = true end }
    end
    host:subscribeExistingWindows(function() error("stopped bootstrap must not publish") end)
    assert(returnedStopped and secondCalls == 0 and not next(host.owned) and not next(host.handles))
  end,
  ["LIFE-004: async setup faults reentry and mailbox faults clean exact resources"] = function()
    for _,phase in ipairs({'create','set','timer','poll','stopTimer'})do
      local f=fake();f.window.isFullScreen=function()return false end
      local host,cb,stopped,cleared= nil,nil,0,0
      local worker={stop=function()stopped=stopped+1 end,set=function(_,element)
        if not element then cleared=cleared+1 elseif phase=='set' then host:stop()end
      end,poll=function()if phase=='poll'then error('private')end;return {}end}
      f.hs.timer={doEvery=function(_,callback)
        cb=callback
        if phase=='timer'then host:stop()end
        return {stop=function()if phase=='stopTimer'then error('private')end end}
      end}
      host=Host.new(f.hs,{displayId='d',regularSpaceId=9},nil,nil,{create=function()
        if phase=='create'then host:stop()end;return worker
      end}):start()
      host:subscribeExistingWindows(function()end);host:subscribeWindow(f.window,function()end); host:enableManaged(9, host.handles[9].lease)
      host.windowCallback=function()end;f.focusedWindow=f.window;host:observeFocus()
      if phase=='poll'then cb();assert(host.validityError=='mailbox_poll_failed');cb()end
      host:stop();assert(stopped==1 and not host.validityTarget and not host.validityTimer)
      if phase=='stopTimer'then assert(host.validityError=='mailbox_stop_failed' and cleared>0)end
    end
  end,
  ["WIN-005 FOCUS-004: focused asynchronous invalidity removes exact lease without native callback"] = function()
    local f, app = fake(); f.window.isFullScreen = function() return false end
    local callback, rows, stops, sets = nil, {}, 0, 0
    f.hs.timer = { doEvery = function(delay, cb)
      assert(delay == 0.05); callback = cb
      return { stop = function() end }
    end }
    local worker = { set = function(_, _, token) sets = sets + 1; assert(type(token) == "number") end,
      poll = function() return rows end, stop = function() stops = stops + 1 end }
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }, nil, nil,
      { create = function() return worker end }):start()
    local events = {}
    host:subscribeExistingWindows(function() end)
    host:subscribeWindow(f.window, function() end)
    host:enableManaged(9, host.handles[9].lease)
    host.windowCallback = function(e)
      events[#events + 1] = e
      if e.kind == "destroyed" then host:releaseWindow(e.id, e.resource) end
    end
    f.focusedWindow = f.window; host:observeFocus()
    assert(callback and sets == 1)
    host:observeFocus(); assert(sets == 1)
    local target = host.validityTarget
    rows = {{ token = target.token, status = "unknown", error = -25204 }}; callback()
    assert(host.handles[9])
    rows = {{ token = target.token + 1, status = "invalid", error = -25202 }}; callback()
    assert(host.handles[9])
    rows = {{ token = target.token, status = "invalid", error = -25202 }}
    f.hs.axuielement.windowElement(f.window).isValid = function() return false end
    callback()
    assert(not host.handles[9] and events[#events].kind == "destroyed" and events[#events].resource == target.lease)
    assert(stops == 0); callback(); host:stop(); assert(stops == 1)
  end,
  ["STATE-004 WIN-004 LIFE-004: locked session invalidity retains membership and stale mailbox invalidity is reconfirmed after unlock"] = function()
    local f, app, element = fake(); f.window.isFullScreen = function() return false end
    local locked, valid, callback, rows = false, true, nil, {}
    f.hs.caffeinate = { sessionProperties = function() return { CGSSessionScreenIsLocked = locked, kCGSSessionOnConsoleKey = true } end }
    element.isValid = function() return valid end
    f.hs.timer = { doEvery = function(_, cb) callback = cb; return { stop = function() end } end }
    local worker = { set = function() end, poll = function() return rows end, stop = function() end }
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }, nil, nil, { create = function() return worker end }):start()
    host:subscribeExistingWindows(function() end);host:subscribeWindow(f.window, function() end)
    host:enableManaged(9, host.handles[9].lease)
    local destroyed = 0
    host.windowCallback = function(event) if event.kind == "destroyed" then destroyed = destroyed + 1 end end
    f.focusedWindow = f.window;host:observeFocus()
    local token = host.validityTarget.token
    locked, valid = true, false
    rows = {{ token = token, status = "invalid", error = -25202 }}
    callback();host:observeFocus()
    assert(destroyed == 0 and host.handles[9])
    locked, valid = false, true
    callback() -- queued lock-era result delivered after unlock
    assert(destroyed == 0 and host.handles[9])
    valid = false;callback()
    assert(destroyed == 1, "real unlocked destruction must still retire")
    host:stop()
  end,

  ["LIFE-004 FOCUS-004: mailbox rejects reentrant focus scope lease stop and unavailable targets"] = function()
    for _,mode in ipairs({ "focus", "scope", "lease", "stop", "minimized", "hidden", "fullscreen" }) do
      local f, app = fake(); f.window.isFullScreen = function() return false end
      local cb, host, token
      f.hs.timer = { doEvery = function(_, callback) cb = callback; return { stop = function() end } end }
      local worker = { set = function(_, _, value) token = value end, stop = function() end,
        poll = function()
          if mode == "focus" then host.presentationWindow = nil
          elseif mode == "scope" then host:setContext({ displayId = "d", regularSpaceId = 10 })
          elseif mode == "lease" then host.handles[9].lease = 999
          elseif mode == "stop" then host:stop() end
          return {{token=token,status="invalid",error=-25202}}
        end }
      host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }, nil, nil, {create=function()return worker end}):start()
      host:subscribeExistingWindows(function() end); host:subscribeWindow(f.window,function()end); host:enableManaged(9, host.handles[9].lease)
      local destroyed = 0; host.windowCallback = function(e) if e.kind == "destroyed" then destroyed = destroyed + 1 end end
      f.focusedWindow = f.window
      if mode == "minimized" then f.window.isMinimized=function()return true end
      elseif mode == "hidden" then app.isHidden=function()return true end
      elseif mode == "fullscreen" then f.window.isFullScreen=function()return true end end
      host:observeFocus()
      if mode == "minimized" or mode == "hidden" or mode == "fullscreen" then assert(not cb)
      else assert(cb); cb() end
      assert(destroyed == 0); host:stop()
    end
  end,
  ["DISC-002: repeated same-scope refresh preserves exact timer and three-attempt budget"] = function()
    local f, host, timers, events, create = readinessFixture()
    create(); local token = host.readiness[9]
    for i = 1, 4 do host:setContext({ displayId = "d", regularSpaceId = 9, workArea = { w = i } }) end
    assert(host.readiness[9] == token and token.timer == timers[1] and token.attempts == 1)
    timers[1].callback()
    host:setContext({ displayId = "d", regularSpaceId = 9 })
    timers[1].callback(); assert(f.ownerQueries == 2 and token.timer == timers[2])
    timers[2].callback(); assert(f.ownerQueries == 3 and #timers == 2 and not host.readiness[9])
    host:stop()
  end,
  ["DISC-002: scope changes during ownership query cancel even after same-scope refresh"] = function()
    for _, context in ipairs({ { displayId = "other", regularSpaceId = 9 },
        { displayId = "d", regularSpaceId = 10 },
        { displayId = "d", regularSpaceId = nil, spaceType = "fullscreen" } }) do
      local f, host, timers, events, create = readinessFixture()
      create(); host:setContext({ displayId = "d", regularSpaceId = 9 })
      f.hs.spaces.windowSpaces = function() host:setContext(context); return { 9 } end
      timers[1].callback(); assert(#events == 0 and not host.readiness[9] and #timers == 1)
      host:stop()
    end
  end,
  ["DISC-002 LIFE-004: actual Host Windows subscription rejection settles creation"] = function()
    local f = fake(); f.members, f.owners = {}, {}
    local timers = {}
    f.hs.timer = { doAfter = function(_, callback)
      local timer = { callback = callback, stop = function() end }; timers[#timers + 1] = timer; return timer
    end }
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local emitted = 0
    local windows = Windows.new({ sink = function() emitted = emitted + 1; return true end, native = {
      subscribeApplications = function(cb) return host:subscribeApplications(cb) end,
      subscribeExistingWindows = function(cb) return host:subscribeExistingWindows(cb) end,
      subscribeWindow = function(w, cb) return host:subscribeWindow(w, cb) end,
      probeReadiness = function(id, cb) return host:probeReadiness(id, cb) end,
      releaseWindow = function(id, lease) return host:releaseWindow(id, lease) end,
      releaseApplication = function(pid, lease) return host:releaseApplication(pid, lease) end,
      decide = function(event) return event.decision end,
    } }):start()
    f.appWatchers[1].callback(f.window, "AXWindowCreated")
    f.window.newWatcher = function() return nil end
    f.owners = { 9 }; timers[1].callback()
    assert(emitted == 0 and not windows:handleForId(9) and host.handles[9])
    assert(not host.readiness[9] and #timers == 1)
    timers[1].callback(); assert(#timers == 1)
    windows:stop(); host:stop()
  end,
  ["DISC-002 LIFE-004: readiness exceptions clean token and preserve exact error"] = function()
    for _, phase in ipairs({ "initial", "retry", "timer" }) do
      local f, host, timers, events, create = readinessFixture()
      local marker = {}
      local original = host._ready
      if phase == "retry" then create() end
      if phase == "timer" then f.hs.timer.doAfter = function() error(marker) end
      else host._ready = function() error(marker) end end
      local ok, err = pcall(function() if phase == "retry" then timers[1].callback() else create() end end)
      assert(not ok and err == marker)
      assert(not host.readiness[9], "exception must not strand creation token")
      host._ready = original; host:stop()
    end
  end,
  ["DISC-002: stale first timer cannot consume pending second attempt"] = function()
    local f, host, timers, events, create = readinessFixture()
    create(); timers[1].callback()
    assert(f.ownerQueries == 2 and #timers == 2)
    timers[1].callback()
    assert(f.ownerQueries == 2 and host.readiness[9], "replayed timer must not steal final attempt")
    f.owners = { 9 }; timers[2].callback(); assert(#events == 1)
    host:stop()
  end,
  ["DISC-002: launch origin upgrades on creation without budget reset"] = function()
    local f, host, timers, events, create = readinessFixture()
    f.lifecycle.callback(nil, f.hs.application.watcher.launched, f.window:application())
    create(); assert(f.ownerQueries == 1 and #timers == 1)
    f.owners = { 9 }; timers[1].callback()
    assert(events[1].metadata.origin == "created", "AX creation must upgrade launch origin")
    host:stop()
  end,
  ["LIFE-004: final validity reentry cannot publish stale handle app or generation"] = function()
    for _, mode in ipairs({ "handle", "app", "restart" }) do
      local f, host, timers, events, create, app, element = readinessFixture()
      local remember = host._remember
      local armed = false
      host._remember = function(self, window)
        local result = remember(self, window); armed = true; return result
      end
      element.isValid = function()
        if armed then
          armed = false
          if mode == "handle" then host.handles[9] = { handle = {}, lease = 999, active = true }
          elseif mode == "app" then host.appResources[7] = { app = {}, lease = 999, active = true }
          else host:stop(); host:start() end
        end
        return true
      end
      f.owners = { 9 }; create()
      assert(#events == 0, "final native reentry must invalidate publication")
      host:stop()
    end
  end,
  ["DISC-002: creation unknown exhaustion coalesces duplicates and never infers death"] = function()
    local f, host, timers, events, create = readinessFixture()
    create(); create()
    f.lifecycle.callback(nil, f.hs.application.watcher.launched, f.window:application())
    assert(f.ownerQueries == 1 and #timers == 1)
    timers[1].callback(); timers[2].callback()
    assert(f.ownerQueries == 3 and #timers == 2 and #events == 0 and not host.readiness[9])
    timers[1].callback(); timers[2].callback(); assert(f.ownerQueries == 3)
    host:stop()
  end,
  ["DISC-002: lifecycle and Rules unknown metadata recover by positive creation readiness"] = function()
    for _, field in ipairs({ "minimized", "movable" }) do
      local f, host, timers, events, create, app, element = readinessFixture()
      f.owners = { 9 }
      if field == "minimized" then f.window.isMinimized = function() return nil end
      else element.isAttributeSettable = function() return nil end end
      host.windowCallback = function(event)
        local normalized = assert(require("lib.rules").ready(event.metadata))
        if normalized.decision.action == "defer" then return "uncertain" end
        events[#events + 1] = event; return true
      end
      host:_creationReady(f.window, "created", host.windowCallback); assert(#events == 0 and #timers == 1)
      f.window.isMinimized = function() return false end
      element.isAttributeSettable = function() return true end
      timers[1].callback()
      assert(#events == 1 and events[1].kind == "ready" and f.ownerQueries == 2 and not host.readiness[9])
      timers[1].callback(); assert(#events == 1 and f.ownerQueries == 2)
      host:stop()
    end
  end,
  ["DISC-002 FOCUS-004: focus and bootstrap never schedule creation readiness"] = function()
    local f, host, timers = readinessFixture()
    f.focusedWindow = f.window; host:observeFocus()
    host:probeReadiness(9, function() end)
    assert(#timers == 0)
    host:stop()
  end,
  ["DISC-002: exclusion and rejected sink settle without retry"] = function()
    for _, mode in ipairs({ "exclude", "sink" }) do
      local f, host, timers, events, create, app, element = readinessFixture()
      f.owners = { 9 }
      if mode == "exclude" then element.attributeValue = function() return true end
      else host.windowCallback = function() return false end end
      host:_creationReady(f.window, "created", host.windowCallback)
      assert(#timers == 0 and not host.readiness[9])
      host:stop()
    end
  end,
  ["LIFE-004 DISC-002: creation cancellation rejects queued context stop app termination and superseded resources"] = function()
    for _, mode in ipairs({ "context", "stop", "releaseApp", "terminate", "supersede" }) do
      local f, host, timers, events, create, app = readinessFixture()
      create(); local old = timers[1]
      if mode == "context" then host:setContext({ displayId = "d", regularSpaceId = 10 })
      elseif mode == "stop" then host:stop()
      elseif mode == "releaseApp" then host:releaseApplication(7, host.appResources[7].lease)
      elseif mode == "terminate" then f.lifecycle.callback(nil, f.hs.application.watcher.terminated, app)
      else
        local other = {}; for k, v in pairs(f.window) do other[k] = v end
        create(other)
      end
      local queries, count = f.ownerQueries, #events
      f.owners = { 9 }; old.callback()
      assert(f.ownerQueries == queries and #events == count and old.stopped)
      if mode == "supersede" then
        timers[2].callback(); assert(events[#events].handle ~= f.window)
      end
      host:stop()
    end
  end,
  ["LIFE-004 DISC-002: explicit candidate invalidity cancels without snapshot death"] = function()
    local f, host, timers, events, create, app, element = readinessFixture()
    create(); element.isValid = function() return false end
    f.owners = { 9 }; timers[1].callback()
    assert(f.ownerQueries == 1 and #events == 0 and #timers == 1 and not host.readiness[9])
    host:stop()
  end,
  ["LIFE-004 DISC-002: readiness settles before sink reentry and subscription rejection never retries"] = function()
    local f, host, timers, events, create = readinessFixture()
    create(); f.owners = { 9 }
    host.windowCallback = function()
      assert(host.readiness[9], "candidate retains bounded identity through normalization")
      host:setContext({ displayId = "d", regularSpaceId = 10 })
      return false
    end
    -- A real scope transition cancels the old callback; geometry-only refresh
    -- now deliberately preserves it. Exercise a fresh token for sink reentry.
    host:setContext({ displayId = "d", regularSpaceId = 10 })
    host:setContext({ displayId = "d", regularSpaceId = 9 })
    host:_creationReady(f.window, "created", host.windowCallback)
    assert(#timers == 1 and not host.readiness[9])
    local queries = f.ownerQueries; timers[1].callback(); assert(f.ownerQueries == queries)
    host:stop()
  end,
  ["LIFE-004 DISC-002: reentrant query cancellation cannot publish or schedule"] = function()
    local f, host, timers, events, create = readinessFixture()
    f.hs.spaces.windowSpaces = function()
      f.ownerQueries = f.ownerQueries + 1
      host:setContext({ displayId = "d", regularSpaceId = 10 })
      return { 9 }
    end
    create(); assert(#events == 0 and #timers == 0 and not host.readiness[9])
    host:stop()
  end,
  ["DISC-002 FOCUS-004 LIFE-004: created unknown owner plus unknown focus probe recovers only by bounded positive readiness"] = function()
    local f = fake()
    f.members, f.owners = {}, {}
    local timers, admitted, destroyed = {}, 0, 0
    f.hs.timer = { doAfter = function(delay, callback)
      assert(delay == 0.1, "creation readiness must use the existing 100ms timer seam")
      local timer = { callback = callback, stop = function(self) self.stopped = true end }
      timers[#timers + 1] = timer; return timer
    end }
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local windows = Windows.new({ sink = function(event)
      if event.type == "WindowReady" and event.decision.action == "manage" then admitted = admitted + 1 end
      if event.type == "WindowDestroyed" then destroyed = destroyed + 1 end
      return true
    end, native = {
      subscribeApplications = function(callback) return host:subscribeApplications(callback) end,
      subscribeExistingWindows = function(callback) return host:subscribeExistingWindows(callback) end,
      subscribeWindow = function(handle, callback) return host:subscribeWindow(handle, callback) end,
      probeReadiness = function(id, callback) return host:probeReadiness(id, callback) end,
      releaseWindow = function(id, lease) return host:releaseWindow(id, lease) end,
      releaseApplication = function(pid, lease) return host:releaseApplication(pid, lease) end,
      decide = function(event) return event.decision end,
    } }):start()
    -- Empty bootstrap is not death evidence. App observer is already attached.
    local before = f.ownerQueries
    f.appWatchers[1].callback(f.window, "AXWindowCreated")
    f.focusedWindow = f.window; host:observeFocus()
    assert(f.ownerQueries == before + 2, "creation and focus must independently read unknown ownership")
    assert(admitted == 0 and not windows:handleForId(9), "focus cannot admit an unknown owner")
    -- No further app/window/focus event: only the creation-scoped readiness timer.
    assert(#timers == 1, "unknown creation must schedule bounded readiness rather than stay unmanaged")
    timers[1].callback()
    assert(admitted == 0 and destroyed == 0 and not windows:handleForId(9), "unknown retry is neither admission nor death")
    assert(#timers == 2, "three attempts total: initial creation plus two 100ms retries")
    f.owners = { 9 }
    timers[2].callback()
    assert(admitted == 1 and windows:handleForId(9) == f.window, "positive native ownership must admit without another event")
    assert(f.ownerQueries == before + 4 and #timers == 2 and destroyed == 0)
    -- Completed callbacks must be inert even if the timer queue redelivers.
    local queries = f.ownerQueries
    timers[2].callback()
    assert(admitted == 1 and f.ownerQueries == queries, "completed attempt must lose currentness")
    windows:stop(); host:stop()
    timers[1].callback(); timers[2].callback()
    assert(admitted == 1 and f.ownerQueries == queries, "stopped generation cannot retry")
  end,
  ["WIN-005 FOCUS-005: direct retained focus rejects explicitly invalid resource before native request"] = function()
    local f, app, element = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    host:subscribeExistingWindows(function() end); host:subscribeWindow(f.window, function() end); host:enableManaged(9, host.handles[9].lease)
    host.windowCallback = function(event) if event.kind == "destroyed" then host:releaseWindow(event.id, event.resource) end end
    element.isValid = function() return false end
    assert(host:focus(f.window) == nil and f.focusRequests == 0 and not host.handles[9])
    host:stop()
  end,
  ["DISC-002 STATE-008: unknown native lifecycle defers readiness without admitting available state"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local events = {}
    f.window.isMinimized = function() return nil end
    host:subscribeExistingWindows(function(e) events[#events + 1] = e end)
    assert(#events == 0 and not host.handles[9])
    f.window.isMinimized = function() return false end
    app.isHidden = function() return nil end
    host:_ready(f.window, "created", function(e) events[#events + 1] = e end)
    assert(#events == 0 and not host.handles[9])
    host:stop()
  end,
  ["WIN-005 LIFE-004: app focus event removes invalid retained member even after presentation moved elsewhere"] = function()
    local f, app, element = fake()
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local events = {}
    host:subscribeExistingWindows(function() end)
    host:subscribeWindow(f.window, function() end)
    host:enableManaged(9, host.handles[9].lease)
    host.windowCallback = function(event)
      events[#events + 1] = event
      if event.kind == "destroyed" then host:releaseWindow(event.id, event.resource) end
    end
    -- No prior presentation points to this member: a previous focus callback
    -- already selected a different app, but this app now signals a close/focus.
    element.isValid = function() return false end
    f.appWatchers[1].callback(nil, "AXFocusedWindowChanged")
    assert(events[1].kind == "destroyed" and not host.handles[9])
    host:stop()
  end,
  ["WIN-005 FOCUS-004: focus boundary removes only explicitly invalid exact prior managed resource before fallback focus"] = function()
    local f, app, element = fake()
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local events = {}
    host:subscribeExistingWindows(function() end)
    host:subscribeWindow(f.window, function() end)
    host:enableManaged(9, host.handles[9].lease)
    host.windowCallback = function(event)
      events[#events + 1] = event
      if event.kind == "destroyed" then host:releaseWindow(event.id, event.resource) end
    end
    f.focusedWindow = f.window; host:observeFocus()
    for _, shape in ipairs({ "valid", "uncertain", "error" }) do
      element.isValid = function()
        if shape == "error" then error("AX unavailable") end
        if shape == "valid" then return true end
        return nil
      end
      local before = #events; host:observeFocus()
      assert(#events == before + 1 and events[#events].kind == "focus" and host.handles[9])
    end
    element.isValid = function() return false end
    f.focusedWindow = nil
    local before = #events; host:observeFocus()
    assert(events[before + 1].kind == "destroyed" and events[before + 2].kind == "focus")
    assert(not host.handles[9])
    host:stop()
  end,
  ["PERF-001 DISC-001: activation hint readiness retries are bounded and stale after context change or stop"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local timers, hints = {}, 0
    f.hs.timer = { doAfter = function(_, callback)
      local timer = { callback = callback, stop = function(self) self.stopped = true end }
      timers[#timers + 1] = timer; return timer
    end }
    f.hs.window.list = function() hints = hints + 1; return {} end
    f.hs.application.applicationForPID = function() return app end
    host:subscribeExistingWindows(function() end, false)
    assert(#timers == 1)
    timers[1].callback(); timers[2].callback()
    assert(#timers == 2 and hints == 3 and not host.discoveryTimer)
    host:subscribeExistingWindows(function() end, false)
    local old = timers[3]; host:setContext({ regularSpaceId = 10 })
    local before = hints; old.callback(); assert(hints == before and old.stopped)
    host:subscribeExistingWindows(function() end, false)
    old = timers[4]; host:stop(); before = hints; old.callback()
    assert(hints == before and old.stopped)
  end,
  ["DISC-001 DISC-002 PERF-001: same-desktop context refresh preserves entry retry and discovers delayed windows"] = function()
    local f, app = fake()
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local timers, events, exposed = {}, {}, false
    f.hs.timer = { doAfter = function(_, callback)
      local timer = { callback = callback, stop = function(self) self.stopped = true end }
      timers[#timers + 1] = timer; return timer
    end }
    f.hs.window.list = function() return exposed and { { kCGWindowNumber = 9, kCGWindowOwnerPID = 7 } } or {} end
    f.hs.application.applicationForPID = function() return app end
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end, false)
    assert(#timers == 1 and #events == 0)
    for i = 1, 3 do host:setContext({ displayId = "d", regularSpaceId = 9, workArea = { w = i } }) end
    assert(host.discoveryTimer == timers[1] and not timers[1].stopped, "same-scope observation canceled delayed discovery")
    exposed = true
    timers[1].callback()
    assert(host.handles[9] and #events == 1 and events[1].kind == "ready")
    assert(not host.discoveryTimer and #timers == 1)
    host:stop()
  end,

  ["PERF-002 DISC-001: activation scans only hinted unknown owners and never all running applications"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local events = {}
    host:subscribeExistingWindows(function(e) events[#events + 1] = e end, true)
    local scans = f.scans
    f.hs.application.runningApplications = function() error("global activation enumeration") end
    f.hs.window.list = function() error("known-only activation must not query owner hints") end
    host:subscribeExistingWindows(function(e) events[#events + 1] = e end, false)
    assert(f.scans == scans)
    local second = {}; for key, value in pairs(f.window) do second[key] = value end
    second.id = function() return 10 end
    f.members = { 9, 10, 11 }
    local unrelated = { allWindows = function() error("unrelated app scan") end }
    f.hs.application.applicationForPID = function(pid) return pid == 7 and app or unrelated end
    f.hs.window.list = function() return { { kCGWindowNumber = 10, kCGWindowOwnerPID = 7 },
      { kCGWindowNumber = 11, kCGWindowOwnerPID = 7 }, { kCGWindowNumber = 999, kCGWindowOwnerPID = 999 } } end
    app.allWindows = function() f.scans = f.scans + 1; return { f.window, second } end
    host:subscribeExistingWindows(function(e) events[#events + 1] = e end, false)
    assert(f.scans == scans + 1 and host.handles[10] and not host.handles[11])
    -- Snapshot absence and missing hints cannot release current resources.
    f.members = {}; host:subscribeExistingWindows(function() end, false)
    assert(host.handles[9] and host.handles[10])
    host:stop()
  end,
  ["BAR-004 FOCUS-003: focused unmanaged title observation never admits and is released on focus clear"] = function()
    local f = fake(); local title = "Popup"; local unmanagedWatcher
    local unmanaged = { id = function() return 10 end, title = function() return title end,
      application = function() return f.window:application() end, isFullScreen = function() return false end,
      newWatcher = function(_, callback) unmanagedWatcher = { callback = callback, start = function() end,
        stop = function(self) self.stopped = true end }; return unmanagedWatcher end }
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = "regular" }):start(); local events, terminated = {}, nil
    host.windowCallback = function(event) events[#events + 1] = event end
    host:subscribeApplications(function(event) terminated = event end)
    -- Runtime start always attaches application resources through the normal
    -- full discovery path before a later termination is authoritative.
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    f.focusedWindow = unmanaged; assert(host:observeFocus())
    assert(events[#events].id == 10)
    title = "Renamed"; unmanagedWatcher.callback(nil, "AXTitleChanged")
    assert(events[#events].kind == "titleChanged" and events[#events].title == "Renamed")
    local secondWatcher; local second = { id = function() return 11 end, title = function() return "Other popup" end,
      application = function() return f.window:application() end, isFullScreen = function() return false end,
      newWatcher = function(_, callback) secondWatcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return secondWatcher end }
    f.focusedWindow = second; assert(host:observeFocus() and unmanagedWatcher.stopped)
    f.focusedWindow = unmanaged; assert(host:observeFocus() and secondWatcher.stopped)
    title = "Back again"; unmanagedWatcher.callback(nil, "AXTitleChanged")
    assert(events[#events].kind == "titleChanged" and events[#events].title == "Back again")
    f.lifecycle.callback(nil, 3, f.window:application())
    assert(terminated.kind == "terminated" and unmanagedWatcher.stopped)
    f.focusedWindow = nil; assert(host:observeFocus())
    assert(events[#events].kind == "focus" and events[#events].id == nil)
    local count = #events; unmanagedWatcher.callback(nil, "AXTitleChanged")
    assert(#events == count, "detached presentation callback is stale")
    host:stop()
  end,
  ["BAR-004: failed optional unmanaged title observer preserves actual focus"] = function()
    local f = fake(); local transient = { id = function() return 10 end, title = function() return "Popup" end,
      application = function() return f.window:application() end, isFullScreen = function() return false end,
      newWatcher = function() error("unsupported transient watcher") end }
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = "regular" }):start(); local events = {}
    host.windowCallback = function(event) events[#events + 1] = event end
    f.focusedWindow = transient
    assert(host:observeFocus() and #events == 1 and events[1].id == 10 and events[1].title == "Popup")
    host:stop()
  end,
  ["BAR-004: nil and start-failed optional title observers preserve actual focus"] = function()
    for _, shape in ipairs({ "nil", "start" }) do
      local f = fake(); local stopped = false
      local transient = { id = function() return 10 end, title = function() return "Popup" end,
        application = function() return f.window:application() end, isFullScreen = function() return false end,
        newWatcher = function()
          if shape == "nil" then return nil end
          return { start = function() error("start failed") end, stop = function() stopped = true end }
        end }
      local host = Host.new(f.hs, { displayId = "d", regularSpaceId = "regular" }):start(); local events = {}
      host.windowCallback = function(event) events[#events + 1] = event end; f.focusedWindow = transient
      assert(host:observeFocus() and #events == 1 and events[1].id == 10)
      if shape == "start" then assert(stopped) end
      host:stop()
    end
  end,
  ["BAR-004: nonnil focused object without an ID does not clear actual presentation"] = function()
    local f = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = "regular" }):start(); local events = {}
    host.windowCallback = function(event) events[#events + 1] = event end
    f.focusedWindow = { id = function() return nil end }
    assert(not host:observeFocus() and #events == 0)
    f.focusedWindow = nil; assert(host:observeFocus() and #events == 1 and events[1].id == nil)
    host:stop()
  end,
  ["DISC-002 FS-005: focused native fullscreen readiness has actual ownership and no regular placement"] = function()
    local f = fake(); f.spaceType, f.fullscreen, f.focusedWindow = "fullscreen", true, f.window
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = "regular" }):start()
    local events = {}; host.windowCallback = function(e) events[#events + 1] = e end
    host:observeFocus()
    local metadata
    host:probeReadiness(9, function(m, handle) metadata = m; assert(handle == f.window); return true end)
    assert(metadata and metadata.spaceId == 9 and metadata.spaceType == "fullscreen" and metadata.nativeFullscreen)
    assert(events[#events].kind == "focus" and #events == 2)
    assert(f.scans == 0 and f.membershipQueries == 0 and f.ownerQueries == 1)
    host:stop()
  end,
  ["DISC-001 FS-005: startup on fullscreen discovers confirmed regular windows without focus"] = function()
    local f = fake()
    local host = Host.new(f.hs, { displayId = "d", activeSpaceId = 9, spaceType = "fullscreen" }):start()
    local admitted = 0
    host:subscribeExistingWindows(function() admitted = admitted + 1 end)
    assert(admitted == 1 and f.scans == 1 and f.focusRequests == 0)
    host:stop()
  end,
  ["FS-002: fullscreen exit preserves the false native result and emits one exit observation"] = function()
    local f = fake(); f.fullscreen = true
    local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local events = {}; host:subscribeWindow(f.window, function(e) events[#events + 1] = e end)
    f.fullscreen = false; f.windowWatcher.callback(nil, "AXWindowResized")
    f.windowWatcher.callback(nil, "AXWindowResized")
    assert(#events == 1 and events[1].kind == "exitedNativeFullscreen")
    host:stop()
  end,
  ["host bootstrap uses one active-Space snapshot and one app scan, deferring absent handles"] = function()
    local f, _, element = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:subscribeExistingWindows(function(e) events[#events + 1] = e end)
    assert(f.membershipQueries == 2 and f.scans == 1 and events[1].metadata.origin == "bootstrap")
    f.members = {}; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 2 and f.ownerQueries == 2)
    f.owners = { 99 }; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 3 and events[3].metadata.spaceId == 99)
    f.owners = { 9, 10 }; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 3)
    f.owners = { 9 }; f.spaceType = "fullscreen"; f.appWatchers[1].callback(f.window, "AXWindowCreated"); assert(#events == 3)
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
  ["LIFE-001 LIFE-004: Host-to-Windows non-admission and unknown probe release only provisional records"] = function()
    local f, _, element = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    element.attributeValue = function(_, key) return key == "AXModal" and true or false end
    local windows = Windows.new({ sink = function(event) events[#events + 1] = event; return true end, native = {
      subscribeApplications = function(callback) return host:subscribeApplications(callback) end,
      subscribeExistingWindows = function(callback) return host:subscribeExistingWindows(callback) end,
      subscribeWindow = function(handle, callback) return host:subscribeWindow(handle, callback) end,
      probeReadiness = function(id, callback) return host:probeReadiness(id, callback) end,
      releaseWindow = function(id, lease) return host:releaseWindow(id, lease) end,
      releaseApplication = function(pid, lease) return host:releaseApplication(pid, lease) end,
      decide = function(event) return event.decision end,
    } }):start()
    assert(events[1].decision.action == "exclude" and host.handles[9] and not windows:handleForId(9))
    element.attributeValue = function(_, key) return key == "AXModal" and false end
    host:_ready(f.window, "created", host.windowCallback)
    local admitted = host.handles[9]
    assert(admitted and windows:handleForId(9) == f.window)
    f.windowWatcher.callback(nil, "AXUIElementDestroyed")
    assert(not host.handles[9] and not windows:handleForId(9), "managed destruction remains authoritative")

    element.isAttributeSettable = function(_, key) if key == "AXPosition" then return nil end; return true end
    host:_ready(f.window, "created", host.windowCallback)
    assert(host.handles[9] and not windows:handleForId(9), "unknown readiness retains identity without admission")
    element.isAttributeSettable = function() return true end
    local original = f.window.newWatcher; f.window.newWatcher = function() return nil end
    host:_ready(f.window, "created", host.windowCallback)
    assert(host.handles[9] and not windows:handleForId(9), "failed attach retains identity for later readiness")
    f.window.newWatcher = original; host:_ready(f.window, "created", host.windowCallback)
    assert(host.handles[9] and windows:handleForId(9) == f.window, "same ID may retry after provisional cleanup")
    f.windowWatcher.callback(nil, "AXUIElementDestroyed")
    f.owners, f.focusedWindow = {}, f.window; assert(host:observeFocus())
    assert(not host.handles[9] and not windows:handleForId(9), "unknown uncached focus probe releases only its provisional record")
    windows:stop(); host:stop()
  end,
  ["LIFE-001 LIFE-004: failed app/window attachments reject old callbacks and active ownership returns to baseline"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:_acceptApp(app)
    local baseline = ownedCount(host)
    local oldAppCallback, originalAppWatcher = nil, app.newWatcher
    app.newWatcher = function(_, callback)
      oldAppCallback = callback
      return { start = function() error("failed app attach") end, stop = function() f.stops = f.stops + 1 end }
    end
    assert(not pcall(function() host:_attachApp(app, function(event) events[#events + 1] = event end) end))
    app.newWatcher = originalAppWatcher
    host:_attachApp(app, function(event) events[#events + 1] = event end)
    local before = #events; oldAppCallback(f.window, "AXWindowCreated")
    assert(#events == before, "failed app attachment callback must lose currentness on retry")
    f.appWatchers[#f.appWatchers].callback(f.window, "AXWindowCreated")
    assert(#events == before + 1, "current app attachment remains accepted")

    local oldWindowCallback, originalWindowWatcher = nil, f.window.newWatcher
    local windowBaseline = ownedCount(host)
    f.window.newWatcher = function(_, callback)
      oldWindowCallback = callback
      return { start = function() error("failed window attach") end, stop = function() f.stops = f.stops + 1 end }
    end
    assert(not pcall(function() host:subscribeWindow(f.window, function(event) events[#events + 1] = event end) end))
    f.window.newWatcher = originalWindowWatcher
    local subscription = host:subscribeWindow(f.window, function(event) events[#events + 1] = event end)
    before = #events; oldWindowCallback(nil, "AXTitleChanged")
    assert(#events == before, "failed window attachment callback must lose currentness on retry")
    f.windowWatcher.callback(nil, "AXTitleChanged")
    assert(#events == before + 1)
    subscription.detach(); assert(ownedCount(host) == windowBaseline, "detached current watcher must leave active ownership")
    for _ = 1, 3 do
      local churn = host:subscribeWindow(f.window, function() end); host:enableManaged(9, host.handles[9].lease)
      assert(churn); churn.detach()
    end
    assert(ownedCount(host) == windowBaseline, "closed/failed watcher churn cannot retain stopped ownership")
    host:stop(); assert(ownedCount(host) == 0)
  end,
  ["LIFE-001 BAR-004: deferred focused presentation is source-aware and management replaces its title-only watcher"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host.windowCallback = function(event) events[#events + 1] = event end
    host:subscribeApplications(function(event) events[#events + 1] = event end)
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    host:subscribeWindow(f.window, function(event) events[#events + 1] = event end)
    local deferredTitleWatcher, clone = nil, { pid = app.pid, name = app.name, bundleID = app.bundleID, newWatcher = app.newWatcher }
    local deferred = { id = function() return 10 end, title = function() return "Deferred" end, application = function() return clone end,
      isFullScreen = function() return false end, newWatcher = function(_, callback)
        deferredTitleWatcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return deferredTitleWatcher end }
    f.focusedWindow = deferred; assert(host:observeFocus() and host.presentationWindow == deferred)
    f.lifecycle.callback(nil, 3, app)
    assert(not deferredTitleWatcher.stopped, "termination of accepted app A cannot stop deferred same-PID source B")
    local sameIdWatcher
    local sameId = { id = f.window.id, title = function() return "Same ID conflict" end, application = function() return clone end,
      isFullScreen = function() return false end, newWatcher = function(_, callback)
        sameIdWatcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }; return sameIdWatcher end }
    f.focusedWindow = sameId; assert(host:observeFocus() and host.presentationWindow == sameId and deferredTitleWatcher.stopped)
    sameIdWatcher.callback(nil, "AXTitleChanged"); assert(events[#events].presentationResource == host.presentationLease)

    local titleWatchers = {}
    local managed = { id = function() return 11 end, title = function() return "Promote" end, application = function() return app end,
      isFullScreen = function() return false end, newWatcher = function(_, callback)
        local watcher = { callback = callback, start = function() end, stop = function(self) self.stopped = true end }
        titleWatchers[#titleWatchers + 1] = watcher; return watcher end }
    f.focusedWindow = managed; assert(host:observeFocus() and #titleWatchers == 1)
    host:subscribeWindow(managed, function(event) events[#events + 1] = event end)
    assert(titleWatchers[1].stopped and #titleWatchers == 2, "managed watcher replaces title-only observer")
    local before = #events; titleWatchers[1].callback(nil, "AXTitleChanged")
    assert(#events == before, "stopped title-only attachment callback is no longer current")
    host:stop()
  end,
  ["PERF-003 WIN-007: synchronization reads actual frames and corrects drift without redundant writes"] = function()
    local f = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
    local adapter = { handleForId = function() return f.window end }
    local intent = { kind = "frame", windowId = 9, frame = { x = 0, y = 0, w = 10, h = 10 } }
    host:execute(adapter, { intent }); assert(f.frameReads == 1 and not f.writes)
    f.actual = { x = 3, y = 0, w = 10, h = 10 }
    host:execute(adapter, { intent }); assert(f.frameReads == 2 and f.writes == 1)
    host:execute(adapter, { intent }); assert(f.frameReads == 3 and f.writes == 1)
    host:stop()
  end,
  ["LIFE-001: effect execution resolves the matching current window lease"] = function()
    local f = fake(); local registry = Registry.new(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }, nil, registry):start()
    registry:remember(9, 9, f.window, 7, 30, 40)
    local adapter = { handleForId = function() error("unscoped adapter lookup must not run") end }
    host:execute(adapter, { { kind = "frame", windowId = 9, spaceId = 9, lease = 31, frame = { x = 1, y = 0, w = 10, h = 10 } } })
    assert(not f.writes)
    host:execute(adapter, { { kind = "frame", windowId = 9, spaceId = 9, lease = 30, frame = { x = 1, y = 0, w = 10, h = 10 } } })
    assert(f.writes == 1)
    host:stop()
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
  ["STATE-005 LIFE-004: entry app liveness is bounded and rejects reentrant authority changes"] = function()
    for _, mode in ipairs({ "stop", "restart", "context", "record", "callback", "retirement-stop", "retry" }) do
      local f, app = fake()
      local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start()
      local events, queries = {}, 0
      local callback = function(event)
        events[#events + 1] = event
        if mode == "retirement-stop" then host:stop() end
      end
      local subscription = host:subscribeApplications(callback)
      local record = host:_acceptApp(app)
      app.isRunning = function()
        queries = queries + 1
        if mode == "stop" then host:stop()
        elseif mode == "restart" then host:stop():start(); host:subscribeApplications(callback)
        elseif mode == "context" then host:setContext({ displayId = "d", regularSpaceId = 11 })
        elseif mode == "record" then host.appResources[7] = { pid = 7, app = app, active = true, lease = 999 }
        elseif mode == "callback" then host:subscribeApplications(callback); subscription.detach() end
        return false
      end
      f.members = {}
      local before = f.membershipQueries
      host:subscribeExistingWindows(function() error("unexpected readiness") end, false)
      assert(queries == 1)
      assert(#events == ((mode == "retirement-stop" or mode == "retry") and 1 or 0))
      if mode ~= "record" and mode ~= "retry" then assert(f.membershipQueries == before, "stale pass must not continue discovery") end
      if mode == "record" then assert(host.appResources[7].lease == 999 and record.active) end
      if mode == "callback" then assert(host.applicationCallback == callback, "old detach cannot clear replacement owner") end
      if mode == "retry" then
        host:subscribeExistingWindows(function() end, false, 2)
        host:subscribeExistingWindows(function() end, false, 3)
        assert(queries == 1, "activation retries must not repeat app liveness")
      end
      host:stop()
      assert(host.applicationCallback == nil and host.applicationOwner == nil)
    end
  end,
  ["host caches known handles, clears destruction/termination, and owns watchers once"] = function()
    local f, app, element = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:subscribeApplications(function(e) events[#events + 1] = e end); host:subscribeExistingWindows(function(e) events[#events + 1] = e end)
    local subscription = host:subscribeWindow(f.window, function(e) events[#events + 1] = e end)
    host:probeReadiness(9, function(metadata) assert(metadata and metadata.origin == "targetedReadiness") end); local scans = f.scans
    host:probeReadiness(99, function(metadata) assert(metadata == nil) end); assert(f.scans == scans)
    f.windowWatcher.callback(nil, "AXWindowMiniaturized"); f.fullscreen = true; f.windowWatcher.callback(nil, "AXWindowResized"); f.windowWatcher.callback(nil, "AXUIElementDestroyed")
    local destroyed = events[#events]
    assert(destroyed.kind == "destroyed" and host.handles[9], "routing owns the record until it commits")
    host:releaseWindow(9, destroyed.resource)
    host:probeReadiness(9, function(metadata) assert(metadata == nil) end)
    local lifecycleCount, scansBeforeLaunch = #events, f.scans
    f.focusedWindow, f.fullscreen = f.window, false
    f.lifecycle.callback(nil, 5, app)
    assert(events[#events].kind == "focus" and events[#events].id == 9)
    lifecycleCount = #events
    f.lifecycle.callback(nil, 2, app)
    assert(#events == lifecycleCount + 1 and events[#events].kind == "ready")
    assert(events[#events].metadata.origin == "targetedReadiness")
    assert(f.scans == scansBeforeLaunch + 1, "launch must perform exactly one app-local readiness scan")
    f.appWatchers[#f.appWatchers].callback(f.window, "AXWindowCreated"); assert(events[#events].kind == "ready")
    local old = f.appWatchers[#f.appWatchers].callback
    f.lifecycle.callback(nil, 3, app); subscription.detach(); host:stop():stop(); assert(f.stops >= 4)
    host:start(); old(element, "AXWindowCreated"); assert(events[#events].kind == "terminated")
  end,
  ["LIFE-001 LIFE-004: optional app watcher failure retains app lease and termination releases later subscriptions"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    local original = app.newWatcher; app.newWatcher = function() return nil end
    host:subscribeApplications(function(event) events[#events + 1] = event end)
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    local ready = events[1]
    assert(ready.resource and ready.appResource and host.handles[9].appLease == ready.appResource)
    app.newWatcher = original
    host:_attachApp(app, function(event) events[#events + 1] = event end)
    host:subscribeWindow(f.window, function(event) events[#events + 1] = event end)
    f.lifecycle.callback(nil, 3, app)
    local terminated = events[#events]
    host:releaseApplication(7, terminated.resource)
    assert(f.appWatchers[1].stopped and f.windowWatcher.stopped and not host.handles[9] and not host.appResources[7])
    host:stop()
  end,
  ["LIFE-001 LIFE-004: current records reject stale callbacks and defer same-PID app conflicts"] = function()
    local f, app = fake(); local host = Host.new(f.hs, { displayId = "d", regularSpaceId = 9 }):start(); local events = {}
    host:subscribeApplications(function(event) events[#events + 1] = event end)
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    local firstReady, originalWatcher = events[1], f.appWatchers[1]
    host:subscribeWindow(f.window, function(event) events[#events + 1] = event end)
    local currentWindowWatcher = f.windowWatcher.callback
    local clone = { isHidden = app.isHidden, pid = app.pid, name = app.name, bundleID = app.bundleID, allWindows = app.allWindows,
      newWatcher = app.newWatcher }
    local scans, watchers = f.scans, #f.appWatchers
    f.lifecycle.callback(nil, 2, clone)
    assert(f.scans == scans and #f.appWatchers == watchers and host.appResources[7].app == app)
    f.lifecycle.callback(nil, 4, clone)
    assert(#events == 1, "mismatched lifecycle payload is not authoritative")
    local cloneWindow = { isMinimized = f.window.isMinimized, id = function() return 10 end, title = function() return "Candidate" end,
      application = function() return clone end, role = f.window.role, subrole = f.window.subrole,
      isFullScreen = function() return false end, newWatcher = f.window.newWatcher }
    clone.allWindows = function() f.scans = f.scans + 1; return { cloneWindow } end
    f.members = { 9, 10 }; f.hs.application.runningApplications = function() return { clone } end
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    assert(#events == 1 and not host.handles[10], "complete conflict scan must defer its unequal app window")
    f.lifecycle.callback(nil, 3, app)
    local terminated = events[#events]
    assert(terminated.kind == "terminated" and terminated.resource == host.appResources[7].lease)
    host:releaseApplication(7, terminated.resource)
    currentWindowWatcher(nil, "AXTitleChanged")
    originalWatcher.callback(f.window, "AXWindowCreated")
    assert(#events == 2, "released app/window callbacks are stale")
    f.hs.application.runningApplications = function() return { clone } end
    host:subscribeExistingWindows(function(event) events[#events + 1] = event end)
    assert(#f.appWatchers == watchers + 1 and events[#events].kind == "ready" and events[#events].resource ~= firstReady.resource)
    host:stop()
  end,
}
