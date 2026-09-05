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

return Correlation
