-- Direct application/UI-element observation adapter. Native handles remain here;
-- the sink receives only normalized plain Lua events.
local Rules = require("lib.rules")

local Windows = {}
Windows.__index = Windows

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
    if not plain(key, seen) or not plain(item, seen) then return false end
  end
  seen[value] = nil
  return true
end

local function detach(subscription)
  if subscription and type(subscription.detach) == "function" then subscription:detach() end
end

local function requireFunction(value, name)
  if type(value) ~= "function" then error("window adapter requires native." .. name, 3) end
end

function Windows.new(dependencies)
  if type(dependencies) ~= "table" or type(dependencies.sink) ~= "function" or type(dependencies.native) ~= "table" then
    error("window adapter requires sink and native dependencies", 2)
  end
  for _, name in ipairs({ "subscribeApplications", "subscribeExistingWindows", "subscribeWindow", "probeReadiness", "managedDecision" }) do
    requireFunction(dependencies.native[name], name)
  end
  return setmetatable({
    sink = dependencies.sink, native = dependencies.native, subscriptions = {}, cache = {},
    probeSubscriptions = {}, probing = {}, generation = 0, started = false,
  }, Windows)
end

function Windows:handleForId(id)
  local entry = self.cache[id]
  return entry and entry.handle or nil
end

function Windows:_active(generation)
  return self.started and self.generation == generation
end

function Windows:_emit(event)
  if not plain(event) then error("adapter event must be plain data", 2) end
  if self.native.recordEvent then self.native.recordEvent(event.type)
  elseif self.native.record then self.native.record("normalizedEvents") end
  return self.sink(event)
end

function Windows:_retain(id, handle, pid, resource, appResource, generation)
  local previous = self.cache[id]
  if previous and previous.resource == resource then return previous.subscription, false end
  -- A different resource for a current ID is deferred by Host. Do not detach a
  -- still-live subscription merely because a wrapper comparison differed.
  if previous then return nil, false end
  local ok, subscription = pcall(self.native.subscribeWindow, handle, function(observation)
    self:_window(observation, generation)
  end)
  if not ok or not subscription or not self:_active(generation) then detach(subscription); return nil, false end
  self.cache[id] = { handle = handle, pid = pid, resource = resource, appResource = appResource, subscription = subscription }
  return subscription, true
end

function Windows:_discardProvisional(id, resource)
  local entry = self.cache[id]
  if entry and entry.resource == resource then return false end
  if resource ~= nil and self.native.releaseWindow then self.native.releaseWindow(id, resource) end
  return true
end

