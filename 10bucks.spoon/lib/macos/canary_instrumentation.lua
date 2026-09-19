-- Private Canary A measurement owner. It is constructed only from the temporary
-- canary configuration, never from the normal default configuration.  It keeps
-- aggregate primitive facts only: no native ID, title, handle, or AX value is
-- accepted by this module.
local Instrumentation = {}
Instrumentation.__index = Instrumentation

local function copyCounts(counts)
  local result = {}
  for key, value in pairs(counts) do result[key] = value end
  return result
end

function Instrumentation.new(now)
  return setmetatable({ now = now or os.clock, counts = {}, timestamps = {}, activeTimers = 0 }, Instrumentation)
end

function Instrumentation:record(kind)
  assert(type(kind) == "string" and kind:match("^[%a][%w%.]*$") and #kind <= 80, "canary instrumentation kind must be a safe string")
  self.counts[kind] = (self.counts[kind] or 0) + 1
  self.timestamps[#self.timestamps + 1] = { kind = kind, at = self.now() }
end

function Instrumentation:recordEvent(eventType)
  assert(type(eventType) == "string" and eventType:match("^[A-Z][A-Za-z0-9]*$") and #eventType <= 80,
    "canary instrumentation event type must be a safe normalized name")
  self:record("event." .. eventType)
end

function Instrumentation:setActiveTimers(count)
  assert(type(count) == "number" and count >= 0, "canary instrumentation timer count must be non-negative")
  self.activeTimers = count
end

function Instrumentation:status()
  return { enabled = true, counts = copyCounts(self.counts), activeTimers = self.activeTimers, timestampCount = #self.timestamps }
end

function Instrumentation:export()
  local timestamps = {}
  for index, value in ipairs(self.timestamps) do timestamps[index] = { kind = value.kind, at = value.at } end
  return { enabled = true, counts = copyCounts(self.counts), activeTimers = self.activeTimers, timestamps = timestamps }
end

return Instrumentation
