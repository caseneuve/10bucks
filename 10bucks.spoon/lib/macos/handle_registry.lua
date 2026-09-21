-- Ephemeral composition-owned native handle cache. This is deliberately not
-- durable manager state and performs no lookup or scan on resolution.
local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({ entries = {} }, Registry)
end

-- Only a confirmed ownership observation may assign a descriptor Space.
function Registry:remember(windowId, spaceId, handle, pid)
  if windowId == nil or spaceId == nil or handle == nil then return end
  self.entries[windowId] = { windowId = windowId, spaceId = spaceId, handle = handle, pid = pid }
end

-- A focus callback can precede the Space watcher. It refreshes a known native
-- handle without guessing that the receiving host owns the descriptor's Space.
function Registry:refresh(windowId, handle, pid)
  if windowId == nil or handle == nil then return end
  local entry = self.entries[windowId]
  if entry then entry.handle, entry.pid = handle, pid
  else self.entries[windowId] = { windowId = windowId, handle = handle, pid = pid } end
end

function Registry:cached(windowId)
  local entry = self.entries[windowId]
  if not entry then return nil end
  return { windowId = entry.windowId, spaceId = entry.spaceId, handle = entry.handle, pid = entry.pid }
end

function Registry:target(windowId)
  local entry = self.entries[windowId]
  if not entry or entry.spaceId == nil then return nil end
  return { windowId = entry.windowId, spaceId = entry.spaceId }
end

function Registry:record(target)
  local entry = target and self.entries[target.windowId]
  if not entry or entry.spaceId ~= target.spaceId then return nil end
  return { windowId = entry.windowId, spaceId = entry.spaceId, handle = entry.handle, pid = entry.pid }
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
