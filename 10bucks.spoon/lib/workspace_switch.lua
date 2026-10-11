-- Pure regular-Space switching state. Native topology and switching remain
-- adapter concerns; this reducer owns only committed primitive intent/history.
local WorkspaceSwitch = {}

local function validId(value)
  return (type(value) == "string" and value ~= "") or (type(value) == "number" and value == value)
end

local function orderedIds(ids)
  if type(ids) ~= "table" then return nil end
  local seen = {}
  for index, id in ipairs(ids) do
    if not validId(id) or seen[id] then return nil end
    seen[id] = true
  end
  for key in pairs(ids) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #ids then return nil end
  end
  return seen
end

local function contains(ids, id)
  for _, candidate in ipairs(ids) do if candidate == id then return true end end
  return false
end

local function validOptionalId(value, ids)
  return value == nil or (validId(value) and contains(ids, value))
end

function WorkspaceSwitch.initial(input)
  if type(input) ~= "table" or not validId(input.displayId) or not orderedIds(input.regularSpaceIds)
    or not validOptionalId(input.activeRegularSpaceId, input.regularSpaceIds) then
    error("workspace switch state requires display identity, ordered regular Spaces, and optional active regular Space", 2)
  end
  local active = input.activeRegularSpaceId
  return {
    displayId = input.displayId,
    regularSpaceIds = input.regularSpaceIds,
    activeRegularSpaceId = active,
    lastConfirmedRegularSpaceId = active,
    previousRegularSpaceId = nil,
    switch = { desiredSpaceId = nil, inFlight = nil, nextGeneration = 0 },
  }
end

function WorkspaceSwitch.validate(state)
  if type(state) ~= "table" or not validId(state.displayId) then return false, "workspace display identity is malformed" end
  if not orderedIds(state.regularSpaceIds)
    or not validOptionalId(state.activeRegularSpaceId, state.regularSpaceIds)
    or not validOptionalId(state.lastConfirmedRegularSpaceId, state.regularSpaceIds)
    or not validOptionalId(state.previousRegularSpaceId, state.regularSpaceIds) then
    return false, "workspace regular topology or history is malformed"
  end
  local switch = state.switch
  if type(switch) ~= "table" or type(switch.nextGeneration) ~= "number" or switch.nextGeneration < 0
    or switch.nextGeneration % 1 ~= 0 or not validOptionalId(switch.desiredSpaceId, state.regularSpaceIds) then
    return false, "workspace switch intent is malformed"
  end
  if switch.inFlight ~= nil then
    -- A topology observation can remove an already-issued destination. Retain
    -- that generation as the serialization barrier until its failure/timeout;
    -- do not overlap a replacement native request.
    if type(switch.inFlight) ~= "table" or not validId(switch.inFlight.destinationId)
      or type(switch.inFlight.generation) ~= "number" or switch.inFlight.generation < 1
      or switch.inFlight.generation % 1 ~= 0 or switch.inFlight.generation > switch.nextGeneration then
      return false, "workspace in-flight switch is malformed"
    end
  end
  return true
end

local function beginIfNeeded(state)
  local switch = state.switch
  if switch.inFlight or not switch.desiredSpaceId or switch.desiredSpaceId == state.activeRegularSpaceId then return end
  switch.nextGeneration = switch.nextGeneration + 1
  switch.inFlight = { destinationId = switch.desiredSpaceId, generation = switch.nextGeneration }
end

local function request(state, destination)
  if not destination or (not state.switch.inFlight and destination == state.activeRegularSpaceId) then return end
  state.switch.desiredSpaceId = destination
  beginIfNeeded(state)
end

