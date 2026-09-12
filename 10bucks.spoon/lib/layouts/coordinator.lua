-- Pure per-Space layout coordinator. Configuration and layout modules are
-- ephemeral inputs; its state is only the selected ID plus layout-owned data.
local Coordinator = {}

local function validLayoutId(value)
  return type(value) == "string" and value ~= ""
end

local function validMemberId(value)
  if type(value) == "string" then return value ~= "" end
  return type(value) == "number" and value == value
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
  if seen[value] then error("coordinator state must not contain cycles", 3) end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function arrayLength(value)
  if type(value) ~= "table" or getmetatable(value) ~= nil then return nil end
  local maximum = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return nil end
    if key > maximum then maximum = key end
  end
  for index = 1, maximum do if value[index] == nil then return nil end end
  return maximum
end

local function validateMembers(memberIds)
  local length = arrayLength(memberIds)
  if length == nil then return false, "member IDs must be a plain dense array" end
  local seen = {}
  for index = 1, length do
    if not validMemberId(memberIds[index]) or seen[memberIds[index]] then return false, "member IDs must be unique valid identities" end
    seen[memberIds[index]] = true
  end
  return true, seen
end

local function dependenciesValid(dependencies)
  if type(dependencies) ~= "table" or type(dependencies.registry) ~= "table" then
    return false, "layout coordinator requires a registry"
  end
  local ids = dependencies.layoutIds
  local length = arrayLength(ids)
  if not length or length == 0 then return false, "configured layout IDs must be a non-empty dense array" end
  local seen = {}
  for index = 1, length do
    local id = ids[index]
    if not validLayoutId(id) or seen[id] then return false, "configured layout IDs must be unique non-empty strings" end
    seen[id] = true
    local layout = dependencies.registry[id]
    if type(layout) ~= "table" then return false, "configured layout is not registered" end
    for _, method in ipairs({ "initialState", "reduce", "project", "status", "validate", "memberIds", "supports" }) do
      if type(layout[method]) ~= "function" then return false, "registered layout has an incomplete interface" end
    end
  end
  if dependencies.activeLayoutId ~= nil and not seen[dependencies.activeLayoutId] then
    return false, "configured active layout is unknown"
  end
  return true, seen
end

local function layoutContext(id, context, dependencies)
  local result = {}
  for key, value in pairs(context or {}) do result[key] = value end
  result.config = dependencies.layoutConfigs and dependencies.layoutConfigs[id]
  return result
end

local function requireDependencies(dependencies, level)
  local valid, err = dependenciesValid(dependencies)
  if not valid then error(err, level or 3) end
end

local function requireMembers(memberIds, level)
  local valid, err = validateMembers(memberIds)
  if not valid then error(err, level or 3) end
end

local function configuredIndex(ids, id)
  for index, configuredId in ipairs(ids) do if configuredId == id then return index end end
end

local function stateWith(state, activeLayoutId, layouts)
  return { activeLayoutId = activeLayoutId or state.activeLayoutId, layouts = layouts or copy(state.layouts) }
end

function Coordinator.validate(state, memberIds, context, dependencies)
  local configValid, configured = dependenciesValid(dependencies)
  if not configValid then return false, configured end
  local membersValid, allMembers = validateMembers(memberIds)
  if not membersValid then return false, allMembers end
  if not plain(state) or type(state) ~= "table" or type(state.layouts) ~= "table" then
    return false, "coordinator state must be plain active-layout state"
  end
  for key in pairs(state) do if key ~= "activeLayoutId" and key ~= "layouts" then return false, "coordinator state is malformed" end end
  if not configured[state.activeLayoutId] then return false, "active layout is not configured" end
  if state.layouts[state.activeLayoutId] == nil then return false, "active layout state is missing" end

  for id, layoutState in pairs(state.layouts) do
    if not configured[id] then return false, "retained state names an unconfigured layout" end
    local layout = dependencies.registry[id]
    local assigned = layout.memberIds(layoutState)
    local assignedValid, assignedSet = validateMembers(assigned)
    if not assignedValid then return false, assignedSet end
    for memberId in pairs(assignedSet) do if not allMembers[memberId] then return false, "retained layout contains an absent member" end end
    if id == state.activeLayoutId then
      for memberId in pairs(allMembers) do if not assignedSet[memberId] then return false, "active layout membership is incomplete" end end
    end
    local valid, err = layout.validate(layoutState, assigned, layoutContext(id, context, dependencies))
    if not valid then return false, err end
  end
  return true
end

local function requireValid(state, memberIds, context, dependencies, level)
  local valid, err = Coordinator.validate(state, memberIds, context, dependencies)
  if not valid then error(err, level or 3) end
end

-- Before an admission/removal/synchronization, the authoritative member list
-- may already describe the post-event manager state. Validate each retained
-- layout against its own assigned members first; the result is checked against
-- the supplied authoritative list by callers/tests after the transition.
local function requireRetainedValid(state, context, dependencies, level)
  local configValid, configured = dependenciesValid(dependencies)
  if not configValid then error(configured, level or 3) end
  if not plain(state) or type(state) ~= "table" or type(state.layouts) ~= "table"
    or not configured[state.activeLayoutId] or state.layouts[state.activeLayoutId] == nil then
    error("coordinator retained state is malformed", level or 3)
  end
  for id, layoutState in pairs(state.layouts) do
    if not configured[id] then error("retained state names an unconfigured layout", level or 3) end
    local assigned = dependencies.registry[id].memberIds(layoutState)
    local assignedValid, err = validateMembers(assigned)
    if not assignedValid then error(err, level or 3) end
    local valid, validationError = dependencies.registry[id].validate(layoutState, assigned, layoutContext(id, context, dependencies))
    if not valid then error(validationError, level or 3) end
  end
