-- Composition-global managed-focus state. It holds only primitive descriptors;
-- native handles remain in the adapter-owned handle registry. All writes go
-- through the pure reducer below so history, unplaced fullscreen targets, and
-- global pending focus stay one coherent committed state.
local FocusHistory = {}
FocusHistory.__index = FocusHistory

local function validId(value)
  return (type(value) == "string" and value ~= "") or (type(value) == "number" and value == value)
end

local function plain(value, seen)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "string" then return true end
  if kind == "number" then return value == value end
  if kind ~= "table" or getmetatable(value) ~= nil then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  for key, item in pairs(value) do
    if not plain(key, seen) or not plain(item, seen) then seen[value] = nil; return false end
  end
  seen[value] = nil
  return true
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("focus state must not contain cycles", 3) end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function target(value)
  if type(value) ~= "table" or not validId(value.windowId) or not validId(value.spaceId) then
    error("focus target requires windowId and spaceId", 3)
  end
  return { windowId = value.windowId, spaceId = value.spaceId }
end

local function sameTarget(left, right)
  return left.windowId == right.windowId and left.spaceId == right.spaceId
end

local function removeEntry(entries, windowId)
  for index = #entries, 1, -1 do
    if entries[index].windowId == windowId then table.remove(entries, index) end
  end
end

local function emptyState()
  return { entries = {}, unplaced = {}, pending = nil }
end

local function validState(state)
  if not plain(state) or type(state) ~= "table" or type(state.entries) ~= "table" or type(state.unplaced) ~= "table" then
    return false, "focus state is malformed"
  end
  local seen = {}
  for _, entry in ipairs(state.entries) do
    if not validId(entry.windowId) or not validId(entry.spaceId) or seen[entry.windowId] then
      return false, "focus history entries are malformed"
    end
    seen[entry.windowId] = true
  end
  for windowId, record in pairs(state.unplaced) do
    if not validId(windowId) or type(record) ~= "table" or type(record.target) ~= "table"
      or record.target.windowId ~= windowId or not validId(record.target.spaceId) or not validId(record.pid) then
      return false, "unplaced fullscreen state is malformed"
    end
  end
  if state.pending ~= nil and (type(state.pending) ~= "table" or not validId(state.pending.windowId)
    or not validId(state.pending.spaceId)) then
    return false, "pending global focus is malformed"
  end
  return true
end

local function requireState(state)
  local valid, err = validState(state)
  if not valid then error(err, 3) end
end

local function registerRecord(event)
  if type(event) ~= "table" or event.type ~= "WindowReady" or type(event.metadata) ~= "table"
    or type(event.decision) ~= "table" or event.decision.action ~= "manage" then
    error("unplaced fullscreen registration requires managed WindowReady", 3)
  end
  local metadata = event.metadata
  if metadata.id ~= event.id or metadata.spaceId ~= event.spaceId or metadata.spaceType ~= "fullscreen"
    or metadata.nativeFullscreen ~= true or type(metadata.application) ~= "table"
    or not validId(metadata.application.pid) then
    error("unplaced fullscreen registration requires confirmed fullscreen metadata", 3)
  end
  return target({ windowId = event.id, spaceId = event.spaceId }), metadata.application.pid
end

