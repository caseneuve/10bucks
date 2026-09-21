-- Composition-global confirmed managed focus history. Entries are plain target
-- descriptors; native handles remain in the separate ephemeral registry.
local FocusHistory = {}
FocusHistory.__index = FocusHistory

local function validId(value)
  return (type(value) == "string" and value ~= "") or (type(value) == "number" and value == value)
end

local function copy(target)
  return { windowId = target.windowId, spaceId = target.spaceId }
end

function FocusHistory.new()
  return setmetatable({ entries = {} }, FocusHistory)
end

function FocusHistory:observe(target)
  assert(type(target) == "table" and validId(target.windowId) and validId(target.spaceId),
    "focus history requires a managed window and confirmed Space")
  self:remove(target.windowId)
  self.entries[#self.entries + 1] = copy(target)
end

function FocusHistory:remove(windowId)
  for index = #self.entries, 1, -1 do
    if self.entries[index].windowId == windowId then table.remove(self.entries, index) end
  end
end

-- Resolve from newest previous to oldest, pruning dead descriptors as they are
-- encountered. The newest live entry is the actual managed anchor and is not
-- itself a previous-window target.
function FocusHistory:previous(resolve)
  assert(type(resolve) == "function", "focus history requires a target resolver")
  for index = #self.entries, 1, -1 do
    if not resolve(self.entries[index]) then table.remove(self.entries, index) end
  end
  if #self.entries < 2 then return nil end
  return copy(self.entries[#self.entries - 1])
end

function FocusHistory:snapshot()
  local result = {}
  for index, target in ipairs(self.entries) do result[index] = copy(target) end
  return result
end

return FocusHistory
