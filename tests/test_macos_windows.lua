local Windows = require("lib.macos.windows")
local Model = require("lib.model")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function metadata(id, overrides)
  local value = {
    id = id or "window-1", application = { pid = 41, bundleID = "example.app", name = "Example" },
    title = "Original", displayId = "built-in", spaceId = "space-1", role = "AXWindow",
    subrole = "AXStandardWindow", modal = false, movable = true, resizable = true,
    selfProcess = false, origin = "created",
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

local function fake()
  local value = { events = {}, detached = 0, globalQueries = 0, timers = 0, probes = {}, applicationCallbacks = {}, existingCallbacks = {}, windowSubscriptions = 0,
    releasedWindows = {}, releasedApplications = {} }
  local function subscription()
    return { detach = function() value.detached = value.detached + 1 end }
  end
  value.native = {
    managedDecision = function(id) return value.decisions and value.decisions[id] end,
    subscribeApplications = function(callback) table.insert(value.applicationCallbacks, callback); return subscription() end,
    subscribeExistingWindows = function(callback) table.insert(value.existingCallbacks, callback); return subscription() end,
    subscribeWindow = function(handle, callback)
      value.windowSubscriptions = value.windowSubscriptions + 1
      value.windowCallbacks = value.windowCallbacks or {}
      value.windowCallbacks[handle] = callback
      return subscription()
    end,
    probeReadiness = function(id, callback) value.probes[id] = callback; return subscription() end,
    releaseWindow = function(id, lease) value.releasedWindows[#value.releasedWindows + 1] = { id = id, lease = lease } end,
    releaseApplication = function(pid, lease) value.releasedApplications[#value.releasedApplications + 1] = { pid = pid, lease = lease } end,
    globalWindowQuery = function() value.globalQueries = value.globalQueries + 1 end,
    timer = function() value.timers = value.timers + 1 end,
  }
  return value
end

local function adapter(fake)
  return Windows.new({ sink = function(event) table.insert(fake.events, event) end, native = fake.native })
end

return {
  ["STATE-003 PERF-001 PERF-002: adapter only sends plain normalized events and has no global-query or timer path"] = function()
    local f, instance = fake(), nil
    instance = adapter(f):start()
    local handle = { native = true }
    f.existingCallbacks[1]({ kind = "ready", metadata = metadata(), handle = handle })
    equal(f.events[1].type, "WindowReady")
    assert(f.events[1].handle == nil)
    assert(instance:handleForId("window-1") == handle)
    assert(f.globalQueries == 0 and f.timers == 0)
  end,

  ["LIFE-001 LIFE-002 FS-002 WIN-004: direct callbacks normalize independently in callback order"] = function()
    local f = fake()
    adapter(f):start()
    local window, application = f.existingCallbacks[1], f.applicationCallbacks[1]
    window({ kind = "ready", metadata = metadata(), handle = {}, resource = 1, appResource = 2 })
    window({ kind = "minimized", id = "window-1", resource = 1 })
    application({ kind = "hidden", pid = 41, resource = 2 })
    window({ kind = "enteredNativeFullscreen", id = "window-1", resource = 1 })
    application({ kind = "unhidden", pid = 41, resource = 2 })
    window({ kind = "restored", id = "window-1", resource = 1 })
    window({ kind = "exitedNativeFullscreen", id = "window-1", resource = 1 })
    local types = {}
    for _, event in ipairs(f.events) do table.insert(types, event.type) end
    equal(table.concat(types, ","), "WindowReady,WindowMinimized,ApplicationHidden,WindowEnteredNativeFullscreen,ApplicationUnhidden,WindowRestored,WindowExitedNativeFullscreen")
  end,

  ["FOCUS-003 DISC-002: actual focus is separate; probe success is independent and one-shot"] = function()
    local f = fake()
    adapter(f):start()
    local window = f.existingCallbacks[1]
    window({ kind = "focus", id = "unknown", title = "Popup", applicationName = "Popup App" })
    window({ kind = "focus", id = "unknown" })
    equal(#f.events, 2)
    equal(f.events[1].type, "ActualFocusChanged")
    local completion = f.probes.unknown
    completion(nil)
    equal(#f.events, 2)
    window({ kind = "focus", id = "unknown" })
    completion = f.probes.unknown
    local delayed, handle = metadata("unknown", { origin = "created" }), {}
    completion(delayed, handle)
    completion(metadata("unknown"), {})
    equal(#f.events, 4)
    equal(f.events[4].type, "WindowReady")
    equal(f.events[4].metadata.origin, "targetedReadiness")
    equal(delayed.origin, "created")
    assert(adapter and f.windowSubscriptions == 1)
  end,

  ["LIFE-003 STATE-001: adapter title event reduces copy-on-write without admission or ordering change"] = function()
    local f = fake()
    adapter(f):start()
    local window = f.existingCallbacks[1]
    window({ kind = "ready", metadata = metadata("managed"), handle = {}, resource = 1, appResource = 2 })
    window({ kind = "titleChanged", id = "managed", title = "Renamed", resource = 1 })
    local state = Model.new({ displayId = "built-in", activeRegularSpaceId = "space-1" })
    state = Model.reduce(state, f.events[1])
    local before, updated = state, Model.reduce(state, f.events[2])
    assert(updated ~= before)
    equal(updated.windows.managed.title, "Renamed")
    equal(updated.spaces["space-1"].memberIds[1], "managed")
    assert(Model.reduce(updated, { type = "WindowTitleChanged", id = "unknown", title = "Ignored" }) == updated)
  end,

  ["RULE-002 STATE-003: deferred/excluded ready events never cache handles or attach per-window subscriptions"] = function()
    local f, instance = fake(), nil
    instance = adapter(f):start()
    local window = f.existingCallbacks[1]
    local deferred = metadata("deferred")
    deferred.movable = nil
    window({ kind = "ready", metadata = deferred, handle = {} })
    window({ kind = "ready", metadata = metadata("excluded", { modal = true }), handle = {} })
    equal(f.events[1].decision.action, "defer")
    equal(f.events[2].decision.action, "exclude")
    assert(instance:handleForId("deferred") == nil and instance:handleForId("excluded") == nil)
    equal(f.windowSubscriptions, 0)
  end,

  ["STATE-003 LIFE-004: stopped and previous-generation callbacks cannot resurrect cache, subscriptions, or events"] = function()
    local f, instance = fake(), nil
    instance = adapter(f):start()
    local priorWindow, priorApplication = f.existingCallbacks[1], f.applicationCallbacks[1]
    priorWindow({ kind = "focus", id = "late" })
    local completion = f.probes.late
    instance:stop()
    completion(metadata("late"), {})
    priorWindow({ kind = "ready", metadata = metadata("old"), handle = {} })
    priorApplication({ kind = "hidden", pid = 41 })
    equal(#f.events, 1)
    assert(instance:handleForId("late") == nil and instance:handleForId("old") == nil)
    instance:start()
    priorWindow({ kind = "ready", metadata = metadata("stale"), handle = {} })
    priorApplication({ kind = "terminated", pid = 41 })
    equal(#f.events, 1)
    assert(instance:handleForId("stale") == nil)
  end,

  ["WIN-005 STATE-004 STATE-005: only direct destruction and termination remove; each clears ephemeral handles"] = function()
    local f, instance = fake(), nil
    instance = adapter(f):start()
    local window, application = f.existingCallbacks[1], f.applicationCallbacks[1]
    local one, two = {}, {}
    window({ kind = "ready", metadata = metadata("one"), handle = one })
    window({ kind = "ready", metadata = metadata("two"), handle = two })
    window({ kind = "destroyed", id = "one" })
    assert(instance:handleForId("one") == nil)
    application({ kind = "terminated", pid = 41 })
    assert(instance:handleForId("two") == nil)
    equal(f.events[3].type, "WindowDestroyed")
    equal(f.events[4].type, "ApplicationTerminated")
  end,

  ["STATE-003 LIFE-004: partial start and stop detach every owned subscription and clear the cache"] = function()
    local f = fake()
    f.native.subscribeExistingWindows = function() error("second attach failed") end
    local instance = adapter(f)
    assert(not pcall(function() instance:start() end))
    equal(f.detached, 1)
    assert(not instance.started and instance:handleForId("window-1") == nil)

    f = fake()
    instance = adapter(f):start()
    f.existingCallbacks[1]({ kind = "ready", metadata = metadata(), handle = {} })
    instance:stop():stop()
    equal(f.detached, 3)
    assert(instance:handleForId("window-1") == nil)
  end,
  ["LIFE-004: failing readiness probe and per-window attach leave no retained adapter state"] = function()
    local f, instance = fake(), nil
    instance = adapter(f):start()
    f.native.probeReadiness = function() error("probe construction failed") end
    assert(not pcall(function() f.existingCallbacks[1]({ kind = "focus", id = "probe" }) end))
    assert(instance.probing.probe == nil and instance:handleForId("probe") == nil)
    f.native.probeReadiness = function(id, callback) f.probes[id] = callback; return { detach = function() f.detached = f.detached + 1 end } end
    f.existingCallbacks[1]({ kind = "focus", id = "probe" })
    assert(f.probes.probe and instance.probing.probe)
    f.native.subscribeWindow = function() error("window watcher construction failed") end
    f.existingCallbacks[1]({ kind = "ready", metadata = metadata("attach"), handle = {}, resource = 2, appResource = 3 })
    assert(instance:handleForId("attach") == nil and #f.events == 2, "focus facts only; failed attach cannot admit")
    instance:stop()
  end,
  ["LIFE-001 LIFE-004: repeated current readiness survives explicit false and thrown sink outcomes"] = function()
    local f, reject = fake(), false
    local instance = Windows.new({ native = f.native, sink = function(event)
      f.events[#f.events + 1] = event
      if reject == "throw" then error("post-commit effect failed") end
      return reject and false or true
    end }):start()
    local window, handle = f.existingCallbacks[1], {}
    window({ kind = "ready", metadata = metadata("managed"), handle = handle, resource = 10, appResource = 20 })
    reject = true; window({ kind = "ready", metadata = metadata("managed"), handle = handle, resource = 10, appResource = 20 })
    assert(instance:handleForId("managed") == handle and #f.releasedWindows == 0)
    reject = "throw"; assert(not pcall(function()
      window({ kind = "ready", metadata = metadata("managed"), handle = handle, resource = 10, appResource = 20 })
    end))
    assert(instance:handleForId("managed") == handle and #f.releasedWindows == 0)
    instance:stop()
  end,
  ["LIFE-001 LIFE-004: stale leases do not route and protected destruction releases after sink failure"] = function()
    local f = fake()
    local instance = Windows.new({ native = f.native, sink = function(event)
      f.events[#f.events + 1] = event
      if event.type == "WindowDestroyed" then error("reducer failure") end
    end }):start()
    local window = f.existingCallbacks[1]
    local handle = {}
    window({ kind = "ready", metadata = metadata("managed"), handle = handle, resource = 10, appResource = 20 })
    window({ kind = "ready", metadata = metadata("managed"), handle = {}, resource = 11, appResource = 20 })
    window({ kind = "titleChanged", id = "managed", title = "stale", resource = 11 })
    assert(#f.events == 1 and instance:handleForId("managed") == handle)
    assert(#f.releasedWindows == 1 and f.releasedWindows[1].lease == 11, "unadmitted conflict releases only its provisional lease")
    local ok = pcall(function() window({ kind = "destroyed", id = "managed", resource = 10 }) end)
    assert(not ok and f.events[#f.events].type == "WindowDestroyed")
    assert(instance:handleForId("managed") == nil and #f.releasedWindows == 2 and f.releasedWindows[2].lease == 10)
    local app = f.applicationCallbacks[1]
    app({ kind = "terminated", pid = 41, resource = 20 })
    assert(#f.releasedApplications == 1 and f.releasedApplications[1].lease == 20)
  end,
}
