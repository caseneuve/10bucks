local Runtime = require("lib.runtime")
local WorkspaceSwitch = require("lib.workspace_switch")

local function runtime(active, onObserve)
  local observed, machine
  machine = Runtime.new({
    initialState = WorkspaceSwitch.initial({ displayId = "built-in", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = active }),
    reduce = WorkspaceSwitch.reduce,
    validate = WorkspaceSwitch.validate,
    deriveIntents = WorkspaceSwitch.deriveIntents,
    observeIntents = function(intents)
      observed[#observed + 1] = intents
      if onObserve then onObserve(machine, intents) end
    end,
  })
  observed = {}
  return machine, observed
end

local function submit(machine, event)
  if event.type == "RegularTopologyObserved" then event.displayId = "built-in" end
  local ok, err = machine:submit(event)
  assert(ok, err)
end

local function latest(observed)
  return observed[#observed]
end

return {
  ["SPACE-005 STATE-002: previous regular toggles only after confirmed activation and commits before its switch intent"] = function()
    local machine, observed = runtime("A", function(current, intents)
      if intents[1] and intents[1].kind == "switchRegularSpace" then
        local state = current:state()
        assert(state.switch.inFlight and state.switch.inFlight.destinationId == intents[1].destinationId)
      end
    end)
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "B" })
    submit(machine, { type = "FocusPreviousRegular" })
    local state = machine:state()
    assert(state.activeRegularSpaceId == "B" and state.lastConfirmedRegularSpaceId == "B" and state.previousRegularSpaceId == "A")
    assert(state.switch.inFlight.destinationId == "A" and state.switch.desiredSpaceId == "A")
    assert(latest(observed)[1].kind == "switchRegularSpace" and latest(observed)[1].destinationId == "A")
    local generation = state.switch.inFlight.generation
    submit(machine, { type = "FocusPreviousRegular" })
    assert(machine:state().switch.inFlight.generation == generation and #latest(observed) == 0)
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "A" })
    assert(machine:state().previousRegularSpaceId == "B" and machine:state().switch.inFlight == nil)
    submit(machine, { type = "FocusPreviousRegular" })
    assert(latest(observed)[1].destinationId == "B")
  end,

  ["SPACE-001 SPACE-005: reorder changes numeric positions but retains confirmed history by identity"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "B" })
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "C", "A", "B" }, activeRegularSpaceId = "B" })
    submit(machine, { type = "FocusRegularPosition", position = 1 })
    assert(latest(observed)[1].destinationId == "C")
    submit(machine, { type = "FocusPreviousRegular" })
    assert(machine:state().switch.desiredSpaceId == "A" and #latest(observed) == 0,
      "previous history retains A's identity rather than its old position")
  end,

  ["CMD-005: relative commands coalesce from desired destination while native switches remain serialized"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "FocusRelativeRegular", delta = 1 })
    local first = machine:state().switch.inFlight.generation
    assert(latest(observed)[1].destinationId == "B")
    submit(machine, { type = "FocusRelativeRegular", delta = 1 })
    assert(machine:state().switch.inFlight.generation == first and machine:state().switch.desiredSpaceId == "C" and #latest(observed) == 0)
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "B" })
    assert(latest(observed)[1].destinationId == "C" and machine:state().switch.inFlight.generation == first + 1)

    machine, observed = runtime("A")
    submit(machine, { type = "FocusRelativeRegular", delta = 1 })
    submit(machine, { type = "FocusRelativeRegular", delta = -1 })
    assert(machine:state().switch.desiredSpaceId == "A" and #latest(observed) == 0)
    -- A screen/reorder watcher can report the unchanged source while B is
    -- still in flight. This must retain queued return-to-A intent.
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "C", "A", "B" }, activeRegularSpaceId = "A" })
    assert(machine:state().switch.inFlight.destinationId == "B" and machine:state().switch.desiredSpaceId == "A"
      and #latest(observed) == 0)
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "C", "A", "B" }, activeRegularSpaceId = "B" })
    assert(latest(observed)[1].destinationId == "A")
  end,

  ["CMD-005: absolute replacement and unchanged source snapshots retain a serialized queued destination"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "FocusRelativeRegular", delta = 1 })
    local generation = machine:state().switch.inFlight.generation
    submit(machine, { type = "FocusRegularPosition", position = 3 })
    assert(machine:state().switch.inFlight.generation == generation and machine:state().switch.desiredSpaceId == "C")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "C", "A", "B" }, activeRegularSpaceId = "A" })
    assert(machine:state().switch.inFlight.generation == generation and machine:state().switch.desiredSpaceId == "C"
      and #latest(observed) == 0, "an unchanged/source snapshot must not erase the queued replacement")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "C", "A", "B" }, activeRegularSpaceId = "B" })
    assert(latest(observed)[1].destinationId == "C" and machine:state().switch.inFlight.generation == generation + 1)
  end,

  ["SPACE-004 CMD-005: relative navigation wraps across regular positions"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "FocusRelativeRegular", delta = -1 })
    assert(latest(observed)[1].destinationId == "C")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "C" })
    submit(machine, { type = "FocusRelativeRegular", delta = 1 })
    assert(latest(observed)[1].destinationId == "A")
  end,

  ["SPACE-005: fullscreen actual context remains nil while numbered and history targets remain usable"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "B" })
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = nil })
    local state = machine:state()
    assert(state.activeRegularSpaceId == nil and state.lastConfirmedRegularSpaceId == "B" and state.previousRegularSpaceId == "A")
    submit(machine, { type = "FocusPreviousRegular" })
    assert(latest(observed)[1].destinationId == "A")
    machine, observed = runtime("B")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = nil })
    submit(machine, { type = "FocusRegularPosition", position = 2 })
    assert(latest(observed)[1].destinationId == "B", "numbered B must switch from fullscreen even when B is last confirmed")
    machine, observed = runtime(nil)
    submit(machine, { type = "FocusRegularPosition", position = 2 })
    assert(latest(observed)[1].destinationId == "B")
    submit(machine, { type = "RegularSwitchFailed", generation = machine:state().switch.inFlight.generation })
    submit(machine, { type = "FocusRelativeRegular", delta = 1 })
    assert(#latest(observed) == 0, "relative navigation without an actual or confirmed regular anchor is a no-op")
  end,

  ["SPACE-002 SPACE-005: missing numbered targets and absent previous history issue no switch"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "FocusRegularPosition", position = 9 })
    assert(#latest(observed) == 0)
    submit(machine, { type = "FocusPreviousRegular" })
    assert(#latest(observed) == 0)
  end,

  ["SPACE-006 CMD-006: external topology and current-generation expiry clear only switch intent and stale expiry is ignored"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "FocusRegularPosition", position = 3 })
    local first = machine:state().switch.inFlight.generation
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "B" })
    assert(machine:state().activeRegularSpaceId == "B" and machine:state().switch.inFlight.destinationId == "C",
      "nonmatching observed activation is external reality, not completion")
    submit(machine, { type = "RegularSwitchTimedOut", generation = first })
    assert(machine:state().switch.inFlight == nil and machine:state().switch.desiredSpaceId == nil)
    assert(latest(observed)[1].kind == "resnapshotRegularTopology")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B", "C" }, activeRegularSpaceId = "C" })
    assert(machine:state().lastConfirmedRegularSpaceId == "C" and machine:state().switch.inFlight == nil,
      "late activation after expiry is external, not an expired completion")

    submit(machine, { type = "FocusRegularPosition", position = 1 })
    local second = machine:state().switch.inFlight.generation
    submit(machine, { type = "RegularSwitchFailed", generation = first })
    assert(machine:state().switch.inFlight.generation == second and #latest(observed) == 0)
    submit(machine, { type = "RegularSwitchFailed", generation = second })
    assert(latest(observed)[1].kind == "resnapshotRegularTopology")
  end,

  ["SPACE-006: topology removal retains an issued generation as a serialization barrier without Core-side cleanup"] = function()
    local machine, observed = runtime("A")
    submit(machine, { type = "FocusRelativeRegular", delta = 1 }) -- issued B
    local generation = machine:state().switch.inFlight.generation
    submit(machine, { type = "FocusRelativeRegular", delta = 1 }) -- queued C
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A", "B" }, activeRegularSpaceId = "A" })
    local state = machine:state()
    assert(state.switch.inFlight.destinationId == "B" and state.switch.desiredSpaceId == "B" and #latest(observed) == 0,
      "removing queued C must retain issued B until it confirms or expires")
    submit(machine, { type = "RegularTopologyObserved", regularSpaceIds = { "A" }, activeRegularSpaceId = "A" })
    state = machine:state()
    assert(state.switch.inFlight.destinationId == "B" and state.switch.desiredSpaceId == nil and #latest(observed) == 0,
      "removing issued B must not overlap a new native request")
    submit(machine, { type = "RegularSwitchTimedOut", generation = generation })
    assert(machine:state().switch.inFlight == nil and latest(observed)[1].kind == "resnapshotRegularTopology")
  end,
}
