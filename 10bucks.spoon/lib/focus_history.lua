-- Global most-recently-used focus history. Unlike layout state, this history
-- intentionally crosses displays and macOS Spaces and can contain unmanaged
-- (floating) standard application windows.
local FocusHistory = {}
FocusHistory.__index = FocusHistory

function FocusHistory.new()
  return setmetatable({ entries = {} }, FocusHistory)
end

function FocusHistory:remember(id, window)
  if not id or not window then return false end
  self:forget(id)
  table.insert(self.entries, 1, { id = id, window = window })
  return true
end

function FocusHistory:forget(id)
  for index, entry in ipairs(self.entries) do
    if entry.id == id then
      table.remove(self.entries, index)
      break
    end
  end
  return self
end

-- Return the entry focused immediately before currentId. If the current window
-- is not itself tracked (for example a transient helper surface), the latest
-- tracked standard application window remains the best previous target.
function FocusHistory:previous(currentId)
  for index, entry in ipairs(self.entries) do
    if entry.id == currentId then return self.entries[index + 1] end
  end
  return self.entries[1]
end

return FocusHistory
