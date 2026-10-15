local Stack = require("lib.layouts.stack")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function deepEqual(actual, expected)
  if type(actual) ~= type(expected) then return false end
  if type(actual) ~= "table" then return actual == expected end
  for key, value in pairs(actual) do
    if not deepEqual(value, expected[key]) then return false end
  end
  for key in pairs(expected) do
    if actual[key] == nil then return false end
  end
  return true
end

local function assertValid(state, memberIds)
  local valid, err = Stack.validate(state, memberIds)
  assert(valid, err)
end

local function available(...)
  local result = {}
  for _, id in ipairs({ ... }) do result[id] = true end
  return result
end

local function context(overrides)
  local value = {
    displayId = "built-in",
    spaceId = "space-1",
    availableMembers = {},
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

return {
  ["STACK-001 COL-010 STATE-006: shared gap insets available stack members once and caps uniformly"] = function()
    local state = Stack.initialState({ "one", "two", "three" })
    local area = { x = 100, y = 132, w = 300, h = 400 }
    local availability = available("one", "three")
    for _, gap in ipairs({ 0, 8, 2.5, 1e300 }) do
      local ctx = context({ config = { columnGap = gap } })
      local intents = Stack.project(state, availability, area, ctx)
      local effective = math.min(gap, 150)
      equal(#intents, 2)
      for _, intent in ipairs(intents) do
        assert(deepEqual(intent.frame, { x = 100 + effective, y = 132 + effective,
          w = 300 - 2 * effective, h = 400 - 2 * effective }))
      end
      assert(intents[1].frame ~= intents[2].frame)
      equal(ctx.config.columnGap, gap)
    end
    assert(deepEqual(area, { x = 100, y = 132, w = 300, h = 400 }))
    assert(deepEqual(availability, available("one", "three")))
    assert(deepEqual(state, { members = { "one", "two", "three" }, selectedId = "three" }))
    for _, gap in ipairs({ -1, math.huge, 0/0, false }) do
      assert(not pcall(Stack.project, state, availability, area, context({ config = { columnGap = gap } })))
    end
  end,
  ["ENV-004 STACK-001 STATE-006: projection emits equal plain frame intents with explicit display and Space identity"] = function()
    local state = Stack.initialState({ "one", "two", "three" })
    local before = { members = { "one", "two", "three" }, selectedId = "three" }
    local workArea = { x = 12, y = 34, w = 900, h = 700 }
    local intents = Stack.project(state, available("one", "three"), workArea, context())

    equal(#intents, 2)
    for index, memberId in ipairs({ "one", "three" }) do
      equal(intents[index].windowId, memberId)
      equal(intents[index].displayId, "built-in")
      equal(intents[index].spaceId, "space-1")
      assert(deepEqual(intents[index].frame, workArea))
      assert(intents[index].frame ~= workArea)
    end
    assert(deepEqual(state, before))
  end,

  ["WIN-003 STACK-002: admission appends once, selects the member, and navigation cycles available order"] = function()
    local state = Stack.initialState({ "one" })
    state = Stack.reduce(state, { type = "Admit", memberId = "two" }, context())
    equal(state.members[1], "one")
    equal(state.members[2], "two")
    equal(state.selectedId, "two")
    assert(Stack.reduce(state, { type = "Admit", memberId = "two" }, context()) == state)

    local navigation = context({ availableMembers = available("one", "two") })
    state = Stack.reduce(state, { type = "FocusNext" }, navigation)
    equal(state.selectedId, "one")
    state = Stack.reduce(state, { type = "FocusPrevious" }, navigation)
    equal(state.selectedId, "two")
    assertValid(state, { "one", "two" })
  end,

  ["WIN-002 WIN-004 STACK-002: focus and availability never admit or reorder, and unavailable selection has directional deterministic navigation"] = function()
    local state = Stack.initialState({ "one", "two", "three" })
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    equal(state.selectedId, "two")
    assert(Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "unknown" }, context()) == state)
    assert(deepEqual(state.members, { "one", "two", "three" }))

    local nextContext = context({ availableMembers = available("one", "three") })
    state = Stack.reduce(state, { type = "FocusNext" }, nextContext)
    equal(state.selectedId, "three")
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    state = Stack.reduce(state, { type = "FocusNext" }, nextContext)
    equal(state.selectedId, "three")
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    state = Stack.reduce(state, { type = "FocusPrevious" }, nextContext)
    equal(state.selectedId, "one")

    local unknownSelection = { members = { "one", "two", "three" }, selectedId = nil }
    unknownSelection = Stack.reduce(unknownSelection, { type = "FocusNext" }, nextContext)
    equal(unknownSelection.selectedId, "one")
    unknownSelection = { members = { "one", "two", "three" }, selectedId = nil }
    unknownSelection = Stack.reduce(unknownSelection, { type = "FocusPrevious" }, nextContext)
    equal(unknownSelection.selectedId, "three")
    assert(deepEqual(state.members, { "one", "two", "three" }))
  end,

  ["WIN-004 STATE-006 STACK-001: removal alone changes membership; unknown availability only omits projection and status"] = function()
    local state = Stack.initialState({ "one", "two" })
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    local unknownAvailability = {}
    equal(#Stack.project(state, unknownAvailability, { x = 0, y = 0, w = 1, h = 1 }, context()), 0)
    local status = Stack.status(state, unknownAvailability)
    equal(status.position, nil)
    equal(status.count, 0)
    assert(deepEqual(state.members, { "one", "two" }))
    equal(state.selectedId, "two")

    state = Stack.reduce(state, { type = "Remove", memberId = "two" }, context())
    assert(deepEqual(state.members, { "one" }))
    equal(state.selectedId, "one")
    assertValid(state, { "one" })
  end,

  ["STACK-002: status uses available position/count without changing durable selection"] = function()
    local state = Stack.initialState({ "one", "two", "three" })
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "three" }, context())
    local status = Stack.status(state, available("one", "three"))
    equal(status.position, 2)
    equal(status.count, 2)
    equal(state.selectedId, "three")

    status = Stack.status(state, available("one"))
    equal(status.position, nil)
    equal(status.count, 1)
    equal(state.selectedId, "three")
  end,

  ["LAY-003 STACK-002: synchronize retains surviving order, appends missing members, aligns focus, and is idempotent"] = function()
    local state = Stack.initialState({ "one", "two", "three" })
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    state = Stack.reduce(state, { type = "Synchronize", memberIds = { "one", "three", "four" } }, context({ focusedMemberId = "three" }))
    assert(deepEqual(state.members, { "one", "three", "four" }))
    equal(state.selectedId, "three")
    assert(Stack.reduce(state, { type = "Synchronize", memberIds = { "one", "three", "four" } }, context({ focusedMemberId = "three" })) == state)
    assertValid(state, { "one", "three", "four" })
  end,

  ["COL-007 LAY-004: physical left/right group focus is unsupported and does not mutate stack"] = function()
    local state = Stack.initialState({ "one", "two" })
    assert(not Stack.supports("FocusLeftGroup") and not Stack.supports("FocusRightGroup"))
    assert(not pcall(Stack.reduce, state, { type = "FocusLeftGroup" }, context({ availableMembers = available("one", "two") })))
    assert(deepEqual(state, { members = { "one", "two" }, selectedId = "two" }))
  end,

  ["STATE-003: validation rejects malformed plain data, duplicate/unknown members, invalid selection, and member-set disagreement"] = function()
    local validState = Stack.initialState({ "one", "two" })
    local cases = {
      { state = { members = { "one", "one" }, selectedId = "one" }, memberIds = { "one" } },
      { state = { members = { "one", "unknown" }, selectedId = "one" }, memberIds = { "one", "two" } },
      { state = { members = { "one" }, selectedId = "unknown" }, memberIds = { "one" } },
      { state = { members = { [1] = "one", [3] = "two" }, selectedId = "one" }, memberIds = { "one", "two" } },
      { state = { members = { "one" }, selectedId = "one", extra = true }, memberIds = { "one" } },
      { state = validState, memberIds = { "one", "three" } },
      { state = setmetatable({ members = { "one" }, selectedId = "one" }, {}), memberIds = { "one" } },
    }
    for _, case in ipairs(cases) do
      local valid = Stack.validate(case.state, case.memberIds)
      assert(not valid)
    end
  end,
}
