-- POC-001 pure Space-ownership correlation. It accepts redacted reciprocal
-- observations only; it never decides liveness or performs effects.
local Ownership = {}
Ownership.__index = Ownership

local function alias(value, kind)
  assert(type(value) == "string" and value:match("^" .. kind .. "%-%d+$"), kind .. " must be a redacted alias")
end

local function classify(memberships)
  local regular, fullscreen, unknown, reciprocal = {}, {}, false, 0
  for _, membership in ipairs(memberships or {}) do
    alias(membership.space, "space")
    if membership.reciprocal == true then reciprocal = reciprocal + 1 else unknown = true end
    if membership.kind == "regular" then regular[#regular + 1] = membership.space
    elseif membership.kind == "fullscreen" then fullscreen[#fullscreen + 1] = membership.space
    else unknown = true end
  end
  local count = #(memberships or {})
  if count == 0 then return "unknown", nil, "missing", reciprocal end
  if unknown then return "unknown", nil, "query_error", reciprocal end
  if #regular == 1 and #fullscreen == 0 and reciprocal == 1 then return "regular", regular[1], "unique_regular", reciprocal end
  if #regular == 0 and #fullscreen == 1 and reciprocal == 1 then return "fullscreen", fullscreen[1], "fullscreen", reciprocal end
  return "unknown", nil, "ambiguous", reciprocal
end

function Ownership.new()
  return setmetatable({ windows = {} }, Ownership)
end

-- Only a uniquely regular reciprocal observation may supersede confirmed
-- regular ownership. Fullscreen, missing, failed, and ambiguous evidence keep
-- the prior owner and are explicitly non-moving outcomes.
function Ownership:observe(window, memberships)
  alias(window, "win")
  local record = self.windows[window] or { kind = "unknown" }
  local kind, space, reason, reciprocal_count = classify(memberships)
  local prior_regular = record.confirmed_regular
  local changed = record.kind ~= kind or record.space ~= space
  local result = {
    kind = kind, space = space, reason = reason,
    membership_count = #(memberships or {}), reciprocal_confirmed_count = reciprocal_count,
    retained_regular = prior_regular, changed = changed,
  }

  if kind == "regular" then
    record.kind, record.space, record.confirmed_regular = kind, space, space
    result.retained_regular = space
    if prior_regular and prior_regular ~= space then
      result.move = { from = prior_regular, to = space }
    elseif prior_regular == space then
      result.reason, result.no_regular_move = "same_regular", true
    end
  else
    record.kind, record.space = kind, space
    result.no_regular_move = true
  end
  self.windows[window] = record
  return result
end

function Ownership:window(window)
  local record = self.windows[window]
  if not record then return nil end
  return { kind = record.kind, space = record.space, confirmed_regular = record.confirmed_regular }
end

return Ownership
