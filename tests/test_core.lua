local Core = require("lib.core")
local Model = require("lib.model")
local Stack = require("lib.layouts.stack")
local Columns = require("lib.layouts.columns")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[deepCopy(key)] = deepCopy(item) end
  return result
end

local function ready(id, pid)
  return { type = "WindowReady", id = id, title = id, displayId = "built-in", spaceId = "space-1",
    application = { pid = pid or 1, name = "Example", bundleID = "example.app" } }
end

local function new(observer, model)
  return Core.new({
    displayId = "built-in", regularSpaceId = "space-1", workArea = { x = 10, y = 20, w = 1000, h = 600 },
    initialModelState = model or Model.new({ displayId = "built-in", activeRegularSpaceId = "space-1" }),
    layoutDependencies = {
      layoutIds = { "stack", "columns" }, registry = { stack = Stack, columns = Columns },
      layoutConfigs = { columns = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.5 } },
    },
    observeIntents = observer,
  })
end

local function frames(intents)
  local result = {}
  for _, intent in ipairs(intents) do if intent.kind == "frame" then result[#result + 1] = intent end end
  return result
end

return {
  ["STATE-001 STATE-002 ENV-004 PERF-003: core commits composite state before deduplicated explicit-identity projection"] = function()
    local observed, core
    core = new(function(intents)
      observed = intents
      local state = core:state()
      assert(state.manager.windows.one, "observer must see committed admission")
      assert(state.coordinators["space-1"], "observer must see committed coordinator")
    end)
    assert(core:submit(ready("one")))
    local emitted = frames(observed)
    equal(#emitted, 1)
    equal(emitted[1].windowId, "one")
    equal(emitted[1].displayId, "built-in")
    equal(emitted[1].spaceId, "space-1")
    equal(emitted[1].frame.w, 1000)
  end,

  ["WIN-003 COL-002 PERF-003: second admission derives only final columns frames without a wrong-column frame"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit({ type = "CycleLayout" })
    core:submit(ready("one"))
    core:submit(ready("two"))
    core:submit({ type = "ActualFocusChanged", id = "two" })
    local emitted = frames(observed[#observed - 1])
    equal(#emitted, 2)
    equal(emitted[1].windowId, "one")
    equal(emitted[1].frame.w, 500)
    equal(emitted[2].windowId, "two")
    equal(emitted[2].frame.x, 510)
    equal(emitted[2].frame.w, 500)

    core:submit({ type = "ActualFocusChanged", id = "one" })
    core:submit(ready("three"))
    local state = core:state()
    local columns = state.coordinators["space-1"].layouts.columns
    equal(columns.activeStack, 1)
    equal(columns.stacks[1].selectedId, "three")
    core:submit({ type = "WindowTitleChanged", id = "one", title = "late callback" })
    core:submit({ type = "WindowVisibilityObserved", id = "one", visible = true })
    columns = core:state().coordinators["space-1"].layouts.columns
    equal(columns.activeStack, 1)
    equal(columns.stacks[1].selectedId, "three")
  end,

  ["FOCUS-003 WIN-002 FOCUS-006: focus observation never admits or reorders and requested focus changes only selection"] = function()
    local core = new(function() end)
    core:submit(ready("one")); core:submit(ready("two"))
    core:submit({ type = "ActualFocusChanged", id = "popup", title = "popup" })
    core:submit({ type = "FocusPrevious" })
    local state = core:state()
    assert(state.manager.windows.popup == nil)
    equal(state.manager.spaces["space-1"].memberIds[1], "one")
    equal(state.manager.spaces["space-1"].memberIds[2], "two")
    equal(state.coordinators["space-1"].layouts.stack.selectedId, "one")
  end,

  ["FOCUS-001 LAY-003: layout cycling retains last managed focus across unmanaged actual focus"] = function()
    local core = new(function() end)
    core:submit(ready("one")); core:submit(ready("two")); core:submit(ready("three"))
    core:submit({ type = "CycleLayout" })
    core:submit({ type = "ActualFocusChanged", id = "one" })
    core:submit({ type = "ActualFocusChanged", id = "popup" })
    core:submit({ type = "CycleLayout" }); core:submit({ type = "CycleLayout" })
    local state = core:state()
    local columns = state.coordinators["space-1"].layouts.columns
    equal(columns.activeStack, 1)
    equal(columns.stacks[1].selectedId, "one")
  end,

  ["FOCUS-004 COL-005: native focus fallback before destruction still recovers in the source column"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("a")); core:submit(ready("b"))
    core:submit({ type = "CycleLayout" })
    core:submit({ type = "ActualFocusChanged", id = "a" })
    core:submit(ready("c2"))
    core:submit({ type = "ActualFocusChanged", id = "c2" })
    core:submit({ type = "WindowDestroyed", id = "c2" })
    local state = core:state()
    local columns = state.coordinators["space-1"].layouts.columns
    equal(columns.activeStack, 1)
    equal(columns.stacks[1].selectedId, "a")
    local target
    for _, intent in ipairs(observed[#observed]) do if intent.kind == "focus" then target = intent.windowId end end
    equal(target, "a")
  end,

  ["STATE-008 WIN-004 WIN-005 FOCUS-004: unavailable/destroyed selected member retains slots or removes them and recovers current-Space focus"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("one")); core:submit(ready("two")); core:submit(ready("three"))
    core:submit({ type = "ActualFocusChanged", id = "one" })
    core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit({ type = "WindowMinimized", id = "two" })
    local state = core:state()
    equal(#state.manager.spaces["space-1"].memberIds, 3)
    local intents = observed[#observed]
    local focus
    for _, intent in ipairs(intents) do if intent.kind == "focus" then focus = intent end end
    equal(focus.windowId, "three") -- FOCUS-004: last available survivor in the source stack
    core:submit({ type = "WindowDestroyed", id = "three" })
    state = core:state()
    equal(#state.manager.spaces["space-1"].memberIds, 2)
    for _, intent in ipairs(frames(observed[#observed])) do assert(intent.windowId ~= "three") end
  end,

  ["STATE-008 WIN-002 WIN-004 LIFE-003: lifecycle and title sequences retain ordered slots while projection follows Model-derived availability"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("one", 1)); core:submit(ready("two", 2))
    core:submit({ type = "ApplicationHidden", pid = 1 })
    equal(#frames(observed[#observed]), 1)
    equal(frames(observed[#observed])[1].windowId, "two")
    core:submit({ type = "WindowMinimized", id = "two" })
    equal(#frames(observed[#observed]), 0)
    core:submit({ type = "ApplicationUnhidden", pid = 1 })
    equal(#frames(observed[#observed]), 1)
    equal(frames(observed[#observed])[1].windowId, "one")
    core:submit({ type = "WindowEnteredNativeFullscreen", id = "one" })
    equal(#frames(observed[#observed]), 0)
    core:submit({ type = "WindowExitedNativeFullscreen", id = "one" })
    core:submit({ type = "WindowTitleChanged", id = "one", title = "renamed" })
    local state = core:state()
    equal(state.manager.spaces["space-1"].memberIds[1], "one")
    equal(state.manager.spaces["space-1"].memberIds[2], "two")
    equal(state.manager.windows.one.title, "renamed")
  end,

  ["CMD-003 CMD-005 LAY-004: rapid navigation reduces committed selection and capability rejection is a plain result"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("one")); core:submit(ready("two")); core:submit(ready("three"))
    core:submit({ type = "ActualFocusChanged", id = "three" })
    core:submit({ type = "FocusNext" }); core:submit({ type = "FocusNext" })
    equal(core:state().coordinators["space-1"].layouts.stack.selectedId, "two")
    core:submit({ type = "MoveFocusedToOther" })
    local result
    for _, intent in ipairs(observed[#observed]) do if intent.kind == "result" then result = intent end end
    assert(result and result.accepted == false)
    equal(result.reason, "unsupported")
  end,

  ["STATE-003 STATE-006: input state and exposed projection/state snapshots are immutable boundaries"] = function()
    local initial = Model.new({ displayId = "built-in", activeRegularSpaceId = "space-1" })
    local initialBefore = deepCopy(initial)
    local core = new(function(intents) intents[1].frame.w = -1 end, initial)
    core:submit(ready("one"))
    assert(initial.windows.one == initialBefore.windows.one)
    local state = core:state(); state.manager.windows.one.title = "corrupt"
    equal(core:state().manager.windows.one.title, "one")
  end,
}
