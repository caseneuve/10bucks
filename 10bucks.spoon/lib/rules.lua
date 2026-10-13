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

function Rules.ready(input)
  if not plain(input) or type(input) ~= "table" then return nil, "readiness metadata must be plain Lua data" end
  if not onlyKeys(input, {
    id = true, application = true, title = true, displayId = true, spaceId = true,
    role = true, subrole = true, modal = true, movable = true, resizable = true,
    selfProcess = true, origin = true, spaceType = true, nativeFullscreen = true,
    minimized = true, appHidden = true,
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
  for _, field in ipairs({ "modal", "movable", "resizable", "selfProcess", "minimized", "appHidden" }) do
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
    minimized = input.minimized, appHidden = input.appHidden,
    createdAfterStart = input.origin == "created",
  }
  local result = decision(metadata)
  return {
    type = "WindowReady", id = metadata.id, application = metadata.application, title = metadata.title,
    displayId = metadata.displayId, spaceId = metadata.spaceId, metadata = metadata, decision = result,
  }
end

-- RULE-001/002: user rules only narrow generic eligibility. An unavailable
-- specified field blocks later rules only when this rule could still match.
function Rules.filter(metadata, rules, generic)
  if generic.action ~= "manage" then return generic end
  for _, rule in ipairs(rules) do
    local mismatch, unknown = false, false
    for field, expected in pairs(rule.match) do
      local actual
      if field == "bundleID" then actual = metadata.application.bundleID else actual = metadata.title end
      if actual == nil then unknown = true
      elseif (field == "titlePrefix" and actual:sub(1, #expected) ~= expected)
        or (field ~= "titlePrefix" and actual ~= expected) then mismatch = true end
    end
    if not mismatch then
      if unknown then return { action = "defer", reason = "unknown-rule-field" } end
      return { action = rule.action }
    end
  end
  return { action = "manage" }
end

-- LIFE-003/STATE-001: the Host-scoped composition owner replaces its map only
-- with this reducer's output. Leases, not numeric IDs, authorize reuse/removal.
function Rules.reduce(records, event)
  assert(plain(records) and type(records) == "table" and plain(event) and type(event) == "table", "rule state/events must be plain data")
  local prior = records[event.id]
  if event.type == "WindowReady" then
    assert(validId(event.id), "rule decision requires window identity")
    if prior then return records end -- conflicting identity remains uncertainty
    local action = event.decision.action
    if action == "defer" then return records end
    assert(action == "manage" or action == "exclude", "unsupported rule action")
    assert(validId(event.resource) and validId(event.appResource) and validId(event.application.pid), "rule decision requires lifetime identities")
  elseif event.type == "WindowDestroyed" then
    if not prior or prior.resource ~= event.resource then return records end
  elseif event.type ~= "ApplicationTerminated" then
    return records
  end
  local nextRecords = {}
  for id, record in pairs(records) do nextRecords[id] = record end
  if event.type == "WindowReady" then
    local action = event.decision.action
    nextRecords[event.id] = { resource = event.resource, appResource = event.appResource,
      pid = event.application.pid, action = action }
  elseif event.type == "WindowDestroyed" then
    if not prior or prior.resource ~= event.resource then return records end
    nextRecords[event.id] = nil
  elseif event.type == "ApplicationTerminated" then
    for id, record in pairs(records) do
      if record.pid == event.pid and record.appResource == event.resource then nextRecords[id] = nil end
    end
  else
    return records
  end
  return nextRecords
end

function Rules.action(records, id, resource, appResource, pid)
  local record = records[id]
  if record and record.resource == resource and record.appResource == appResource and record.pid == pid then return record.action end
end

return Rules
