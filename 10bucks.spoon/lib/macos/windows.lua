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
  for _, name in ipairs({ "subscribeApplications", "subscribeExistingWindows", "subscribeWindow", "probeReadiness", "decide" }) do
    requireFunction(dependencies.native[name], name)
  end
  return setmetatable({
    sink = dependencies.sink, native = dependencies.native, withTransaction = dependencies.withTransaction or function(work) return work() end, subscriptions = {}, cache = {},
    probeSubscriptions = {}, probing = {}, generation = 0, started = false,
  }, Windows)
end

function Windows:handleForId(id)
  local entry = self.cache[id]
  return entry and entry.managed and entry.handle or nil
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
  if previous and previous.resource == resource and (previous.subscription or previous.attaching) then return previous.subscription, false end
  -- A different resource for a current ID is deferred by Host. Do not detach a
  -- still-live subscription merely because a wrapper comparison differed.
  if previous and previous.resource ~= resource then return nil, false end
  -- LIFE-004: keep the exact observed identity through attachment uncertainty.
  local entry = previous or { handle = handle, pid = pid, resource = resource, appResource = appResource }
  entry.attaching = true
  self.cache[id] = entry
  local ok, subscription = pcall(self.native.subscribeWindow, handle, function(observation)
    self:_window(observation, generation)
  end)
  if not ok or not subscription or not self:_active(generation) or self.cache[id] ~= entry then
    detach(subscription)
    entry.attaching = nil
    return nil, false
  end
  entry.attaching, entry.subscription = nil, subscription
  return subscription, true
end

local function clearCreationFullscreen(entry)
  local pending = entry.creationFullscreen
  entry.creationFullscreen = nil
  if pending then detach(pending.deadline) end
end

function Windows:_discardProvisional(id, resource)
  local entry = self.cache[id]
  if entry and entry.resource == resource then return false end
  if resource ~= nil and self.native.releaseWindow then self.native.releaseWindow(id, resource) end
  return true
end

function Windows:_ready(observation, generation)
  return self.withTransaction(function() return self:_readyTransaction(observation, generation) end)
end

