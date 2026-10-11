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

local function sameData(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not sameData(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
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
    managedFocusHistory = manager.focus.managedHistory,
  }
end

local function contains(ids, id)
  for _, value in ipairs(ids) do if value == id then return true end end
  return false
end

local function selectedId(coordinator, available)
  local state = coordinator.layouts[coordinator.activeLayoutId]
  if state.selectedId ~= nil then
    if not available or available[state.selectedId] then return state.selectedId end
    for index = #(state.members or {}), 1, -1 do
      if available[state.members[index]] then return state.members[index] end
    end
    return nil
  end
  if state.activeStack then
    local stack = state.stacks[state.activeStack]
    if not available or available[stack.selectedId] then return stack.selectedId end
    for index = #stack.members, 1, -1 do
      if available[stack.members[index]] then return stack.members[index] end
    end
  end
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

local function fullscreenFocusable(window)
  local life = window and window.lifecycle
  return life and life.nativeFullscreen and not life.minimized and not life.appHidden
end

local focusCommands = {
  FocusNext = true, FocusPrevious = true, FocusLeftGroup = true, FocusRightGroup = true,
  FocusTarget = true, MoveFocusedToOther = true, SwapGroups = true,
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
  -- Composition supplies this primitive authority fact for lifecycle routing to
  -- inactive retained scopes. State/layout still reduce there, but admission or
  -- recovery must not strand a pending native focus request.
  local focusAuthority = transaction.focusAuthority ~= false
  local isCommand = transaction.type == "Command"
  if not isCommand then manager = Model.reduce(manager, transaction) end
  local coordinator = current.coordinators[spaceId]
  local oldIds, newIds = members(before, spaceId), members(manager, spaceId)

  local removedSelected, recoveryGroup = false, nil
  -- Capture recovery authority from the complete pre-removal layout before
  -- any multi-member pruning can erase a later selected source.
  for _, id in ipairs(oldIds) do
    local group = groupForMember(coordinator, id)
    if not contains(newIds, id) and isGroupSelection(coordinator, id, group)
      and (not selectedGroup(coordinator) or group == selectedGroup(coordinator)) then
      removedSelected, recoveryGroup = true, group
    end
  end
  for _, id in ipairs(oldIds) do
    if not contains(newIds, id) then
      local sourceGroup = groupForMember(coordinator, id)
      local wasSelected = isGroupSelection(coordinator, id, sourceGroup)
      local needsRecovery = wasSelected and (not selectedGroup(coordinator) or sourceGroup == selectedGroup(coordinator))
      coordinator = Coordinator.reduce(coordinator,
        { type = "Remove", memberId = id, recoverSource = needsRecovery }, newIds,
        context(manager, displayId, spaceId), dependencies)
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
  if transaction.type == "WindowMinimized"
    and selectedId(coordinator) == transaction.id and not availability(manager)[transaction.id] then
    recoveryGroup = selectedGroup(coordinator)
    coordinator = Coordinator.reduce(coordinator, { type = "RecoverSource", sourceGroup = recoveryGroup }, newIds,
      context(manager, displayId, spaceId), dependencies)
    removedSelected = true
  elseif removedSelected then
    coordinator = Coordinator.reduce(coordinator, { type = "RecoverSource", sourceGroup = recoveryGroup }, newIds,
      context(manager, displayId, spaceId), dependencies)
  end
  local commandChanged, commandAccepted = false, false
  if isCommand then
    local beforeCommand = coordinator
    if transaction.name == "FocusTarget" then
      local window = manager.windows[transaction.windowId]
      commandAccepted = window ~= nil and window.placementSpaceId == spaceId
        and (availability(manager)[transaction.windowId] == true or fullscreenFocusable(window))
      if commandAccepted and availability(manager)[transaction.windowId] then
        coordinator = Coordinator.reduce(coordinator,
          { type = "ManagedFocusObserved", memberId = transaction.windowId }, newIds,
          context(manager, displayId, spaceId), dependencies)
      end
    else
      local event = { type = transaction.name }
      for key, value in pairs(transaction) do if key ~= "type" and key ~= "name" then event[key] = value end end
      local capability
      coordinator, capability = Coordinator.reduce(coordinator, event, newIds, context(manager, displayId, spaceId), dependencies)
      commandAccepted = capability.handled == true
    end
    commandChanged = coordinator ~= beforeCommand
  end
  local available = availability(manager)
  local target = transaction.name == "FocusTarget" and transaction.windowId or selectedId(coordinator, available)
  local admitted = #newIds > #oldIds
  local bootstrapAdmission = admitted and transaction.type == "WindowReady"
    and transaction.metadata and transaction.metadata.origin == "bootstrap"
  local directional = transaction.name == "FocusLeftGroup" or transaction.name == "FocusRightGroup"
  local commandFocus = isCommand and commandAccepted and focusCommands[transaction.name] and (not directional or commandChanged)
  if focusAuthority and target and (available[target] or fullscreenFocusable(manager.windows[target])) and ((admitted and not bootstrapAdmission) or removedSelected or commandFocus) then
    manager = setDesired(manager, spaceId, target, true, selectedGroup(coordinator))
  elseif focusAuthority and isCommand and commandAccepted
    and (transaction.name == "CycleLayout" or transaction.name == "ActivateLayout") and target then
    local desired = manager.focus.desiredBySpace[spaceId]
    if desired.pending then
      manager = copy(manager)
      manager.focus.desiredBySpace[spaceId].sourceGroup = selectedGroup(coordinator)
    else
      manager = setDesired(manager, spaceId, target, false, selectedGroup(coordinator))
    end
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
    deriveIntents = function(committed, input, _, previous)
      local coordinator = committed.coordinators[core.spaceId]
      local intents = {}
      local available = availability(committed.manager)
      local commandAccepted = false
      if input.type == "Command" then
        local event = { type = input.name }
        for key, value in pairs(input) do if key ~= "type" and key ~= "name" then event[key] = value end end
        local capability
        if input.name == "FocusTarget" then
          local window = committed.manager.windows[input.windowId]
          capability = { handled = window ~= nil and window.placementSpaceId == core.spaceId
              and (available[input.windowId] == true or fullscreenFocusable(window)),
            reason = "unknown-or-unavailable-target" }
        else
          _, capability = Coordinator.reduce(coordinator, event, members(committed.manager, core.spaceId),
            context(committed.manager, core.displayId, core.spaceId), core.dependencies)
        end
        commandAccepted = capability.handled == true
        if not capability.handled then intents[#intents + 1] = { kind = "result", accepted = false, reason = capability.reason } end
      end
      local desired = committed.manager.focus.desiredBySpace[core.spaceId]
      local actualId = committed.manager.focus.actualWindow.id
      -- Presentation and duplicate readiness do not synchronize geometry. Real
      -- layout/availability changes and explicit commands remain drift-correction
      -- boundaries (WIN-007). A stale focus callback cannot add such a boundary.
      local lifecycleChanged = false
      for id, window in pairs(committed.manager.windows) do
        local before = previous.manager.windows[id]
        if before and not sameData(window.lifecycle, before.lifecycle) then lifecycleChanged = true; break end
      end
      local synchronize = commandAccepted or lifecycleChanged
        or not sameData(coordinator, previous.coordinators[core.spaceId])
        or not sameData(members(committed.manager, core.spaceId), members(previous.manager, core.spaceId))
        or not sameData(available, availability(previous.manager))
        or (actualId ~= previous.manager.focus.actualWindow.id and available[actualId] == true
          and not desired.pending)
      if synchronize then
        local projected = Coordinator.project(coordinator, available, core.workArea,
          context(committed.manager, core.displayId, core.spaceId), core.dependencies)
        core.currentFrames = {}
        local emitted = {}
        for _, frame in ipairs(projected) do
          core.currentFrames[frame.windowId] = copy(frame.frame)
          if not emitted[frame.windowId] then
            emitted[frame.windowId] = true
            intents[#intents + 1] = { kind = "frame", windowId = frame.windowId,
              displayId = frame.displayId, spaceId = frame.spaceId, frame = copy(frame.frame),
              duration = 0 }
          end
        end
      end
      -- Only this transaction's newly committed request may produce an effect.
      -- Background lifecycle facts must not replay an older pending request
      -- over a newer global fullscreen target.
      local priorDesired = previous.manager.focus.desiredBySpace[core.spaceId]
      local requestsFocus = desired.generation > priorDesired.generation
      local explicitFullscreen = input.type == "Command" and input.name == "FocusTarget"
        and fullscreenFocusable(committed.manager.windows[desired.targetId])
      if requestsFocus and desired.pending and desired.targetId and (available[desired.targetId] or explicitFullscreen) then
        intents[#intents + 1] = { kind = "focus", windowId = desired.targetId, displayId = core.displayId,
          spaceId = core.spaceId, generation = desired.generation }
      end
      return intents
    end,
    observeIntents = function(intents, version)
      core.pendingIntents = core.pendingIntents or {}
      core.pendingIntents[#core.pendingIntents + 1] = { intents = copy(intents), version = version }
    end,
  })
  return core
end

function Core:frameIsCurrent(intent)
  -- Projection is derived once per synchronization transaction, not once per
  -- native window effect. This cache owns no membership/selection decisions.
  local frame = self.currentFrames and self.currentFrames[intent.windowId]
  return frame ~= nil and sameData(frame, intent.frame)
end

function Core:submit(input)
  local translated = input
  if input.type ~= "Command" and ({ CycleLayout = true, ActivateLayout = true, FocusNext = true, FocusPrevious = true,
      FocusLeftGroup = true, FocusRightGroup = true, FocusTarget = true, MoveFocusedToOther = true, SwapGroups = true,
      ResizeRatio = true, ResizeRatioDelta = true, ResetRatio = true, Synchronize = true, Reflow = true })[input.type] then
    translated = copy(input)
    translated.name = translated.type == "Reflow" and "Synchronize" or translated.type
    translated.type = "Command"
  end
  local ok, err = self.runtime:submit(translated)
  self.lastResult = ok and { accepted = true } or { accepted = false, reason = err }
  -- Execute observers after the reducer queue drains. Native callbacks can now
  -- submit/commit newer events before the old intent list resumes.
  if not self.runtime.draining then
    local pending = self.pendingIntents or {}; self.pendingIntents = {}
    for _, entry in ipairs(pending) do self.observer(entry.intents, entry.version) end
  end
  return ok, err
end

function Core:setWorkArea(nextWorkArea)
  if type(nextWorkArea) ~= "table" or type(nextWorkArea.x) ~= "number" or type(nextWorkArea.y) ~= "number"
    or type(nextWorkArea.w) ~= "number" or type(nextWorkArea.h) ~= "number" then error("work area must be primitive geometry", 2) end
  local current = self.workArea
  if current.x == nextWorkArea.x and current.y == nextWorkArea.y and current.w == nextWorkArea.w and current.h == nextWorkArea.h then return end
  self.workArea = copy(nextWorkArea)
  self.currentFrames = nil
end
function Core:state() return self.runtime:state() end
function Core:version() return self.runtime:version() end

return Core
