local Lifecycle = require("lib.lifecycle")

local function fakeWindow(id)
  return { id = function() return id end }
end

local function engineStub(overrides)
  local engine = {
    windowFocused = function() end,
    windowCreated = function() end,
    windowDestroyed = function() end,
    windowMinimized = function() end,
    windowUnminimized = function() end,
    focusRecovery = function() return false end,
    reconcileActiveWorkspace = function() end,
  }
  for name, method in pairs(overrides or {}) do engine[name] = method end
  return engine
end

local function lifecycleHarness(engine)
  local events, delayed, recurring = nil, {}, {}
  local filter = {
    subscribe = function(_, registered) events = registered end,
    delete = function() end,
  }
  local hs = {
    window = {
      filter = {
        new = function() return filter end,
        windowCreated = "created",
        windowFocused = "focused",
        windowDestroyed = "destroyed",
        windowMinimized = "minimized",
        windowUnminimized = "unminimized",
      },
    },
    timer = {
      doAfter = function(delay, callback)
        local timer = { delay = delay, callback = callback, stopped = false }
        function timer:stop() self.stopped = true end
        table.insert(delayed, timer)
        return timer
      end,
      doEvery = function(delay, callback)
        local timer = { delay = delay, callback = callback, stopped = false }
        function timer:stop() self.stopped = true end
        table.insert(recurring, timer)
        return timer
      end,
    },
  }
  return Lifecycle.new(hs, engine):start(), function() return events end, delayed, recurring
end

return {
  ["lifecycle removes a minimized window after the delayed transition"] = function()
    local engine = engineStub()
    engine.windowMinimized = function(_, id)
      engine.minimized = { id = id }
    end
    engine.windowUnminimized = function(_, window)
      engine.unminimized = window
    end
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    local events, window = getEvents(), fakeWindow(42)

    events.minimized(window)
    assert(#delayed == 1 and delayed[1].delay == 0.05)
    delayed[1].callback()
    assert(engine.minimized.id == 42)

    events.unminimized(window)
    assert(engine.unminimized == window)
    lifecycle:stop()
  end,

  ["lifecycle retries a rejected focus request until focus appears"] = function()
    local focusAttempts = 0
    local engine = engineStub({
      windowDestroyed = function()
        focusAttempts = focusAttempts + 1
        return true, { id = 42 }
      end,
      focusRecovery = function()
        focusAttempts = focusAttempts + 1
        return false
      end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    getEvents().destroyed(fakeWindow(42))
    delayed[1].callback()
    assert(#delayed == 2)
    delayed[2].callback()
    assert(focusAttempts == 2)
    assert(#delayed == 2)
    lifecycle:stop()
  end,

  ["lifecycle bounds repeated focus recovery attempts"] = function()
    local retries = 0
    local engine = engineStub({
      windowDestroyed = function() return true, { id = 42 } end,
      focusRecovery = function()
        retries = retries + 1
        return true
      end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    getEvents().destroyed(fakeWindow(42))
    delayed[1].callback()
    delayed[2].callback()
    delayed[3].callback()
    assert(retries == 2)
    assert(#delayed == 3)
    lifecycle:stop()
  end,

  ["lifecycle stops recovery when focus appears elsewhere"] = function()
    local retries = 0
    local engine = engineStub({
      windowDestroyed = function() return true, { id = 42 } end,
      focusRecovery = function()
        retries = retries + 1
        return false
      end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    getEvents().destroyed(fakeWindow(42))
    delayed[1].callback()
    delayed[2].callback()
    assert(retries == 1)
    assert(#delayed == 2)
    lifecycle:stop()
  end,

  ["lifecycle stop cancels owned focus recovery timers"] = function()
    local engine = engineStub({
      windowDestroyed = function() return true, { id = 42 } end,
      focusRecovery = function() return true end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    getEvents().destroyed(fakeWindow(42))
    delayed[1].callback()
    local recoveryTimer = delayed[2]
    lifecycle:stop()
    assert(recoveryTimer.stopped)
  end,

  ["lifecycle stop cancels the initial unavailable timer"] = function()
    local calls = 0
    local engine = engineStub({
      windowDestroyed = function()
        calls = calls + 1
        return true, { id = 42 }
      end,
      focusRecovery = function()
        calls = calls + 1
        return true
      end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    getEvents().destroyed(fakeWindow(42))
    lifecycle:stop()
    assert(delayed[1].stopped)
    delayed[1].callback()
    assert(calls == 0)
    assert(#delayed == 1)
  end,

  ["lifecycle periodically reconciles missed window teardown events"] = function()
    local calls = 0
    local engine = engineStub({
      reconcileActiveWorkspace = function() calls = calls + 1 end,
    })
    local lifecycle, _, _, recurring = lifecycleHarness(engine)

    assert(#recurring == 1 and recurring[1].delay == 0.25)
    recurring[1].callback()
    assert(calls == 1)

    lifecycle:stop()
    assert(recurring[1].stopped)
  end,
}