local function topology(state, event)
  if event.displayId ~= state.displayId or not orderedIds(event.regularSpaceIds)
    or not validOptionalId(event.activeRegularSpaceId, event.regularSpaceIds) then
    error("RegularTopologyObserved requires this display identity, ordered regular Space identities, and optional active regular Space", 3)
  end
  state.regularSpaceIds = event.regularSpaceIds
  if not contains(state.regularSpaceIds, state.lastConfirmedRegularSpaceId) then state.lastConfirmedRegularSpaceId = nil end
  if not contains(state.regularSpaceIds, state.previousRegularSpaceId) then state.previousRegularSpaceId = nil end
  if not contains(state.regularSpaceIds, state.switch.desiredSpaceId) then
    -- A queued destination disappeared, but an already-issued valid destination
    -- must remain the coherent desired completion until it settles.
    local inFlight = state.switch.inFlight
    state.switch.desiredSpaceId = inFlight and contains(state.regularSpaceIds, inFlight.destinationId)
      and inFlight.destinationId or nil
  end

  state.activeRegularSpaceId = event.activeRegularSpaceId
  if event.activeRegularSpaceId and event.activeRegularSpaceId ~= state.lastConfirmedRegularSpaceId then
    state.previousRegularSpaceId = state.lastConfirmedRegularSpaceId
    state.lastConfirmedRegularSpaceId = event.activeRegularSpaceId
  end
  if state.switch.inFlight and event.activeRegularSpaceId == state.switch.inFlight.destinationId then
    state.switch.inFlight = nil
  end
  if not state.switch.inFlight and state.switch.desiredSpaceId == state.activeRegularSpaceId then
    state.switch.desiredSpaceId = nil
  end
  beginIfNeeded(state)
end

function WorkspaceSwitch.reduce(state, event)
  if type(event) ~= "table" or type(event.type) ~= "string" then error("workspace input must be normalized", 2) end
  if event.type == "RegularTopologyObserved" then
    topology(state, event)
  elseif event.type == "FocusRegularPosition" then
    if type(event.position) ~= "number" or event.position < 1 or event.position > 9 or event.position % 1 ~= 0 then
      error("FocusRegularPosition requires a position from 1 through 9", 2)
    end
    request(state, state.regularSpaceIds[event.position])
  elseif event.type == "FocusRelativeRegular" then
    if event.delta ~= 1 and event.delta ~= -1 then error("FocusRelativeRegular requires delta 1 or -1", 2) end
    local anchor = state.switch.desiredSpaceId or state.activeRegularSpaceId or state.lastConfirmedRegularSpaceId
    if anchor then
      for index, id in ipairs(state.regularSpaceIds) do
        if id == anchor then
          local destination = ((index - 1 + event.delta) % #state.regularSpaceIds) + 1
          request(state, state.regularSpaceIds[destination])
          break
        end
      end
    end
  elseif event.type == "FocusPreviousRegular" then
    request(state, state.previousRegularSpaceId)
  elseif event.type == "RegularSwitchTimedOut" or event.type == "RegularSwitchFailed" then
    if type(event.generation) ~= "number" or event.generation < 1 or event.generation % 1 ~= 0 then
      error(event.type .. " requires a positive integer generation", 2)
    end
    if state.switch.inFlight and state.switch.inFlight.generation == event.generation then
      state.switch.inFlight, state.switch.desiredSpaceId = nil, nil
    end
  else
    error("unknown workspace input: " .. event.type, 2)
  end
  return state
end

function WorkspaceSwitch.deriveIntents(committed, event, _, previous)
  local intents, current, before = {}, committed.switch.inFlight, previous.switch.inFlight
  if current and (not before or current.generation ~= before.generation) then
    intents[#intents + 1] = { kind = "switchRegularSpace", displayId = committed.displayId,
      destinationId = current.destinationId, generation = current.generation }
  end
  if (event.type == "RegularSwitchTimedOut" or event.type == "RegularSwitchFailed")
    and before and before.generation == event.generation and not current then
    intents[#intents + 1] = { kind = "resnapshotRegularTopology", displayId = committed.displayId }
  end
  return intents
end

return WorkspaceSwitch
