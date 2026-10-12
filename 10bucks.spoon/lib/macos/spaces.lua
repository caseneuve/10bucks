-- Timer-yielding POC002 mechanism; no gotoSpace busy wait or durable state.
local Spaces = {}
Spaces.__index = Spaces
local function copy(v)
  if type(v) ~= "table" then return v end
  local result = {}; for k, x in pairs(v) do result[k] = copy(x) end; return result
end
local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
  for i, v in ipairs(a) do if b[i] ~= v then return false end end
  return true
end
local function tuple(a, b)
  return a and b and a.generation == b.generation and a.sourceId == b.sourceId
    and a.sourceType == b.sourceType and a.destinationId == b.destinationId
end
local function child(parent, identifier)
  if not parent then return nil end
  for _, element in ipairs(parent:attributeValue("AXChildren") or {}) do
    if element:attributeValue("AXIdentifier") == identifier then return element end
  end
end
function Spaces.new(hs, dependencies)
  assert(type(dependencies.submit) == "function" and type(dependencies.current) == "function"
    and type(dependencies.snapshot) == "function", "spaces requires submit/current/snapshot")
  return setmetatable({ hs = hs, dependencies = dependencies, stopped = false }, Spaces)
end
function Spaces:_live(op)
  return not self.stopped and self.operation == op
end
function Spaces:_clear(op)
  if self.operation ~= op then return end
  self.operation = nil
  for _, timer in ipairs(op.timers) do pcall(timer.stop, timer) end
  op.timers = {}
end
function Spaces:_receipt(op, kind)
  local event = { type = kind, generation = op.intent.generation, sourceId = op.intent.sourceId,
    sourceType = op.intent.sourceType, destinationId = op.intent.destinationId }
  self.dependencies.submit(event)
end
function Spaces:_finish(op, kind)
  if not self:_live(op) then return end
  self:_cleanupStatus(op)
  self:_clear(op) -- permit reentrant next intent only after retiring callbacks
  self:_receipt(op, kind)
