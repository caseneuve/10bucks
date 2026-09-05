-- Hammerspoon event adapter. It intentionally owns subscriptions so state and
-- engine modules remain testable without hs.window.filter.
local Lifecycle = {}
Lifecycle.__index = Lifecycle

local RECOVERY_DELAY = 0.05
local MAX_RECOVERY_ATTEMPTS = 3
local RECONCILE_INTERVAL = 0.25
local FULLSCREEN_VERIFICATION_DELAY = 2

function Lifecycle.new(hs, engine)
  return setmetatable({
    hs = hs,
    engine = engine,
    recoveryTimers = {},
    recoveryGeneration = 0,
    fullscreenTimers = {},
  }, Lifecycle)
end

function Lifecycle:removeRecoveryTimer(entry)
  for index, current in ipairs(self.recoveryTimers) do
    if current == entry then
      table.remove(self.recoveryTimers, index)
      return
    end
  end
end

function Lifecycle:scheduleTimer(delay, callback)
  local entry = { generation = self.recoveryGeneration }
  table.insert(self.recoveryTimers, entry)
  entry.timer = self.hs.timer.doAfter(delay, function()
    self:removeRecoveryTimer(entry)
    if entry.generation ~= self.recoveryGeneration then return end
    callback()
  end)
  return entry
end

function Lifecycle:cancelFullscreenVerification(windowOrId)
  local isId = type(windowOrId) == "number" or type(windowOrId) == "string"
  local id = isId and windowOrId or windowOrId and windowOrId:id()
  local entry = id and self.fullscreenTimers[id]
  if not entry then return end
  self.fullscreenTimers[id] = nil
  self:removeRecoveryTimer(entry)
  if entry.timer and type(entry.timer.stop) == "function" then entry.timer:stop() end
end

function Lifecycle:scheduleFullscreenVerification(window)
  local id = window and window:id()
  if not id or self.fullscreenTimers[id] then return end
  local entry
  entry = self:scheduleTimer(FULLSCREEN_VERIFICATION_DELAY, function()
    if self.fullscreenTimers[id] ~= entry then return end
    self.fullscreenTimers[id] = nil
    self.engine:fullscreenTransitionTimedOut(window)
  end)
  self.fullscreenTimers[id] = entry
end

function Lifecycle:scheduleFocusRecovery(recovery, attempts)
  if attempts >= MAX_RECOVERY_ATTEMPTS then return end
  self:scheduleTimer(RECOVERY_DELAY, function()
    if self.engine:focusRecovery(recovery) then
      self:scheduleFocusRecovery(recovery, attempts + 1)
    end
  end)
end

function Lifecycle:cancelFocusRecovery()
  self.recoveryGeneration = self.recoveryGeneration + 1
  for _, entry in ipairs(self.recoveryTimers) do
    if entry.timer and type(entry.timer.stop) == "function" then entry.timer:stop() end
  end
  self.recoveryTimers = {}
end

function Lifecycle:start()
  if self.filter then return self end
  self.filter = self.hs.window.filter.new(true)

  self.onCreated = function(window)
    local _, transition = self.engine:windowCreated(window)
    -- setFullScreen() can synchronously emit completion before returning.
    if transition == "fullscreen-pending" and self.engine:isFullscreenPending(window) then
      self:scheduleFullscreenVerification(window)
    end
  end
  self.onFocused = function(window)
    self.engine:windowFocused(window)
  end
  self.onUnavailable = function(window, callback)
    local id = window and window:id()
    if not id then return end
    -- macOS may not have chosen a new key window while the event fires.
    self:scheduleTimer(0.05, function()
      local _, recovery = callback(id)
      if recovery then self:scheduleFocusRecovery(recovery, 1) end
    end)
  end
  self.onDestroyed = function(window)
    self:cancelFullscreenVerification(window)
    self.onUnavailable(window, function(id)
      return self.engine:windowDestroyed(id)
    end)
  end
  self.onMinimized = function(window)
    self:cancelFullscreenVerification(window)
    self.onUnavailable(window, function(id)
      return self.engine:windowMinimized(id)
    end)
  end
  self.onUnminimized = function(window)
    self.engine:windowUnminimized(window)
  end
  self.onFullscreened = function(window)
    self:cancelFullscreenVerification(window)
    self.engine:fullscreenCompleted(window)
  end
  self.onUnfullscreened = function(window)
    self:cancelFullscreenVerification(window)
    self.engine:windowUnfullscreened(window)
  end

  self.filter:subscribe({
    [self.hs.window.filter.windowCreated] = self.onCreated,
    [self.hs.window.filter.windowFocused] = self.onFocused,
    [self.hs.window.filter.windowDestroyed] = self.onDestroyed,
    [self.hs.window.filter.windowMinimized] = self.onMinimized,
    [self.hs.window.filter.windowUnminimized] = self.onUnminimized,
  }, nil, true)
  self.filter:subscribe({
    [self.hs.window.filter.windowFullscreened] = self.onFullscreened,
    [self.hs.window.filter.windowUnfullscreened] = self.onUnfullscreened,
  })

  -- hs.window.filter can miss Chromium's last-window Cmd-W teardown entirely.
  -- Reconcile only the active managed scope at a modest cadence so the layout
  -- and focus invariants do not depend on receiving that event.
  self.reconcileTimer = self.hs.timer.doEvery(RECONCILE_INTERVAL, function()
    self.engine:reconcileActiveWorkspace()
  end)
  return self
end

function Lifecycle:stop()
  self:cancelFocusRecovery()
  self.fullscreenTimers = {}
  self.engine:cancelFullscreenTransitions()
  if self.reconcileTimer then self.reconcileTimer:stop() self.reconcileTimer = nil end
  if self.filter then self.filter:delete() end
  self.filter, self.onCreated, self.onFocused, self.onUnavailable, self.onDestroyed,
    self.onMinimized, self.onUnminimized, self.onFullscreened, self.onUnfullscreened =
    nil, nil, nil, nil, nil, nil, nil, nil, nil
  return self
end

return Lifecycle
