-- Native macOS Space adapter. 10bucks maps only ordinary user Spaces to
-- numbered desktops; fullscreen/tiled Spaces are deliberately left unnumbered
-- so they can act as scratchpads.
local Workspaces = {}
Workspaces.__index = Workspaces

local function call(module, method, ...)
  if not module or type(module[method]) ~= "function" then return nil end
  local ok, first, second = pcall(module[method], ...)
  if not ok then return nil, first end
  return first, second
end

local function screenKey(screen)
  return tostring(screen:getUUID())
end

local LABEL_SETTINGS_PREFIX = "10bucks.workspaceLabels."

function Workspaces.new(hs)
  return setmetatable({
    hs = hs,
    pending = {},
    pendingTimers = {},
    pendingRemovals = {},
    pendingRemovalTimers = {},
    labelStates = {},
    activeDesktops = {},
    previouslyFocusedDesktops = {},
  }, Workspaces)
end

function Workspaces:isAvailable()
  local spaces = self.hs and self.hs.spaces
  return spaces and type(spaces.spacesForScreen) == "function"
    and type(spaces.activeSpaceOnScreen) == "function"
    and type(spaces.spaceType) == "function"
    and type(spaces.gotoSpace) == "function"
end

function Workspaces:canCreateDesktop()
  local spaces = self.hs and self.hs.spaces
  return self:isAvailable() and type(spaces.addSpaceToScreen) == "function"
end

function Workspaces:spaceType(spaceId)
  return call(self.hs and self.hs.spaces, "spaceType", spaceId)
end

function Workspaces:isDesktopSpace(spaceId)
  return self:spaceType(spaceId) == "user"
end

function Workspaces:isFullscreenSpace(spaceId)
  return self:spaceType(spaceId) == "fullscreen"
end

function Workspaces:desktopSpaces(screen)
  if not self:isAvailable() then return {} end
  local spaces = call(self.hs.spaces, "spacesForScreen", screen)
  if type(spaces) ~= "table" then return {} end

  local desktops = {}
  for _, spaceId in ipairs(spaces) do
    if self:isDesktopSpace(spaceId) then table.insert(desktops, spaceId) end
  end
  return desktops
end

function Workspaces:labelState(screen, spaceIds)
  local key = screenKey(screen)
  local state = self.labelStates[key]
  if not state then
    local stored = call(self.hs and self.hs.settings, "get", LABEL_SETTINGS_PREFIX .. key)
    state = { labels = {}, nextLabel = 1 }
    if type(stored) == "table" then
      if type(stored.labels) == "table" then
        for spaceId, label in pairs(stored.labels) do
          if type(label) == "number" and label > 0 and label % 1 == 0 then
            state.labels[tostring(spaceId)] = label
            state.nextLabel = math.max(state.nextLabel, label + 1)
          end
        end
      end
      if type(stored.nextLabel) == "number" and stored.nextLabel % 1 == 0 then
        state.nextLabel = math.max(state.nextLabel, stored.nextLabel)
      end
    end
    self.labelStates[key] = state
  end

  local current, changed = {}, false
  for _, spaceId in ipairs(spaceIds) do
    local id = tostring(spaceId)
    current[id] = true
    if not state.labels[id] then
      state.labels[id] = state.nextLabel
      state.nextLabel = state.nextLabel + 1
      changed = true
    end
  end
  for spaceId in pairs(state.labels) do
    if not current[spaceId] then state.labels[spaceId], changed = nil, true end
  end
  if changed then self:saveLabelState(screen, state) end
  return state
end

function Workspaces:saveLabelState(screen, state)
  call(self.hs and self.hs.settings, "set", LABEL_SETTINGS_PREFIX .. screenKey(screen), state)
  return self
end

function Workspaces:desktopRecords(screen)
  local spaces = self:desktopSpaces(screen)
  local labels = self:labelState(screen, spaces).labels
  local records = {}
  for _, spaceId in ipairs(spaces) do
    table.insert(records, { id = spaceId, index = labels[tostring(spaceId)] })
  end
  return records
end

function Workspaces:activeSpace(screen)
  if not self:isAvailable() then return nil end
  return call(self.hs.spaces, "activeSpaceOnScreen", screen)
end

function Workspaces:activeDesktop(screen)
  local active = self:activeSpace(screen)
  if not active then return nil end
  for _, desktop in ipairs(self:desktopRecords(screen)) do
    if desktop.id == active then return desktop end
  end
  return nil
end

function Workspaces:desktopAt(screen, index)
  if type(index) ~= "number" or index % 1 ~= 0 then return nil end
  for _, desktop in ipairs(self:desktopRecords(screen)) do
    if desktop.index == index then return desktop end
  end
  return nil
