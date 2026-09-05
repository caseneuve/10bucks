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
    isFullscreenPending = function() return false end,
    fullscreenTransitionTimedOut = function() end,
    fullscreenCompleted = function() end,
    windowUnfullscreened = function() end,
    cancelFullscreenTransitions = function() end,
    focusRecovery = function() return false end,
    reconcileActiveWorkspace = function() end,
  }
  for name, method in pairs(overrides or {}) do engine[name] = method end
  return engine
end

local function lifecycleHarness(engine)
  local subscriptions, delayed, recurring = {}, {}, {}
  local filter = {
    subscribe = function(_, registered, _, immediate)
      table.insert(subscriptions, { events = registered, immediate = immediate })
    end,
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
        windowFullscreened = "fullscreened",
        windowUnfullscreened = "unfullscreened",
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
  return Lifecycle.new(hs, engine):start(), function()
    local events = {}
    for _, subscription in ipairs(subscriptions) do
      for event, callback in pairs(subscription.events) do events[event] = callback end
    end
    return events
  end, delayed, recurring, subscriptions
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

  ["normal window creation does not schedule fullscreen verification"] = function()
    local lifecycle, getEvents, delayed = lifecycleHarness(engineStub())

    getEvents().created(fakeWindow(42))
    assert(#delayed == 0)
    lifecycle:stop()
  end,

  ["pending fullscreen creation schedules one bounded verification"] = function()
    local timedOut = nil
    local engine = engineStub({
      windowCreated = function() return true, "fullscreen-pending" end,
      isFullscreenPending = function() return true end,
      fullscreenTransitionTimedOut = function(_, window) timedOut = window end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    local window = fakeWindow(42)

    getEvents().created(window)
    getEvents().created(window)
    assert(#delayed == 1 and delayed[1].delay == 2)
    delayed[1].callback()
    assert(timedOut == window)
    assert(lifecycle.fullscreenTimers[42] == nil)
    lifecycle:stop()
  end,

  ["fullscreen completion cancels verification and forwards the window"] = function()
    local completed = nil
    local engine = engineStub({
      windowCreated = function() return true, "fullscreen-pending" end,
      isFullscreenPending = function() return true end,
      fullscreenCompleted = function(_, window) completed = window end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    local window = fakeWindow(42)

    getEvents().created(window)
    getEvents().fullscreened(window)
    assert(delayed[1].stopped)
    assert(completed == window)
    assert(lifecycle.fullscreenTimers[42] == nil)
    lifecycle:stop()
  end,

  ["unfullscreen cancels verification and forwards the window"] = function()
    local unfullscreened = nil
    local engine = engineStub({
      windowCreated = function() return true, "fullscreen-pending" end,
      isFullscreenPending = function() return true end,
      windowUnfullscreened = function(_, window) unfullscreened = window end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    local window = fakeWindow(42)

    getEvents().created(window)
    getEvents().unfullscreened(window)
    assert(delayed[1].stopped)
    assert(unfullscreened == window)
    assert(lifecycle.fullscreenTimers[42] == nil)
    lifecycle:stop()
  end,

  ["unavailable windows cancel verification but retain delayed handling"] = function()
    local minimized = nil
    local engine = engineStub({
      windowCreated = function() return true, "fullscreen-pending" end,
      isFullscreenPending = function() return true end,
      windowMinimized = function(_, id) minimized = id end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)
    local window = fakeWindow(42)

    getEvents().created(window)
    getEvents().minimized(window)
    assert(delayed[1].stopped)
    assert(#delayed == 2 and delayed[2].delay == 0.05)
    delayed[2].callback()
    assert(minimized == 42)
    lifecycle:stop()
  end,

  ["lifecycle stop cancels fullscreen verification and clears engine state"] = function()
    local cancellations = 0
    local engine = engineStub({
      windowCreated = function() return true, "fullscreen-pending" end,
      isFullscreenPending = function() return true end,
      cancelFullscreenTransitions = function() cancellations = cancellations + 1 end,
    })
    local lifecycle, getEvents, delayed = lifecycleHarness(engine)

    getEvents().created(fakeWindow(42))
    lifecycle:stop()
    assert(delayed[1].stopped)
    assert(next(lifecycle.fullscreenTimers) == nil)
    assert(cancellations == 1)
  end,

  ["lifecycle preserves immediate replay only for original events"] = function()
    local lifecycle, _, _, _, subscriptions = lifecycleHarness(engineStub())
    local original, fullscreen = subscriptions[1], subscriptions[2]

    assert(#subscriptions == 2)
    assert(original.immediate == true)
    assert(type(original.events.created) == "function")
    assert(type(original.events.focused) == "function")
    assert(type(original.events.destroyed) == "function")
    assert(type(original.events.minimized) == "function")
    assert(type(original.events.unminimized) == "function")
    assert(original.events.fullscreened == nil)
    assert(original.events.unfullscreened == nil)
    assert(fullscreen.immediate == nil)
    assert(type(fullscreen.events.fullscreened) == "function")
    assert(type(fullscreen.events.unfullscreened) == "function")
    lifecycle:stop()
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