end
function Spaces:_later(op, delay, callback)
  local timer = self.hs.timer.doAfter(delay, function()
    if not self:_live(op) then return end
    local ok = pcall(callback)
    if not ok and self:_live(op) then
      -- An exception during AXPress is ambiguous: retain the barrier to timeout.
      if not op.pressed then self:_finish(op, "RegularSwitchFailed") end
    end
  end)
  if self:_live(op) then op.timers[#op.timers + 1] = timer else timer:stop() end
end
function Spaces:_authority(op)
  local current = self.dependencies.current()
  return tuple(current, op.intent) and not current.invalidated
end
function Spaces:_missionControl()
  local apps = self.hs.application.applicationsForBundleID("com.apple.dock")
  assert(apps and #apps == 1, "one Dock required")
  return child(self.hs.axuielement.applicationElement(apps[1]), "mc")
end
function Spaces:_attempt(op)
  if op.pressed or not self:_live(op) then return end
  if not self:_authority(op) then self:_finish(op, "RegularSwitchCancelled"); return end
  if self.hs.timer.absoluteTime() / 1e9 >= op.readinessDeadline then
    self:_finish(op, "RegularSwitchFailed"); return
  end
  local group, display = self:_missionControl(), nil
  if group then op.group = group end
  for _, element in ipairs(group and group:attributeValue("AXChildren") or {}) do
    if element:attributeValue("AXIdentifier") == "mc.display"
      and element:attributeValue("AXDisplayID") == op.screenId then display = element; break end
  end
  local list = child(child(display, "mc.spaces"), "mc.spaces.list")
  if not list then self:_later(op, .05, function() self:_attempt(op) end); return end
  local observed = self.dependencies.snapshot()
  local intent = op.intent
  local current = self.dependencies.current()
  if not self:_live(op) then return end
  if not tuple(current, intent) or current.invalidated then self:_finish(op, "RegularSwitchCancelled"); return end
  if observed.displayId ~= intent.displayId or observed.nativeSpaceId ~= (current.pressSourceId or intent.sourceId)
    or observed.nativeSpaceType ~= (current.pressSourceType or intent.sourceType) or not same(observed.fullSpaceIds, intent.fullSpaceIds)
    or not same(observed.regularSpaceIds, intent.regularSpaceIds) then
    self:_finish(op, "RegularSwitchFailed"); return
  end
  local index
  for i, space in ipairs(observed.fullSpaceIds) do if space == intent.destinationId then index = i end end
  local children = list:attributeValue("AXChildren") or {}
  if not index or #children ~= #observed.fullSpaceIds then self:_finish(op, "RegularSwitchFailed"); return end
  if not self:_live(op) or not self:_authority(op) then
    self:_finish(op, "RegularSwitchCancelled"); return
  end
  op.pressed = true -- at most one press, even on ambiguous exception/rejection
  self:_receipt(op, "RegularSwitchPressed") -- commit attempted phase before native reentry
  if not self:_live(op) then return end
  if op.cancelled or not self:_authority(op) or op.boundaryRevoked or self:_missionControl() ~= op.group then
    -- The phase receipt may reenter composition, but no native action has yet
    -- been attempted. Retire this known-not-issued leg safely, not after 5s.
    op.pressed = false
    local current = self.dependencies.current()
    local kind = tuple(current, op.intent) and current.invalidated and "RegularSwitchCancelled" or "RegularSwitchFailed"
    self:_finish(op, kind)
    return
  end
  -- No reducer/user callback between final authority check, AXPress and the
  -- proved paired Dock-targeted Escape. Never send a global or delayed Escape.
  local ok, accepted = pcall(children[index].performAction, children[index], "AXPress")
  self.lastPress = { accepted = ok and accepted ~= nil and accepted ~= false,
    live = self:_live(op), revoked = op.boundaryRevoked == true, sameGroup = self:_missionControl() == op.group }
  if ok and accepted and self:_live(op) and not op.cancelled and self:_authority(op)
    and not op.boundaryRevoked and self:_missionControl() == op.group then
    local down = self.hs.eventtap.event.newKeyEvent({}, "escape", true)
    local up = self.hs.eventtap.event.newKeyEvent({}, "escape", false)
    down:post(op.dockApp)
    up:post(op.dockApp)
  end
  if not ok or not accepted then
    self.lastError = "Desktop switch AXPress outcome is uncertain; waiting for native confirmation or timeout."
  end
end
function Spaces:execute(intent)
  if self.stopped then return false end
  if intent.kind == "cancelRegularSwitch" then
    local op = self.operation
    if op and tuple(op.intent, intent) then
      op.cancelled = true
      if not op.pressed then self:_finish(op, "RegularSwitchCancelled") end
      -- Postpress cancellation cannot recall the OS effect. Keep timeout and
      -- observation ownership; never claim a speculative drained acknowledgement.
    end
    return true
  end
  assert(intent.kind == "switchRegularSpace", "unknown Space effect")
  if self.operation then return false, "native switch still pending" end
  local op = { intent = copy(intent), timers = {}, pressed = false }
  self.operation = op
  local ok = pcall(function()
    assert(self:_authority(op), "stale switch authority")
    local apps = self.hs.application.applicationsForBundleID("com.apple.dock")
    assert(apps and #apps == 1, "one Dock required")
    op.dockApp = apps[1]
    local visible = self:_missionControl()
    assert(not visible or self.settling or self.awaitingDismissal, "Mission Control already open")
    for _, screen in ipairs(self.hs.screen.allScreens()) do
      if screen:getUUID() == intent.displayId then op.screenId = screen:id(); break end
    end
    assert(op.screenId, "display absent")
    if not self:_live(op) then return end
    assert(self:_authority(op), "stale switch authority")
    op.readinessDeadline = self.hs.timer.absoluteTime() / 1e9 + 2
    self:_later(op, 5, function() self:_finish(op, "RegularSwitchTimedOut") end)
    if not self:_live(op) then return end
    local function open()
      if not self:_live(op) then return end
      if not self:_authority(op) then self:_finish(op, "RegularSwitchCancelled"); return end
      if self.awaitingDismissal then
        if self.hs.timer.absoluteTime() / 1e9 >= op.readinessDeadline then self:_finish(op, "RegularSwitchFailed")
        else self:_later(op, .05, open) end
        return
      end
      if self:_missionControl() then
        if not self.settling then self:_finish(op, "RegularSwitchFailed"); return end
        if self.hs.timer.absoluteTime() / 1e9 >= op.readinessDeadline then self:_finish(op, "RegularSwitchFailed")
        else self:_later(op, .05, open) end
        return
      end
      local observed = self.dependencies.snapshot()
      if observed.displayId ~= op.intent.displayId or observed.nativeSpaceId ~= op.intent.sourceId
        or observed.nativeSpaceType ~= op.intent.sourceType or not same(observed.fullSpaceIds, op.intent.fullSpaceIds)
        or not same(observed.regularSpaceIds, op.intent.regularSpaceIds) then
        self:_finish(op, "RegularSwitchFailed"); return
      end
      if not self:_live(op) or not self:_authority(op) then self:_finish(op, "RegularSwitchCancelled"); return end
      self.settling = false
      op.opened = true
      self.hs.spaces.openMissionControl()
      if self:_live(op) then self:_later(op, .3, function() self:_attempt(op) end) end
    end
    if visible or self.awaitingDismissal then self:_later(op, .05, open) else open() end
  end)
  if not ok then self:_finish(op, "RegularSwitchFailed") end
  return ok
end
-- Called with a fresh complete Context observation BEFORE ordinary topology
-- delivery. Return a correlated copy; caller owns revision and reducer delivery.
function Spaces:observe(context)
  local op = self.operation
  if op and op.opened and not op.pressed and op.intent.sourceType == "fullscreen"
    and context.nativeSpaceType == "user" and context.displayId == op.intent.displayId
    and not op.boundaryRevoked and not op.cancelled and self:_authority(op) then
    local current = self.dependencies.current()
    local group = self:_missionControl()
    if group and not current.pressSourceId and (not op.group or op.group == group)
      and same(context.fullSpaceIds, op.intent.fullSpaceIds) and same(context.regularSpaceIds, op.intent.regularSpaceIds) then
      op.group = group
      local result = copy(context)
      result.workspaceEventType = "RegularSwitchContextRebased"
      for _, key in ipairs({ "generation", "sourceId", "sourceType", "destinationId" }) do result[key] = op.intent[key] end
      return result
    end
  end
  if not op or not op.pressed or context.displayId ~= op.intent.displayId
    or context.nativeSpaceType ~= "user" or context.nativeSpaceId ~= op.intent.destinationId then return context end
  local ok, visible = pcall(self._missionControl, self)
  if not ok or visible then return context end
  local current = self.dependencies.current()
  local invalidated = not tuple(current, op.intent) or current.invalidated
  local result = copy(context)
  for _, key in ipairs({ "generation", "sourceId", "sourceType", "destinationId" }) do result[key] = op.intent[key] end
  self:_clear(op)
  self.settling = not op.cancelled and not invalidated
  self.awaitingDismissal = self.settling and not op.sawBoundary
  if op.cancelled or invalidated then
    -- OS destination is now observed, but reducer authority was invalidated.
    -- Failure clears uncertain intent; the observation remains external reality.
    self:_receipt(op, "RegularSwitchFailed")
    return context
  end
  return result
end
function Spaces:dockBoundary()
  self.settling = false
  local op = self.operation
  if self.awaitingDismissal and (not op or not op.opened) then
    self.awaitingDismissal = false
    return -- late prior dismissal: pending leg has not acquired a session
  end
  if op and op.opened then
    op.sawBoundary = true
    op.boundaryRevoked = true
    if not op.pressed then self:_finish(op, "RegularSwitchFailed") end
  end
end
function Spaces:_cleanupStatus(op)
  if not op.opened then return end
  local ok, visible = pcall(self._missionControl, self)
  self.cleanupUncertain = not ok or visible ~= nil
  if self.cleanupUncertain then
    self.lastError = "Mission Control cleanup is uncertain. Dismiss Mission Control manually before retrying a desktop command."
  end
end
function Spaces:status()
  return { pending = self.operation ~= nil, cleanupUncertain = self.cleanupUncertain == true, message = self.lastError, lastPress = self.lastPress }
end
function Spaces:stop()
  if self.stopped then return end
  self.stopped = true
  if self.operation then self:_cleanupStatus(self.operation); self:_clear(self.operation) end
  -- Never close MC: opening alone cannot prove dismissal/reopening ownership.
end
return Spaces
