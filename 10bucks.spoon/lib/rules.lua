-- Pure readiness normalization and generic admission policy. This module accepts
-- adapter-produced plain facts only; it never receives a native window handle.
local Rules = {}

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

local function onlyKeys(value, allowed)
  for key in pairs(value) do if not allowed[key] then return false end end
  return true
end

local function copyApplication(application)
  return { pid = application.pid, bundleID = application.bundleID, name = application.name }
end

local function managedDecision(value)
  if value == nil then return false end
  if type(value) ~= "table" or value.action ~= "manage" then
    return nil, "prior managed decision must be manage"
  end
  return true
end

local function decision(metadata)
  if metadata.origin == "focus" then return { action = "defer", reason = "focus-is-not-readiness" } end
  for _, field in ipairs({ "selfProcess", "role", "subrole", "modal", "movable", "resizable" }) do
    if metadata[field] == nil then return { action = "defer", reason = "unknown-" .. field } end
  end
  if metadata.selfProcess then return { action = "exclude", reason = "self-process" } end
  if metadata.role ~= "AXWindow" then return { action = "exclude", reason = "non-standard-role" } end
  if metadata.subrole ~= "AXStandardWindow" then return { action = "exclude", reason = "transient-subrole" } end
  if metadata.modal then return { action = "exclude", reason = "modal" } end
  -- Native fullscreen commonly locks AXPosition. That is not a generic
  -- floating-window exemption: it is acceptable only after both the native
  -- fullscreen lifecycle fact and fullscreen Space ownership were normalized.
  local positionLockedFullscreen = metadata.spaceType == "fullscreen" and metadata.nativeFullscreen
  if not metadata.movable and not positionLockedFullscreen then return { action = "exclude", reason = "not-movable" } end
  if not metadata.resizable then return { action = "exclude", reason = "not-resizable" } end
  return { action = "manage" }
end

function Rules.ready(input, priorManagedDecision)
  if not plain(input) or type(input) ~= "table" then return nil, "readiness metadata must be plain Lua data" end
  local prior, priorError = managedDecision(priorManagedDecision)
  if priorError then return nil, priorError end
  if not onlyKeys(input, {
    id = true, application = true, title = true, displayId = true, spaceId = true,
    role = true, subrole = true, modal = true, movable = true, resizable = true,
    selfProcess = true, origin = true, spaceType = true, nativeFullscreen = true,
  }) then return nil, "readiness metadata contains unsupported facts" end
  if not validId(input.id) or not validId(input.displayId) or not validId(input.spaceId)
    or type(input.application) ~= "table" or getmetatable(input.application) ~= nil
    or not onlyKeys(input.application, { pid = true, bundleID = true, name = true })
    or not validId(input.application.pid) then
    return nil, "readiness metadata lacks normalized identity"
  end
  if input.title ~= nil and type(input.title) ~= "string" then return nil, "title must be a string or nil" end
  if input.application.bundleID ~= nil and type(input.application.bundleID) ~= "string" then return nil, "bundleID must be a string or nil" end
  if input.application.name ~= nil and type(input.application.name) ~= "string" then return nil, "application name must be a string or nil" end
  if input.origin ~= "created" and input.origin ~= "bootstrap" and input.origin ~= "targetedReadiness" and input.origin ~= "focus" then
    return nil, "readiness origin is invalid"
  end
  if input.spaceType ~= nil and input.spaceType ~= "user" and input.spaceType ~= "fullscreen" then
    return nil, "spaceType must be user, fullscreen, or nil"
  end
  if input.nativeFullscreen ~= nil and type(input.nativeFullscreen) ~= "boolean" then
    return nil, "nativeFullscreen must be boolean or nil"
  end
  for _, field in ipairs({ "modal", "movable", "resizable", "selfProcess" }) do
    if input[field] ~= nil and type(input[field]) ~= "boolean" then return nil, field .. " must be boolean or nil" end
  end
  for _, field in ipairs({ "role", "subrole" }) do
    if input[field] ~= nil and type(input[field]) ~= "string" then return nil, field .. " must be a string or nil" end
  end

  local metadata = {
    id = input.id, application = copyApplication(input.application), title = input.title,
    displayId = input.displayId, spaceId = input.spaceId, role = input.role, subrole = input.subrole,
    modal = input.modal, movable = input.movable, resizable = input.resizable,
    selfProcess = input.selfProcess, origin = input.origin,
    spaceType = input.spaceType or "user", nativeFullscreen = input.nativeFullscreen or false,
    createdAfterStart = input.origin == "created",
  }
  -- A committed manage decision is stable across independent lifecycle
  -- readiness (for example, native-fullscreen exit). Focus remains only an
  -- observation boundary and can never turn the prior decision into admission.
  local result = prior and metadata.origin ~= "focus" and { action = "manage" } or decision(metadata)
  return {
    type = "WindowReady", id = metadata.id, application = metadata.application, title = metadata.title,
    displayId = metadata.displayId, spaceId = metadata.spaceId, metadata = metadata, decision = result,
  }
end

return Rules
