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

local function bootstrapReady(id, pid)
  local event = ready(id, pid)
  event.metadata = {
    id = event.id, application = event.application, title = event.title,
    displayId = event.displayId, spaceId = event.spaceId, origin = "bootstrap", createdAfterStart = false,
    role = "AXWindow", subrole = "AXStandardWindow", modal = false,
    movable = true, resizable = true, selfProcess = false,
  }
  event.decision = { action = "manage" }
  return event
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
  ["STACK-001 COL-004 WIN-003 FOCUS-005 BAR-003: established tab group keeps its slot and effects follow only the selected tab"] = function()
    local group, other = "native-tabs:1", "native-tabs:2"
    local observed
    local core = new(function(intents) observed = intents end)
    local function admit(id, tabGroup)
      local event = bootstrapReady(id)
      event.tabGroup = tabGroup
      assert(core:submit(event))
    end
    local function focus(id, tabGroup)
      assert(core:submit({ type = "ActualFocusChanged", id = id, tabGroup = tabGroup }))
    end
    admit("left")
    admit("control", other) -- same app, distinct AX group
    admit("first", group)
    focus("first", group)
    assert(core:submit({ type = "CycleLayout" }))
    focus("control", other)
    assert(core:submit({ type = "MoveFocusedToOther", memberId = "control" }))
    focus("control", other)
    focus("first", group)
    local base = core:state().coordinators["space-1"].layouts.columns
    equal(table.concat(base.stacks[1].members, ","), "left")
    equal(table.concat(base.stacks[2].members, ","), group .. "," .. other)
    local status = core:status(); equal(status.count, 2); equal(status.position, 1)

    admit("second", group)
    focus("second", group)
    assert(core:chooserTabVisible("second") and not core:chooserTabVisible("first"))
    assert(core:chooserTabVisible("control") and core:chooserTabVisible("left"))
    assert(core:submit({ type = "Reflow" }))
    status = core:status(); equal(status.count, 2); equal(status.position, 1)
    local layout = core:state().coordinators["space-1"].layouts.columns
    equal(table.concat(layout.stacks[2].members, ","), group .. "," .. other)
    local sawSecond = false
    for _, frame in ipairs(frames(observed)) do
      assert(frame.windowId ~= "first")
      if frame.windowId == "second" then equal(frame.frame.x, 510); sawSecond = true end
    end
    assert(sawSecond)
    local function navigate(command, expected)
      assert(core:submit({ type = command }))
      for _, intent in ipairs(observed) do
        if intent.kind == "focus" then equal(intent.windowId, expected); return end
      end
      error("missing focus intent")
    end
    navigate("FocusNext", "control"); focus("control", other)
    navigate("FocusPrevious", "second"); focus("second", group)
    assert(core:state().manager.windows.first)
    assert(core:submit({ type = "WindowDestroyed", id = "first" }))
    status = core:status(); equal(status.count, 2); equal(status.position, 1)
  end,

  ["LIFE-003 WIN-003 STACK-001 BAR-003: first tab creation suppresses exact ownerless slot without assigning or destroying it"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    assert(core:submit(bootstrapReady("control")))
    assert(core:submit(bootstrapReady("original")))
    local event = bootstrapReady("new")
    event.tabGroup = "native-tabs:1"
    event.tabOwners = { original = { ownerless = true }, control = { ownerless = false } }
    assert(core:submit(event))
    local original = core:state().manager.windows.original
    assert(original and original.observations.tabOwnerless and not original.observations.tabGroup)
    local status = core:status(); equal(status.count, 2)
    for _, frame in ipairs(frames(observed)) do assert(frame.windowId ~= "original") end
    -- Unknown owner read (no fact) preserves both membership and the last checked availability.
    assert(core:submit({ type = "ActualFocusChanged", id = "new", tabGroup = event.tabGroup }))
    status = core:status(); equal(status.count, 2); equal(status.position, 2)
    assert(core:submit({ type = "FocusNext" }))
    local desired = core:state().manager.focus.desiredBySpace["space-1"]
    equal(desired.targetId, "control")
    assert(core:submit({ type = "ActualFocusChanged", id = "control" }))
    assert(core:submit({ type = "ActualFocusChanged", id = "original", tabOwners = { original = { ownerless = false } } }))
    status = core:status(); equal(status.count, 3)
    assert(not core:state().manager.windows.original.observations.tabOwnerless)
  end,

  ["COL-004 COL-005 LIFE-001 FOCUS-004 STATE-002: minimizing sole right member re-splits before effects, restore and admission keep visible columns"] = function()
    local observed, core
    core = new(function(intents) observed = intents end)
    for _, id in ipairs({ "A", "B", "C" }) do core:submit(bootstrapReady(id)) end
    core:submit({ type = "ActualFocusChanged", id = "C" })
    core:submit({ type = "CycleLayout" })
    assert(core:submit({ type = "WindowMinimized", id = "C" }))
    local layout = core:state().coordinators["space-1"].layouts.columns
    equal(table.concat(layout.stacks[1].members, ","), "A")
    equal(table.concat(layout.stacks[2].members, ","), "C,B")
    equal(layout.activeStack, 2)
    equal(core:state().manager.focus.desiredBySpace["space-1"].targetId, "B")
    equal(#frames(observed), 2)
    for _, frame in ipairs(frames(observed)) do equal(frame.frame.w, 500) end
    core:submit({ type = "ActualFocusChanged", id = "B" })
    core:submit({ type = "WindowRestored", id = "C" })
    core:submit({ type = "ActualFocusChanged", id = "C" })
    core:submit({ type = "WindowMinimized", id = "C" })
    equal(#frames(observed), 2)
    for _, frame in ipairs(frames(observed)) do equal(frame.frame.w, 500) end
    core:submit(ready("D"))
    layout = core:state().coordinators["space-1"].layouts.columns
    equal(table.concat(layout.stacks[2].members, ","), "C,B,D")
    equal(#frames(observed), 3)
    for _, frame in ipairs(frames(observed)) do equal(frame.frame.w, 500) end
    assert(core:state().manager.windows.C.lifecycle.minimized)
  end,

  ["COL-002 COL-004 LIFE-001: one visible survivor then new admission recreates a split despite retained minimized members"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    core:submit(bootstrapReady("A")); core:submit(bootstrapReady("B"))
    core:submit({ type = "ActualFocusChanged", id = "B" }); core:submit({ type = "CycleLayout" })
    core:submit({ type = "WindowMinimized", id = "B" })
    equal(#frames(observed), 1); equal(frames(observed)[1].frame.w, 1000)
    core:submit(ready("C"))
    equal(#frames(observed), 2)
    for _, frame in ipairs(frames(observed)) do equal(frame.frame.w, 500) end
    local layout = core:state().coordinators["space-1"].layouts.columns
    equal(table.concat(layout.stacks[1].members, ","), "A")
    equal(table.concat(layout.stacks[2].members, ","), "B,C")
  end,

  ["COL-004 LIFE-002 FS-002 FOCUS-006: background left column loss preserves actual focus and normalizes newest available survivor right"] = function()
    for _, event in ipairs({ { type = "ApplicationHidden", pid = 1 }, { type = "WindowEnteredNativeFullscreen", id = "A" }, { type = "WindowMinimized", id = "A" } }) do
      local observed
      local core = new(function(intents) observed = intents end)
      for index, id in ipairs({ "A", "B", "C" }) do core:submit(bootstrapReady(id, index)) end
      core:submit({ type = "ActualFocusChanged", id = "C" }); core:submit({ type = "CycleLayout" })
      core:submit({ type = "MoveFocusedToOther", memberId = "B" })
      core:submit({ type = "ActualFocusChanged", id = "B" })
      core:submit({ type = "ActualFocusChanged", id = "C" })
      core:submit(event)
      local layout = core:state().coordinators["space-1"].layouts.columns
      equal(table.concat(layout.stacks[1].members, ","), "A,C")
      equal(table.concat(layout.stacks[2].members, ","), "B")
      equal(layout.activeStack, 1)
      equal(#frames(observed), 2)
      for _, intent in ipairs(observed) do assert(intent.kind ~= "focus") end
    end
  end,
  ["COL-006 STATE-002: move effects see complete C,A|B state and split geometry"] = function()
    local checking, observed, core
    core = new(function(intents)
      observed = intents
      if not checking then return end
      local layout = core:state().coordinators["space-1"].layouts.columns
      equal(table.concat(layout.stacks[1].members, ","), "C,A")
      equal(table.concat(layout.stacks[2].members, ","), "B")
      equal(layout.stacks[1].selectedId, "C")
      equal(layout.stacks[2].selectedId, "B")
      equal(layout.activeStack, 1)
      for _, intent in ipairs(intents) do
        if intent.kind == "frame" then
          equal(intent.frame.w, 500)
          equal(intent.frame.x, intent.windowId == "B" and 510 or 10)
        elseif intent.kind == "focus" then equal(intent.windowId, "C") end
      end
    end)
    for _, id in ipairs({ "A", "B", "C" }) do core:submit(bootstrapReady(id)) end
    core:submit({ type = "ActualFocusChanged", id = "A" })
    core:submit({ type = "CycleLayout" })
    core:submit({ type = "ActualFocusChanged", id = "C" })
    checking = true
    assert(core:submit({ type = "MoveFocusedToOther", memberId = "C" }))
    equal(#frames(observed), 3)
    equal(core:state().manager.focus.desiredBySpace["space-1"].targetId, "C")
  end,

  ["COL-006 STATE-008 LIFE-001 LIFE-002 FS-002: replacement eligibility honors independent overlapping availability"] = function()
    for mask = 1, 7 do
      local core = new(function() end)
      for index, id in ipairs({ "A", "B", "D", "C" }) do core:submit(bootstrapReady(id, index)) end
      core:submit({ type = "ActualFocusChanged", id = "A" })
      core:submit({ type = "CycleLayout" })
      if mask % 2 == 1 then core:submit({ type = "WindowMinimized", id = "D" }) end
      if math.floor(mask / 2) % 2 == 1 then core:submit({ type = "ApplicationHidden", pid = 3 }) end
      if mask >= 4 then core:submit({ type = "WindowEnteredNativeFullscreen", id = "D" }) end
      if mask == 7 then
        core:submit({ type = "WindowRestored", id = "D" })
        core:submit({ type = "ApplicationUnhidden", pid = 3 })
      end
      core:submit({ type = "ActualFocusChanged", id = "C" })
      assert(core:submit({ type = "MoveFocusedToOther", memberId = "C" }))
      local layout = core:state().coordinators["space-1"].layouts.columns
      equal(table.concat(layout.stacks[1].members, ","), "C,A,D")
      equal(table.concat(layout.stacks[2].members, ","), "B")
      assert(not Model.isAvailable(core:state().manager.windows.D))
    end
  end,
  ["STATE-008 FOCUS-006: unavailable created member cannot strand desired focus while restore preserves independent hide"] = function()
    local core = new(function() end)
    core:submit(bootstrapReady("one")); core:submit({ type = "ActualFocusChanged", id = "one" })
    local event = bootstrapReady("two", 2)
    event.metadata.origin = "created"; event.metadata.createdAfterStart = true
    event.metadata.minimized, event.metadata.appHidden = true, true
    assert(core:submit(event))
    local state = core:state(); local desired = state.manager.focus.desiredBySpace["space-1"]
    assert(desired.targetId ~= "two" and not Model.isAvailable(state.manager.windows.two))
    core:submit({ type = "ActualFocusChanged", id = "one" })
    assert(not core:state().manager.focus.desiredBySpace["space-1"].pending)
    core:submit({ type = "WindowRestored", id = "two" })
    assert(not Model.isAvailable(core:state().manager.windows.two))
    core:submit({ type = "ApplicationUnhidden", pid = 2 })
    assert(Model.isAvailable(core:state().manager.windows.two))
    equal(#core:state().manager.spaces["space-1"].memberIds, 2)
  end,
  ["FOCUS-004 WIN-005: app termination captures focused source before removing every affected member"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    core:submit(bootstrapReady("one", 1)); core:submit(bootstrapReady("two", 1)); core:submit(bootstrapReady("three", 2))
    core:submit({ type = "ActualFocusChanged", id = "two" }); core:submit({ type = "CycleLayout" })
    core:submit({ type = "ApplicationTerminated", pid = 1 })
    local state = core:state(); equal(#state.manager.spaces["space-1"].memberIds, 1)
    equal(state.manager.focus.desiredBySpace["space-1"].targetId, "three")
    local requested
    for _, intent in ipairs(observed) do if intent.kind == "focus" then requested = intent.windowId end end
    equal(requested, "three")
  end,
  ["STATE-001 WIN-002 WIN-005 FOCUS-006: combined focus-layout-delete orderings preserve membership and pending authority after every transition"] = function()
    for _, initial in ipairs({ "stack", "columns" }) do
      for _, late in ipairs({ "one", "two", "popup" }) do
        local core = new(function() end)
        local function send(event, expectedMembers)
          assert(core:submit(event))
          local state = core:state()
          assert(Model.validate(state.manager))
          equal(#state.manager.spaces["space-1"].memberIds, expectedMembers)
          local memberIds = state.manager.spaces["space-1"].memberIds
          if expectedMembers > 0 then equal(memberIds[1], "one") end
          if expectedMembers > 1 then equal(memberIds[2], "two") end
          return state
        end
        send(bootstrapReady("one"), 1); send(bootstrapReady("two"), 2)
        send({ type = "ActualFocusChanged", id = "two" }, 2)
        if initial == "columns" then send({ type = "CycleLayout" }, 2) end
        send({ type = "FocusPrevious" }, 2)
        local pending = core:state().manager.focus.desiredBySpace["space-1"]
        send({ type = "CycleLayout" }, 2)
        send({ type = "ActualFocusChanged", id = late }, 2)
        local desired = core:state().manager.focus.desiredBySpace["space-1"]
        if late ~= pending.targetId then
          assert(desired.pending and desired.targetId == pending.targetId and desired.generation == pending.generation)
        end
        send({ type = "ActualFocusChanged", id = pending.targetId }, 2)
        send(ready("three"), 3)
        send({ type = "WindowTitleChanged", id = "one", title = "updated" }, 3)
        send({ type = "WindowDestroyed", id = "three" }, 2)
        local state = send({ type = "ActualFocusChanged", id = late }, 2)
        assert(not state.manager.windows.three)
        for _, id in ipairs(state.manager.focus.managedHistory) do assert(id ~= "three") end
        send({ type = "CycleLayout" }, 2)
      end
    end
  end,
  ["FOCUS-004 WIN-002: deleting a background column selection preserves active group and emits no recovery focus"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    core:submit(bootstrapReady("one")); core:submit(bootstrapReady("two"))
    core:submit({ type = "CycleLayout" }); core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit({ type = "WindowDestroyed", id = "one" })
    local state = core:state()
    equal(state.coordinators["space-1"].layouts.columns.stacks[1].selectedId, "two")
    for _, intent in ipairs(observed) do assert(intent.kind ~= "focus", "background deletion must not request focus") end
  end,
  ["FOCUS-006 LAY-003: layout cycling preserves pending desired focus against late actual observations"] = function()
    local core = new(function() end)
    core:submit(bootstrapReady("one")); core:submit(bootstrapReady("two"))
    core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit({ type = "FocusPrevious" })
    local desired = core:state().manager.focus.desiredBySpace["space-1"]
    assert(desired.pending and desired.targetId == "one")
    core:submit({ type = "CycleLayout" })
    local switched = core:state().manager.focus.desiredBySpace["space-1"]
    assert(switched.pending and switched.targetId == "one" and switched.generation == desired.generation)
    core:submit({ type = "ActualFocusChanged", id = "two" })
    local state = core:state(); local layout = state.coordinators["space-1"].layouts.columns
    equal(layout.stacks[layout.activeStack].selectedId, "one")
    core:submit({ type = "ActualFocusChanged", id = "one" })
    assert(not core:state().manager.focus.desiredBySpace["space-1"].pending)
  end,
  ["FOCUS-003 CMD-001: rejected unknown focus target cannot invalidate or replace a pending request"] = function()
    local core = new(function() end)
    core:submit(bootstrapReady("one")); core:submit(bootstrapReady("two"))
    core:submit({ type = "ActualFocusChanged", id = "two" }); core:submit({ type = "FocusPrevious" })
    assert(core:submit({ type = "FocusTarget", windowId = "unknown" }))
    local desired = core:state().manager.focus.desiredBySpace["space-1"]
    assert(desired.pending and desired.targetId == "one")
  end,
  ["LAY-003 COL-007: first columns activation retains last focused member in each newly formed group"] = function()
    local core = new(function() end)
    core:submit(bootstrapReady("one")); core:submit(bootstrapReady("two"))
    core:submit({ type = "ActualFocusChanged", id = "one" })
    core:submit(ready("three")); core:submit({ type = "ActualFocusChanged", id = "three" })
    core:submit({ type = "CycleLayout" })
    local layout = core:state().coordinators["space-1"].layouts.columns
    equal(layout.stacks[1].selectedId, "one"); equal(layout.stacks[2].selectedId, "three")
    core:submit({ type = "FocusLeftGroup" })
    equal(core:state().manager.focus.desiredBySpace["space-1"].targetId, "one")
    equal(layout.stacks[1].members[1], "one"); equal(layout.stacks[1].members[2], "two")
  end,
  ["LAY-003 COL-001: stack admissions activate columns with two occupied groups and close recovery"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    core:submit(bootstrapReady("one")); core:submit(bootstrapReady("two"))
    core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit(ready("three")); core:submit({ type = "ActualFocusChanged", id = "three" })
    assert(core:submit({ type = "CycleLayout" }))
    local layout = core:state().coordinators["space-1"].layouts.columns
    equal(#layout.stacks, 2); equal(#layout.stacks[1].members, 2); equal(#layout.stacks[2].members, 1)
    equal(#frames(observed), 3)
    assert(core:submit({ type = "WindowDestroyed", id = "three" }))
    layout = core:state().coordinators["space-1"].layouts.columns
    equal(#layout.stacks, 2); equal(#layout.stacks[1].members, 1); equal(#layout.stacks[2].members, 1)
    equal(core:state().manager.focus.desiredBySpace["space-1"].targetId, "two")
  end,
  ["PERF-002 WIN-007: title and duplicate readiness emit no frames while reflow and managed focus synchronize"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    assert(core:submit(bootstrapReady("one")))
    assert(core:submit({ type = "ActualFocusChanged", id = "one" }))
    assert(core:submit({ type = "WindowTitleChanged", id = "one", title = "renamed" }))
    equal(#frames(observed), 0)
    equal(core:state().manager.windows.one.title, "renamed")
    assert(core:submit(bootstrapReady("one")))
    equal(#frames(observed), 0)
    assert(core:submit({ type = "ActualFocusChanged", id = "one" }))
    equal(#frames(observed), 0)
    assert(core:submit({ type = "Reflow" }))
    equal(#frames(observed), 1)
    assert(core:submit(bootstrapReady("two")))
    assert(core:submit({ type = "ActualFocusChanged", id = "two" }))
    equal(#frames(observed), 2)
  end,
  ["PERF-002 FOCUS-006: stale focus and unsupported command do not trigger geometry synchronization"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    assert(core:submit(bootstrapReady("one")))
    assert(core:submit(bootstrapReady("two")))
    assert(core:submit({ type = "ActualFocusChanged", id = "two" }))
    assert(core:submit({ type = "FocusPrevious" }))
    assert(core:submit({ type = "ActualFocusChanged", id = "two" }))
    equal(#frames(observed), 0)
    assert(core:state().manager.focus.desiredBySpace["space-1"].pending)
    assert(core:submit({ type = "MoveFocusedToOther" }))
    equal(#frames(observed), 0)
    assert(core:submit({ type = "WindowVisibilityObserved", id = "one", visible = false }))
    equal(#frames(observed), 0)
  end,
  ["WIN-007 STATE-008: overlapping restore and unhide synchronize even while the restored member remains unavailable"] = function()
    local observed
    local core = new(function(intents) observed = intents end)
    core:submit(bootstrapReady("one", 1)); core:submit(bootstrapReady("two", 2))
    core:submit({ type = "WindowMinimized", id = "one" })
    core:submit({ type = "ApplicationHidden", pid = 1 })
    assert(core:submit({ type = "WindowRestored", id = "one" }))
    equal(#frames(observed), 1); equal(frames(observed)[1].windowId, "two")
    assert(not Model.isAvailable(core:state().manager.windows.one))
    assert(core:submit({ type = "WindowRestored", id = "one" }))
    equal(#frames(observed), 0)
    core:submit({ type = "WindowMinimized", id = "one" })
    assert(core:submit({ type = "ApplicationUnhidden", pid = 1 }))
    equal(#frames(observed), 1); equal(frames(observed)[1].windowId, "two")
    assert(not Model.isAvailable(core:state().manager.windows.one))
  end,
  ["FOCUS-004 FOCUS-006: background lifecycle events never replay an older pending focus request"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("one")); core:submit(ready("two"))
    assert(core:state().manager.focus.desiredBySpace["space-1"].pending)
    core:submit({ type = "WindowMinimized", id = "one" })
    for _, intent in ipairs(observed[#observed]) do assert(intent.kind ~= "focus") end
    core:submit({ type = "WindowDestroyed", id = "one" })
    for _, intent in ipairs(observed[#observed]) do assert(intent.kind ~= "focus") end
  end,
  ["FS-002 FOCUS-005: native fullscreen retains its slot and explicit global focus can target it without recovery focus"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("one")); core:submit(ready("two"))
    core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit({ type = "WindowEnteredNativeFullscreen", id = "two" })
    for _, intent in ipairs(observed[#observed]) do assert(intent.kind ~= "focus", "entering fullscreen must not focus behind it") end
    assert(core:state().manager.spaces["space-1"].memberIds[2] == "two")
    core:submit({ type = "FocusTarget", windowId = "two" })
    local focus
    for _, intent in ipairs(observed[#observed]) do
      if intent.kind == "focus" then focus = intent end
      assert(intent.kind ~= "result" or intent.accepted ~= false)
      assert(intent.kind ~= "frame" or intent.windowId ~= "two")
    end
    assert(focus and focus.windowId == "two")
    core:submit({ type = "ActualFocusChanged", id = "two" })
    assert(not core:state().manager.focus.desiredBySpace["space-1"].pending)
  end,
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

  ["DISC-001 COL-009 FOCUS-006: bootstrap and duplicate readiness never steal focus"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(bootstrapReady("one")); core:submit(bootstrapReady("two"))
    local state = core:state()
    assert(state.manager.windows.one and state.manager.windows.two)
    assert(not state.manager.focus.desiredBySpace["space-1"].pending)
    for _, index in ipairs({ 1, 2 }) do
      for _, intent in ipairs(observed[index]) do assert(intent.kind ~= "focus") end
    end

    core:submit(ready("three"))
    local focusCount = 0
    for _, intent in ipairs(observed[#observed]) do if intent.kind == "focus" then focusCount = focusCount + 1 end end
    equal(focusCount, 1)
    core:submit(ready("three"))
    focusCount = 0
    for _, intent in ipairs(observed[#observed]) do if intent.kind == "focus" then focusCount = focusCount + 1 end end
    equal(focusCount, 0)
    assert(core:state().manager.focus.desiredBySpace["space-1"].pending)
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
    core:submit({ type = "ActualFocusChanged", id = "three" }) -- confirm setup before mouse focus
    core:submit({ type = "CycleLayout" })
    core:submit({ type = "ActualFocusChanged", id = "one" })
    core:submit({ type = "ActualFocusChanged", id = "popup" })
    core:submit({ type = "CycleLayout" }); core:submit({ type = "CycleLayout" })
    local state = core:state()
    local columns = state.coordinators["space-1"].layouts.columns
    equal(columns.activeStack, 1)
    equal(columns.stacks[1].selectedId, "one")
  end,

  ["FOCUS-004 COL-005: authoritative destruction recovers in the source column"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("a")); core:submit(ready("b"))
    core:submit({ type = "ActualFocusChanged", id = "b" })
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
    core:submit({ type = "ActualFocusChanged", id = "three" }) -- acknowledge admission before mouse focus
    core:submit({ type = "ActualFocusChanged", id = "one" })
    core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit({ type = "WindowMinimized", id = "two" })
    local state = core:state()
    equal(#state.manager.spaces["space-1"].memberIds, 3)
    local intents = observed[#observed]
    local focus
    for _, intent in ipairs(intents) do if intent.kind == "focus" then focus = intent end end
    equal(focus.windowId, "one") -- FOCUS-004: most recently confirmed available source survivor
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
  ["LIFE-002 FOCUS-004: inactive lifecycle reduction preserves selection without creating recovery focus"] = function()
    local observed = {}
    local core = new(function(intents) observed[#observed + 1] = intents end)
    core:submit(ready("one")); core:submit(ready("two")); core:submit({ type = "ActualFocusChanged", id = "two" })
    core:submit({ type = "WindowDestroyed", id = "two", focusAuthority = false })
    local desired = core:state().manager.focus.desiredBySpace["space-1"]
    assert(core:state().manager.windows.one and not core:state().manager.windows.two and not desired.pending)
    for _, intent in ipairs(observed[#observed]) do assert(intent.kind ~= "focus") end
  end,
}
