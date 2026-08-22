local Lifecycle = require("lib.lifecycle")

local function fakeWindow(id)
  return { id = function() return id end }
end

return {
  ["lifecycle removes a minimized focused window after the transition"] = function()
    local events, delayed = nil, {}
    local engine = {}
    engine.windowFocused = function() end
    engine.windowCreated = function() end
    engine.windowDestroyed = function() end
    engine.windowMinimized = function(_, id, wasFocused)
      engine.minimized = { id = id, wasFocused = wasFocused }
    end
    engine.windowUnminimized = function(_, window)
      engine.unminimized = window
    end
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
          table.insert(delayed, { delay = delay, callback = callback })
        end,
      },
    }
    local window = fakeWindow(42)
    local lifecycle = Lifecycle.new(hs, engine):start()

    events.focused(window)
    events.minimized(window)
    assert(#delayed == 1 and delayed[1].delay == 0.05)
    delayed[1].callback()
    assert(engine.minimized.id == 42)
    assert(engine.minimized.wasFocused)

    events.unminimized(window)
    assert(engine.unminimized == window)
    lifecycle:stop()
  end,
}
