-- Hammerspoon event adapter. It intentionally owns subscriptions so state and
-- engine modules remain testable without hs.window.filter.
local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(hs, engine)
  return setmetatable({ hs = hs, engine = engine }, Lifecycle)
end

function Lifecycle:start()
  if self.filter then return self end
  self.filter = self.hs.window.filter.new(true)

  self.onCreated = function(window)
    self.engine:windowCreated(window)
  end
  self.onFocused = function(window)
    local id = window and window:id()
    if id then self.lastFocusedId = id end
    self.engine:windowFocused(window)
  end
  self.onUnavailable = function(window, callback)
    local id = window and window:id()
    if not id then return end
    -- Capture this before macOS focuses another app during the close/minimize
    -- transition. A focus event may otherwise make this look like a background
    -- window and leave the remaining managed window unfocused.
    local wasFocused = self.lastFocusedId == id
    if wasFocused then self.lastFocusedId = nil end
    -- macOS may not have chosen a new key window while the event fires.
    self.hs.timer.doAfter(0.05, function() callback(id, wasFocused) end)
  end
  self.onDestroyed = function(window)
    self.onUnavailable(window, function(id, wasFocused) self.engine:windowDestroyed(id, wasFocused) end)
  end
  self.onMinimized = function(window)
    self.onUnavailable(window, function(id, wasFocused) self.engine:windowMinimized(id, wasFocused) end)
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
  return self
end

function Lifecycle:stop()
  if self.filter then self.filter:delete() end
  self.filter, self.onCreated, self.onFocused, self.onUnavailable, self.onDestroyed,
    self.onMinimized, self.onUnminimized, self.lastFocusedId = nil, nil, nil, nil, nil, nil, nil, nil
  return self
end

return Lifecycle
