local Coordinator = require("lib.layouts.coordinator")
local Stack = require("lib.layouts.stack")
local Columns = require("lib.layouts.columns")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function deepEqual(actual, expected)
  if type(actual) ~= type(expected) then return false end
  if type(actual) ~= "table" then return actual == expected end
  for key, value in pairs(actual) do if not deepEqual(value, expected[key]) then return false end end
  for key in pairs(expected) do if actual[key] == nil then return false end end
  return true
end

local function dependencies()
  return {
    layoutIds = { "stack", "columns" },
    registry = { stack = Stack, columns = Columns },
    layoutConfigs = { columns = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.5 } },
  }
end

local function context(overrides)
  local value = { displayId = "built-in", spaceId = "space-1", availableMembers = {} }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

local function assertValid(state, members, ctx)
  local valid, err = Coordinator.validate(state, members, ctx or context(), dependencies())
  assert(valid, err)
end

return {
  ["LAY-001: independent per-Space coordinator states retain layout choice, ratio, selection, and membership independently"] = function()
    local first = Coordinator.initialState({ "one", "two" }, context(), dependencies())
    local second = Coordinator.initialState({ "three", "four" }, context({ spaceId = "space-2" }), dependencies())
    first = Coordinator.reduce(first, { type = "CycleLayout" }, { "one", "two" }, context({ focusedMemberId = "one" }), dependencies())
    first = Coordinator.reduce(first, { type = "ResizeRatio", ratio = 0.7 }, { "one", "two" }, context(), dependencies())
    first = Coordinator.reduce(first, { type = "FocusPrevious" }, { "one", "two" }, context({ availableMembers = { one = true, two = true } }), dependencies())

    equal(first.activeLayoutId, "columns")
    equal(first.layouts.columns.ratio, 0.7)
    equal(first.layouts.columns.activeStack, 1)
    equal(second.activeLayoutId, "stack")
    assert(second.layouts.columns == nil)
    equal(second.layouts.stack.selectedId, "four")
    assertValid(first, { "one", "two" })
    assertValid(second, { "three", "four" }, context({ spaceId = "space-2" }))
  end,

  ["LAY-002 LAY-003: relative cycling wraps and every activation deterministically synchronizes retained target state"] = function()
    local state = Coordinator.initialState({ "one", "two", "three" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { "one", "two", "three" }, context({ focusedMemberId = "two" }), dependencies())
    equal(state.activeLayoutId, "columns")
    equal(state.layouts.columns.activeStack, 1)
    equal(state.layouts.columns.stacks[1].selectedId, "two")
    state = Coordinator.reduce(state, { type = "ResizeRatio", ratio = 0.7 }, { "one", "two", "three" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "ActivateLayout", layoutId = "stack" }, { "one", "three", "four" }, context({ focusedMemberId = "three" }), dependencies())
    equal(state.activeLayoutId, "stack")
    assert(deepEqual(state.layouts.stack.members, { "one", "three", "four" }))
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { "one", "three", "four" }, context({ focusedMemberId = "four" }), dependencies())
    equal(state.activeLayoutId, "columns")
    assert(deepEqual(state.layouts.columns.stacks[1].members, { "one", "four" }))
    assert(deepEqual(state.layouts.columns.stacks[2].members, { "three" }))
    equal(state.layouts.columns.ratio, 0.7)
    equal(state.layouts.columns.stacks[1].selectedId, "four")
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { "one", "three", "four" }, context(), dependencies())
    equal(state.activeLayoutId, "stack")
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { "one", "three", "four" }, context(), dependencies())
    equal(state.activeLayoutId, "columns")
    assertValid(state, { "one", "three", "four" })
  end,

  ["LAY-002 LAY-003: numeric native member IDs synchronize and cycle with focused selection"] = function()
    local state = Coordinator.initialState({ 101, 202 }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { 101, 202 }, context({ focusedMemberId = 101 }), dependencies())
    equal(state.activeLayoutId, "columns")
    equal(state.layouts.columns.stacks[1].selectedId, 101)
    state = Coordinator.reduce(state, { type = "ActivateLayout", layoutId = "stack" }, { 101, 303 }, context({ focusedMemberId = 303 }), dependencies())
    assert(deepEqual(state.layouts.stack.members, { 101, 303 }))
    equal(state.layouts.stack.selectedId, 303)
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { 101, 303 }, context({ focusedMemberId = 303 }), dependencies())
    assert(deepEqual(state.layouts.columns.stacks[1].members, { 101 }))
    assert(deepEqual(state.layouts.columns.stacks[2].members, { 303 }))
    equal(state.layouts.columns.stacks[2].selectedId, 303)
    assertValid(state, { 101, 303 })
  end,

  ["LAY-003: admission changes only the active layout while permanent removal reaches every instantiated retained layout"] = function()
    local state = Coordinator.initialState({ "one", "two" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { "one", "two" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "ActivateLayout", layoutId = "stack" }, { "one", "two" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "Admit", memberId = "three" }, { "one", "two", "three" }, context(), dependencies())
    assert(deepEqual(state.layouts.stack.members, { "one", "two", "three" }))
    assert(deepEqual(state.layouts.columns.stacks[2].members, { "two" }))
    state = Coordinator.reduce(state, { type = "Remove", memberId = "two" }, { "one", "three" }, context(), dependencies())
    assert(deepEqual(state.layouts.stack.members, { "one", "three" }))
    assert(deepEqual(state.layouts.columns.stacks[1].members, { "one" }))
    assert(#state.layouts.columns.stacks == 1)
    assertValid(state, { "one", "three" })
  end,

  ["LAY-004: registry capability dispatch never needs layout IDs and rejects unsupported events without mutation"] = function()
    local state = Coordinator.initialState({ "one" }, context(), dependencies())
    local nextState, capability = Coordinator.reduce(state, { type = "MoveFocusedToOther" }, { "one" }, context(), dependencies())
    assert(nextState == state)
    equal(capability.handled, false)
    equal(capability.reason, "unsupported")
    local valid = Coordinator.validate({ activeLayoutId = "missing", layouts = {} }, { "one" }, context(), dependencies())
    assert(not valid)
  end,

  ["STATE-006 ENV-004: projection and status delegate with explicit display/Space context without mutating coordinator state"] = function()
    local state = Coordinator.initialState({ "one", "two" }, context(), dependencies())
    local before = { activeLayoutId = "stack", layouts = { stack = { members = { "one", "two" }, selectedId = "two" } } }
    local intents = Coordinator.project(state, { one = true, two = true }, { x = 1, y = 2, w = 300, h = 400 }, context(), dependencies())
    equal(#intents, 2)
    equal(intents[1].displayId, "built-in")
    equal(intents[1].spaceId, "space-1")
    local status = Coordinator.status(state, { one = true }, context(), dependencies())
    equal(status.count, 1)
    assert(deepEqual(state, before))
  end,

  ["LAY-003 STATE-003: validation permits inactive retained subsets but rejects non-plain state and active membership drift"] = function()
    local state = Coordinator.initialState({ "one", "two" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "CycleLayout" }, { "one", "two" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "ActivateLayout", layoutId = "stack" }, { "one", "two" }, context(), dependencies())
    state = Coordinator.reduce(state, { type = "Admit", memberId = "three" }, { "one", "two", "three" }, context(), dependencies())
    assertValid(state, { "one", "two", "three" })
    local broken = { activeLayoutId = state.activeLayoutId, layouts = state.layouts }
    broken.layouts.stack = { members = { "one" }, selectedId = "one" }
    assert(not Coordinator.validate(broken, { "one", "two", "three" }, context(), dependencies()))
    broken = { activeLayoutId = "stack", layouts = { stack = setmetatable({ members = { "one", "two", "three" }, selectedId = "three" }, {}) } }
    assert(not Coordinator.validate(broken, { "one", "two", "three" }, context(), dependencies()))
  end,
}
