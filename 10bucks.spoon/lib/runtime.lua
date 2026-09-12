-- Pure transaction boundary. Adapters submit normalized data and may observe the
-- resulting data intents, but neither receives the committed state by reference.
local Runtime = {}
Runtime.__index = Runtime

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

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("plain transaction data must not contain cycles", 3) end

  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function equivalent(left, right, seen)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end

  seen = seen or {}
  if seen[left] then return seen[left] == right end
  seen[left] = right
  for key, value in pairs(left) do
    if right[key] == nil or not equivalent(value, right[key], seen) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local function validate(runtime, candidate)
  if not plain(candidate) then error("durable state must contain plain, acyclic Lua values", 3) end
  local valid, err = runtime.validate(candidate)
  if not valid then error(err or "candidate state is invalid", 3) end
end

function Runtime.new(dependencies)
  if type(dependencies) ~= "table" or type(dependencies.reduce) ~= "function"
    or type(dependencies.validate) ~= "function" then
    error("Runtime requires initialState, reduce, and validate dependencies", 2)
  end
  if dependencies.deriveIntents ~= nil and type(dependencies.deriveIntents) ~= "function" then
    error("deriveIntents must be a function", 2)
  end
  if dependencies.observeIntents ~= nil and type(dependencies.observeIntents) ~= "function" then
    error("observeIntents must be a function", 2)
  end

  local runtime = setmetatable({
    reduce = dependencies.reduce,
    validate = dependencies.validate,
    deriveIntents = dependencies.deriveIntents or function() return {} end,
    observeIntents = dependencies.observeIntents or function() end,
    committedState = copy(dependencies.initialState),
    committedVersion = 0,
    queue = {},
    draining = false,
  }, Runtime)
  validate(runtime, runtime.committedState)
  return runtime
end

function Runtime:state()
  return copy(self.committedState)
end

function Runtime:version()
  return self.committedVersion
end

function Runtime:_process(event)
  if not plain(event) then error("normalized events must contain plain, acyclic Lua values", 2) end

  -- A reducer cannot corrupt the committed state while it is constructing a
  -- candidate. Equivalent output is a no-op and retains the committed pointer.
  local candidate = self.reduce(copy(self.committedState), event)
  validate(self, candidate)

  if not equivalent(candidate, self.committedState) then
    self.committedState = copy(candidate)
    self.committedVersion = self.committedVersion + 1
  end

  -- No-op events intentionally still derive intents. They can request a
  -- post-commit synchronization from the current, unchanged committed state.
  local intents = self.deriveIntents(copy(self.committedState), event, self.committedVersion)
  if intents == nil then intents = {} end
  if type(intents) ~= "table" or not plain(intents) then
    error("intents must contain plain, acyclic Lua data", 2)
  end
  self.observeIntents(copy(intents), self.committedVersion)
end

function Runtime:submit(event)
  self.queue[#self.queue + 1] = event
  if self.draining then return true end

  self.draining = true
  local accepted, failure = true, nil
  while #self.queue > 0 do
    local nextEvent = table.remove(self.queue, 1)
    local ok, err = pcall(self._process, self, nextEvent)
    if not ok and accepted then
      accepted, failure = false, err
    end
  end
  self.draining = false
  return accepted, failure
end

return Runtime
