local Model = {}

local function validId(value)
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
    if not plain(key, seen) or not plain(item, seen) then return false end
  end
  seen[value] = nil
  return true
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("durable state must not contain cycles") end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function arrayLength(value)
  if type(value) ~= "table" then return nil end
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

local function fail(message)
  return false, message
end

function Model.validate(state)
  if not plain(state) then return fail("durable state must contain plain, acyclic Lua values") end
  if type(state) ~= "table" or type(state.windows) ~= "table" or type(state.spaces) ~= "table"
    or type(state.displays) ~= "table" or type(state.focus) ~= "table" then
    return fail("state shape is malformed")
  end

  for displayId, display in pairs(state.displays) do
    if not validId(displayId) or type(display) ~= "table" or display.id ~= displayId
      or not validId(display.activeRegularSpaceId) then
      return fail("display identity is malformed")
    end
    local active = state.spaces[display.activeRegularSpaceId]
    if not active or active.displayId ~= displayId then
      return fail("display active regular Space is malformed")
    end
  end

  local memberships = {}
  for spaceId, space in pairs(state.spaces) do
    if not validId(spaceId) or type(space) ~= "table" or space.id ~= spaceId
      or not state.displays[space.displayId] or arrayLength(space.memberIds) == nil then
      return fail("regular Space identity or membership is malformed")
    end
    for _, windowId in ipairs(space.memberIds) do
      if not validId(windowId) or memberships[windowId] then
        return fail("window membership must be unique")
      end
      memberships[windowId] = spaceId
    end
  end

  for windowId, window in pairs(state.windows) do
    if not validId(windowId) or type(window) ~= "table" or window.id ~= windowId
      or type(window.application) ~= "table" or not validId(window.application.pid)
      or type(window.lifecycle) ~= "table" then
      return fail("window identity is malformed")
    end
    if type(window.lifecycle.minimized) ~= "boolean" or type(window.lifecycle.appHidden) ~= "boolean"
      or type(window.lifecycle.nativeFullscreen) ~= "boolean" then
      return fail("window lifecycle is malformed")
    end
    if type(window.observations) ~= "table"
      or (window.observations.visible ~= nil and type(window.observations.visible) ~= "boolean") then
      return fail("window observations are malformed")
    end
    if window.ruleAction ~= "manage" then return fail("managed window rule decision is malformed") end
    if window.readiness ~= nil and (type(window.readiness) ~= "table"
      or (window.readiness.origin ~= "created" and window.readiness.origin ~= "bootstrap" and window.readiness.origin ~= "targetedReadiness")
      or type(window.readiness.createdAfterStart) ~= "boolean"
      or type(window.readiness.role) ~= "string" or type(window.readiness.subrole) ~= "string"
      or type(window.readiness.modal) ~= "boolean" or type(window.readiness.movable) ~= "boolean"
      or type(window.readiness.resizable) ~= "boolean" or type(window.readiness.selfProcess) ~= "boolean") then
      return fail("window readiness is malformed")
    end
    if not state.displays[window.actualDisplayId] or not state.spaces[window.actualSpaceId]
      or state.spaces[window.actualSpaceId].displayId ~= window.actualDisplayId
      or window.placementSpaceId ~= memberships[windowId] then
      return fail("window placement is malformed")
    end
    local placement = state.spaces[window.placementSpaceId]
    if not placement or placement.displayId ~= window.actualDisplayId then
      return fail("window membership must match its display and placement")
    end
  end

  for windowId in pairs(memberships) do
    if not state.windows[windowId] then return fail("membership references an unknown window") end
  end

  if type(state.focus.actualWindow) ~= "table" or type(state.focus.managedHistory) ~= "table"
    or arrayLength(state.focus.managedHistory) == nil then
    return fail("focus state is malformed")
  end
  if state.focus.actualWindow.id ~= nil and not validId(state.focus.actualWindow.id) then
    return fail("actual focus identity is malformed")
  end
  local history = {}
  for _, windowId in ipairs(state.focus.managedHistory) do
    if not state.windows[windowId] or history[windowId] then
      return fail("managed focus history is malformed")
    end
    history[windowId] = true
  end
  return true
end

local function requireValid(state)
  local valid, err = Model.validate(state)
  if not valid then error(err, 3) end
end

function Model.new(identity)
  if type(identity) ~= "table" or not validId(identity.displayId) or not validId(identity.activeRegularSpaceId) then
    error("ManagerState requires explicit displayId and activeRegularSpaceId", 2)
  end
  local state = {
    windows = {},
    spaces = {
      [identity.activeRegularSpaceId] = {
        id = identity.activeRegularSpaceId,
        displayId = identity.displayId,
        memberIds = {},
      },
    },
    displays = {
      [identity.displayId] = {
        id = identity.displayId,
        activeRegularSpaceId = identity.activeRegularSpaceId,
      },
    },
    focus = { actualWindow = {}, managedHistory = {} },
  }
  requireValid(state)
  return state
end

function Model.isAvailable(window)
  local lifecycle = window and window.lifecycle
  return lifecycle ~= nil and not lifecycle.minimized and not lifecycle.appHidden and not lifecycle.nativeFullscreen
end

local function removeFromArray(array, value)
  for index = #array, 1, -1 do
    if array[index] == value then table.remove(array, index) end
  end
end

