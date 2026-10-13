local Rules = require("lib.rules")
local Model = require("lib.model")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function deepEqual(left, right)
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return left == right end
  for key, value in pairs(left) do if not deepEqual(value, right[key]) then return false end end
  for key in pairs(right) do if left[key] == nil then return false end end
  return true
end

local function metadata(overrides)
  local value = {
    id = "window-1",
    application = { pid = 99, bundleID = "example.app", name = "Example" },
    title = "Original title",
    displayId = "built-in",
    spaceId = "space-1",
    role = "AXWindow",
    subrole = "AXStandardWindow",
    modal = false,
    movable = true,
    resizable = true,
    selfProcess = false,
    origin = "created",
  }
  for key, item in pairs(overrides or {}) do value[key] = item end
  return value
end

local function initial()
  return Model.new({ displayId = "built-in", activeRegularSpaceId = "space-1" })
end

return {
  ["RULE-001 RULE-002: titlePrefix is literal case-sensitive conjunctive data with existing unknown and safety semantics"] = function()
    local rules = {
      { match = { bundleID = "example.app", titlePrefix = "[Utility].*" }, action = "exclude" },
      { match = {}, action = "manage" },
    }
    local input = metadata({ title = "[Utility].* draft" })
    local function action(generic) return Rules.filter(input, rules, generic or { action = "manage" }).action end
    equal(action(), "exclude")
    input.title = "[utility].* draft"; equal(action(), "manage")
    input.title = "Utility draft"; equal(action(), "manage")
    input.title = nil; equal(action(), "defer")
    input.application.bundleID = "other.app"; equal(action(), "manage")
    input.application.bundleID, input.title = "example.app", "[Utility].* draft"
    equal(Rules.filter(input, { rules[2], rules[1] }, { action = "manage" }).action, "manage")
    equal(action({ action = "exclude" }), "exclude")
    equal(action({ action = "defer" }), "defer")
    rules[1].match.title = "exact"; equal(action(), "manage")
    rules[1].match.titlePrefix, input.title = "ex", "exact"; equal(action(), "exclude")
    rules[1].match = { titlePrefix = "" }; input.title = ""; equal(action(), "exclude")
    input.title = nil; equal(action(), "defer")
  end,
  ["RULE-001 LIFE-003 STATE-001: ordered exact decisions defer unknown matches and retain exact lifetimes"] = function()
    local configured = {
      { match = { bundleID = "example.app", title = "Utility" }, action = "exclude" },
      { match = { bundleID = "example.app" }, action = "manage" },
    }
    local input = metadata({ title = "Utility" })
    local ready = assert(Rules.ready(input))
    ready.decision = Rules.filter(ready.metadata, configured, ready.decision)
    equal(ready.decision.action, "exclude")
    ready.resource, ready.appResource = 10, 20
    local records = Rules.reduce({}, ready)
    equal(Rules.action(records, ready.id, 10, 20, 99), "exclude")
    assert(Rules.action(records, ready.id, 11, 20, 99) == nil)
    input.title = "Changed"
    equal(Rules.filter(input, configured, { action = "manage" }).action, "manage")
    assert(Rules.reduce(records, ready) == records)
    ready.decision = { action = "manage" }
    assert(Rules.reduce(records, ready) == records)
    ready.resource = 11
    assert(Rules.reduce(records, ready) == records)
    ready.resource, ready.decision = 10, { action = "exclude" }
    assert(Rules.action(records, ready.id, 10, 20, 100) == nil)
    local invalid = { type = "WindowReady", application = { pid = 99 }, resource = 1, appResource = 2, decision = { action = "manage" } }
    assert(not pcall(Rules.reduce, {}, invalid))
    invalid.id = "other"
    invalid.application.handle = io.stdout
    assert(not pcall(Rules.reduce, {}, invalid))
    input.title = nil
    equal(Rules.filter(input, configured, { action = "manage" }).action, "defer")
    input.application.bundleID = "other.app"
    equal(Rules.filter(input, configured, { action = "manage" }).action, "manage")
    equal(Rules.filter(input, configured, { action = "exclude" }).action, "exclude")
    input.application.bundleID, input.title = nil, "Utility"
    equal(Rules.filter(input, configured, { action = "manage" }).action, "defer")
    input.title = "known mismatch"
    equal(Rules.filter(input, { configured[1] }, { action = "manage" }).action, "manage")
    input.application.bundleID, input.title = "example.app", ""
    equal(Rules.filter(input, { { match = { title = "" }, action = "exclude" } }, { action = "manage" }).action, "exclude")
    equal(Rules.filter(input, { configured[2], { match = {}, action = "exclude" } }, { action = "manage" }).action, "manage")
    assert(Rules.reduce(records, { type = "WindowDestroyed", id = ready.id, resource = 11 }) == records)
    assert(Rules.reduce(records, { type = "ApplicationTerminated", pid = 99, resource = 21 })[ready.id])
    local removed = Rules.reduce(records, { type = "WindowDestroyed", id = ready.id, resource = 10 })
    assert(removed[ready.id] == nil and records[ready.id] ~= nil)
    ready.resource = 11
    equal(Rules.action(Rules.reduce(removed, ready), ready.id, 11, 20, 99), "exclude")
    assert(Rules.reduce(records, { type = "ApplicationTerminated", pid = 99, resource = 20 })[ready.id] == nil)
    ready.decision = { action = "defer" }
    assert(next(Rules.reduce({}, ready)) == nil)
  end,
  ["STATE-003 RULE-002 RULE-003: readiness normalizes by immutable primitive copy and rejects userdata, functions, and metatables"] = function()
    local input = metadata()
    local event = assert(Rules.ready(input))
    assert(event ~= input and event.application ~= input.application)
    assert(deepEqual(input, metadata()))
    input.title = "Changed outside"
    input.application.name = "Changed app"
    equal(event.title, "Original title")
    equal(event.application.name, "Example")
    equal(event.decision.action, "manage")

    for _, corrupt in ipairs({
      function(value) value.title = function() end end,
      function(value) value.handle = io.stdout end,
      function(value) setmetatable(value, {}) end,
      function(value) setmetatable(value.application, {}) end,
    }) do
      local value = metadata()
      corrupt(value)
      local normalized, err = Rules.ready(value)
      assert(normalized == nil and type(err) == "string")
    end
  end,

  ["RULE-002 WIN-008: generic policy has no app-specific branch and excludes self, nonstandard, modal/transient, immovable, and fixed-size windows"] = function()
    local accepted = assert(Rules.ready(metadata({ application = { pid = 99, bundleID = "example.first", name = "First App" } })))
    equal(accepted.decision.action, "manage")
    local other = assert(Rules.ready(metadata({ application = { pid = 99, bundleID = "example.second", name = "Second App" } })))
    equal(other.decision.action, "manage")

    local cases = {
      { selfProcess = true, reason = "self-process" },
      { role = "AXSheet", reason = "non-standard-role" },
      { subrole = "AXDialog", reason = "transient-subrole" },
      { modal = true, reason = "modal" },
      { movable = false, reason = "not-movable" },
      { resizable = false, reason = "not-resizable" },
    }
    for _, case in ipairs(cases) do
      local input = metadata(case)
      input.reason = nil
      local event = assert(Rules.ready(input))
      equal(event.decision.action, "exclude")
      equal(event.decision.reason, case.reason)
    end
  end,

  ["RULE-002 FS-005: native fullscreen readiness generically permits position-locking only with confirmed fullscreen facts"] = function()
    local ordinary = assert(Rules.ready(metadata()))
    equal(ordinary.metadata.spaceType, "user")
    assert(not ordinary.metadata.nativeFullscreen)

    local fullscreen = assert(Rules.ready(metadata({
      movable = false, resizable = true, spaceType = "fullscreen", nativeFullscreen = true,
    })))
    equal(fullscreen.decision.action, "manage")
    equal(fullscreen.metadata.spaceType, "fullscreen")
    assert(fullscreen.metadata.nativeFullscreen)

    equal(assert(Rules.ready(metadata({ movable = false })).decision.reason, "not-movable"))
    equal(assert(Rules.ready(metadata({ movable = false, spaceType = "fullscreen" })).decision.reason, "not-movable"))
    equal(assert(Rules.ready(metadata({ movable = false, nativeFullscreen = true })).decision.reason, "not-movable"))
    equal(assert(Rules.ready(metadata({ movable = false, spaceType = "fullscreen", nativeFullscreen = true, resizable = false })).decision.reason, "not-resizable"))
    assert(not Rules.ready(metadata({ spaceType = "tiled" })))
    assert(not Rules.ready(metadata({ nativeFullscreen = "true" })))
  end,

  ["RULE-002 DISC-002 FOCUS-003: unknown safety facts defer and focus is never an admission origin"] = function()
    for _, key in ipairs({ "role", "subrole", "modal", "movable", "resizable", "selfProcess" }) do
      local value = metadata()
      value[key] = nil
      local event = assert(Rules.ready(value))
      equal(event.decision.action, "defer")
      equal(event.decision.reason, "unknown-" .. key)
    end
    local focus = metadata({ origin = "focus" })
    local event = assert(Rules.ready(focus))
    equal(event.decision.action, "defer")
    equal(event.decision.reason, "focus-is-not-readiness")
    equal(assert(Rules.ready(metadata({ origin = "targetedReadiness" }))).decision.action, "manage")
  end,

  ["RULE-004 DISC-001 DISC-002: readiness preserves bootstrap, creation, and confirmed targeted-readiness origin"] = function()
    local created = assert(Rules.ready(metadata({ origin = "created" })))
    assert(created.metadata.createdAfterStart)
    equal(created.metadata.origin, "created")
    local bootstrap = assert(Rules.ready(metadata({ origin = "bootstrap" })))
    assert(not bootstrap.metadata.createdAfterStart)
    equal(bootstrap.metadata.origin, "bootstrap")
    local targeted = assert(Rules.ready(metadata({ origin = "targetedReadiness" })))
    assert(not targeted.metadata.createdAfterStart)
    equal(targeted.metadata.origin, "targetedReadiness")
  end,

  ["LIFE-003 RULE-002 FOCUS-003: prior manage action survives independent exit readiness but never focus admission"] = function()
    local changed = metadata({
      origin = "targetedReadiness", movable = false, resizable = false,
      spaceType = "user", nativeFullscreen = false,
    })
    equal(assert(Rules.ready(changed)).decision.action, "exclude")
    local original = assert(Rules.ready(metadata()))
    original.resource, original.appResource = 10, 20
    local records = Rules.reduce({}, original)
    local reobserved = assert(Rules.ready(changed))
    reobserved.decision = { action = assert(Rules.action(records, changed.id, 10, 20, 99)) }
    equal(reobserved.decision.action, "manage")
    assert(Rules.reduce(records, reobserved) == records)

    local focus = assert(Rules.ready(metadata({ origin = "focus" })))
    equal(focus.decision.action, "defer")
    equal(focus.decision.reason, "focus-is-not-readiness")
  end,

  ["LIFE-003 WIN-003: reducer admits only stable manage readiness, duplicates are idempotent, and later metadata cannot reclassify or reorder"] = function()
    local state = initial()
    local ready = assert(Rules.ready(metadata()))
    state = Model.reduce(state, ready)
    equal(state.windows["window-1"].ruleAction, "manage")
    equal(state.windows["window-1"].readiness.origin, "created")
    equal(state.spaces["space-1"].memberIds[1], "window-1")
    assert(Model.reduce(state, ready) == state)

    local conflicting = assert(Rules.ready(metadata({ title = "Later title", movable = false })))
    assert(Model.reduce(state, conflicting) == state)
    equal(state.windows["window-1"].title, "Original title")
    equal(state.windows["window-1"].ruleAction, "manage")
    equal(#state.spaces["space-1"].memberIds, 1)

    local uncertain = metadata({ id = "window-2" })
    uncertain.movable = nil
    local deferred = assert(Rules.ready(uncertain))
    assert(Model.reduce(state, deferred) == state)
    assert(state.windows["window-2"] == nil)
  end,
}
