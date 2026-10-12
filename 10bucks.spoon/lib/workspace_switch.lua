-- Pure workspace authority. All native work consumes post-commit intents.
local WorkspaceSwitch = {}
local function id(v)
  return (type(v) == "string" and v ~= "") or (type(v) == "number" and v == v and math.abs(v) ~= math.huge)
end
local function integer(v) return type(v) == "number" and v >= 0 and v % 1 == 0 end
local function dense(ids)
  if type(ids) ~= "table" then return nil end
  local count, seen = 0, {}
  for k, v in pairs(ids) do
    if not integer(k) or k < 1 or not id(v) or seen[v] then return nil end
    count = count + 1; seen[v] = true
  end
  for i = 1, count do if ids[i] == nil then return nil end end
  return seen
end
local function same(a, b)
  if #a ~= #b then return false end
  for i, v in ipairs(a) do if b[i] ~= v then return false end end
  return true
end
local function snapshot(v)
  local regular, full = dense(v.regularSpaceIds), dense(v.fullSpaceIds)
  if not id(v.displayId) or not integer(v.revision) or not regular or not full
    or not id(v.nativeSpaceId) or not full[v.nativeSpaceId]
    or (v.nativeSpaceType ~= "user" and v.nativeSpaceType ~= "fullscreen") then return false end
  local position = 1
  for _, space in ipairs(v.fullSpaceIds) do
    if regular[space] then
      if v.regularSpaceIds[position] ~= space then return false end
      position = position + 1
    end
  end
  if position ~= #v.regularSpaceIds + 1 then return false end
  return (v.nativeSpaceType == "user") == (regular[v.nativeSpaceId] == true)
end
local function matching(op, event)
  return op and event.generation == op.generation and event.sourceId == op.sourceId
    and event.sourceType == op.sourceType and event.destinationId == op.destinationId
end
function WorkspaceSwitch.initial(input)
  assert(type(input) == "table" and snapshot(input), "workspace requires a complete native topology snapshot")
  local active = input.nativeSpaceType == "user" and input.nativeSpaceId or nil
  return { displayId = input.displayId, revision = input.revision, nativeSpaceId = input.nativeSpaceId,
    nativeSpaceType = input.nativeSpaceType, regularSpaceIds = input.regularSpaceIds, fullSpaceIds = input.fullSpaceIds,
    activeRegularSpaceId = active, lastConfirmedRegularSpaceId = active, previousRegularSpaceId = nil,
    stopped = false, switch = { nextGeneration = 0 } }
end
function WorkspaceSwitch.validate(state)
  if not snapshot(state) or type(state.stopped) ~= "boolean" then return false, "malformed workspace topology" end
  local regular = dense(state.regularSpaceIds)
  for _, key in ipairs({ "activeRegularSpaceId", "lastConfirmedRegularSpaceId", "previousRegularSpaceId" }) do
    if state[key] ~= nil and not regular[state[key]] then return false, "malformed regular history" end
  end
  if state.activeRegularSpaceId ~= (state.nativeSpaceType == "user" and state.nativeSpaceId or nil) then
    return false, "actual regular scope disagrees with native reality"
  end
  local s = state.switch
  if type(s) ~= "table" or not integer(s.nextGeneration)
    or (s.desiredSpaceId ~= nil and not regular[s.desiredSpaceId]) then return false, "malformed switch intent" end
  local op = s.inFlight
  if op and (not id(op.sourceId) or type(op.sourceType) ~= "string" or not id(op.destinationId)
    or not integer(op.generation) or op.generation < 1 or op.generation > s.nextGeneration
    or not integer(op.revision) or not dense(op.fullSpaceIds) or not dense(op.regularSpaceIds)
    or (op.phase ~= "requested" and op.phase ~= "pressed") or type(op.invalidated) ~= "boolean") then
    return false, "malformed switch operation"
  end
  if op then
    local captured = { displayId = state.displayId, revision = op.revision, nativeSpaceId = op.sourceId,
      nativeSpaceType = op.sourceType, regularSpaceIds = op.regularSpaceIds, fullSpaceIds = op.fullSpaceIds }
    if not snapshot(captured) or not dense(op.regularSpaceIds)[op.destinationId] or op.revision > state.revision then
      return false, "malformed captured operation topology"
    end
  end
  if state.stopped and (op or s.desiredSpaceId) then return false, "stopped switch retains intent" end
  return true
end
local function begin(state)
  local s = state.switch
  if state.stopped or s.inFlight or not s.desiredSpaceId then return end
  if s.desiredSpaceId == state.activeRegularSpaceId then s.desiredSpaceId = nil; return end
  s.nextGeneration = s.nextGeneration + 1
  s.inFlight = { sourceId = state.nativeSpaceId, sourceType = state.nativeSpaceType,
    destinationId = s.desiredSpaceId, generation = s.nextGeneration, revision = state.revision,
    fullSpaceIds = state.fullSpaceIds, regularSpaceIds = state.regularSpaceIds, phase = "requested", invalidated = false }
end
local function request(state, destination)
  if destination then state.switch.desiredSpaceId = destination; begin(state) end