local function removeWindow(state, windowId)
  local window = state.windows[windowId]
  if not window then return false end
  local space = state.spaces[window.placementSpaceId]
  removeFromArray(space.memberIds, windowId)
  state.windows[windowId] = nil
  removeFromArray(state.focus.managedHistory, windowId)
  if state.focus.actualWindow.id == windowId then state.focus.actualWindow = {} end
  return true
end

local function normalizeReady(state, event)
  if not validId(event.id) or type(event.application) ~= "table" or not validId(event.application.pid)
    or not validId(event.displayId) or not validId(event.spaceId) then
    error("WindowReady must contain normalized window, application, display, and Space identities", 3)
  end
  local space = state.spaces[event.spaceId]
  if not space or space.displayId ~= event.displayId then
    error("WindowReady must name a known regular Space on its display", 3)
  end
  if not plain(event) then error("normalized events must contain plain Lua values", 3) end
  local metadata = event.metadata
  local decision = event.decision
  if metadata ~= nil or decision ~= nil then
    if type(metadata) ~= "table" or type(decision) ~= "table" or metadata.id ~= event.id
      or metadata.displayId ~= event.displayId or metadata.spaceId ~= event.spaceId
      or metadata.application ~= event.application or decision.action ~= "manage" then
      return nil
    end
  end
  return {
    id = event.id,
    application = { pid = event.application.pid, bundleID = event.application.bundleID, name = event.application.name },
    title = event.title,
    actualDisplayId = event.displayId,
    actualSpaceId = event.spaceId,
    placementSpaceId = event.spaceId,
    ruleAction = metadata and decision.action or "manage",
    readiness = metadata and {
      origin = metadata.origin, createdAfterStart = metadata.createdAfterStart,
      role = metadata.role, subrole = metadata.subrole, modal = metadata.modal,
      movable = metadata.movable, resizable = metadata.resizable, selfProcess = metadata.selfProcess,
    } or nil,
    lifecycle = { minimized = false, appHidden = false, nativeFullscreen = false },
    observations = {},
  }
end

function Model.reduce(state, event)
  requireValid(state)
  if type(event) ~= "table" or type(event.type) ~= "string" then error("event must be normalized", 2) end
  if not plain(event) then error("normalized events must contain plain Lua values", 2) end

  if event.type == "WindowReady" then
    if state.windows[event.id] then return state end
    local nextState = copy(state)
    local window = normalizeReady(nextState, event)
    if not window then return state end
    nextState.windows[window.id] = window
    table.insert(nextState.spaces[window.placementSpaceId].memberIds, window.id)
    requireValid(nextState)
    return nextState
  end

  if event.type == "WindowAbsentFromSnapshot" then
    return state
  end

  local nextState = copy(state)
  local changed = false
  if event.type == "WindowVisibilityObserved" then
    if not validId(event.id) or type(event.visible) ~= "boolean" then
      error("WindowVisibilityObserved requires an id and explicit boolean visibility", 2)
    end
    local window = nextState.windows[event.id]
    if window and window.observations.visible ~= event.visible then
      window.observations.visible = event.visible
      changed = true
    end
  elseif event.type == "WindowDestroyed" then
    if not validId(event.id) then error("WindowDestroyed requires an id", 2) end
    changed = removeWindow(nextState, event.id)
  elseif event.type == "ApplicationTerminated" then
    if not validId(event.pid) then error("ApplicationTerminated requires a pid", 2) end
    local ids = {}
    for id, window in pairs(nextState.windows) do
      if window.application.pid == event.pid then table.insert(ids, id) end
    end
    for _, id in ipairs(ids) do changed = removeWindow(nextState, id) or changed end
  elseif event.type == "WindowMinimized" or event.type == "WindowRestored"
    or event.type == "WindowEnteredNativeFullscreen" or event.type == "WindowExitedNativeFullscreen" then
    local window = nextState.windows[event.id]
    if window then
      local field = ({ WindowMinimized = "minimized", WindowRestored = "minimized", WindowEnteredNativeFullscreen = "nativeFullscreen", WindowExitedNativeFullscreen = "nativeFullscreen" })[event.type]
      local value = event.type == "WindowMinimized" or event.type == "WindowEnteredNativeFullscreen"
      if window.lifecycle[field] ~= value then window.lifecycle[field] = value; changed = true end
    end
  elseif event.type == "ApplicationHidden" or event.type == "ApplicationUnhidden" then
    if not validId(event.pid) then error(event.type .. " requires a pid", 2) end
    local value = event.type == "ApplicationHidden"
    for _, window in pairs(nextState.windows) do
      if window.application.pid == event.pid and window.lifecycle.appHidden ~= value then
        window.lifecycle.appHidden = value
        changed = true
      end
    end
  elseif event.type == "ActualFocusChanged" then
    if not validId(event.id) then error("ActualFocusChanged requires an id", 2) end
    nextState.focus.actualWindow = { id = event.id, title = event.title, applicationName = event.applicationName }
    local member = nextState.windows[event.id]
    if member then
      removeFromArray(nextState.focus.managedHistory, event.id)
      table.insert(nextState.focus.managedHistory, event.id)
    end
    changed = true
  else
    error("unknown normalized event: " .. event.type, 2)
  end

  if not changed then return state end
  requireValid(nextState)
  return nextState
end

return Model
