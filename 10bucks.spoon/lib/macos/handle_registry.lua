-- Ephemeral composition-owned native handle cache. This is deliberately not
-- durable manager state and performs no lookup or scan on resolution.
local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({ entries = {} }, Registry)
end

function Registry:remember(windowId, spaceId, handle, pid)
  if windowId == nil or spaceId == nil or handle == nil then return end
  self.entries[windowId] = { windowId = windowId, spaceId = spaceId, handle = handle, pid = pid }
end

function Registry:forget(windowId, handle)
  local entry = self.entries[windowId]
  if entry and (handle == nil or entry.handle == handle) then self.entries[windowId] = nil end
end

function Registry:forgetPid(pid)
  for windowId, entry in pairs(self.entries) do
    if entry.pid == pid then self.entries[windowId] = nil end
  end
end

function Registry:resolve(target)
  local entry = target and self.entries[target.windowId]
  if not entry or entry.spaceId ~= target.spaceId then return nil end
  return entry.handle
end

function Registry:clear() self.entries = {} end

return Registry
