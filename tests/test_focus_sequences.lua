local Core = require("lib.core")
local Model = require("lib.model")
local Stack = require("lib.layouts.stack")
local Columns = require("lib.layouts.columns")

local function equal(actual, expected, message)
  assert(actual == expected, message or string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function dependencies()
  return {
    layoutIds = { "stack", "columns" }, registry = { stack = Stack, columns = Columns },
    layoutConfigs = { columns = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.5 } },
  }
end

local function ready(id)
  return { type = "WindowReady", id = id, title = id, displayId = "built-in", spaceId = "space-1",
    application = { pid = 1, name = "Example", bundleID = "example.app" } }
end

local function harness()
  local observed = {}
  local core = Core.new({
    displayId = "built-in", regularSpaceId = "space-1", workArea = { x = 0, y = 0, w = 1000, h = 600 },
    initialModelState = Model.new({ displayId = "built-in", activeRegularSpaceId = "space-1" }),
    layoutDependencies = dependencies(),
    observeIntents = function(intents) observed[#observed + 1] = intents end,
  })
  local value = { core = core, observed = observed }
  function value:send(event) assert(self.core:submit(event)); return self end
  function value:focusIntent()
    for _, intent in ipairs(self.observed[#self.observed] or {}) do if intent.kind == "focus" then return intent end end
  end
  function value:desired() return self.core:state().manager.focus.desiredBySpace["space-1"] end
  function value:columns() return self.core:state().coordinators["space-1"].layouts.columns end
  return value
end

local cases = {
  {
    name = "COL-007 FOCUS-006 CMD-005: group travel targets retained tops and every rapid h/l counts",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "ActualFocusChanged", id = "C" })
      h:send({ type = "FocusPreviousGroup" })
      equal(h:focusIntent().windowId, "B")
      equal(h:columns().stacks[1].selectedId, "B"); equal(h:columns().stacks[2].selectedId, "C")
      h:send({ type = "FocusNextGroup" }):send({ type = "FocusPreviousGroup" }):send({ type = "FocusNextGroup" })
      equal(h:desired().targetId, "C"); equal(h:columns().activeStack, 2)
      equal(h:columns().stacks[1].selectedId, "B"); equal(h:columns().stacks[2].selectedId, "C")
    end,
  },
  {
    name = "FOCUS-006: native focus immediately changes active selection only when no request is pending",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send({ type = "ActualFocusChanged", id = "B" })
      equal(h:columns().activeStack, 2)
      h:send({ type = "FocusPreviousGroup" }); equal(h:focusIntent().windowId, "A")
      h:send({ type = "ActualFocusChanged", id = "A" })
      h:send({ type = "FocusNextGroup" }); equal(h:focusIntent().windowId, "B")
    end,
  },
  {
    name = "LAY-003 FOCUS-001: layout roundtrip preserves managed or last-managed focus and other group top",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "ActualFocusChanged", id = "C" })
       :send({ type = "CycleLayout" }):send({ type = "CycleLayout" })
      equal(h:columns().activeStack, 2); equal(h:columns().stacks[1].selectedId, "B")
      h:send({ type = "FocusPreviousGroup" }); equal(h:focusIntent().windowId, "B")
      h:send({ type = "ActualFocusChanged", id = "C" }):send({ type = "ActualFocusChanged", id = "popup" })
       :send({ type = "CycleLayout" }):send({ type = "CycleLayout" })
      equal(h:columns().activeStack, 2); equal(h:columns().stacks[1].selectedId, "B")
    end,
  },
  {
    name = "WIN-003 FOCUS-006: admission request survives delayed metadata and stale actual callback",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send(ready("C"))
      equal(h:desired().targetId, "C"); assert(h:desired().pending)
      h:send({ type = "WindowTitleChanged", id = "C", title = "ready later" })
      assert(h:focusIntent() == nil)
      h:send({ type = "ActualFocusChanged", id = "A" })
      assert(h:focusIntent() == nil)
      equal(h:desired().targetId, "C"); assert(h:desired().pending); equal(h:columns().stacks[1].selectedId, "C")
      h:send({ type = "ActualFocusChanged", id = "C" }); assert(not h:desired().pending)
      h:send({ type = "CycleLayout" }):send({ type = "CycleLayout" })
      equal(h:columns().stacks[1].selectedId, "C")
    end,
  },
  {
    name = "FOCUS-004 COL-005: focused destruction ignores transient fallback and background destruction preserves focus",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send(ready("C")):send({ type = "ActualFocusChanged", id = "C" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "WindowDestroyed", id = "C" })
      equal(h:focusIntent().windowId, "A"); equal(h:columns().activeStack, 1)

      local other = harness()
      other:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send(ready("C")):send({ type = "ActualFocusChanged", id = "C" })
       :send({ type = "WindowDestroyed", id = "C" })
      equal(other:focusIntent().windowId, "A")

      local background = harness()
      background:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send(ready("C")):send({ type = "ActualFocusChanged", id = "C" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "WindowDestroyed", id = "A" })
      equal(background:columns().activeStack, 2); equal(background:columns().stacks[1].selectedId, "C")
      assert(background:focusIntent() == nil)
    end,
  },
  {
    name = "COL-005 FOCUS-004: sole focused source column is re-split and recovers on the same physical side",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "C" }):send({ type = "WindowDestroyed", id = "C" })
      equal(h:columns().activeStack, 2); equal(h:columns().stacks[2].selectedId, "B")
      equal(h:focusIntent().windowId, "B")
    end,
  },
  {
    name = "CMD-005 FOCUS-006: rapid j/k reduce desired selection and only latest callback confirms",
    run = function(h)
      h:send(ready("A")):send({ type = "ActualFocusChanged", id = "A" }):send(ready("B"))
       :send({ type = "ActualFocusChanged", id = "B" }):send(ready("C")):send({ type = "ActualFocusChanged", id = "C" })
      h:send({ type = "FocusNext" }):send({ type = "FocusNext" }):send({ type = "FocusPrevious" })
      equal(h:desired().targetId, "A"); assert(h:desired().pending)
      local generation = h:desired().generation
      h:send({ type = "ActualFocusChanged", id = "B" })
      equal(h:desired().targetId, "A"); equal(h:desired().generation, generation); assert(h:desired().pending)
      h:send({ type = "ActualFocusChanged", id = "A" }); assert(not h:desired().pending)
    end,
  },
}

local suite = {}
for _, case in ipairs(cases) do suite[case.name] = function() case.run(harness()) end end
return suite
