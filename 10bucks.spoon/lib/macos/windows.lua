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
  self.sink(event)
end

function Windows:_retain(id, handle, pid, generation)
  local previous = self.cache[id]
  if previous and previous.handle == handle then return previous.subscription end
  local subscription = self.native.subscribeWindow(handle, function(observation)
    self:_window(observation, generation)
  end)
  if previous then detach(previous.subscription) end
  if not self:_active(generation) then detach(subscription); return end
  self.cache[id] = { handle = handle, pid = pid, subscription = subscription }
  return subscription
end

-- An already managed, still unplaced lifetime outlives an active regular host.
-- Reattach its observer without another admission or history update. Reconcile
-- an exit missed across detach/attach from the subscription's initial AX fact.
function Windows:retainManaged(id, handle, pid)
  if not self.started then return end
  local subscription = self:_retain(id, handle, pid, self.generation)
  if subscription and subscription.initialNativeFullscreen == false then
    self:_window({ kind = "exitedNativeFullscreen", id = id }, self.generation)
  end
end

function Windows:_ready(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" then return end
  if type(observation.metadata) ~= "table" then return end
  -- Re-observation/exit reuses the already committed lifetime decision.
  local event = Rules.ready(observation.metadata, self.native.managedDecision(observation.metadata.id))
  if not event then return end
  -- Defer/exclude are still reducer-visible facts, but only managed readiness
  -- owns a native handle/subscription for later effect execution.
  if event.decision.action == "manage" and observation.handle ~= nil then
    self:_retain(event.id, observation.handle, event.application.pid, generation)
    if not self:_active(generation) then return end
  end
  self:_emit(event)
  return event.decision.action == "manage"
end

function Windows:_probe(id, generation, force)
  if not self:_active(generation) or not validId(id) or (self.cache[id] and not force) or self.probing[id] then return end
  self.probing[id] = true
  local subscription, completed = nil, false
  local function completion(metadata, handle)
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
      return self:_ready({ metadata = normalized, handle = handle }, generation)
    end
  end
  subscription = self.native.probeReadiness(id, completion)
  if completed then
    detach(subscription)
  elseif self:_active(generation) then
    self.probeSubscriptions[subscription] = true
  else
    detach(subscription)
  end
end

function Windows:_application(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" or not validId(observation.pid) then return end
  if observation.kind == "terminated" then
    for id, entry in pairs(self.cache) do
      if entry.pid == observation.pid then detach(entry.subscription); self.cache[id] = nil end
    end
    self:_emit({ type = "ApplicationTerminated", pid = observation.pid })
  elseif observation.kind == "hidden" then
    self:_emit({ type = "ApplicationHidden", pid = observation.pid })
  elseif observation.kind == "unhidden" then
    self:_emit({ type = "ApplicationUnhidden", pid = observation.pid })
  end
end

function Windows:_window(observation, generation)
  if not self:_active(generation) or type(observation) ~= "table" then return end
  if observation.kind == "ready" then return self:_ready(observation, generation) end
  if observation.kind == "focus" then
    if not validId(observation.id) then return end
    self:_emit({ type = "ActualFocusChanged", id = observation.id,
      title = type(observation.title) == "string" and observation.title or nil,
      applicationName = type(observation.applicationName) == "string" and observation.applicationName or nil })
    self:_probe(observation.id, generation)
    return
  end
  if observation.kind == "destroyed" and validId(observation.id) then
    local entry = self.cache[observation.id]
    if entry then detach(entry.subscription) end
    self.cache[observation.id] = nil
    self:_emit({ type = "WindowDestroyed", id = observation.id })
    return
  end
  local types = { minimized = "WindowMinimized", restored = "WindowRestored",
    enteredNativeFullscreen = "WindowEnteredNativeFullscreen", exitedNativeFullscreen = "WindowExitedNativeFullscreen" }
  if types[observation.kind] and validId(observation.id) then
    self:_emit({ type = types[observation.kind], id = observation.id })
    if observation.kind == "exitedNativeFullscreen" then self:_probe(observation.id, generation, true) end
  elseif observation.kind == "titleChanged" and validId(observation.id) and type(observation.title) == "string" then
    self:_emit({ type = "WindowTitleChanged", id = observation.id, title = observation.title })
  end
end

function Windows:start()
  if self.started then return self end
  self.generation = self.generation + 1
  self.started = true
  local generation, attached = self.generation, {}
  local ok, err = pcall(function()
    attached[#attached + 1] = self.native.subscribeApplications(function(event) self:_application(event, generation) end)
    attached[#attached + 1] = self.native.subscribeExistingWindows(function(event) self:_window(event, generation) end)
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
