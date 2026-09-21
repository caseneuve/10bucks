-- Pure replacement engine for one explicit display/current regular Space.
-- It composes the manager reducer with a per-Space layout coordinator, commits
-- their single composite state through Runtime, and publishes only plain intents.
local Model = require("lib.model")
local Runtime = require("lib.runtime")
local Coordinator = require("lib.layouts.coordinator")

local Core = {}
Core.__index = Core

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("core data must not contain cycles", 3) end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function validId(value)
  return (type(value) == "string" and value ~= "") or (type(value) == "number" and value == value)
end

local function members(manager, spaceId)
  return manager.spaces[spaceId].memberIds
end

local function availability(manager)
  local result = {}
  for id, window in pairs(manager.windows) do result[id] = Model.isAvailable(window) end
  return result
end

local function context(manager, displayId, spaceId)
  local actual = manager.focus.actualWindow.id
  local available = availability(manager)
  local desired = manager.focus.desiredBySpace[spaceId]
  local focused = desired and desired.pending and desired.targetId
    and available[desired.targetId] and desired.targetId or nil
  if not focused then focused = manager.windows[actual] and available[actual] and actual or nil end
  if not focused then
    for index = #manager.focus.managedHistory, 1, -1 do
      local candidate = manager.focus.managedHistory[index]
      local window = manager.windows[candidate]
      if window and window.placementSpaceId == spaceId and available[candidate] then
        focused = candidate
        break
      end
    end
  end
  return {
    displayId = displayId,
    spaceId = spaceId,
    availableMembers = available,
    -- Layout activation follows actual managed focus, or the last available
    -- managed focus when a popup/unmanaged window currently owns macOS focus.
    focusedMemberId = focused,
  }
end

local function contains(ids, id)
  for _, value in ipairs(ids) do if value == id then return true end end
  return false
end

local function selectedId(coordinator)
  local state = coordinator.layouts[coordinator.activeLayoutId]
  if state.selectedId ~= nil then return state.selectedId end
  if state.activeStack then return state.stacks[state.activeStack].selectedId end
  return nil
end

local function selectedGroup(coordinator)
  local state = coordinator.layouts[coordinator.activeLayoutId]
  return state.activeStack
end

local function groupForMember(coordinator, memberId)
  local state = coordinator.layouts[coordinator.activeLayoutId]
  if state.stacks then
    for index, stack in ipairs(state.stacks) do
      for _, id in ipairs(stack.members) do if id == memberId then return index end end
    end
  elseif state.selectedId == memberId then
    return 1
  end
end

local function isGroupSelection(coordinator, memberId, group)
  local state = coordinator.layouts[coordinator.activeLayoutId]
  if state.stacks then return group and state.stacks[group].selectedId == memberId end
  return state.selectedId == memberId
end

local function setDesired(manager, spaceId, targetId, pending, sourceGroup)
  local nextManager = copy(manager)
  local previous = nextManager.focus.desiredBySpace[spaceId]
  nextManager.focus.desiredBySpace[spaceId] = {
    targetId = targetId,
    pending = pending == true,
    generation = previous.generation + (pending and 1 or 0),
    sourceGroup = sourceGroup,
  }
  return nextManager
end

local focusCommands = {
  FocusNext = true, FocusPrevious = true, FocusNextGroup = true, FocusPreviousGroup = true,
  MoveFocusedToOther = true, SwapGroups = true,
}

local function validateComposite(state, displayId, spaceId, dependencies)
  if type(state) ~= "table" or type(state.manager) ~= "table" or type(state.coordinators) ~= "table" then
    return false, "core composite state is malformed"
  end
  local valid, err = Model.validate(state.manager)
  if not valid then return false, err end
  local space = state.manager.spaces[spaceId]
  if not space or space.displayId ~= displayId or not state.coordinators[spaceId] then
    return false, "core scope identity is malformed"
  end
  return Coordinator.validate(state.coordinators[spaceId], members(state.manager, spaceId),
    context(state.manager, displayId, spaceId), dependencies)
