local Core = require("lib.core")
local Model = require("lib.model")
local Stack = require("lib.layouts.stack")
local Columns = require("lib.layouts.columns")

local function core(observe)
  return Core.new({ displayId = "display", regularSpaceId = "space", workArea = { x = 0, y = 0, w = 100, h = 100 },
    initialModelState = Model.new({ displayId = "display", activeRegularSpaceId = "space" }),
    layoutDependencies = { activeLayoutId = "stack", layoutIds = { "stack", "columns" }, registry = { stack = Stack, columns = Columns }, layoutConfigs = { columns = { minRatio = .25, maxRatio = .75, defaultRatio = .5 } } },
    observeIntents = observe,
  })
end
local function ready(id, pid)
  return { type = "WindowReady", id = id, title = id, displayId = "display", spaceId = "space", application = { pid = pid, name = "App" } }
end

return {
  ["Canary A: bootstrap generic readiness atomically commits then projects one final frame"] = function()
    local captured = {}
    local instance = core(function(intents) captured = intents end)
    assert(instance:submit(ready("one", 1)))
    assert(instance:state().manager.windows.one.readiness == nil)
    local frames = 0
    for _, intent in ipairs(captured) do if intent.kind == "frame" then frames = frames + 1; assert(intent.duration == 0) end end
    assert(frames == 1)
  end,
  ["WIN-002 CMD-005: every stack command counts and latest target is focused"] = function()
    local captured = {}; local instance = core(function(intents) captured = intents end)
    instance:submit(ready("one", 1)); instance:submit(ready("two", 2)); instance:submit(ready("three", 3))
    instance:submit({ type = "FocusPrevious" }); instance:submit({ type = "FocusPrevious" })
    local focus
    for _, intent in ipairs(captured) do if intent.kind == "focus" then focus = intent.windowId end end
    assert(focus == "one")
  end,
  ["FOCUS-003: unknown focus is never admission"] = function()
    local instance = core(function() end)
    instance:submit({ type = "ActualFocusChanged", id = "unknown" })
    assert(instance:state().manager.windows.unknown == nil)
  end,
  ["LIFE-001 LIFE-002 STATE-004: lifecycle events retain membership without snapshot pruning"] = function()
    local instance = core(function() end)
    instance:submit(ready("one", 1)); instance:submit({ type = "WindowMinimized", id = "one" }); instance:submit({ type = "ApplicationHidden", pid = 1 }); instance:submit({ type = "WindowAbsentFromSnapshot", id = "one" }); instance:submit({ type = "WindowRestored", id = "one" }); instance:submit({ type = "ApplicationUnhidden", pid = 1 })
    assert(instance:state().manager.windows.one)
  end,
}