function Windows:_ready(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" then return end
  if type(observation.metadata) ~= "table" then
    self:_discardProvisional(observation.id, observation.resource)
    return
  end
  -- Re-observation/exit reuses the already committed lifetime decision.
  local event = Rules.ready(observation.metadata, self.native.managedDecision(observation.metadata.id))
  if not event then
    self:_discardProvisional(observation.metadata.id, observation.resource)
    return
  end
  -- Defer/exclude facts remain reducer-visible, but their provisional Host
  -- records do not prove liveness or ownership after the decision commits.
  event.resource, event.appResource = observation.resource, observation.appResource
  local retained, created = nil, false
  if event.decision.action == "manage" and observation.handle ~= nil then
    retained, created = self:_retain(event.id, observation.handle, event.application.pid, observation.resource, observation.appResource, generation)
    if not retained then
      self:_discardProvisional(event.id, observation.resource)
      return
    end
  end
  if not self:_active(generation) then
    if event.decision.action == "manage" then
      local entry = self.cache[event.id]
      if entry and entry.resource == observation.resource then detach(entry.subscription); self.cache[event.id] = nil end
    end
    self:_discardProvisional(event.id, observation.resource)
    return
  end
  local ok, accepted = pcall(self._emit, self, event)
  if accepted == false and event.decision.action == "manage" and created then
    local entry = self.cache[event.id]
    if entry and entry.resource == observation.resource then detach(entry.subscription); self.cache[event.id] = nil end
    self:_discardProvisional(event.id, observation.resource)
  elseif event.decision.action ~= "manage" then
    self:_discardProvisional(event.id, observation.resource)
  end
  if not ok then error(accepted, 0) end
  return accepted ~= false and event.decision.action == "manage"
end

function Windows:_probe(id, generation, force)
  if not self:_active(generation) or not validId(id) or (self.cache[id] and not force) or self.probing[id] then return end
  local hadCachedResource = self.cache[id] ~= nil
  self.probing[id] = true
  local subscription, completed = nil, false
  local function completion(metadata, handle, resource, appResource)
    if completed then return end
    completed = true
    if subscription then
      detach(subscription)
      self.probeSubscriptions[subscription] = nil
    end
    if not self:_active(generation) then return end
    self.probing[id] = nil
    if type(metadata) == "table" then
      local normalized = {}
      for key, value in pairs(metadata) do normalized[key] = value end
      if type(metadata.application) == "table" then
        normalized.application = {}
        for key, value in pairs(metadata.application) do normalized.application[key] = value end
      end
      normalized.origin = "targetedReadiness"
      return self:_ready({ metadata = normalized, handle = handle, resource = resource, appResource = appResource }, generation)
    elseif not hadCachedResource then
      self:_discardProvisional(id, resource)
    end
  end
  local ok, result = pcall(self.native.probeReadiness, id, completion)
  if not ok then
    self.probing[id] = nil
    error(result, 0)
  end
  subscription = result
  if completed then
    detach(subscription)
  elseif self:_active(generation) then
    if subscription then self.probeSubscriptions[subscription] = true else self.probing[id] = nil end
  else
    self.probing[id] = nil
    detach(subscription)
  end
end

function Windows:_application(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" or not validId(observation.pid) then return end
  if observation.kind == "terminated" then
    local event = { type = "ApplicationTerminated", pid = observation.pid, resource = observation.resource }
    local ok, err = pcall(self._emit, self, event)
    for id, entry in pairs(self.cache) do
      if entry.pid == observation.pid and entry.appResource == observation.resource then
        detach(entry.subscription); self.cache[id] = nil
      end
    end
    if self.native.releaseApplication then self.native.releaseApplication(observation.pid, observation.resource) end
    if not ok then error(err, 0) end
  elseif observation.kind == "hidden" then
    self:_emit({ type = "ApplicationHidden", pid = observation.pid, resource = observation.resource })
  elseif observation.kind == "unhidden" then
    self:_emit({ type = "ApplicationUnhidden", pid = observation.pid, resource = observation.resource })
  end
end

function Windows:_window(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" then return end
  if observation.kind == "ready" then return self:_ready(observation, generation) end
  if observation.kind == "presentationEnded" then
    if validId(observation.id) and observation.presentationResource ~= nil then
      self:_emit({ type = "PresentationEnded", id = observation.id, presentationResource = observation.presentationResource })
    end
    return
  end
  if observation.kind == "focus" then
    if observation.id ~= nil and not validId(observation.id) then return end
    self:_emit({ type = "ActualFocusChanged", id = observation.id,
      title = type(observation.title) == "string" and observation.title or nil,
      applicationName = type(observation.applicationName) == "string" and observation.applicationName or nil,
      applicationPid = observation.applicationPid, resource = observation.resource,
      appResource = observation.appResource, presentationResource = observation.presentationResource,
      nativeFullscreen = observation.nativeFullscreen == true })
    if observation.id ~= nil then self:_probe(observation.id, generation) end
    return
  end
  if observation.kind == "destroyed" and validId(observation.id) then
    local entry = self.cache[observation.id]
    if not entry or entry.resource ~= observation.resource then return end
    local event = { type = "WindowDestroyed", id = observation.id, resource = observation.resource,
      presentationResource = observation.presentationResource }
    local ok, err = pcall(self._emit, self, event)
    -- Sink reduction/routing happens synchronously above. Release is protected
    -- even if that sink rejects the fact.
    if entry then detach(entry.subscription); self.cache[observation.id] = nil end
    if self.native.releaseWindow then self.native.releaseWindow(observation.id, observation.resource) end
    if not ok then error(err, 0) end
    return
  end
  local types = { minimized = "WindowMinimized", restored = "WindowRestored",
    enteredNativeFullscreen = "WindowEnteredNativeFullscreen", exitedNativeFullscreen = "WindowExitedNativeFullscreen" }
  if types[observation.kind] and validId(observation.id) then
    local entry = self.cache[observation.id]
    if not entry or entry.resource ~= observation.resource then return end
    self:_emit({ type = types[observation.kind], id = observation.id, resource = observation.resource,
      presentationResource = observation.presentationResource })
    if observation.kind == "exitedNativeFullscreen" then self:_probe(observation.id, generation, true) end
  elseif observation.kind == "titleChanged" and validId(observation.id) and type(observation.title) == "string" then
    local entry = self.cache[observation.id]
    if observation.presentationResource ~= nil then
      if observation.resource ~= nil and (not entry or entry.resource ~= observation.resource) then return end
      self:_emit({ type = "WindowTitleChanged", id = observation.id, title = observation.title,
        resource = observation.resource, presentationResource = observation.presentationResource })
      return
    end
    if not entry or entry.resource ~= observation.resource then return end
    self:_emit({ type = "WindowTitleChanged", id = observation.id, title = observation.title, resource = observation.resource })
  end
end

function Windows:discover(bootstrap)
  if not self.started then return end
  local generation = self.generation
  return self.native.subscribeExistingWindows(function(event) self:_window(event, generation) end, bootstrap == true)
end

function Windows:start()
  if self.started then return self end
  self.generation = self.generation + 1
  self.started = true
  local generation, attached = self.generation, {}
  local ok, err = pcall(function()
    attached[#attached + 1] = self.native.subscribeApplications(function(event) self:_application(event, generation) end)
    attached[#attached + 1] = self:discover(true)
  end)
  if not ok then
    for _, subscription in ipairs(attached) do detach(subscription) end
    self.started = false
    self.generation = self.generation + 1
    error(err, 0)
  end
  self.subscriptions = attached
  return self
end

function Windows:stop()
  self.started = false
  self.generation = self.generation + 1
  for _, subscription in ipairs(self.subscriptions) do detach(subscription) end
  for _, entry in pairs(self.cache) do detach(entry.subscription) end
  for subscription in pairs(self.probeSubscriptions) do detach(subscription) end
  self.subscriptions, self.probeSubscriptions, self.probing, self.cache = {}, {}, {}, {}
  return self
end

return Windows
