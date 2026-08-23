-- Hammerspoon event adapter. It intentionally owns subscriptions so state and
-- engine modules remain testable without hs.window.filter.
local Lifecycle = {}
Lifecycle.__index = Lifecycle

local RECOVERY_DELAY = 0.05
local MAX_RECOVERY_ATTEMPTS = 3
local RECONCILE_INTERVAL = 0.25

function Lifecycle.new(hs, engine)
  return setmetatable({
    hs = hs,
    engine = engine,
    recoveryTimers = {},
    recoveryGeneration = 0,
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
    self.engine:windowCreated(window)
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
    self.onUnavailable(window, function(id)
      return self.engine:windowDestroyed(id)
    end)
  end
  self.onMinimized = function(window)
    self.onUnavailable(window, function(id)
      return self.engine:windowMinimized(id)
    end)
  end
  self.onUnminimized = function(window)
    self.engine:windowUnminimized(window)
  end

  self.filter:subscribe({
    [self.hs.window.filter.windowCreated] = self.onCreated,
    [self.hs.window.filter.windowFocused] = self.onFocused,
    [self.hs.window.filter.windowDestroyed] = self.onDestroyed,
    [self.hs.window.filter.windowMinimized] = self.onMinimized,
    [self.hs.window.filter.windowUnminimized] = self.onUnminimized,
  }, nil, true)

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
  if self.reconcileTimer then self.reconcileTimer:stop() self.reconcileTimer = nil end
  if self.filter then self.filter:delete() end
  self.filter, self.onCreated, self.onFocused, self.onUnavailable, self.onDestroyed,
    self.onMinimized, self.onUnminimized = nil, nil, nil, nil, nil, nil, nil
  return self
end

return Lifecycle
