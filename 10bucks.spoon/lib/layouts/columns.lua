-- Pure columns layout. `stacks` is ordered by physical direction: left then
-- right. Availability is ephemeral and never changes this durable structure.
local Columns = { id = "columns" }

function Columns.supports(eventType)
  return eventType == "Admit" or eventType == "Remove" or eventType == "ManagedFocusObserved"
    or eventType == "FocusNext" or eventType == "FocusPrevious" or eventType == "FocusLeftGroup"
    or eventType == "FocusRightGroup" or eventType == "RecoverSource" or eventType == "MoveFocusedToOther" or eventType == "SwapGroups"
    or eventType == "ResizeRatio" or eventType == "ResizeRatioDelta" or eventType == "ResetRatio" or eventType == "Synchronize"
end

local function validId(value)
  if type(value) == "string" then return value ~= "" end
  return type(value) == "number" and value == value
end

local function arrayLength(value)
  if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
  local maximum = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
    if key > maximum then maximum = key end
  end
  for index = 1, maximum do
    if value[index] == nil then return nil end
  end
  return maximum
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
    if not plain(key, seen) or not plain(item, seen) then
      seen[value] = nil
      return false
    end
  end
  seen[value] = nil
  return true
end

local function memberSet(memberIds)
  local length = arrayLength(memberIds)
  if length == nil then return nil, "member IDs must be a plain dense array" end
  local members = {}
  for index = 1, length do
    local id = memberIds[index]
    if not validId(id) or members[id] then return nil, "member IDs must be unique valid identities" end
    members[id] = true
  end
  return members
end

local function ratioConfig(context)
  local config = context and context.config
  if type(config) ~= "table" or getmetatable(config) ~= nil then return nil, "columns requires plain ratio config" end
  local minimum, maximum, default = config.minRatio, config.maxRatio, config.defaultRatio
  if type(minimum) ~= "number" or type(maximum) ~= "number" or type(default) ~= "number"
    or minimum ~= minimum or maximum ~= maximum or default ~= default
    or minimum <= 0 or maximum >= 1 or minimum > maximum or default < minimum or default > maximum then
    return nil, "columns ratio config is invalid"
  end
  return { min = minimum, max = maximum, default = default }
end

local function copyMembers(members)
  local result = {}
  for index, memberId in ipairs(members) do result[index] = memberId end
  return result
end

local function copyStack(stack)
  return { members = copyMembers(stack.members), selectedId = stack.selectedId }
end

local function copyStacks(stacks)
  local result = {}
  for index, stack in ipairs(stacks) do result[index] = copyStack(stack) end
  return result
end

local function copyState(state, stacks, activeStack, ratio)
  return {
    stacks = stacks or copyStacks(state.stacks),
    activeStack = activeStack,
    ratio = ratio == nil and state.ratio or ratio,
  }
end

local function isAvailable(availability, memberId)
  return type(availability) == "table" and availability[memberId] == true
end

local function stackIndexForMember(state, memberId)
  for stackIndex, stack in ipairs(state.stacks) do
    for _, id in ipairs(stack.members) do
      if id == memberId then return stackIndex end
    end
  end
end

local function stackHasAvailable(stack, availability)
  for _, memberId in ipairs(stack.members) do
    if isAvailable(availability, memberId) then return true end
  end
  return false
end

local function requireValid(state, memberIds, context, level)
  local valid, err = Columns.validate(state, memberIds, context)
  if not valid then error(err, level or 3) end
end

function Columns.validate(state, memberIds, context)
  if not plain(state) then return false, "columns state must contain plain, acyclic Lua values" end
  if type(state) ~= "table" or type(state.stacks) ~= "table" then return false, "columns state is malformed" end
  for key in pairs(state) do
    if key ~= "stacks" and key ~= "activeStack" and key ~= "ratio" then return false, "columns state is malformed" end
  end
  local expected, memberError = memberSet(memberIds)
  if not expected then return false, memberError end
  local config, configError = ratioConfig(context)
  if not config then return false, configError end
  if type(state.ratio) ~= "number" or state.ratio ~= state.ratio or state.ratio < config.min or state.ratio > config.max then
    return false, "columns ratio is outside configured bounds"
  end

  local count = arrayLength(state.stacks)
  if count == nil or count > 2 then return false, "columns stacks must be a plain dense array of at most two stacks" end
  if count == 0 then
    if next(expected) ~= nil or state.activeStack ~= nil then return false, "empty columns state has invalid members or active stack" end
    return true
  end
  if type(state.activeStack) ~= "number" or state.activeStack % 1 ~= 0 or state.activeStack < 1 or state.activeStack > count then
    return false, "columns active stack is invalid"
  end

  local seen = {}
  for _, stack in ipairs(state.stacks) do
    if type(stack) ~= "table" or getmetatable(stack) ~= nil or type(stack.members) ~= "table" then
      return false, "columns stack is malformed"
    end
    for key in pairs(stack) do
      if key ~= "members" and key ~= "selectedId" then return false, "columns stack is malformed" end
    end
    local length = arrayLength(stack.members)
    if length == nil or length == 0 then return false, "columns durable stacks must be non-empty dense arrays" end
    local selected = false
    for index = 1, length do
      local memberId = stack.members[index]
      if not validId(memberId) or seen[memberId] or not expected[memberId] then
        return false, "columns members must be unique known identities"
      end
      seen[memberId] = true
      if memberId == stack.selectedId then selected = true end
    end
    if not selected then return false, "columns stack selection must be a member" end
  end
  for memberId in pairs(expected) do
    if not seen[memberId] then return false, "columns and member IDs disagree" end
  end
  return true