end

function Coordinator.initialState(memberIds, context, dependencies)
  requireDependencies(dependencies, 2)
  requireMembers(memberIds, 2)
  local activeId = dependencies.activeLayoutId or dependencies.layoutIds[1]
  local layout = dependencies.registry[activeId]
  local state = { activeLayoutId = activeId, layouts = {
    [activeId] = layout.initialState(memberIds, layoutContext(activeId, context, dependencies)),
  } }
  requireValid(state, memberIds, context, dependencies, 2)
  return state
end

local function complete(nextState, capability, memberIds, context, dependencies)
  requireValid(nextState, memberIds, context, dependencies, 3)
  return nextState, capability
end

local function pruneAbsent(state, memberIds, context, dependencies)
  local _, expected = validateMembers(memberIds)
  local layouts, changed = copy(state.layouts), false
  for id, layoutState in pairs(state.layouts) do
    local layout, nextLayout = dependencies.registry[id], layoutState
    for _, memberId in ipairs(layout.memberIds(layoutState)) do
      if not expected[memberId] then
        nextLayout = layout.reduce(nextLayout, { type = "Remove", memberId = memberId }, layoutContext(id, context, dependencies))
      end
    end
    if nextLayout ~= layoutState then layouts[id] = nextLayout; changed = true end
  end
  return changed and stateWith(state, nil, layouts) or state
end

local function synchronize(state, memberIds, context, dependencies)
  local id = state.activeLayoutId
  local layout = dependencies.registry[id]
  local nextLayout = layout.reduce(state.layouts[id], { type = "Synchronize", memberIds = copy(memberIds) }, layoutContext(id, context, dependencies))
  if nextLayout == state.layouts[id] then return state end
  local layouts = copy(state.layouts)
  layouts[id] = nextLayout
  return stateWith(state, nil, layouts)
end

function Coordinator.reduce(state, event, memberIds, context, dependencies)
  requireDependencies(dependencies, 2)
  requireMembers(memberIds, 2)
  requireRetainedValid(state, context, dependencies, 2)
  if not plain(event) or type(event) ~= "table" or type(event.type) ~= "string" then error("layout event must be plain data with a type", 2) end

  -- The reducer-owned list is authoritative for permanent membership. Prune
  -- every instantiated layout before any active-layout-only operation.
  state = pruneAbsent(state, memberIds, context, dependencies)

  if event.type == "CycleLayout" or event.type == "ActivateLayout" then
    local targetId
    if event.type == "CycleLayout" then
      local currentIndex = configuredIndex(dependencies.layoutIds, state.activeLayoutId)
      targetId = dependencies.layoutIds[(currentIndex % #dependencies.layoutIds) + 1]
    else
      targetId = event.layoutId
      if not configuredIndex(dependencies.layoutIds, targetId) then return state, { handled = false, reason = "unknown-layout" } end
    end
    local nextState = state
    if targetId ~= state.activeLayoutId then
      local layouts = copy(state.layouts)
      if not layouts[targetId] then
        layouts[targetId] = dependencies.registry[targetId].initialState(memberIds, layoutContext(targetId, context, dependencies))
      end
      nextState = stateWith(state, targetId, layouts)
    end
    return complete(synchronize(nextState, memberIds, context, dependencies), { handled = true }, memberIds, context, dependencies)
  end

  if event.type == "Synchronize" then
    return complete(synchronize(state, memberIds, context, dependencies), { handled = true }, memberIds, context, dependencies)
  end

  if event.type == "Remove" then
    local layouts, changed = copy(state.layouts), false
    for id, layoutState in pairs(state.layouts) do
      local layout = dependencies.registry[id]
      if layout.supports(event.type) then
        local nextLayout = layout.reduce(layoutState, event, layoutContext(id, context, dependencies))
        if nextLayout ~= layoutState then layouts[id] = nextLayout; changed = true end
      end
    end
    return complete(changed and stateWith(state, nil, layouts) or state, { handled = true }, memberIds, context, dependencies)
  end

  local layout = dependencies.registry[state.activeLayoutId]
  if not layout.supports(event.type) then return state, { handled = false, reason = "unsupported" } end
  local nextLayout = layout.reduce(state.layouts[state.activeLayoutId], event, layoutContext(state.activeLayoutId, context, dependencies))
  if nextLayout == state.layouts[state.activeLayoutId] then
    return complete(state, { handled = true }, memberIds, context, dependencies)
  end
  local layouts = copy(state.layouts)
  layouts[state.activeLayoutId] = nextLayout
  return complete(stateWith(state, nil, layouts), { handled = true }, memberIds, context, dependencies)
end

function Coordinator.project(state, availability, workArea, context, dependencies)
  requireDependencies(dependencies, 2)
  local members = dependencies.registry[state.activeLayoutId].memberIds(state.layouts[state.activeLayoutId])
  requireValid(state, members, context, dependencies, 2)
  local id, layout = state.activeLayoutId, dependencies.registry[state.activeLayoutId]
  return layout.project(state.layouts[id], availability, workArea, layoutContext(id, context, dependencies))
end

function Coordinator.status(state, availability, context, dependencies)
  requireDependencies(dependencies, 2)
  local members = dependencies.registry[state.activeLayoutId].memberIds(state.layouts[state.activeLayoutId])
  requireValid(state, members, context, dependencies, 2)
  local id, layout = state.activeLayoutId, dependencies.registry[state.activeLayoutId]
  return layout.status(state.layouts[id], availability, layoutContext(id, context, dependencies))
end

return Coordinator
