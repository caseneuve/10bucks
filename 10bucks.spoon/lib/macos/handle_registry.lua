-- Ephemeral composition-owned native handle leases. This is deliberately not
-- durable manager state and performs no lookup or scan on resolution.
local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({ entries = {} }, Registry)
end

-- A lease is allocated by the native Host and is valid only for that Host
-- resource lifetime. Native numeric IDs are lookup keys, not lease identity.
function Registry:canRemember(windowId, lease)
  local existing = self.entries[windowId]
  return not existing or existing.lease == lease
end

function Registry:remember(windowId, spaceId, handle, pid, lease, appLease)
  if windowId == nil or spaceId == nil or handle == nil then return end
  if not self:canRemember(windowId, lease) then return nil end
  self.entries[windowId] = { windowId = windowId, spaceId = spaceId, handle = handle,
    pid = pid, lease = lease, appLease = appLease }
  return true
end

function Registry:target(windowId, lease)
  local entry = self.entries[windowId]
  if not entry or (lease ~= nil and entry.lease ~= lease) then return nil end
  return { windowId = entry.windowId, spaceId = entry.spaceId, lease = entry.lease }
end

function Registry:matches(windowId, lease)
  local entry = self.entries[windowId]
  return entry ~= nil and entry.lease == lease
end

function Registry:forget(windowId, handle, lease)
  local entry = self.entries[windowId]
  if entry and (handle == nil or entry.handle == handle) and (lease == nil or entry.lease == lease) then
    self.entries[windowId] = nil
    return true
  end
  return false
end

function Registry:forgetPid(pid, appLease)
  for windowId, entry in pairs(self.entries) do
    if entry.pid == pid and (appLease == nil or entry.appLease == appLease) then self.entries[windowId] = nil end
  end
end

function Registry:resolve(target)
  local entry = target and self.entries[target.windowId]
  if not entry or entry.spaceId ~= target.spaceId then return nil end
  if target.lease ~= nil and entry.lease ~= target.lease then return nil end
  return entry.handle
end

function Registry:clear() self.entries = {} end

return Registry
