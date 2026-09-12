local Model = require("lib.model")
local Runtime = require("lib.runtime")
local Coordinator = require("lib.layouts.coordinator")
local Stack = require("lib.layouts.stack")
local Columns = require("lib.layouts.columns")

-- This deliberately test-local composition exercises the pure seams without
-- becoming production composition. Its oracle is independent of Model's
-- member arrays and its PRNG has no dependency on math.random.
local DISPLAY, SPACE = "built-in", "space-1"
local STEPS = 240
local SEEDS = { 104729, 271828, 314159, 987643 }

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  assert(not seen[value], "test data unexpectedly cyclic")
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  seen[value] = nil
  return result
end

local function equal(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function sameSet(left, right)
  if #left ~= #right then return false end
  local seen = {}
  for _, value in ipairs(left) do seen[value] = (seen[value] or 0) + 1 end
  for _, value in ipairs(right) do
    if not seen[value] then return false end
    seen[value] = seen[value] - 1
    if seen[value] == 0 then seen[value] = nil end
  end
  return next(seen) == nil
end

local function fail(seed, step, action, message)
  error(string.format("seed=%d step=%d action=%s: %s", seed, step, action, message), 3)
end

local function assertThat(value, seed, step, action, message)
  if not value then fail(seed, step, action, message) end
end

local function dependencies()
  return {
    layoutIds = { "stack", "columns" },
    registry = { stack = Stack, columns = Columns },
    layoutConfigs = { columns = { minRatio = 0.25, maxRatio = 0.75, defaultRatio = 0.5 } },
  }
end

local function availability(manager)
  local result = {}
  for id, window in pairs(manager.windows) do result[id] = Model.isAvailable(window) end
  return result
end

local function context(manager)
  local actual = manager.focus.actualWindow.id
  return {
    displayId = DISPLAY,
    spaceId = SPACE,
    focusedMemberId = manager.windows[actual] and actual or nil,
    availableMembers = availability(manager),
  }
end

local function memberIds(manager)
  return manager.spaces[SPACE].memberIds
end

local function makeComposite()
  local manager = Model.new({ displayId = DISPLAY, activeRegularSpaceId = SPACE })
  return { manager = manager, coordinators = { [SPACE] = Coordinator.initialState({}, context(manager), dependencies()) } }
end

local function layoutMembers(coordinator)
  local result = {}
  for id, state in pairs(coordinator.layouts) do result[id] = Coordinator and dependencies().registry[id].memberIds(state) end
  return result
end

local function validateComposite(state)
  local valid, err = Model.validate(state.manager)
  if not valid then return false, err end
  local coordinator = state.coordinators[SPACE]
  if type(coordinator) ~= "table" then return false, "missing per-Space coordinator" end
  return Coordinator.validate(coordinator, memberIds(state.manager), context(state.manager), dependencies())
end

local function reduceComposite(current, transaction)
  local manager = current.manager
  if transaction.model then manager = Model.reduce(manager, transaction.model) end
  local coordinator = current.coordinators[SPACE]
  local oldIds, newIds = memberIds(current.manager), memberIds(manager)
  local old, new = {}, {}
  for _, id in ipairs(oldIds) do old[id] = true end
  for _, id in ipairs(newIds) do new[id] = true end
  local ctx = context(manager)

  -- The model's post-reduction member list is authoritative: propagate
  -- permanent removals, admissions, and actual managed focus in that order.
  for _, id in ipairs(oldIds) do
    if not new[id] then coordinator = Coordinator.reduce(coordinator, { type = "Remove", memberId = id }, newIds, ctx, dependencies()) end
  end
  for _, id in ipairs(newIds) do
    if not old[id] then coordinator = Coordinator.reduce(coordinator, { type = "Admit", memberId = id }, newIds, ctx, dependencies()) end
  end
  if transaction.model and transaction.model.type == "ActualFocusChanged" and manager.windows[transaction.model.id] then
    coordinator = Coordinator.reduce(coordinator, { type = "ManagedFocusObserved", memberId = transaction.model.id }, newIds, ctx, dependencies())
  end
  if transaction.command then coordinator = Coordinator.reduce(coordinator, transaction.command, newIds, ctx, dependencies()) end
  coordinator = Coordinator.reduce(coordinator, { type = "Synchronize" }, newIds, ctx, dependencies())
  return { manager = manager, coordinators = { [SPACE] = coordinator } }
end

local function projectComposite(committed)
  local before = copy(committed)
  local intents = Coordinator.project(committed.coordinators[SPACE], availability(committed.manager),
    { x = 10, y = 20, w = 1200, h = 800 }, context(committed.manager), dependencies())
  assert(equal(committed, before), "STATE-006 projection mutated committed composite state")
  return intents
end

local function ready(id, pid)
  return { type = "WindowReady", id = id, application = { pid = pid, bundleID = "example." .. pid, name = "Example" },
    title = "window-" .. id, displayId = DISPLAY, spaceId = SPACE }
end

local function prng(seed)
  local value = seed
  return function(limit)
    value = (value * 48271) % 2147483647
    return (value % limit) + 1
  end
end

local function actionFor(index, random)
  local names = {
    "ready", "duplicate-ready", "destroy", "terminate", "visible-false", "visible-true", "snapshot-absent",
    "minimize", "restore", "hide", "unhide", "fullscreen-enter", "fullscreen-exit", "focus-known", "focus-unknown",
    "cycle-layout", "focus-next", "focus-previous", "group-next", "group-previous", "move", "swap", "resize", "reset", "synchronize", "noop-focus",
  }
  return names[index <= #names and index or random(#names)]
end

local function windowId(random)
  return "w" .. random(7)
end

local function transactionFor(action, random, state)
  local manager = state.manager
  local ids = memberIds(manager)
  local known = ids[random(math.max(1, #ids))] or windowId(random)
  local pid = random(2) == 1 and 11 or 22
  local model, command
  if action == "ready" then model = ready(windowId(random), pid)
  elseif action == "duplicate-ready" then model = ready(known, pid)
  elseif action == "destroy" then model = { type = "WindowDestroyed", id = known }
  elseif action == "terminate" then model = { type = "ApplicationTerminated", pid = pid }
  elseif action == "visible-false" then model = { type = "WindowVisibilityObserved", id = known, visible = false }
  elseif action == "visible-true" then model = { type = "WindowVisibilityObserved", id = known, visible = true }
  elseif action == "snapshot-absent" then model = { type = "WindowAbsentFromSnapshot", id = known }
  elseif action == "minimize" then model = { type = "WindowMinimized", id = known }
  elseif action == "restore" then model = { type = "WindowRestored", id = known }
  elseif action == "hide" then model = { type = "ApplicationHidden", pid = pid }
  elseif action == "unhide" then model = { type = "ApplicationUnhidden", pid = pid }
  elseif action == "fullscreen-enter" then model = { type = "WindowEnteredNativeFullscreen", id = known }
  elseif action == "fullscreen-exit" then model = { type = "WindowExitedNativeFullscreen", id = known }
  elseif action == "focus-known" then model = { type = "ActualFocusChanged", id = known, title = "focused" }
  elseif action == "focus-unknown" then model = { type = "ActualFocusChanged", id = "unknown-" .. random(5), title = "popup" }
  elseif action == "cycle-layout" then command = { type = "CycleLayout" }
  elseif action == "focus-next" then command = { type = "FocusNext" }
  elseif action == "focus-previous" then command = { type = "FocusPrevious" }
  elseif action == "group-next" then command = { type = "FocusNextGroup" }
  elseif action == "group-previous" then command = { type = "FocusPreviousGroup" }
  elseif action == "move" then command = { type = "MoveFocusedToOther" }
  elseif action == "swap" then command = { type = "SwapGroups" }
  elseif action == "resize" then command = { type = "ResizeRatio", ratio = random(3) == 1 and 0.3 or 0.7 }
  elseif action == "reset" then command = { type = "ResetRatio" }
  elseif action == "synchronize" then command = { type = "Synchronize" }
  else model = { type = "ActualFocusChanged", id = manager.focus.actualWindow.id or "unknown-noop", title = "noop" } end
  return { model = model, command = command }
end

local function assertOracle(state, oracle, seed, step, action)
  local actual = memberIds(state.manager)
  assertThat(equal(actual, oracle), seed, step, action, "manager membership diverged from independent oracle")
  local seen = {}
  for _, id in ipairs(actual) do assertThat(not seen[id], seed, step, action, "duplicate manager member"); seen[id] = true end
  for id, window in pairs(state.manager.windows) do
    local facts = window.lifecycle
    assertThat(Model.isAvailable(window) == (not facts.minimized and not facts.appHidden and not facts.nativeFullscreen), seed, step, action, "STATE-008 availability is not conjunction")
  end
  local valid, err = validateComposite(state)
  assertThat(valid, seed, step, action, "validator failed: " .. tostring(err))

  local coordinator = state.coordinators[SPACE]
  local activeMembers = dependencies().registry[coordinator.activeLayoutId].memberIds(coordinator.layouts[coordinator.activeLayoutId])
  assertThat(sameSet(activeMembers, actual), seed, step, action, "active layout membership drift manager=" .. table.concat(actual, ",") .. " layout=" .. table.concat(activeMembers, ","))
  local members = {}
  for _, id in ipairs(actual) do members[id] = true end
  for id, layoutState in pairs(coordinator.layouts) do
    for _, memberId in ipairs(dependencies().registry[id].memberIds(layoutState)) do
      assertThat(members[memberId], seed, step, action, "inactive layout retained dead member")
    end
  end
end

local function generated(seed)
  local random, oracle, actionCounts = prng(seed), {}, {}
  local derivedSnapshots, observed = {}, {}
  local runtime
  runtime = Runtime.new({
    initialState = makeComposite(), reduce = reduceComposite, validate = validateComposite,
    deriveIntents = function(committed, transaction, version)
      local snapshot = copy(committed)
      local intents = projectComposite(committed)
      derivedSnapshots[#derivedSnapshots + 1] = { state = snapshot, version = version, action = transaction.action }
      return intents
    end,
    observeIntents = function(intents, version)
      local derived = derivedSnapshots[#derivedSnapshots]
      observed[#observed + 1] = { state = runtime:state(), version = version, intents = copy(intents), derived = derived }
    end,
  })

  for step = 1, STEPS do
    local action = actionFor(step, random)
    actionCounts[action] = (actionCounts[action] or 0) + 1
    local before = runtime:state()
    local beforeLayouts, beforeMembers = layoutMembers(before.coordinators[SPACE]), copy(memberIds(before.manager))
    local transaction = transactionFor(action, random, before)
    transaction.action = action

    -- Independent admission/removal oracle; all other observations are non-destructive.
    local event = transaction.model
    if event and event.type == "WindowReady" and not (function() for _, id in ipairs(oracle) do if id == event.id then return true end end end)() then
      oracle[#oracle + 1] = event.id
    elseif event and event.type == "WindowDestroyed" then
      for index = #oracle, 1, -1 do if oracle[index] == event.id then table.remove(oracle, index) end end
    elseif event and event.type == "ApplicationTerminated" then
      for index = #oracle, 1, -1 do
        local window = before.manager.windows[oracle[index]]
        if window and window.application.pid == event.pid then table.remove(oracle, index) end
      end
    end

    local ok, err = runtime:submit(transaction)
    assertThat(ok, seed, step, action, tostring(err))
    local after = runtime:state()
    assertOracle(after, oracle, seed, step, action)

    if action == "visible-false" or action == "visible-true" or action == "snapshot-absent" or action == "minimize" or action == "restore" or action == "hide" or action == "unhide" or action == "fullscreen-enter" or action == "fullscreen-exit" then
      assertThat(equal(memberIds(after.manager), beforeMembers), seed, step, action, "STATE-004/WIN-004 observation changed membership")
      assertThat(equal(layoutMembers(after.coordinators[SPACE]), beforeLayouts), seed, step, action, "STATE-004/WIN-004 observation changed layout order")
    elseif action == "focus-known" or action == "focus-unknown" or action == "noop-focus" then
      assertThat(equal(memberIds(after.manager), beforeMembers), seed, step, action, "FOCUS-003 changed membership")
      for id, members in pairs(layoutMembers(after.coordinators[SPACE])) do assertThat(equal(members, beforeLayouts[id]), seed, step, action, "FOCUS-003/WIN-002 reordered " .. id) end
    end

    local observation = observed[#observed]
    assertThat(observation.version == observation.derived.version and equal(observation.state, observation.derived.state), seed, step, action, "STATE-002 observer did not see derived committed state")
    local available = availability(after.manager)
    local emitted = {}
    for _, intent in ipairs(observation.intents) do
      assertThat(available[intent.windowId] == true and not emitted[intent.windowId], seed, step, action, "STATE-006 projected unavailable or duplicate member")
      assertThat(intent.displayId == DISPLAY and intent.spaceId == SPACE, seed, step, action, "ENV-004 projection identity missing")
      emitted[intent.windowId] = true
    end
    local coordinator = after.coordinators[SPACE]
    local activeIds = dependencies().registry[coordinator.activeLayoutId].memberIds(coordinator.layouts[coordinator.activeLayoutId])
    for _, id in ipairs(activeIds) do
      assertThat((emitted[id] ~= nil) == (available[id] == true), seed, step, action, "STATE-006 projection did not emit exactly the available active members")
    end
  end
  for _, action in ipairs({ "ready", "duplicate-ready", "destroy", "terminate", "visible-false", "visible-true", "snapshot-absent", "minimize", "restore", "hide", "unhide", "fullscreen-enter", "fullscreen-exit", "focus-known", "focus-unknown", "cycle-layout", "focus-next", "focus-previous", "group-next", "group-previous", "move", "swap", "resize", "reset", "synchronize", "noop-focus" }) do
    assert(actionCounts[action] and actionCounts[action] > 0, "published seed did not cover action " .. action)
  end
end

return {
  ["FOCUS-004 STACK-002: selected-member removal chooses stable predecessor with wrapping"] = function()
    local state = Stack.initialState({ "one", "two", "three" })
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "two" }, {})
    state = Stack.reduce(state, { type = "Remove", memberId = "two" }, {})
    assert(state.selectedId == "one", "FOCUS-004 expected predecessor one after removing selected two")
    state = Stack.initialState({ "one", "two" })
    state = Stack.reduce(state, { type = "ManagedFocusObserved", memberId = "one" }, {})
    state = Stack.reduce(state, { type = "Remove", memberId = "one" }, {})
    assert(state.selectedId == "two", "FOCUS-004 expected predecessor wrapping to two")
  end,

  ["STATE-001 STATE-002 STATE-003 STATE-004 STATE-005 STATE-006 STATE-008 WIN-002 WIN-003 WIN-004 WIN-005 FOCUS-003 LAY-003 LAY-004 STACK-001 COL-004: deterministic generated pure transactions"] = function()
    for _, seed in ipairs(SEEDS) do generated(seed) end
  end,
}
