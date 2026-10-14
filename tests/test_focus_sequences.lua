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

local function ready(id, created)
  local event = { type = "WindowReady", id = id, title = id, displayId = "built-in", spaceId = "space-1",
    application = { pid = 1, name = "Example", bundleID = "example.app" } }
  if not created then
    event.metadata = { id = id, application = event.application, title = id, displayId = event.displayId,
      spaceId = event.spaceId, origin = "bootstrap", createdAfterStart = false, role = "AXWindow",
      subrole = "AXStandardWindow", modal = false, movable = true, resizable = true, selfProcess = false }
    event.decision = { action = "manage" }
  end
  return event
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
    name = "FOCUS-004 WIN-002: close reveals prior focused source survivor without reordering navigation",
    run = function(h)
      for _, layout in ipairs({ "stack", "columns" }) do
        for _, prior in ipairs({ "A", "B" }) do
          local test = harness()
          test:send(ready("A")):send(ready("B")):send(ready("C"))
          if layout == "columns" then test:send({ type = "CycleLayout" }) end
          test:send({ type = "ActualFocusChanged", id = prior }):send(ready("D", true))
              :send({ type = "ActualFocusChanged", id = "D" })
              :send({ type = "ActualFocusChanged", id = "excluded" })
              :send({ type = "WindowDestroyed", id = "D" })
          equal(test:focusIntent().windowId, prior)
          local state = test.core:state()
          equal(table.concat(state.manager.spaces["space-1"].memberIds, ","), "A,B,C")
          if layout == "columns" then
            equal(table.concat(test:columns().stacks[1].members, ","), "A,B")
            equal(test:columns().stacks[2].selectedId, "C")
          end
        end
      end
    end,
  },
  {
    name = "FOCUS-004: unavailable prior source skips to surviving local history, not other column",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "ActualFocusChanged", id = "A" })
       :send(ready("D", true)):send({ type = "ActualFocusChanged", id = "D" })
       :send({ type = "WindowMinimized", id = "A" }):send({ type = "WindowDestroyed", id = "D" })
      equal(h:focusIntent().windowId, "B")
      equal(h:columns().stacks[2].selectedId, "C")
    end,
  },
  {
    name = "FOCUS-004: deliberate source or peer focus before background close remains authoritative",
    run = function(h)
      for _, target in ipairs({ "B", "C" }) do
        local test = harness()
        test:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
         :send({ type = "ActualFocusChanged", id = "A" }):send(ready("D", true))
         :send({ type = "ActualFocusChanged", id = "D" }):send({ type = "ActualFocusChanged", id = target })
         :send({ type = "WindowDestroyed", id = "D" })
        assert(test:focusIntent() == nil)
        equal(test.core:state().manager.focus.actualWindow.id, target)
      end
    end,
  },
  {
    name = "COL-007 FOCUS-006: h/l are physical, retain both tops, and never toggle or cycle",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "ActualFocusChanged", id = "C" })
      h:send({ type = "FocusLeftGroup" })
      equal(h:focusIntent().windowId, "B")
      equal(h:columns().stacks[1].selectedId, "B"); equal(h:columns().stacks[2].selectedId, "C")
      h:send({ type = "FocusLeftGroup" }); assert(h:focusIntent() == nil); equal(h:columns().activeStack, 1)
      h:send({ type = "FocusRightGroup" }); equal(h:focusIntent().windowId, "C")
      h:send({ type = "FocusRightGroup" }); assert(h:focusIntent() == nil); equal(h:columns().activeStack, 2)
      equal(h:columns().stacks[1].selectedId, "B"); equal(h:columns().stacks[2].selectedId, "C")
    end,
  },
  {
    name = "COL-007 WIN-004: directional travel uses top available fallback without mutating retained selection",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "ActualFocusChanged", id = "C" })
       :send({ type = "WindowMinimized", id = "B" }):send({ type = "FocusLeftGroup" })
      equal(h:focusIntent().windowId, "A")
      equal(h:columns().activeStack, 1)
      equal(h:columns().stacks[1].selectedId, "B")
      equal(h:columns().stacks[2].selectedId, "C")
    end,
  },
  {
    name = "FOCUS-006: native focus immediately changes active selection only when no request is pending",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send({ type = "ActualFocusChanged", id = "B" })
      equal(h:columns().activeStack, 2)
      h:send({ type = "FocusLeftGroup" }); equal(h:focusIntent().windowId, "A")
      h:send({ type = "ActualFocusChanged", id = "A" })
      h:send({ type = "FocusRightGroup" }); equal(h:focusIntent().windowId, "B")
    end,
  },
  {
    name = "LAY-003 FOCUS-001: layout roundtrip preserves managed or last-managed focus and other group top",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send(ready("C")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "B" }):send({ type = "ActualFocusChanged", id = "C" })
       :send({ type = "CycleLayout" }):send({ type = "CycleLayout" })
      equal(h:columns().activeStack, 2); equal(h:columns().stacks[1].selectedId, "B")
      h:send({ type = "FocusLeftGroup" }); equal(h:focusIntent().windowId, "B")
      h:send({ type = "ActualFocusChanged", id = "B" }) -- confirm requested left focus
       :send({ type = "ActualFocusChanged", id = "C" }):send({ type = "ActualFocusChanged", id = "popup" })
       :send({ type = "CycleLayout" }):send({ type = "CycleLayout" })
      equal(h:columns().activeStack, 2); equal(h:columns().stacks[1].selectedId, "B")
    end,
  },
  {
    name = "WIN-003 FOCUS-006: admission request survives delayed metadata and stale actual callback",
    run = function(h)
      h:send(ready("A")):send(ready("B")):send({ type = "CycleLayout" })
       :send({ type = "ActualFocusChanged", id = "A" }):send(ready("C", true))
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
       :send({ type = "WindowDestroyed", id = "C" })
      -- Host normalizes invalid-resource removal before sampling fallback focus.
      equal(h:focusIntent().windowId, "A"); equal(h:columns().activeStack, 1)
      h:send({ type = "ActualFocusChanged", id = "B" })
      equal(h:desired().targetId, "A"); assert(h:desired().pending)

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
    name = "FOCUS-005: explicit same-Space global target focuses without consulting per-Core history",
    run = function(h)
      h:send(ready("A")):send({ type = "ActualFocusChanged", id = "A" })
       :send(ready("B")):send({ type = "ActualFocusChanged", id = "B" })
       :send({ type = "FocusTarget", windowId = "A" })
      equal(h:focusIntent().windowId, "A")
      equal(h:desired().targetId, "A"); assert(h:desired().pending)
      h:send({ type = "ActualFocusChanged", id = "B" })
      equal(h:desired().targetId, "A"); assert(h:desired().pending)
      h:send({ type = "ActualFocusChanged", id = "A" }); assert(not h:desired().pending)
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