end

function Columns.initialState(memberIds, context)
  memberIds = memberIds or {}
  local expected, err = memberSet(memberIds)
  if not expected then error(err, 2) end
  local config, configError = ratioConfig(context)
  if not config then error(configError, 2) end

  local stacks = {}
  local count = #memberIds
  if count == 1 then
    stacks[1] = { members = { memberIds[1] }, selectedId = memberIds[1] }
  elseif count >= 2 then
    local left = {}
    for index = 1, count - 1 do left[index] = memberIds[index] end
    stacks[1] = { members = left, selectedId = left[#left] }
    stacks[2] = { members = { memberIds[count] }, selectedId = memberIds[count] }
  end
  -- New groups inherit their most recent available managed focus, not z-order
  -- or a reordering of admission membership. Existing layout states retain their
  -- own selections on later activations.
  local history = context and context.managedFocusHistory or {}
  for _, stack in ipairs(stacks) do
    for index = #history, 1, -1 do
      local id = history[index]
      if isAvailable(context.availableMembers, id) then
        local found = false
        for _, member in ipairs(stack.members) do if member == id then found = true; break end end
        if found then stack.selectedId = id; break end
      end
    end
  end
  local activeStack = #stacks > 0 and #stacks or nil
  if validId(context and context.focusedMemberId) then
    local focusedStack = stackIndexForMember({ stacks = stacks }, context.focusedMemberId)
    if focusedStack then
      activeStack = focusedStack
      stacks[focusedStack].selectedId = context.focusedMemberId
    end
  end
  local state = { stacks = stacks, activeStack = activeStack, ratio = config.default }
  requireValid(state, memberIds, context, 2)
  return state
end

function Columns.memberIds(state)
  if type(state) ~= "table" or type(state.stacks) ~= "table" then return {} end
  local members = {}
  for _, stack in ipairs(state.stacks) do
    if type(stack) == "table" and type(stack.members) == "table" then
      for _, memberId in ipairs(stack.members) do members[#members + 1] = memberId end
    end
  end
  return members
end

function Columns.reduce(state, event, context)
  requireValid(state, (function()
    local members = {}
    for _, stack in ipairs(state.stacks) do for _, id in ipairs(stack.members) do members[#members + 1] = id end end
    return members
  end)(), context, 2)
  if not plain(event) or type(event) ~= "table" or type(event.type) ~= "string" then
    error("columns event must be plain data with a type", 2)
  end
  local config, configError = ratioConfig(context)
  if not config then error(configError, 2) end

  if event.type == "Synchronize" then
    local expected, err = memberSet(event.memberIds)
    if not expected then error(err, 2) end
    local nextState = state
    local existing = Columns.memberIds(nextState)
    for _, memberId in ipairs(existing) do
      if not expected[memberId] then nextState = Columns.reduce(nextState, { type = "Remove", memberId = memberId }, context) end
    end
    for _, memberId in ipairs(event.memberIds) do
      if not stackIndexForMember(nextState, memberId) then
        nextState = Columns.reduce(nextState, { type = "Admit", memberId = memberId }, context)
      end
    end
    if context and validId(context.focusedMemberId) and stackIndexForMember(nextState, context.focusedMemberId) then
      nextState = Columns.reduce(nextState, { type = "ManagedFocusObserved", memberId = context.focusedMemberId }, context)
    end
    return nextState
  end

  if event.type == "Admit" then
    if not validId(event.memberId) then error("Admit requires a memberId", 2) end
    if stackIndexForMember(state, event.memberId) then return state end
    local stacks = copyStacks(state.stacks)
    if #stacks == 0 then
      stacks[1] = { members = { event.memberId }, selectedId = event.memberId }
      return copyState(state, stacks, 1)
    end
    if #stacks == 1 then
      stacks[2] = { members = { event.memberId }, selectedId = event.memberId }
      return copyState(state, stacks, 2)
    end
    local active = state.activeStack
    local target = stacks[active]
    target.members[#target.members + 1] = event.memberId
    target.selectedId = event.memberId
    return copyState(state, stacks, active)
  end

  if event.type == "Remove" then
    if not validId(event.memberId) then error("Remove requires a memberId", 2) end
    local stackIndex = stackIndexForMember(state, event.memberId)
    if not stackIndex then return state end
    local stacks = copyStacks(state.stacks)
    local stack = stacks[stackIndex]
    local removedIndex
    for index, memberId in ipairs(stack.members) do if memberId == event.memberId then removedIndex = index; break end end
    table.remove(stack.members, removedIndex)
    local active = state.activeStack
    local removedActiveStack = active == stackIndex or event.recoverSource == true
    if #stack.members == 0 then
      table.remove(stacks, stackIndex)
      if #stacks == 0 then
        active = nil
      else
        local survivor = stacks[1]
        -- A permanent removal must not leave columns visually identical to
        -- stack when at least two durable windows survive. Normalize surviving
        -- content to physical left and split its newest member to the right.
        if #survivor.members >= 2 then
          local rightId = table.remove(survivor.members)
          local activeId = survivor.selectedId
          if activeId == rightId then
            survivor.selectedId = survivor.members[#survivor.members]
          end
          stacks[2] = { members = { rightId }, selectedId = rightId }
          if removedActiveStack then
            -- Replace the emptied active physical side and keep focus there.
            active = stackIndex
          elseif activeId == rightId then
            active = 2
          else
            active = 1
          end
        else
          active = 1
        end
      end
    else
      if stack.selectedId == event.memberId then stack.selectedId = stack.members[#stack.members] end
      if event.recoverSource == true then active = stackIndex end
    end
    return copyState(state, stacks, active)
  end

  if event.type == "RecoverSource" then
    local source = event.sourceGroup
    if type(source) ~= "number" or source < 1 or source > #state.stacks then return state end
    local stack, target = state.stacks[source]
    for index = #(context.managedFocusHistory or {}), 1, -1 do
      local candidate = context.managedFocusHistory[index]
      if stackIndexForMember(state, candidate) == source and isAvailable(context.availableMembers, candidate) then
        target = candidate; break
      end
    end
    if not target then
      for index = #stack.members, 1, -1 do
        if isAvailable(context.availableMembers, stack.members[index]) then target = stack.members[index]; break end
      end
    end
    if not target then return state end
    local stacks = copyStacks(state.stacks)
    stacks[source].selectedId = target
    return copyState(state, stacks, source)
  end

  if event.type == "ManagedFocusObserved" then
    if not validId(event.memberId) then error("ManagedFocusObserved requires a memberId", 2) end
    local stackIndex = stackIndexForMember(state, event.memberId)
    if not stackIndex then return state end
    local stack = state.stacks[stackIndex]
    if state.activeStack == stackIndex and stack.selectedId == event.memberId then return state end
    local stacks = copyStacks(state.stacks)
    stacks[stackIndex].selectedId = event.memberId
    return copyState(state, stacks, stackIndex)
  end

  if event.type == "FocusNext" or event.type == "FocusPrevious" then
    if #state.stacks == 0 then return state end
    local stack = state.stacks[state.activeStack]
    local selectedIndex
    for index, memberId in ipairs(stack.members) do if memberId == stack.selectedId then selectedIndex = index; break end end
    local delta = event.type == "FocusNext" and 1 or -1
    local target
    for offset = 1, #stack.members do
      local index = ((selectedIndex - 1 + delta * offset) % #stack.members) + 1
      if isAvailable(context.availableMembers, stack.members[index]) then target = stack.members[index]; break end
    end
    if not target or target == stack.selectedId then return state end
    local stacks = copyStacks(state.stacks)
    stacks[state.activeStack].selectedId = target
    return copyState(state, stacks, state.activeStack)
  end

  if event.type == "FocusLeftGroup" or event.type == "FocusRightGroup" then
    local destination = event.type == "FocusLeftGroup" and 1 or 2
    if #state.stacks < destination then return state end
    local stack = state.stacks[destination]
    -- Direction is physical and idempotent. Group travel never rewrites either
    -- retained top; Core resolves the selected/top available destination member.
    if not stackHasAvailable(stack, context.availableMembers) then return state end
    if state.activeStack == destination then return state end
    return copyState(state, nil, destination)
  end

  if event.type == "MoveFocusedToOther" then
    if #state.stacks ~= 2 then return state end
    -- COL-006/FOCUS-002: composition supplies the actual authorized member.
    local sourceIndex = event.memberId and stackIndexForMember(state, event.memberId)
    if not sourceIndex then return state end
    local destinationIndex = sourceIndex == 1 and 2 or 1
    local source = state.stacks[sourceIndex]
    if #source.members < 2 then return state end
    local selectedId = event.memberId
    local selectedIndex
    for index, memberId in ipairs(source.members) do if memberId == selectedId then selectedIndex = index; break end end
    local stacks = copyStacks(state.stacks)
    local newSource, destination = stacks[sourceIndex], stacks[destinationIndex]
    table.remove(newSource.members, selectedIndex)
    newSource.selectedId = newSource.members[math.min(selectedIndex, #newSource.members)]
    destination.members[#destination.members + 1] = selectedId
    destination.selectedId = selectedId
    return copyState(state, stacks, destinationIndex)
  end

  if event.type == "SwapGroups" then
    if #state.stacks ~= 2 then return state end
    local stacks = { copyStack(state.stacks[2]), copyStack(state.stacks[1]) }
    return copyState(state, stacks, state.activeStack == 1 and 2 or 1)
  end

  if event.type == "ResizeRatio" or event.type == "ResizeRatioDelta" then
    local ratio = event.ratio
    if event.type == "ResizeRatioDelta" then
      if type(event.delta) ~= "number" or event.delta ~= event.delta then error("ResizeRatioDelta requires a numeric delta", 2) end
      ratio = math.max(config.min, math.min(config.max, state.ratio + event.delta))
    end
    if type(ratio) ~= "number" or ratio ~= ratio then error("ResizeRatio requires a numeric ratio", 2) end
    if ratio < config.min or ratio > config.max or ratio == state.ratio then return state end
    return copyState(state, nil, state.activeStack, ratio)
  end

  if event.type == "ResetRatio" then
    if state.ratio == config.default then return state end
    return copyState(state, nil, state.activeStack, config.default)
  end

  error("unsupported columns event: " .. event.type, 2)
end

function Columns.project(state, availability, workArea, context)
  local members = {}
  for _, stack in ipairs(state.stacks) do for _, id in ipairs(stack.members) do members[#members + 1] = id end end
  requireValid(state, members, context, 2)
  if type(workArea) ~= "table" or type(workArea.x) ~= "number" or type(workArea.y) ~= "number"
    or type(workArea.w) ~= "number" or type(workArea.h) ~= "number" then
    error("columns projection requires a numeric work area", 2)
  end
  if type(context) ~= "table" or not validId(context.displayId) or not validId(context.spaceId) then
    error("columns projection requires explicit displayId and spaceId", 2)
  end
  local availableStacks = {}
  for index, stack in ipairs(state.stacks) do availableStacks[index] = stackHasAvailable(stack, availability) end
  local availableCount = 0
  for _, present in pairs(availableStacks) do if present then availableCount = availableCount + 1 end end
  local intents = {}
  for index, stack in ipairs(state.stacks) do
    if availableStacks[index] then
      local frame
      if availableCount == 1 then frame = { x = workArea.x, y = workArea.y, w = workArea.w, h = workArea.h }
      elseif index == 1 then frame = { x = workArea.x, y = workArea.y, w = workArea.w * state.ratio, h = workArea.h }
      else frame = { x = workArea.x + workArea.w * state.ratio, y = workArea.y, w = workArea.w * (1 - state.ratio), h = workArea.h } end
      for _, memberId in ipairs(stack.members) do
        if isAvailable(availability, memberId) then
          intents[#intents + 1] = { windowId = memberId, displayId = context.displayId, spaceId = context.spaceId,
            frame = { x = frame.x, y = frame.y, w = frame.w, h = frame.h } }
        end
      end
    end
  end
  return intents
end

function Columns.status(state, availability, context)
  local members = {}
  for _, stack in ipairs(state.stacks) do for _, id in ipairs(stack.members) do members[#members + 1] = id end end
  -- Status has no layout context in the minimal interface. When callers do
  -- supply one, validate its configured bounds; otherwise still reject a
  -- structurally invalid physical ratio.
  local validationContext = context or { config = { minRatio = 0.000001, maxRatio = 0.999999, defaultRatio = 0.5 } }
  requireValid(state, members, validationContext, 2)
  if not state.activeStack then return { position = nil, count = 0, groupPosition = nil, groupCount = 0 } end
  local stack, available = state.stacks[state.activeStack], {}
  for _, memberId in ipairs(stack.members) do if isAvailable(availability, memberId) then available[#available + 1] = memberId end end
  local position
  for index, memberId in ipairs(available) do if memberId == stack.selectedId then position = index; break end end
  return { position = position, count = #available, groupPosition = state.activeStack, groupCount = #state.stacks }
end

return Columns