end
function WorkspaceSwitch.reduce(state, event)
  assert(type(event) == "table" and type(event.type) == "string", "workspace input must be normalized")
  local s, kind = state.switch, event.type
  if kind == "WorkspaceSwitchStopped" then
    state.stopped = true; s.inFlight = nil; s.desiredSpaceId = nil
  elseif kind == "RegularTopologyObserved" then
    assert(snapshot(event) and event.displayId == state.displayId, "requires complete topology for this display")
    if event.revision <= state.revision then return state end
    local op, regular = s.inFlight, dense(event.regularSpaceIds)
    local confirmed = matching(op, event) and not op.invalidated and op.phase == "pressed"
      and event.nativeSpaceType == "user" and event.nativeSpaceId == op.destinationId
      and regular[op.destinationId]
    local sourceUnchanged = op and event.nativeSpaceId == op.sourceId and event.nativeSpaceType == op.sourceType
    local destinationObserved = op and event.nativeSpaceId == op.destinationId and event.nativeSpaceType == "user"
    local invalid = op and (not regular[op.destinationId]
      or (op.phase == "requested" and (not same(event.fullSpaceIds, op.fullSpaceIds)
        or not same(event.regularSpaceIds, op.regularSpaceIds) or not sourceUnchanged))
      or (op.phase == "pressed" and not sourceUnchanged and not destinationObserved))
    if op and not confirmed and invalid then
      op.invalidated = true -- retain barrier until adapter acknowledges cancellation/failure
    end
    state.revision = event.revision; state.nativeSpaceId = event.nativeSpaceId; state.nativeSpaceType = event.nativeSpaceType
    state.regularSpaceIds = event.regularSpaceIds; state.fullSpaceIds = event.fullSpaceIds
    if not regular[state.lastConfirmedRegularSpaceId] then state.lastConfirmedRegularSpaceId = nil end
    if not regular[state.previousRegularSpaceId] then state.previousRegularSpaceId = nil end
    state.activeRegularSpaceId = event.nativeSpaceType == "user" and event.nativeSpaceId or nil
    if state.activeRegularSpaceId and state.activeRegularSpaceId ~= state.lastConfirmedRegularSpaceId then
      state.previousRegularSpaceId = state.lastConfirmedRegularSpaceId
      state.lastConfirmedRegularSpaceId = state.activeRegularSpaceId
    end
    if s.desiredSpaceId and not regular[s.desiredSpaceId] then
      s.desiredSpaceId = op and regular[op.destinationId] and op.destinationId or nil
    end
    if confirmed then s.inFlight = nil; begin(state) end
  elseif state.stopped then
    return state
  elseif kind == "FocusRegularPosition" then
    assert(integer(event.position) and event.position >= 1 and event.position <= 9, "requires position 1..9")
    request(state, state.regularSpaceIds[event.position])
  elseif kind == "FocusRelativeRegular" then
    assert(event.delta == 1 or event.delta == -1, "requires delta +/-1")
    local anchor = s.desiredSpaceId or state.activeRegularSpaceId or state.lastConfirmedRegularSpaceId
    for i, space in ipairs(state.regularSpaceIds) do
      if space == anchor then request(state, state.regularSpaceIds[(i - 1 + event.delta) % #state.regularSpaceIds + 1]); break end
    end
  elseif kind == "FocusPreviousRegular" then
    request(state, state.previousRegularSpaceId)
  elseif kind == "RegularSwitchPressed" then
    if matching(s.inFlight, event) and not s.inFlight.invalidated then s.inFlight.phase = "pressed" end
  elseif kind == "RegularSwitchCancelled" then
    if matching(s.inFlight, event) and s.inFlight.invalidated then s.inFlight = nil; begin(state) end
  elseif kind == "RegularSwitchTimedOut" or kind == "RegularSwitchFailed" then
    if matching(s.inFlight, event) then s.inFlight = nil; s.desiredSpaceId = nil end
  else error("unknown workspace input: " .. kind, 2) end
  return state
end
local function operationIntent(kind, state, op)
  return { kind = kind, displayId = state.displayId, sourceId = op.sourceId, sourceType = op.sourceType,
    destinationId = op.destinationId, generation = op.generation, revision = op.revision,
    fullSpaceIds = op.fullSpaceIds, regularSpaceIds = op.regularSpaceIds }
end
function WorkspaceSwitch.deriveIntents(state, event, _, previous)
  local intents, op, before = {}, state.switch.inFlight, previous.switch.inFlight
  if event.type == "RegularTopologyObserved" and state.revision > previous.revision then
    local remaining = dense(state.regularSpaceIds)
    for _, space in ipairs(previous.regularSpaceIds) do
      if not remaining[space] then intents[#intents + 1] = { kind = "RegularSpaceRemoved", spaceId = space, revision = state.revision } end
    end
  end
  if before and not before.invalidated and ((state.stopped and not previous.stopped) or (op and op.invalidated)) then
    intents[#intents + 1] = operationIntent("cancelRegularSwitch", state, before)
  end
  if op and (not before or op.generation ~= before.generation) then
    intents[#intents + 1] = operationIntent("switchRegularSpace", state, op)
  end
  if (event.type == "RegularSwitchTimedOut" or event.type == "RegularSwitchFailed") and matching(before, event) and not op then
    intents[#intents + 1] = { kind = "resnapshotRegularTopology", displayId = state.displayId }
  end
  return intents
end
return WorkspaceSwitch
