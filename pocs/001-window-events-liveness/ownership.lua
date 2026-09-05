-- POC-001 pure Space-ownership correlation.  It has no Hammerspoon dependency,
-- accepts only redacted aliases, and never decides liveness or performs effects.
local Ownership = {}
Ownership.__index = Ownership

local function alias(value, kind)
  assert(type(value) == "string" and value:match("^" .. kind .. "%-%d+$"), kind .. " must be a redacted alias")
end

local function classify(memberships)
  local regular, fullscreen, unknown = {}, {}, false
  for _, membership in ipairs(memberships or {}) do
    alias(membership.space, "space")
    if membership.kind == "regular" then
      regular[#regular + 1] = membership.space
    elseif membership.kind == "fullscreen" then
      fullscreen[#fullscreen + 1] = membership.space
    else
      unknown = true
    end
  end
  if not unknown and #regular == 1 and #fullscreen == 0 then return "regular", regular[1] end
  if not unknown and #regular == 0 and #fullscreen == 1 then return "fullscreen", fullscreen[1] end
  return "unknown", nil
end

function Ownership.new()
  return setmetatable({ windows = {} }, Ownership)
end

-- `memberships` is one bounded reciprocal observation. A uniquely regular
-- result is the only fact allowed to supersede confirmed regular ownership.
function Ownership:observe(window, memberships)
  alias(window, "win")
  local record = self.windows[window] or { kind = "unknown" }
  local kind, space = classify(memberships)
  local prior_regular = record.confirmed_regular
  local changed = record.kind ~= kind or record.space ~= space
  local result = { kind = kind, space = space, retained_regular = prior_regular, changed = changed }

  if kind == "regular" then
    record.kind, record.space = kind, space
    record.confirmed_regular = space
    result.retained_regular = space
    if prior_regular and prior_regular ~= space then
      result.move = { from = prior_regular, to = space }
    end
  else
    -- Fullscreen and uncertainty are observations, not evidence that the last
    -- confirmed regular owner disappeared. Keep it for later comparison.
    record.kind, record.space = kind, space
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
