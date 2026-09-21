local Model = require("lib.model")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function assertValid(state)
  local valid, err = Model.validate(state)
  assert(valid, err)
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[deepCopy(key)] = deepCopy(item) end
  return result
end

local function initial()
  return Model.new({ displayId = "built-in", activeRegularSpaceId = "space-1" })
end

local function ready(id, overrides)
  local event = {
    type = "WindowReady",
    id = id,
    application = { pid = 42, bundleID = "example.app", name = "Example" },
    title = "Example window",
    displayId = "built-in",
    spaceId = "space-1",
  }
  for key, value in pairs(overrides or {}) do event[key] = value end
  return event
end

return {
  ["ENV-004 STATE-003: initial state carries explicit display and regular-Space identity"] = function()
    local state = initial()
    equal(state.displays["built-in"].id, "built-in")
    equal(state.displays["built-in"].activeRegularSpaceId, "space-1")
    equal(state.spaces["space-1"].id, "space-1")
    equal(state.spaces["space-1"].displayId, "built-in")
    equal(#state.spaces["space-1"].memberIds, 0)
    equal(state.focus.desiredBySpace["space-1"].pending, false)
    equal(state.focus.desiredBySpace["space-1"].generation, 0)
    assertValid(state)
  end,

  ["STATE-001 STATE-003 WIN-003: ready admission copies only plain facts and appends once"] = function()
    local state = initial()
    local event = ready("window-1")
    local nextState = Model.reduce(state, event)

    assert(nextState ~= state)
    equal(nextState.windows["window-1"].actualDisplayId, "built-in")
    equal(nextState.windows["window-1"].actualSpaceId, "space-1")
    equal(nextState.windows["window-1"].placementSpaceId, "space-1")
    equal(nextState.windows["window-1"].lifecycle.minimized, false)
    equal(nextState.spaces["space-1"].memberIds[1], "window-1")
    assert(state.windows["window-1"] == nil)
    assert(Model.reduce(nextState, event) == nextState)
    assertValid(nextState)
  end,

  ["WIN-005 STATE-005: destruction and application termination are removal facts"] = function()
    local state = Model.reduce(initial(), ready("one"))
    state = Model.reduce(state, ready("two", { application = { pid = 99, bundleID = "two.app", name = "Two" } }))
    state = Model.reduce(state, { type = "WindowDestroyed", id = "one" })
    assert(state.windows.one == nil)
    equal(state.spaces["space-1"].memberIds[1], "two")

    state = Model.reduce(state, { type = "ApplicationTerminated", pid = 99 })
    assert(state.windows.two == nil)
    equal(#state.spaces["space-1"].memberIds, 0)
    assertValid(state)
  end,

  ["STATE-004 STATE-005: visibility is observed independently without changing membership or availability"] = function()
    local state = Model.reduce(initial(), ready("window-1"))
    local observed = Model.reduce(state, { type = "WindowVisibilityObserved", id = "window-1", visible = false })
    equal(observed.windows["window-1"].observations.visible, false)
    assert(Model.isAvailable(observed.windows["window-1"]))
    observed = Model.reduce(observed, { type = "WindowAbsentFromSnapshot", id = "window-1" })
    assert(observed.windows["window-1"] ~= nil)
    equal(observed.windows["window-1"].observations.visible, false)
    equal(observed.spaces["space-1"].memberIds[1], "window-1")
    assert(Model.reduce(observed, { type = "WindowVisibilityObserved", id = "unknown", visible = false }).windows.unknown == nil)
    assertValid(observed)
  end,

  ["STATE-001 STATE-008 WIN-004: lifecycle conditions are independent, preserve visibility, and use copy-on-write"] = function()
    local state = Model.reduce(initial(), ready("window-1"))
    state = Model.reduce(state, { type = "WindowVisibilityObserved", id = "window-1", visible = false })
    local beforeMinimize = state
    state = Model.reduce(state, { type = "WindowMinimized", id = "window-1" })
    assert(beforeMinimize ~= state)
    equal(beforeMinimize.windows["window-1"].lifecycle.minimized, false)
    equal(beforeMinimize.windows["window-1"].observations.visible, false)
    equal(state.windows["window-1"].observations.visible, false)
    state = Model.reduce(state, { type = "ApplicationHidden", pid = 42 })
    state = Model.reduce(state, { type = "WindowEnteredNativeFullscreen", id = "window-1" })
    assert(not Model.isAvailable(state.windows["window-1"]))
    equal(state.windows["window-1"].observations.visible, false)

    state = Model.reduce(state, { type = "WindowRestored", id = "window-1" })
    assert(not Model.isAvailable(state.windows["window-1"]))
    state = Model.reduce(state, { type = "ApplicationUnhidden", pid = 42 })
    assert(not Model.isAvailable(state.windows["window-1"]))
    state = Model.reduce(state, { type = "WindowExitedNativeFullscreen", id = "window-1" })
    assert(Model.isAvailable(state.windows["window-1"]))
    equal(state.windows["window-1"].observations.visible, false)
    equal(state.spaces["space-1"].memberIds[1], "window-1")
    assertValid(state)
  end,

  ["LIFE-003 WIN-002: title changes copy-on-write for managed IDs only and never reclassify or reorder"] = function()
    local state = Model.reduce(initial(), ready("one"))
    state = Model.reduce(state, ready("two"))
    local before = state
    local updated = Model.reduce(state, { type = "WindowTitleChanged", id = "one", title = "Renamed" })
    assert(updated ~= before)
    equal(before.windows.one.title, "Example window")
    equal(updated.windows.one.title, "Renamed")
    equal(updated.windows.one.ruleAction, "manage")
    equal(updated.spaces["space-1"].memberIds[1], "one")
    equal(updated.spaces["space-1"].memberIds[2], "two")
    assert(Model.reduce(updated, { type = "WindowTitleChanged", id = "one", title = "Renamed" }) == updated)
    assert(Model.reduce(updated, { type = "WindowTitleChanged", id = "unknown", title = "Ignored" }) == updated)
    assertValid(updated)
  end,

  ["FOCUS-003 WIN-002: focus neither admits unknown windows nor reorders members"] = function()
    local state = Model.reduce(initial(), ready("one"))
    state = Model.reduce(state, ready("two"))
    local observedUnknown = Model.reduce(state, { type = "ActualFocusChanged", id = "unknown", title = "Popup" })
    assert(observedUnknown.windows.unknown == nil)
    equal(#observedUnknown.spaces["space-1"].memberIds, 2)

    local focused = Model.reduce(observedUnknown, { type = "ActualFocusChanged", id = "one", title = "One" })
    equal(focused.spaces["space-1"].memberIds[1], "one")
    equal(focused.spaces["space-1"].memberIds[2], "two")
    equal(focused.focus.managedHistory[1], "one")
    assertValid(focused)
  end,

  ["STATE-003: validator rejects malformed identity, membership, lifecycle, and non-plain durable values"] = function()
    local state = Model.reduce(initial(), ready("window-1"))
    local cases = {
      function(s) s.displays["built-in"].activeRegularSpaceId = "missing" end,
      function(s) s.spaces["space-1"].memberIds[2] = "window-1" end,
      function(s) s.windows["window-1"].lifecycle.minimized = "false" end,
      function(s) s.windows["window-1"].adapterHandle = function() end end,
      function(s) setmetatable(s.windows["window-1"], {}) end,
      function(s) s.focus.desiredBySpace["space-1"] = { targetId = "missing", pending = true, generation = 1 } end,
      function(s) s.focus.desiredBySpace["space-1"].generation = -1 end,
    }
    for _, corrupt in ipairs(cases) do
      local copy = deepCopy(state)
      corrupt(copy)
      local valid = Model.validate(copy)
      assert(not valid)
    end
  end,
}