end

-- Record the last regular desktop for this display only after macOS reports it
-- as active. Fullscreen/tiled scratchpads deliberately do not replace it.
function Workspaces:rememberActiveDesktop(screen)
  local active = self:activeDesktop(screen)
  if not active then return nil end
  local key = screenKey(screen)
  local previous = self.activeDesktops[key]
  if previous and previous.id ~= active.id then self.previouslyFocusedDesktops[key] = previous end
  self.activeDesktops[key] = active
  return active
end

function Workspaces:previouslyFocusedDesktop(screen)
  local previous = self.previouslyFocusedDesktops[screenKey(screen)]
  if not previous then return nil end
  for _, desktop in ipairs(self:desktopRecords(screen)) do
    if desktop.id == previous.id then return desktop end
  end
  return nil
end

-- Return the next mapped desktop in a physical direction. When invoked from a
-- fullscreen scratchpad, search the complete native Space order so the user
-- can return to the adjacent desktop without mapping the scratchpad itself.
function Workspaces:neighboringDesktop(screen, direction)
  if direction ~= -1 and direction ~= 1 then return nil end
  local desktops = self:desktopRecords(screen)
  if #desktops == 0 then return nil end

  local active = self:activeSpace(screen)
  for position, desktop in ipairs(desktops) do
    if desktop.id == active then
      local destination = ((position - 1 + direction) % #desktops) + 1
      return desktops[destination]
    end
  end

  -- The active Space is a fullscreen/tiled scratchpad. Preserve native order
  -- when choosing which mapped desktop to enter next.
  local allSpaces = call(self.hs.spaces, "spacesForScreen", screen) or {}
  local activeIndex
  for index, spaceId in ipairs(allSpaces) do
    if spaceId == active then activeIndex = index break end
  end
  if activeIndex then
    for offset = 1, #allSpaces do
      local index = ((activeIndex - 1 + (direction * offset)) % #allSpaces) + 1
      local spaceId = allSpaces[index]
      if self:isDesktopSpace(spaceId) then
        for _, desktop in ipairs(desktops) do
          if desktop.id == spaceId then return desktop end
        end
      end
    end
  end
  return nil
end

-- Optimistically select the target in the bar. hs.spaces.gotoSpace() must
-- invoke Mission Control and may not report its new active Space until its
-- animation finishes; without this, the UI visibly trails an accepted keypress.
function Workspaces:setPendingDesktop(screen, destination)
  local key = screenKey(screen)
  self:clearPendingDesktop(screen)
  self.pending[key] = destination
  if self.hs and self.hs.timer and type(self.hs.timer.doAfter) == "function" then
    self.pendingTimers[key] = self.hs.timer.doAfter(1.5, function()
      self.pending[key], self.pendingTimers[key] = nil, nil
    end)
  end
  return self
end

function Workspaces:clearPendingDesktop(screen)
  local key = screenKey(screen)
  if self.pendingTimers[key] then self.pendingTimers[key]:stop() end
  self.pending[key], self.pendingTimers[key] = nil, nil
  return self
end

function Workspaces:closeMissionControl()
  call(self.hs and self.hs.spaces, "closeMissionControl")
  return self
end

function Workspaces:canRemoveDesktop()
  local spaces = self.hs and self.hs.spaces
  return self:isAvailable() and type(spaces.removeSpace) == "function"
end

function Workspaces:clearPendingRemoval(screen)
  local key = screenKey(screen)
  if self.pendingRemovalTimers[key] then self.pendingRemovalTimers[key]:stop() end
  self.pendingRemovals[key], self.pendingRemovalTimers[key] = nil, nil
  return self
end

-- A Space cannot be removed while active. Queue the source desktop, then let
-- completePendingRemoval() remove it only after the watcher confirms that the
-- requested previous desktop is active.
function Workspaces:queueDesktopRemoval(screen, source, destination)
  if not self:canRemoveDesktop() or not source or not destination or source.id == destination.id then
    return false, "Desktop workspace removal is unavailable"
  end
  local key = screenKey(screen)
  self:clearPendingRemoval(screen)
  self.pendingRemovals[key] = { source = source, destination = destination }
  if self.hs and self.hs.timer and type(self.hs.timer.doAfter) == "function" then
    self.pendingRemovalTimers[key] = self.hs.timer.doAfter(3, function()
      self:clearPendingRemoval(screen)
    end)
  end
  return true
end

function Workspaces:forgetDesktop(spaceId)
  for key, desktop in pairs(self.activeDesktops) do
    if desktop.id == spaceId then self.activeDesktops[key] = nil end
  end
  for key, desktop in pairs(self.previouslyFocusedDesktops) do
    if desktop.id == spaceId then self.previouslyFocusedDesktops[key] = nil end
  end
  for key, state in pairs(self.labelStates) do
    if state.labels[tostring(spaceId)] then
      state.labels[tostring(spaceId)] = nil
      call(self.hs and self.hs.settings, "set", LABEL_SETTINGS_PREFIX .. key, state)
    end
  end
  return self
end

function Workspaces:completePendingRemoval(screen)
  local key = screenKey(screen)
  local pending = self.pendingRemovals[key]
  if not pending then return false end

  local active = self:activeDesktop(screen)
  if not active or active.id ~= pending.destination.id then
    self:clearPendingRemoval(screen)
    return false, "Desktop removal cancelled: destination was not activated"
  end

  self:clearPendingRemoval(screen)
  local removed, err = call(self.hs.spaces, "removeSpace", pending.source.id)
  if not removed then return false, err or "Unable to remove desktop workspace" end
  self:forgetDesktop(pending.source.id)
  return true, pending.source
end

function Workspaces:gotoDesktop(spaceId)
  if not self:isAvailable() or not self:isDesktopSpace(spaceId) then
    return false, "Desktop workspace support is unavailable"
  end
  local ok, result, err = pcall(self.hs.spaces.gotoSpace, spaceId)
  if not ok then return false, result end
  if result then return true end
  return false, err or "Unable to switch workspace"
end

-- Create a regular native desktop and return its new mapped-desktop metadata.
-- Keeping Mission Control open lets the following gotoDesktop() select it in the
-- same transition. The caller must call gotoDesktop() or closeMissionControl().
function Workspaces:addDesktop(screen, requestedLabel)
  if not self:canCreateDesktop() then
    return false, "Desktop workspace creation is unavailable"
  end
  if requestedLabel ~= nil and (type(requestedLabel) ~= "number" or requestedLabel < 1 or requestedLabel % 1 ~= 0) then
    return false, "Desktop label must be a positive integer"
  end

  local existing = self:desktopSpaces(screen)
  local known, labels = {}, self:labelState(screen, existing)
  for _, spaceId in ipairs(existing) do known[spaceId] = true end
  if requestedLabel then
    for _, label in pairs(labels.labels) do
      if label == requestedLabel then return false, "Desktop label is already in use" end
    end
  end

  local added, err = call(self.hs.spaces, "addSpaceToScreen", screen, false)
  if not added then return false, err or "Unable to create desktop workspace" end

  local desktops = self:desktopSpaces(screen)
  for _, spaceId in ipairs(desktops) do
    if not known[spaceId] then
      if requestedLabel then
        labels.labels[tostring(spaceId)] = requestedLabel
        labels.nextLabel = math.max(labels.nextLabel, requestedLabel + 1)
        self:saveLabelState(screen, labels)
      end
      for _, desktop in ipairs(self:desktopRecords(screen)) do
        if desktop.id == spaceId then return true, desktop end
      end
    end
  end

  -- addSpaceToScreen(..., false) intentionally leaves Mission Control open;
  -- never strand it there if macOS does not report the created Space.
  self:closeMissionControl()
  return false, "Created desktop workspace could not be identified"
end

function Workspaces:label(screen)
  local desktops = self:desktopRecords(screen)
  if #desktops == 0 then return nil end
  local active = self:activeSpace(screen)
  local pending = self.pending[screenKey(screen)]
  if pending then
    if active == pending.id then self:clearPendingDesktop(screen)
    else active = pending.id end
  end
  local labels = {}
  for position, desktop in ipairs(desktops) do
    labels[position] = desktop.id == active and ("[" .. desktop.index .. "]") or tostring(desktop.index)
  end
  return table.concat(labels, " ")
end

function Workspaces:start(callback)
  if self.watcher or not self.hs or not self.hs.spaces
    or not self.hs.spaces.watcher or type(self.hs.spaces.watcher.new) ~= "function" then
    return self
  end
  self.watcher = self.hs.spaces.watcher.new(function()
    if callback then callback() end
  end)
  self.watcher:start()
  return self
end

function Workspaces:stop()
  if self.watcher then self.watcher:stop() self.watcher = nil end
  for key, timer in pairs(self.pendingTimers) do
    timer:stop()
    self.pendingTimers[key] = nil
  end
  self.pending = {}
  for key, timer in pairs(self.pendingRemovalTimers) do
    timer:stop()
    self.pendingRemovalTimers[key] = nil
  end
  self.pendingRemovals = {}
  self.labelStates = {}
  self.activeDesktops = {}
  self.previouslyFocusedDesktops = {}
  return self
end

return Workspaces
