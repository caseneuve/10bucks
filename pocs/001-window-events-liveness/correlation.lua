-- POC-001 pure fixture--observer correlation bookkeeping. It retains aliases,
-- never raw AX identifiers, and does not infer lifecycle state.
local Correlation = {}
Correlation.__index = Correlation

local PREFIX = "poc001-corr-sha256-"
-- Lua patterns do not express a repeated character class, so this is kept as
-- a small explicit predicate rather than accepting a broader token grammar.
local function valid_raw(value)
  return type(value) == "string" and #value == 21 and value:sub(1, 5) == "corr-"
    and value:sub(6):match("^[A-Z2-7]+$") ~= nil
end

function Correlation.valid_alias(value)
  return type(value) == "string" and #value == #PREFIX + 64
    and value:sub(1, #PREFIX) == PREFIX and value:sub(#PREFIX + 1):match("^[0-9a-f]+$") ~= nil
end

function Correlation.alias(raw, sha256)
  if not valid_raw(raw) then return nil, "malformed" end
  local ok, digest = pcall(sha256, raw)
  if not ok or type(digest) ~= "string" or #digest ~= 64 or not digest:match("^[0-9a-f]+$") then return nil, "hash_error" end
  return PREFIX .. digest
end

function Correlation.new(sha256)
  assert(type(sha256) == "function", "sha256 is required")
  return setmetatable({ sha256 = sha256, aliases_by_window = {}, armed_generation = nil, consumed = false }, Correlation)
end

function Correlation:arm(generation)
  if self.armed_generation ~= nil and not self.consumed then return false, "already_armed" end
  if type(generation) ~= "number" or generation < 1 or generation % 1 ~= 0 then return false, "invalid_generation" end
  self.armed_generation, self.consumed = generation, false
  return true
end

function Correlation:unresolved(reason)
  if self.armed_generation == nil then return { result = "unresolved", reason = "unarmed" } end
  if self.consumed then return { result = "unresolved", reason = "duplicate" } end
  self.consumed = true
  return { result = "unresolved", reason = reason }
end

function Correlation:consume(raw_window_id, raw)
  if self.armed_generation == nil or self.consumed then return self:unresolved("duplicate") end
  self.consumed = true
  if raw == nil then return { result = "unresolved", reason = "missing" } end
  if type(raw) ~= "string" then return { result = "unresolved", reason = "non_string" } end
  local alias, reason = Correlation.alias(raw, self.sha256)
  if not alias then return { result = "unresolved", reason = reason } end
  self.aliases_by_window[tostring(raw_window_id)] = alias
  return { result = "matched", alias = alias, generation = self.armed_generation }
end

function Correlation:alias_for_window(raw_window_id)
  return self.aliases_by_window[tostring(raw_window_id)]
end

function Correlation:count()
  local count = 0
  for _ in pairs(self.aliases_by_window) do count = count + 1 end
  return count
end

function Correlation:clear()
  self.aliases_by_window, self.armed_generation, self.consumed = {}, nil, false
end

function Correlation:state()
  return { armed_generation = self.armed_generation, consumed = self.consumed }
end

function Correlation.join_aliases(fixture_alias, observer_alias)
  if not Correlation.valid_alias(fixture_alias) or not Correlation.valid_alias(observer_alias) then return false, "malformed_alias" end
  if fixture_alias ~= observer_alias then return false, "alias_mismatch" end
  return true
end

-- This diagnostic comparison is deliberately separate from alias joining.
-- Fixture ticks are converted with their frozen mach_timebase_info values;
-- observer absolute_ns is never inferred from its relative monotonic_ms.
function Correlation.close_latency(fixture_close, observer_candidate, options)
  fixture_close, observer_candidate, options = fixture_close or {}, observer_candidate or {}, options or {}
  if options.sleep_observed ~= false then return nil, "sleep_observed" end
  if fixture_close.clock_kind ~= "mach_absolute" then return nil, "fixture_clock_not_absolute" end
  local ticks, numer, denom, observed = fixture_close.ticks, fixture_close.timebase_numer, fixture_close.timebase_denom, observer_candidate.absolute_ns
  if type(numer) ~= "number" or type(denom) ~= "number" or numer <= 0 or denom <= 0
    or numer % 1 ~= 0 or denom % 1 ~= 0 then return nil, "invalid_timebase" end
  if type(ticks) ~= "number" or type(observed) ~= "number" or ticks < 0 or observed < 0
    or ticks % 1 ~= 0 or observed % 1 ~= 0 then return nil, "invalid_timestamp" end
  local quotient, remainder = ticks // denom, ticks % denom
  local max = math.maxinteger or 9223372036854775807
  if quotient > max // numer or remainder > max // numer then return nil, "conversion_overflow" end
  local whole, fractional = quotient * numer, (remainder * numer) // denom
  if whole > max - fractional then return nil, "conversion_overflow" end
  local fixture_ns = whole + fractional
  if observed < fixture_ns then return nil, "negative_or_order_invalid" end
  return observed - fixture_ns
end

return Correlation