end

local function reduceComposite(current, transaction, displayId, spaceId, dependencies)
  if type(transaction) ~= "table" or type(transaction.type) ~= "string" then error("core input must be a normalized event or command", 2) end
  local before, manager = current.manager, current.manager
  local isCommand = transaction.type == "Command"
  if not isCommand then manager = Model.reduce(manager, transaction) end
  local coordinator = current.coordinators[spaceId]
  local oldIds, newIds = members(before, spaceId), members(manager, spaceId)

  local removedSelected, recoveryGroup = false, nil
  for _, id in ipairs(oldIds) do
    if not contains(newIds, id) then
      local sourceGroup = groupForMember(coordinator, id)
      local wasSelected = isGroupSelection(coordinator, id, sourceGroup)
      coordinator = Coordinator.reduce(coordinator,
        { type = "Remove", memberId = id, recoverSource = wasSelected }, newIds,
        context(manager, displayId, spaceId), dependencies)
      if wasSelected then removedSelected, recoveryGroup = true, sourceGroup end
    end
  end
  for _, id in ipairs(newIds) do
    if not contains(oldIds, id) then
      coordinator = Coordinator.reduce(coordinator, { type = "Admit", memberId = id }, newIds,
        context(manager, displayId, spaceId), dependencies)
    end
  end
  if transaction.type == "ActualFocusChanged" and manager.windows[transaction.id] then
    local priorDesired = before.focus.desiredBySpace[spaceId]
    if not priorDesired.pending or priorDesired.targetId == transaction.id then
      coordinator = Coordinator.reduce(coordinator, { type = "ManagedFocusObserved", memberId = transaction.id }, newIds,
        context(manager, displayId, spaceId), dependencies)
      manager = setDesired(manager, spaceId, transaction.id, false, selectedGroup(coordinator))
    end
  end
  if (transaction.type == "WindowMinimized" or transaction.type == "WindowEnteredNativeFullscreen")
    and selectedId(coordinator) == transaction.id and not availability(manager)[transaction.id] then
    recoveryGroup = selectedGroup(coordinator)
    coordinator = Coordinator.reduce(coordinator, { type = "RecoverSource", sourceGroup = recoveryGroup }, newIds,
      context(manager, displayId, spaceId), dependencies)
    removedSelected = true
  elseif removedSelected then
    coordinator = Coordinator.reduce(coordinator, { type = "RecoverSource", sourceGroup = recoveryGroup }, newIds,
      context(manager, displayId, spaceId), dependencies)
  end
  if isCommand then
    local event = { type = transaction.name }
    for key, value in pairs(transaction) do if key ~= "type" and key ~= "name" then event[key] = value end end
    coordinator = Coordinator.reduce(coordinator, event, newIds, context(manager, displayId, spaceId), dependencies)
  end
  local target = selectedId(coordinator)
  local admitted = #newIds > #oldIds
  if target and (admitted or removedSelected or (isCommand and focusCommands[transaction.name])) then
    manager = setDesired(manager, spaceId, target, true, selectedGroup(coordinator))
  elseif isCommand and (transaction.name == "CycleLayout" or transaction.name == "ActivateLayout") and target then
    manager = setDesired(manager, spaceId, target, false, selectedGroup(coordinator))
  end
  -- Admission/removal are propagated explicitly above, focus observations use
  -- ManagedFocusObserved, and layout activation synchronizes internally. Do not
  -- run a blanket synchronization for title/lifecycle callbacks: one commonly
  -- arrives between admission and native focus completion and would overwrite
  -- the newer desired selection with stale actual focus.
  return { manager = manager, coordinators = { [spaceId] = coordinator } }
end