-- Pure reducer. Callers receive a new plain state; no query mutates it.
function FocusHistory.reduce(state, event)
  requireState(state)
  if not plain(event) or type(event) ~= "table" or type(event.type) ~= "string" then
    error("focus history event must be plain normalized data", 2)
  end

  if event.type == "Observe" then
    local observed = target(event.target)
    if state.pending and not sameTarget(state.pending, observed) then return state end
    local newest = state.entries[#state.entries]
    if not state.pending and newest and sameTarget(newest, observed) then return state end
    local nextState = copy(state)
    removeEntry(nextState.entries, observed.windowId)
    nextState.entries[#nextState.entries + 1] = observed
    nextState.pending = nil
    return nextState
  end

  if event.type == "Request" then
    local requested = target(event.target)
    local nextState = copy(state)
    nextState.pending = requested
    return nextState
  end

  if event.type == "Cancel" then
    if not state.pending then return state end
    local nextState = copy(state)
    nextState.pending = nil
    return nextState
  end

  if event.type == "RegisterUnplaced" then
    local descriptor, pid = registerRecord(event.ready)
    local existing = state.unplaced[descriptor.windowId]
    if not existing then
      local nextState = copy(state)
      nextState.unplaced[descriptor.windowId] = { target = descriptor, pid = pid }
      return nextState
    end
    -- A later targeted probe can confirm a new native fullscreen owner for the
    -- same pre-existing window. Rebind focus descriptors in place without an
    -- MRU move or a new admission decision.
    if sameTarget(existing.target, descriptor) then return state end
    local nextState = copy(state)
    nextState.unplaced[descriptor.windowId].target = descriptor
    for _, entry in ipairs(nextState.entries) do
      if entry.windowId == descriptor.windowId then entry.spaceId = descriptor.spaceId end
    end
    if nextState.pending and nextState.pending.windowId == descriptor.windowId then nextState.pending = descriptor end
    return nextState
  end

  if event.type == "Promote" then
    local promoted = target(event.target)
    if not state.unplaced[promoted.windowId] then return state end
    local nextState = copy(state)
    nextState.unplaced[promoted.windowId] = nil
    for _, entry in ipairs(nextState.entries) do
      if entry.windowId == promoted.windowId then entry.spaceId = promoted.spaceId end
    end
    if nextState.pending and nextState.pending.windowId == promoted.windowId then nextState.pending = promoted end
    return nextState
  end

  if event.type == "Remove" then
    if not validId(event.windowId) then error("focus history removal requires windowId", 3) end
    local nextState = copy(state)
    removeEntry(nextState.entries, event.windowId)
    nextState.unplaced[event.windowId] = nil
    if nextState.pending and nextState.pending.windowId == event.windowId then nextState.pending = nil end
    return nextState
  end

  if event.type == "RemoveApplication" then
    if not validId(event.pid) then error("focus history application removal requires pid", 3) end
    local ids = {}
    for windowId, record in pairs(state.unplaced) do
      if record.pid == event.pid then ids[#ids + 1] = windowId end
    end
    if #ids == 0 then return state end
    local nextState = copy(state)
    for _, windowId in ipairs(ids) do
      removeEntry(nextState.entries, windowId)
      nextState.unplaced[windowId] = nil
      if nextState.pending and nextState.pending.windowId == windowId then nextState.pending = nil end
    end
    return nextState
  end

  if event.type == "Prune" then
    if type(event.windowIds) ~= "table" then error("focus history prune requires windowIds", 3) end
    local remove = {}
    for _, windowId in ipairs(event.windowIds) do
      if not validId(windowId) then error("focus history prune requires valid windowIds", 3) end
      remove[windowId] = true
    end
    if next(remove) == nil then return state end
    local nextState = copy(state)
    for index = #nextState.entries, 1, -1 do
      if remove[nextState.entries[index].windowId] then table.remove(nextState.entries, index) end
    end
    -- Pruning is a resolver result, not an authoritative lifecycle removal.
    -- In particular, it must never remove unplaced fullscreen ownership.
    return nextState
  end

  error("unknown focus history event: " .. event.type, 2)
end

function FocusHistory.new()
  return setmetatable({ committed = emptyState() }, FocusHistory)
end

function FocusHistory:_submit(event)
  self.committed = FocusHistory.reduce(self.committed, event)
end

function FocusHistory:observe(observed)
  self:_submit({ type = "Observe", target = target(observed) })
end

function FocusHistory:remove(windowId)
  self:_submit({ type = "Remove", windowId = windowId })
end

function FocusHistory:removeApplication(pid)
  self:_submit({ type = "RemoveApplication", pid = pid })
end

function FocusHistory:registerUnplaced(ready)
  self:_submit({ type = "RegisterUnplaced", ready = ready })
end

function FocusHistory:unplacedTarget(windowId)
  local record = self.committed.unplaced[windowId]
  if not record then return nil end
  return { target = target(record.target), pid = record.pid }
end

function FocusHistory:unplacedTargets()
  local targets = {}
  for _, record in pairs(self.committed.unplaced) do
    targets[#targets + 1] = { target = target(record.target), pid = record.pid }
  end
  return targets
end

function FocusHistory:promote(promoted)
  self:_submit({ type = "Promote", target = target(promoted) })
end

-- Commit a new global request before its native focus effect is issued.
function FocusHistory:request(requested)
  self:_submit({ type = "Request", target = target(requested) })
end

function FocusHistory:pending()
  return self.committed.pending and target(self.committed.pending) or nil
end

function FocusHistory:cancel()
  self:_submit({ type = "Cancel" })
end

-- Resolve from newest previous to oldest. Resolver failures only prune history
-- entries through a reducer event; they never infer that an unplaced target died.
function FocusHistory:previous(resolve)
  assert(type(resolve) == "function", "focus history requires a target resolver")
  local invalid = {}
  for _, candidate in ipairs(self.committed.entries) do
    if not resolve(target(candidate)) then invalid[#invalid + 1] = candidate.windowId end
  end
  if #invalid > 0 then self:_submit({ type = "Prune", windowIds = invalid }) end
  local entries = self.committed.entries
  if #entries < 2 then return nil end
  return target(entries[#entries - 1])
end

function FocusHistory:snapshot()
  return copy(self.committed.entries)
end

return FocusHistory