function Windows:_readyTransaction(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" then return end
  if type(observation.metadata) ~= "table" then
    self:_discardProvisional(observation.id, observation.resource)
    return
  end
  local event = Rules.ready(observation.metadata)
  if not event then
    self:_discardProvisional(observation.metadata.id, observation.resource)
    return
  end
  event.resource, event.appResource = observation.resource, observation.appResource
  event.tabGroup, event.tabOwners = observation.tabGroup, observation.tabOwners
  -- STATE-002: composition commits the exact lifetime decision before attachment.
  event.decision = self.native.decide(event, observation.creationGraceElapsed)
  if event.decision.action == "defer" then
    return event.decision.reason == "await-creation" and "await-creation" or "uncertain"
  end
  local retained, created = nil, false
  if observation.handle ~= nil then
    retained, created = self:_retain(event.id, observation.handle, event.application.pid, observation.resource, observation.appResource, generation)
    if not retained then
      return false
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
  if self.native.current and not self.native.current(event.id, event.resource, event.appResource, event.application.pid) then return false end
  local entry = self.cache[event.id]
  local previouslyManaged = entry and entry.managed
  if entry then
    -- FS-002/DISC-002: a transition during attachment invalidates the
    -- pre-attachment ownership fact. Reuse targeted readiness before placement;
    -- never project a regular slot from that stale ownership snapshot.
    local fullscreenChanged = entry.availability and entry.availability.nativeFullscreen ~= nil
      and entry.availability.nativeFullscreen ~= event.metadata.nativeFullscreen
    for field, value in pairs(entry.availability or {}) do event.metadata[field] = value end
    entry.availability = nil
    if fullscreenChanged then
      self:_probe(event.id, generation, true)
      return false
    end
    -- FS-004: no membership or effects from regular readiness while a
    -- creation request is unsettled. Confirmed fullscreen needs no slot.
    if entry.creationFullscreen then
      if event.metadata.spaceType ~= "fullscreen" then return false end
      clearCreationFullscreen(entry)
    elseif event.decision.createFullscreen then
      local pending = {}
      entry.creationFullscreen = pending
      local function fallback()
        if not self:_active(generation) or self.cache[event.id] ~= entry
          or entry.creationFullscreen ~= pending then return end
        clearCreationFullscreen(entry)
        self:_probe(event.id, generation, true)
      end
      local deadline = self.native.requestCreationFullscreen(event, fallback)
      if entry.creationFullscreen ~= pending then detach(deadline)
      elseif deadline then pending.deadline = deadline
      else fallback() end
      return false -- never publish the pre-request ownership snapshot
    end
    entry.managed = event.decision.action == "manage"
  end
  local ok, accepted = pcall(self._emit, self, event)
  local committed = not ok and self.native.committed and self.native.committed(event)
  if ((ok and accepted ~= false) or committed) and entry and event.decision.action == "manage" and self.native.enableManaged then
    self.native.enableManaged(event.id, event.resource)
  end
  -- A refused admission does not revoke a committed native lifetime. Retry at
  -- an existing readiness boundary with the same identity and observation.
  if (not ok or accepted == false) and not committed and entry then entry.managed = previouslyManaged end
  if not ok then error(accepted, 0) end
  if accepted == false then return false end
  return event.decision.action == "exclude" and "excluded" or true
end

function Windows:_probe(id, generation, force)
  if not self:_active(generation) or not validId(id) or (self.cache[id] and self.cache[id].subscription and not force) or self.probing[id] then return end
  local hadCachedResource = self.cache[id] ~= nil
  self.probing[id] = true
  local subscription, completed = nil, false
  local function completion(metadata, handle, resource, appResource, tabGroup, tabOwners)
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
      return self:_ready({ metadata = normalized, handle = handle, resource = resource, appResource = appResource,
        tabGroup = tabGroup, tabOwners = tabOwners }, generation)
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
  if self.native.appCurrent and not self.native.appCurrent(observation.pid, observation.resource) then return end
  if observation.kind == "hidden" or observation.kind == "unhidden" then
    for _, entry in pairs(self.cache) do
      if entry.attaching and entry.pid == observation.pid and entry.appResource == observation.resource then
        entry.availability = entry.availability or {}; entry.availability.appHidden = observation.kind == "hidden"
      end
    end
  end
  if observation.kind == "terminated" then
    local event = { type = "ApplicationTerminated", pid = observation.pid, resource = observation.resource }
    local ok, err = pcall(self._emit, self, event)
    for id, entry in pairs(self.cache) do
      if entry.pid == observation.pid and entry.appResource == observation.resource then
        clearCreationFullscreen(entry)
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
    local function emitFocus()
      local entry = observation.id and self.cache[observation.id]
      -- Tabs may change native ID without AXWindowCreated. Readiness must carry
      -- the selection and peer availability together, before focus projection.
      if observation.tabGroup and not entry then self:_probe(observation.id, generation) end
      self:_emit({ type = "ActualFocusChanged", id = observation.id,
        title = type(observation.title) == "string" and observation.title or nil,
        applicationName = type(observation.applicationName) == "string" and observation.applicationName or nil,
        applicationPid = observation.applicationPid, resource = observation.resource,
        appResource = observation.appResource, presentationResource = observation.presentationResource,
        nativeFullscreen = observation.nativeFullscreen == true, tabGroup = observation.tabGroup, tabOwners = observation.tabOwners })
      if observation.id ~= nil and (not observation.tabGroup or entry) then
        self:_probe(observation.id, generation, entry and entry.creationFullscreen ~= nil)
      end
    end
    if observation.tabGroup then self.withTransaction(emitFocus) else emitFocus() end
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
    clearCreationFullscreen(entry)
    detach(entry.subscription); self.cache[observation.id] = nil
    if self.native.releaseWindow then self.native.releaseWindow(observation.id, observation.resource) end
    if not ok then error(err, 0) end
    return
  end
  local types = { minimized = "WindowMinimized", restored = "WindowRestored",
    enteredNativeFullscreen = "WindowEnteredNativeFullscreen", exitedNativeFullscreen = "WindowExitedNativeFullscreen" }
  if types[observation.kind] and validId(observation.id) then
    local entry = self.cache[observation.id]
    if not entry or entry.resource ~= observation.resource then return end
    if entry.attaching then
      local field = (observation.kind == "minimized" or observation.kind == "restored") and "minimized" or "nativeFullscreen"
      entry.availability = entry.availability or {}
      entry.availability[field] = observation.kind == "minimized" or observation.kind == "enteredNativeFullscreen"
      return
    end
    if entry.creationFullscreen and observation.kind == "enteredNativeFullscreen" then
      self:_probe(observation.id, generation, true)
      return
    end
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
  return self.native.subscribeExistingWindows(function(event) return self:_window(event, generation) end, bootstrap == true)
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
  if not self:_active(generation) then
    for _, subscription in ipairs(attached) do detach(subscription) end
    return self
  end
  self.subscriptions = attached
  return self
end

function Windows:stop()
  self.started = false
  self.generation = self.generation + 1
  for _, subscription in ipairs(self.subscriptions) do detach(subscription) end
  for _, entry in pairs(self.cache) do
    clearCreationFullscreen(entry)
    detach(entry.subscription)
  end
  for subscription in pairs(self.probeSubscriptions) do detach(subscription) end
  self.subscriptions, self.probeSubscriptions, self.probing, self.cache = {}, {}, {}, {}
  return self
end

return Windows