function Core.new(options)
  if type(options) ~= "table" or not validId(options.displayId) or not validId(options.regularSpaceId)
    or type(options.workArea) ~= "table" or type(options.layoutDependencies) ~= "table" then
    error("Core requires explicit displayId, regularSpaceId, workArea, and layout dependencies", 2)
  end
  if options.observeIntents ~= nil and type(options.observeIntents) ~= "function" then error("observeIntents must be a function", 2) end
  local initialManager = options.initialModelState or Model.new({ displayId = options.displayId, activeRegularSpaceId = options.regularSpaceId })
  local initial = { manager = copy(initialManager), coordinators = {} }
  initial.coordinators[options.regularSpaceId] = options.initialCoordinatorState or Coordinator.initialState(
    members(initial.manager, options.regularSpaceId), context(initial.manager, options.displayId, options.regularSpaceId), options.layoutDependencies)

  local core = setmetatable({ displayId = options.displayId, spaceId = options.regularSpaceId,
    workArea = copy(options.workArea), dependencies = options.layoutDependencies, lastResult = { accepted = true }, observer = options.observeIntents or function() end }, Core)
  core.runtime = Runtime.new({
    initialState = initial,
    reduce = function(state, input) return reduceComposite(state, input, core.displayId, core.spaceId, core.dependencies) end,
    validate = function(state) return validateComposite(state, core.displayId, core.spaceId, core.dependencies) end,
    deriveIntents = function(committed, input)
      local coordinator = committed.coordinators[core.spaceId]
      local intents = {}
      local projected = Coordinator.project(coordinator, availability(committed.manager), core.workArea,
        context(committed.manager, core.displayId, core.spaceId), core.dependencies)
      local emitted = {}
      for _, frame in ipairs(projected) do
        if not emitted[frame.windowId] then emitted[frame.windowId] = true; intents[#intents + 1] = { kind = "frame", windowId = frame.windowId,
          displayId = frame.displayId, spaceId = frame.spaceId, frame = copy(frame.frame), duration = 0 } end
      end
      if input.type == "Command" then
        local event = { type = input.name }
        for key, value in pairs(input) do if key ~= "type" and key ~= "name" then event[key] = value end end
        local _, capability = Coordinator.reduce(coordinator, event, members(committed.manager, core.spaceId),
          context(committed.manager, core.displayId, core.spaceId), core.dependencies)
        if not capability.handled then intents[#intents + 1] = { kind = "result", accepted = false, reason = capability.reason } end
      end
      local desired = committed.manager.focus.desiredBySpace[core.spaceId]
      local available = availability(committed.manager)
      local requestsFocus = input.type == "WindowReady" or input.type == "WindowDestroyed"
        or input.type == "ApplicationTerminated" or input.type == "WindowMinimized"
        or input.type == "WindowEnteredNativeFullscreen"
        or (input.type == "Command" and focusCommands[input.name])
      if requestsFocus and desired.pending and desired.targetId and available[desired.targetId] then
        intents[#intents + 1] = { kind = "focus", windowId = desired.targetId, displayId = core.displayId,
          spaceId = core.spaceId, generation = desired.generation }
      end
      return intents
    end,
    observeIntents = function(intents, version) core.observer(copy(intents), version) end,
  })
  return core
end

function Core:submit(input)
  local translated = input
  if input.type ~= "Command" and ({ CycleLayout = true, ActivateLayout = true, FocusNext = true, FocusPrevious = true,
      FocusNextGroup = true, FocusPreviousGroup = true, MoveFocusedToOther = true, SwapGroups = true,
      ResizeRatio = true, ResizeRatioDelta = true, ResetRatio = true, Synchronize = true, Reflow = true })[input.type] then
    translated = copy(input)
    translated.name = translated.type == "Reflow" and "Synchronize" or translated.type
    translated.type = "Command"
  end
  local ok, err = self.runtime:submit(translated)
  self.lastResult = ok and { accepted = true } or { accepted = false, reason = err }
  return ok, err
end

function Core:state() return self.runtime:state() end
function Core:version() return self.runtime:version() end

return Core
