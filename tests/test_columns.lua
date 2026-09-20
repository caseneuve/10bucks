local Columns = require("lib.layouts.columns")

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
    config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.5 },
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

local function assertValid(state, memberIds, ctx)
  local valid, err = Columns.validate(state, memberIds, ctx or context())
  assert(valid, err)
end

return {
  ["COL-002 COL-003 WIN-003: admission splits a multi-member sole stack once, then appends to active column"] = function()
    local state = { stacks = { { members = { "one", "two" }, selectedId = "two" } }, activeStack = 1, ratio = 0.5 }
    assertValid(state, { "one", "two" })
    state = Columns.reduce(state, { type = "Admit", memberId = "three" }, context())
    assert(deepEqual(state.stacks[1].members, { "one", "two" }))
    assert(deepEqual(state.stacks[2].members, { "three" }))
    equal(state.activeStack, 2)
    equal(state.stacks[2].selectedId, "three")
    assert(Columns.reduce(state, { type = "Admit", memberId = "three" }, context()) == state)

    state = Columns.reduce(state, { type = "Admit", memberId = "four" }, context())
    assert(deepEqual(state.stacks[2].members, { "three", "four" }))
    equal(state.stacks[2].selectedId, "four")
    assertValid(state, { "one", "two", "three", "four" })
  end,

  ["COL-004 WIN-002 WIN-004 STATE-006 ENV-004: temporary-empty projection is full width and restores physical split without reassignment"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    local before = { stacks = {
      { members = { "one", "two" }, selectedId = "two" },
      { members = { "three" }, selectedId = "three" },
    }, activeStack = 2, ratio = 0.5 }
    local workArea = { x = 10, y = 20, w = 1000, h = 600 }
    local onlyLeft = Columns.project(state, available("one", "two"), workArea, context())
    equal(#onlyLeft, 2)
    for _, intent in ipairs(onlyLeft) do
      equal(intent.displayId, "built-in")
      equal(intent.spaceId, "space-1")
      assert(deepEqual(intent.frame, workArea))
    end
    assert(deepEqual(state, before))

    local restored = Columns.project(state, available("one", "three"), workArea, context())
    equal(#restored, 2)
    assert(deepEqual(restored[1].frame, { x = 10, y = 20, w = 500, h = 600 }))
    assert(deepEqual(restored[2].frame, { x = 510, y = 20, w = 500, h = 600 }))
    assert(deepEqual(state, before))
  end,

  ["COL-005: permanent-empty removal re-splits two or more surviving windows"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    state = Columns.reduce(state, { type = "Remove", memberId = "three" }, context())
    equal(#state.stacks, 2)
    assert(deepEqual(state.stacks[1].members, { "one" }))
    assert(deepEqual(state.stacks[2].members, { "two" }))
    assertValid(state, { "one", "two" })

    state = Columns.reduce(state, { type = "Remove", memberId = "two" }, context())
    equal(#state.stacks, 1)
    assert(deepEqual(state.stacks[1].members, { "one" }))
    equal(state.activeStack, 1)
  end,

  ["COL-005 FOCUS-004: removing sole focused column member keeps that physical column active after re-split"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    equal(state.activeStack, 2)
    state = Columns.reduce(state, { type = "Remove", memberId = "three" }, context())
    equal(#state.stacks, 2)
    equal(state.activeStack, 2)
    equal(state.stacks[2].selectedId, "two")
    assert(deepEqual(state.stacks[1].members, { "one" }))
    assert(deepEqual(state.stacks[2].members, { "two" }))
  end,

  ["COL-006 WIN-002: guarded move preserves source order, appends/focuses destination, and never creates an empty placeholder"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    state = Columns.reduce(state, { type = "MoveFocusedToOther" }, context())
    assert(deepEqual(state.stacks[1].members, { "one" }))
    assert(deepEqual(state.stacks[2].members, { "three", "two" }))
    equal(state.activeStack, 2)
    equal(state.stacks[2].selectedId, "two")
    assertValid(state, { "one", "two", "three" })

    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "one" }, context())
    assert(Columns.reduce(state, { type = "MoveFocusedToOther" }, context()) == state)
  end,

  ["COL-007: swap atomically exchanges ordered stacks and selections while active content follows the opposite physical side"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "one" }, context())
    state = Columns.reduce(state, { type = "SwapGroups" }, context())
    assert(deepEqual(state.stacks[1], { members = { "three" }, selectedId = "three" }))
    assert(deepEqual(state.stacks[2], { members = { "one", "two" }, selectedId = "one" }))
    equal(state.activeStack, 2)
  end,

  ["COL-008: physical ratio is bounded, retained across unrelated reductions, and changes only through resize/reset or cold initialization"] = function()
    local initial = Columns.initialState({ "one", "two" }, context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } }))
    equal(initial.ratio, 0.6)
    local state = Columns.reduce(initial, { type = "ResizeRatio", ratio = 0.7 }, context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } }))
    equal(state.ratio, 0.7)
    state = Columns.reduce(state, { type = "ResizeRatioDelta", delta = -0.05 }, context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } }))
    assert(math.abs(state.ratio - 0.65) < 0.000001)
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "one" }, context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } }))
    assert(math.abs(state.ratio - 0.65) < 0.000001)
    assert(Columns.reduce(state, { type = "ResizeRatio", ratio = 0.8 }, context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } })) == state)
    state = Columns.reduce(state, { type = "ResetRatio" }, context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } }))
    equal(state.ratio, 0.6)
  end,

  ["COL-009: cold bootstrap preserves supplied deterministic order and focuses the column containing focused managed member"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context({ focusedMemberId = "one" }))
    assert(deepEqual(state.stacks[1].members, { "one", "two" }))
    assert(deepEqual(state.stacks[2].members, { "three" }))
    equal(state.stacks[1].selectedId, "one")
    equal(state.activeStack, 1)

    state = Columns.initialState({ "one", "two", "three" }, context({ focusedMemberId = "unknown" }))
    equal(state.activeStack, 2)
    equal(state.stacks[2].selectedId, "three")
  end,

  ["COL-001 WIN-002 WIN-004: focus observations and group/member navigation change selection only with available destinations"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "one" }, context())
    equal(state.activeStack, 1)
    assert(Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "unknown" }, context()) == state)
    state = Columns.reduce(state, { type = "FocusNext" }, context({ availableMembers = available("one", "three") }))
    equal(state.stacks[1].selectedId, "one")
    assert(Columns.reduce(state, { type = "FocusNextGroup" }, context({ availableMembers = available("one") })) == state)
    state = Columns.reduce(state, { type = "FocusNextGroup" }, context({ availableMembers = available("one", "three") }))
    equal(state.activeStack, 2)
    equal(state.stacks[2].selectedId, "three")

    state = Columns.reduce(state, { type = "Admit", memberId = "four" }, context())
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "three" }, context())
    state = Columns.reduce(state, { type = "FocusNext" }, context({ availableMembers = available("three", "four") }))
    equal(state.stacks[2].selectedId, "four")
    state = Columns.reduce(state, { type = "FocusPrevious" }, context({ availableMembers = available("three", "four") }))
    equal(state.stacks[2].selectedId, "three")
    local status = Columns.status(state, available("three", "four"))
    equal(status.position, 1)
    equal(status.count, 2)
    equal(status.groupPosition, 2)
    equal(status.groupCount, 2)
  end,

  ["COL-001 STATE-006: empty columns state is valid and every structural or focus command is a safe no-op"] = function()
    local state = Columns.initialState({}, context())
    assertValid(state, {})
    for _, event in ipairs({
      { type = "FocusNext" },
      { type = "FocusPrevious" },
      { type = "FocusNextGroup" },
      { type = "FocusPreviousGroup" },
      { type = "MoveFocusedToOther" },
      { type = "SwapGroups" },
    }) do
      assert(Columns.reduce(state, event, context()) == state)
    end
    equal(#Columns.project(state, available(), { x = 1, y = 2, w = 300, h = 400 }, context()), 0)
    assert(deepEqual(Columns.status(state, available()), {
      position = nil, count = 0, groupPosition = nil, groupCount = 0,
    }))
  end,

  ["COL-005 FOCUS-004: removing a selected middle member preserves order and selects its stable predecessor"] = function()
    local state = Columns.initialState({ "one", "two", "three", "four" }, context())
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    state = Columns.reduce(state, { type = "Remove", memberId = "two" }, context())
    assert(deepEqual(state.stacks[1].members, { "one", "three" }))
    equal(state.stacks[1].selectedId, "one")
    equal(state.activeStack, 1)
    assertValid(state, { "one", "three", "four" })
  end,

  ["COL-008 STATE-006: ratio remains physical across focus and swap, and available peers share their column frame without mutation"] = function()
    local ratioContext = context({ config = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.6 } })
    local state = Columns.initialState({ "one", "two", "three" }, ratioContext)
    state = Columns.reduce(state, { type = "ResizeRatio", ratio = 0.7 }, ratioContext)
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "one" }, ratioContext)
    local workArea = { x = 10, y = 20, w = 1000, h = 600 }
    local before = { stacks = {
      { members = { "one", "two" }, selectedId = "one" },
      { members = { "three" }, selectedId = "three" },
    }, activeStack = 1, ratio = 0.7 }
    local intents = Columns.project(state, available("one", "two", "three"), workArea, ratioContext)
    assert(deepEqual(intents[1].frame, { x = 10, y = 20, w = 700, h = 600 }))
    assert(deepEqual(intents[2].frame, intents[1].frame))
    assert(deepEqual(intents[3].frame, { x = 10 + workArea.w * 0.7, y = 20, w = workArea.w * (1 - 0.7), h = 600 }))
    assert(deepEqual(state, before))

    state = Columns.reduce(state, { type = "SwapGroups" }, ratioContext)
    equal(state.ratio, 0.7)
    equal(state.activeStack, 2)
    intents = Columns.project(state, available("one", "two", "three"), workArea, ratioContext)
    equal(intents[1].windowId, "three")
    assert(deepEqual(intents[1].frame, { x = 10, y = 20, w = 700, h = 600 }))
    assert(deepEqual(intents[2].frame, { x = 10 + workArea.w * 0.7, y = 20, w = workArea.w * (1 - 0.7), h = 600 }))
    assert(deepEqual(intents[3].frame, intents[2].frame))
    equal(state.ratio, 0.7)
  end,

  ["LAY-003 COL-003: synchronize retains columns and ratio, removes absent IDs, appends missing by active-column admission, and aligns focus"] = function()
    local state = Columns.initialState({ "one", "two", "three" }, context())
    state = Columns.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, context())
    state = Columns.reduce(state, { type = "ResizeRatio", ratio = 0.7 }, context())
    state = Columns.reduce(state, { type = "Synchronize", memberIds = { "one", "three", "four" } }, context({ focusedMemberId = "four" }))
    assert(deepEqual(state.stacks[1].members, { "one", "four" }))
    assert(deepEqual(state.stacks[2].members, { "three" }))
    equal(state.activeStack, 1)
    equal(state.stacks[1].selectedId, "four")
    equal(state.ratio, 0.7)
    assert(Columns.reduce(state, { type = "Synchronize", memberIds = { "one", "three", "four" } }, context({ focusedMemberId = "four" })) == state)
    assertValid(state, { "one", "three", "four" })
  end,

  ["COL-001 STATE-003: validation rejects empty/extra stacks, duplicates, member disagreement, bad selections/active/ratio, malformed arrays, and non-plain state"] = function()
    local valid = Columns.initialState({ "one", "two" }, context())
    local cases = {
      { stacks = {}, activeStack = nil, ratio = 0.5 },
      { stacks = { { members = {}, selectedId = nil } }, activeStack = 1, ratio = 0.5 },
      { stacks = { { members = { "one" }, selectedId = "one" }, { members = { "two" }, selectedId = "two" }, { members = { "three" }, selectedId = "three" } }, activeStack = 1, ratio = 0.5 },
      { stacks = { { members = { "one" }, selectedId = "one" }, { members = { "one" }, selectedId = "one" } }, activeStack = 1, ratio = 0.5 },
      { stacks = { { members = { "one" }, selectedId = "unknown" } }, activeStack = 1, ratio = 0.5 },
      { stacks = { { members = { "one" }, selectedId = "one" } }, activeStack = 2, ratio = 0.5 },
      { stacks = { { members = { "one" }, selectedId = "one" } }, activeStack = 1, ratio = 0.9 },
      { stacks = { [1] = { members = { "one" }, selectedId = "one" }, [3] = { members = { "two" }, selectedId = "two" } }, activeStack = 1, ratio = 0.5 },
      setmetatable({ stacks = { { members = { "one" }, selectedId = "one" } }, activeStack = 1, ratio = 0.5 }, {}),
      valid,
    }
    local members = {
      { "one" }, { "one" }, { "one", "two", "three" }, { "one" }, { "one" }, { "one" }, { "one" }, { "one", "two" }, { "one" }, { "one", "three" },
    }
    for index, state in ipairs(cases) do
      local ok = Columns.validate(state, members[index], context())
      assert(not ok)
    end
  end,
}
