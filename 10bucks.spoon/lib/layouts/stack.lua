-- Pure stack layout. Availability is an ephemeral map keyed by member ID with
-- literal true for members currently available to tile or navigate; absent,
-- false, or unknown entries are unavailable for that operation.
local Stack = { id = "stack" }

function Stack.supports(eventType)
  return eventType == "Admit" or eventType == "Remove" or eventType == "ManagedFocusObserved"
    or eventType == "FocusNext" or eventType == "FocusPrevious" or eventType == "RecoverSource"
    or eventType == "Synchronize"
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

local function copyMembers(members)
  local result = {}
  for index, memberId in ipairs(members) do result[index] = memberId end
  return result
end

local function isAvailable(availability, memberId)
  return type(availability) == "table" and availability[memberId] == true
end

local function availableMembers(state, availability)
  local result = {}
  for _, memberId in ipairs(state.members) do
    if isAvailable(availability, memberId) then result[#result + 1] = memberId end
  end
  return result
end

local function copyStateWith(state, members, selectedId)
  return { members = members or copyMembers(state.members), selectedId = selectedId }
end

local function requireValid(state, memberIds, level)
  local valid, err = Stack.validate(state, memberIds)
  if not valid then error(err, level or 3) end
end

function Stack.validate(state, memberIds)
  if not plain(state) then return false, "stack state must contain plain, acyclic Lua values" end
  if type(state) ~= "table" or type(state.members) ~= "table" or state.extra ~= nil then
    return false, "stack state is malformed"
  end
  for key in pairs(state) do
    if key ~= "members" and key ~= "selectedId" then return false, "stack state is malformed" end
  end

  local expected, memberError = memberSet(memberIds)
  if not expected then return false, memberError end
  local length = arrayLength(state.members)
  if length == nil then return false, "stack members must be a plain dense array" end

  local seen = {}
  for index = 1, length do
    local memberId = state.members[index]
    if not validId(memberId) or seen[memberId] then return false, "stack members must be unique valid identities" end
    if not expected[memberId] then return false, "stack contains an unknown member" end
    seen[memberId] = true
  end
  for memberId in pairs(expected) do
    if not seen[memberId] then return false, "stack and member IDs disagree" end
  end
  if state.selectedId ~= nil and (not validId(state.selectedId) or not seen[state.selectedId]) then
    return false, "stack selection must be a member or nil"
  end
  return true
end

function Stack.initialState(memberIds)
  memberIds = memberIds or {}
  local expected, err = memberSet(memberIds)
  if not expected then error(err, 2) end
  local members = copyMembers(memberIds)
  local state = { members = members, selectedId = members[#members] }
  requireValid(state, members, 2)
  return state
end

function Stack.memberIds(state)
  if type(state) ~= "table" or type(state.members) ~= "table" then return {} end
  return copyMembers(state.members)
end

function Stack.reduce(state, event, context)
  requireValid(state, state.members, 2)
  if not plain(event) or type(event) ~= "table" or type(event.type) ~= "string" then
    error("stack event must be plain data with a type", 2)
  end

  if event.type == "Synchronize" then
    local expected, err = memberSet(event.memberIds)
    if not expected then error(err, 2) end
    local members, seen = {}, {}
    for _, memberId in ipairs(state.members) do
      if expected[memberId] then members[#members + 1] = memberId; seen[memberId] = true end
    end
    for _, memberId in ipairs(event.memberIds) do
      if not seen[memberId] then members[#members + 1] = memberId; seen[memberId] = true end
    end
    local selectedId = state.selectedId
    if selectedId ~= nil and not seen[selectedId] then selectedId = members[#members] end
    if context and validId(context.focusedMemberId) and seen[context.focusedMemberId] then
      selectedId = context.focusedMemberId
    end
    local unchanged = selectedId == state.selectedId and #members == #state.members
    if unchanged then for index, memberId in ipairs(members) do if state.members[index] ~= memberId then unchanged = false; break end end end
    if unchanged then return state end
    return copyStateWith(state, members, selectedId)
  end

  if event.type == "Admit" then
    if not validId(event.memberId) then error("Admit requires a memberId", 2) end
    for _, memberId in ipairs(state.members) do
      if memberId == event.memberId then return state end
    end
    local members = copyMembers(state.members)
    members[#members + 1] = event.memberId
    return copyStateWith(state, members, event.memberId)
  end

  if event.type == "Remove" then
    if not validId(event.memberId) then error("Remove requires a memberId", 2) end
    local removedIndex
    for index, memberId in ipairs(state.members) do
      if memberId == event.memberId then removedIndex = index; break end
    end
    if not removedIndex then return state end
    local members = copyMembers(state.members)
    table.remove(members, removedIndex)
    local selectedId = state.selectedId
    if selectedId == event.memberId then selectedId = members[#members] end
    return copyStateWith(state, members, selectedId)
  end

  if event.type == "ManagedFocusObserved" then
    if not validId(event.memberId) then error("ManagedFocusObserved requires a memberId", 2) end
    for _, memberId in ipairs(state.members) do
      if memberId == event.memberId then
        if state.selectedId == memberId then return state end
        return copyStateWith(state, nil, memberId)
      end
    end
    return state
  end

  if event.type == "RecoverSource" then
    local available = availableMembers(state, context and context.availableMembers)
    local target = available[#available]
    if not target or target == state.selectedId then return state end
    return copyStateWith(state, nil, target)
  end

  if event.type == "FocusNext" or event.type == "FocusPrevious" then
    local available = availableMembers(state, context and context.availableMembers)
    if #available == 0 then return state end
    local selectedIndex
    for index, memberId in ipairs(state.members) do
      if memberId == state.selectedId then selectedIndex = index; break end
    end
    local delta = event.type == "FocusNext" and 1 or -1
    if selectedIndex then
      for offset = 1, #state.members do
        local index = ((selectedIndex - 1 + delta * offset) % #state.members) + 1
        local memberId = state.members[index]
        if isAvailable(context and context.availableMembers, memberId) then
          if state.selectedId == memberId then return state end
          return copyStateWith(state, nil, memberId)
        end
      end
    end
    local fallback = event.type == "FocusNext" and available[1] or available[#available]
    if state.selectedId == fallback then return state end
    return copyStateWith(state, nil, fallback)
  end

  error("unsupported stack event: " .. event.type, 2)
end

function Stack.project(state, availability, workArea, context)
  requireValid(state, state.members, 2)
  if type(workArea) ~= "table" or type(workArea.x) ~= "number" or type(workArea.y) ~= "number"
    or type(workArea.w) ~= "number" or type(workArea.h) ~= "number" then
    error("stack projection requires a numeric work area", 2)
  end
  if type(context) ~= "table" or not validId(context.displayId) or not validId(context.spaceId) then
    error("stack projection requires explicit displayId and spaceId", 2)
  end

  local intents = {}
  for _, memberId in ipairs(state.members) do
    if isAvailable(availability, memberId) then
      intents[#intents + 1] = {
        windowId = memberId,
        displayId = context.displayId,
        spaceId = context.spaceId,
        frame = { x = workArea.x, y = workArea.y, w = workArea.w, h = workArea.h },
      }
    end
  end
  return intents
end

function Stack.status(state, availability)
  requireValid(state, state.members, 2)
  local members = availableMembers(state, availability)
  local position
  for index, memberId in ipairs(members) do
    if memberId == state.selectedId then position = index; break end
  end
  return { position = position, count = #members }
end

return Stack
