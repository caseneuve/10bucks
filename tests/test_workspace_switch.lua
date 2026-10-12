local Runtime = require("lib.runtime")
local W = require("lib.workspace_switch")
local function fact(revision, active, regular, full, nativeType)
  return { type = "RegularTopologyObserved", displayId = "built-in", revision = revision,
    nativeSpaceId = active or "A", nativeSpaceType = nativeType or "user",
    regularSpaceIds = regular or { "A", "B", "C" }, fullSpaceIds = full or regular or { "A", "B", "C" } }
end
local function runtime(initial)
  local batches = {}
  local machine
  machine = Runtime.new({ initialState = W.initial(initial or fact(1)), reduce = W.reduce, validate = W.validate,
    deriveIntents = W.deriveIntents, observeIntents = function(intents)
      batches[#batches + 1] = intents
      for _, intent in ipairs(intents) do
        if intent.kind == "switchRegularSpace" then assert(machine:state().switch.inFlight.generation == intent.generation) end
      end
    end })
  return machine, batches
end
local function submit(m, e) local ok, err = m:submit(e); assert(ok, err) end
local function command(m, delta) submit(m, { type = "FocusRelativeRegular", delta = delta }) end
local function operation(m, kind)
  local op = m:state().switch.inFlight
  return { type = kind, generation = op.generation, sourceId = op.sourceId, sourceType = op.sourceType, destinationId = op.destinationId }
end
local function confirm(m, revision)
  local event = operation(m, "RegularTopologyObserved")
  local snapshot = fact(revision, event.destinationId)
  for key, value in pairs(event) do snapshot[key] = value end
  submit(m, snapshot)
end
return {
  ["CMD-005 STATE-002: n,n and n,p serialize B before and after AXPress"] = function()
    for _, pressed in ipairs({ false, true }) do
      for _, delta in ipairs({ 1, -1 }) do
        local m, batches = runtime()
        command(m, 1)
        local first = m:state().switch.inFlight.generation
        if pressed then submit(m, operation(m, "RegularSwitchPressed")) end
        command(m, delta)
        assert(m:state().switch.inFlight.generation == first and #batches[#batches] == 0)
        assert(m:state().switch.desiredSpaceId == (delta == 1 and "C" or "A"))
        submit(m, fact(2)) -- revision alone does not cancel
        assert(not m:state().switch.inFlight.invalidated and #batches[#batches] == 0)
        if not pressed then submit(m, operation(m, "RegularSwitchPressed")) end
        confirm(m, 3)
        assert(m:state().switch.inFlight.destinationId == (delta == 1 and "C" or "A"))
        assert(m:state().switch.inFlight.sourceId == "B" and m:state().switch.inFlight.generation == first + 1)
      end
    end
  end,
  ["SPACE-005: previous is confirmed history; repeated zero and later toggle"] = function()
    local m = runtime()
    submit(m, fact(2, "B"))
    submit(m, { type = "FocusPreviousRegular" })
    local generation = m:state().switch.inFlight.generation
    submit(m, { type = "FocusPreviousRegular" })
    assert(m:state().switch.inFlight.generation == generation and m:state().previousRegularSpaceId == "A")
    submit(m, operation(m, "RegularSwitchPressed")); confirm(m, 3)
    assert(not m:state().switch.inFlight and m:state().previousRegularSpaceId == "B")
    submit(m, { type = "FocusPreviousRegular" })
    assert(m:state().switch.inFlight.destinationId == "B")
  end,
  ["SPACE-001 SPACE-002 SPACE-004: positions reorder, missing rejects, relative wraps"] = function()
    local m, batches = runtime()
    submit(m, { type = "FocusRegularPosition", position = 9 }); assert(#batches[#batches] == 0)
    submit(m, { type = "FocusPreviousRegular" }); assert(#batches[#batches] == 0)
    submit(m, fact(2, "A", { "C", "A", "B" }))
    submit(m, { type = "FocusRegularPosition", position = 1 }); assert(m:state().switch.inFlight.destinationId == "C")
    m = runtime(); command(m, -1); assert(m:state().switch.inFlight.destinationId == "C")
  end,
  ["SPACE-006 STATE-003: complete dense ordered topology rejects holes duplicates partial source and stale observations"] = function()
    local m = runtime()
    for _, bad in ipairs({ fact(2, "A", { [1] = "A", [3] = "C" }), fact(2, "A", { "A", "A" }),
      fact(2, "A", { "A", "B" }, { "A" }), fact(2, "X") }) do
      local ok = m:submit(bad); assert(not ok)
      assert(m:state().revision == 1)
    end
    submit(m, fact(3, "B")); local version = m:version()
    submit(m, fact(2)); submit(m, fact(3)); assert(m:version() == version and m:state().nativeSpaceId == "B")
  end,
  ["SPACE-005: fullscreen source is primitive native identity not fabricated regular scope"] = function()
    local m = runtime(fact(1, "F", { "A", "B", "C" }, { "A", "F", "B", "C" }, "fullscreen"))
    assert(m:state().activeRegularSpaceId == nil)
    submit(m, { type = "FocusRegularPosition", position = 2 })
    local op = m:state().switch.inFlight
    assert(op.sourceId == "F" and op.sourceType == "fullscreen" and op.destinationId == "B")
  end,
  ["CMD-006 SPACE-006: timeout guards clears resnapshots; late native activation is external"] = function()
    local m, batches = runtime(); command(m, 1)
    local timeout = operation(m, "RegularSwitchTimedOut")
    local stale = operation(m, "RegularSwitchTimedOut"); stale.sourceId = "X"
    submit(m, stale); assert(m:state().switch.inFlight and #batches[#batches] == 0)
    stale.sourceId = timeout.sourceId; stale.generation = 99
    submit(m, stale); assert(m:state().switch.inFlight)
    submit(m, timeout); assert(not m:state().switch.inFlight and not m:state().switch.desiredSpaceId)
    assert(batches[#batches][1].kind == "resnapshotRegularTopology")
    submit(m, fact(2, "B")); assert(m:state().lastConfirmedRegularSpaceId == "B" and not m:state().switch.inFlight)
    command(m, 1); submit(m, timeout); assert(m:state().switch.inFlight.generation == 2)
  end,
  ["STATE-003: confirmation requires pressed matching operation plus actual observation"] = function()
    local m, batches = runtime(); command(m, 1)
    local press = operation(m, "RegularSwitchPressed"); press.destinationId = "C"
    submit(m, press); assert(m:state().switch.inFlight.phase == "requested")
    submit(m, operation(m, "RegularSwitchPressed"))
    local bad = fact(2, "B"); bad.generation = 99
    submit(m, bad)
    assert(not m:state().switch.inFlight.invalidated and #batches[#batches] == 0)
    assert(m:state().activeRegularSpaceId == "B")
    confirm(m, 3); assert(not m:state().switch.inFlight)
  end,
  ["SPACE-006 SPACE-009: semantic order removal invalidates but preserves barrier and emits primitive removals"] = function()
    local m, batches = runtime(); command(m, 1); command(m, 1)
    submit(m, fact(2, "A", { "A", "B" }))
    assert(m:state().switch.inFlight.invalidated and m:state().switch.desiredSpaceId == "B")
    assert(batches[#batches][1].kind == "RegularSpaceRemoved" and batches[#batches][1].spaceId == "C")
    assert(batches[#batches][2].kind == "cancelRegularSwitch")
    command(m, -1); assert(#batches[#batches] == 0 and m:state().switch.inFlight.generation == 1)
    submit(m, operation(m, "RegularSwitchFailed")); assert(not m:state().switch.inFlight)
    m, batches = runtime(); command(m, 1)
    submit(m, fact(2, "A", { "C", "A", "B" }))
    assert(m:state().switch.inFlight.invalidated and batches[#batches][1].kind == "cancelRegularSwitch")
  end,
  ["CMD-005 SPACE-006: pressed leg survives queued removal and full-order changes"] = function()
    local m, batches = runtime(); command(m, 1)
    submit(m, operation(m, "RegularSwitchPressed")); command(m, 1)
    submit(m, fact(2, "A", { "A", "B" }))
    assert(not m:state().switch.inFlight.invalidated and m:state().switch.desiredSpaceId == "B")
    assert(#batches[#batches] == 1 and batches[#batches][1].kind == "RegularSpaceRemoved")
    local event = operation(m, "RegularTopologyObserved")
    local observed = fact(3, "B", { "B", "A" })
    for k, v in pairs(event) do observed[k] = v end
    submit(m, observed)
    assert(not m:state().switch.inFlight and not m:state().switch.desiredSpaceId)
  end,
  ["CMD-006: cancellation acknowledgement preserves fresh desired unlike genuine failure"] = function()
    for _, kind in ipairs({ "RegularSwitchCancelled", "RegularSwitchFailed", "RegularSwitchTimedOut" }) do
      local m, batches = runtime(); command(m, 1)
      local receipt = operation(m, kind)
      submit(m, fact(2, "A", { "C", "A", "B" }))
      assert(m:state().switch.inFlight.invalidated)
      submit(m, { type = "FocusRegularPosition", position = 1 })
      submit(m, receipt)
      if kind == "RegularSwitchCancelled" then
        assert(m:state().switch.inFlight.destinationId == "C" and m:state().switch.inFlight.revision == 2)
        assert(batches[#batches][1].kind == "switchRegularSpace")
      else
        assert(not m:state().switch.inFlight and not m:state().switch.desiredSpaceId)
        assert(batches[#batches][1].kind == "resnapshotRegularTopology")
      end
    end
    local m, batches = runtime(); command(m, 1)
    submit(m, operation(m, "RegularSwitchCancelled")); assert(m:state().switch.inFlight)
    submit(m, fact(2, "C")); assert(batches[#batches][1].kind == "cancelRegularSwitch")
    submit(m, { type = "WorkspaceSwitchStopped" }); assert(#batches[#batches] == 0)
  end,
  ["STATE-003: captured operation topology validates source type membership order destination and revision"] = function()
    local m = runtime(); command(m, 1)
    for _, change in ipairs({ function(op) op.sourceType = "mystery" end,
      function(op) op.sourceId = "X" end,
      function(op) op.destinationId = "F" end,
      function(op) op.revision = 99 end,
      function(op) op.regularSpaceIds = { "C", "B", "A" } end }) do
      local state = m:state(); change(state.switch.inFlight)
      assert(not W.validate(state))
    end
    local ok = m:submit(fact(2, "F", { "A" }, { "A", "F" }, "mystery")); assert(not ok)
  end,
  ["CMD-005 SPACE-004 SPACE-005: absolute replacements back to A serialize both phases and both wraps"] = function()
    for _, pressed in ipairs({ false, true }) do
      local m = runtime(); command(m, 1)
      if pressed then submit(m, operation(m, "RegularSwitchPressed")) end
      submit(m, { type = "FocusRegularPosition", position = 3 })
      submit(m, { type = "FocusRegularPosition", position = 1 })
      assert(m:state().switch.inFlight.destinationId == "B" and m:state().switch.desiredSpaceId == "A")
      submit(m, operation(m, "RegularSwitchPressed")); confirm(m, 2)
      assert(m:state().switch.inFlight.destinationId == "A")
    end
    local m = runtime(fact(1, "C")); command(m, 1); assert(m:state().switch.inFlight.destinationId == "A")
    m = runtime(); submit(m, fact(2, "B")); submit(m, fact(3, "B", { "C", "A", "B" }))
    assert(m:state().previousRegularSpaceId == "A")
    submit(m, { type = "FocusPreviousRegular" }); assert(m:state().switch.inFlight.destinationId == "A")
  end,
  ["SPACE-005: fullscreen preserves history permits numbered return and cold relative no-ops"] = function()
    local m = runtime(); submit(m, fact(2, "B"))
    local fullscreen = fact(3, "F", { "A", "B", "C" }, { "A", "F", "B", "C" }, "fullscreen")
    submit(m, fullscreen); assert(m:state().previousRegularSpaceId == "A" and m:state().lastConfirmedRegularSpaceId == "B")
    submit(m, { type = "FocusPreviousRegular" }); assert(m:state().switch.inFlight.destinationId == "A")
    m = runtime(fullscreen); submit(m, { type = "FocusRegularPosition", position = 2 })
    assert(m:state().switch.inFlight.sourceId == "F" and m:state().switch.inFlight.destinationId == "B")
    m = runtime(fullscreen); command(m, 1); assert(not m:state().switch.inFlight)
  end,
  ["SPACE-006 STATE-003: pressed destination removal and stale tuples never release barrier"] = function()
    local m, batches = runtime(); command(m, 1)
    local cancel = operation(m, "RegularSwitchCancelled")
    submit(m, operation(m, "RegularSwitchPressed")); assert(m:state().activeRegularSpaceId == "A")
    submit(m, fact(2, "A", { "A", "C" }))
    assert(m:state().switch.inFlight.invalidated and batches[#batches][2].kind == "cancelRegularSwitch")
    submit(m, { type = "FocusRegularPosition", position = 2 })
    for _, key in ipairs({ "generation", "sourceId", "sourceType", "destinationId" }) do
      local stale = {}; for k,v in pairs(cancel) do stale[k] = v end
      stale[key] = key == "generation" and 99 or "wrong"
      submit(m, stale); assert(m:state().switch.inFlight.destinationId == "B")
    end
    submit(m, cancel); assert(m:state().switch.inFlight.destinationId == "C")
  end,
  ["CMD-006: explicit stop cancels once discards desired and rejects further commands"] = function()
    local m, batches = runtime(); command(m, 1); command(m, 1)
    submit(m, { type = "WorkspaceSwitchStopped" })
    assert(m:state().stopped and not m:state().switch.inFlight and not m:state().switch.desiredSpaceId)
    assert(batches[#batches][1].kind == "cancelRegularSwitch")
    submit(m, { type = "WorkspaceSwitchStopped" }); assert(#batches[#batches] == 0)
    command(m, 1); assert(not m:state().switch.inFlight)
    submit(m, fact(2, "B")); assert(m:state().nativeSpaceId == "B" and not m:state().switch.inFlight)
  end,
}
