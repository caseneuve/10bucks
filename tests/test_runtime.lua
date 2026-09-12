local Runtime = require("lib.runtime")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function state(value)
  return { value = value }
end

local function reducer(current, event)
  if event.type == "add" then return state(current.value + event.amount) end
  if event.type == "noop" then return current end
  if event.type == "broken" then error("reduction failed") end
  return current
end

local function validator(candidate)
  if type(candidate) ~= "table" or type(candidate.value) ~= "number" then
    return false, "invalid candidate"
  end
  return true
end

return {
  ["STATE-001 STATE-002: FIFO reduction serializes an event submitted while committed intents are observed"] = function()
    local seen = {}
    local runtime
    runtime = Runtime.new({
      initialState = state(0),
      reduce = reducer,
      validate = validator,
      deriveIntents = function(committed, event, version)
        return { { event = event.type, value = committed.value, version = version } }
      end,
      observeIntents = function(intents)
        table.insert(seen, intents[1].event .. ":" .. intents[1].value)
        if intents[1].event == "add" and intents[1].value == 1 then
          assert(runtime:submit({ type = "add", amount = 2 }))
        end
      end,
    })

    assert(runtime:submit({ type = "add", amount = 1 }))
    equal(table.concat(seen, ","), "add:1,add:3")
    equal(runtime:state().value, 3)
    equal(runtime:version(), 2)
  end,

  ["STATE-001 STATE-003: failed reduction or validation preserves committed state, exposes no intents, and does not wedge FIFO draining"] = function()
    local observed = {}
    local runtime = Runtime.new({
      initialState = state(4),
      reduce = function(current, event)
        if event.type == "broken" then
          current.value = 123
          error("reduction failed")
        end
        if event.type == "invalid" then return { value = "not-a-number" } end
        return reducer(current, event)
      end,
      validate = validator,
      deriveIntents = function(_, event) return { { event = event.type } } end,
      observeIntents = function(intents) table.insert(observed, intents[1].event) end,
    })

    local ok = runtime:submit({ type = "broken" })
    assert(not ok)
    equal(runtime:state().value, 4)
    equal(#observed, 0)
    ok = runtime:submit({ type = "invalid" })
    assert(not ok)
    equal(runtime:state().value, 4)
    equal(#observed, 0)
    assert(runtime:submit({ type = "add", amount = 3 }))
    equal(runtime:state().value, 7)
    equal(table.concat(observed, ","), "add")
  end,

  ["STATE-002: complete candidate is committed before intent derivation and observation"] = function()
    local runtime
    local derivedVersion, observedValue, observedVersion
    runtime = Runtime.new({
      initialState = state(0),
      reduce = reducer,
      validate = validator,
      deriveIntents = function(committed, _, version)
        derivedVersion = version
        equal(committed.value, 5)
        equal(runtime:state().value, 5)
        equal(runtime:version(), version)
        return { { kind = "plain", value = committed.value } }
      end,
      observeIntents = function(intents, version)
        observedValue = runtime:state().value
        observedVersion = version
        equal(intents[1].value, 5)
      end,
    })

    assert(runtime:submit({ type = "add", amount = 5 }))
    equal(derivedVersion, 1)
    equal(observedVersion, 1)
    equal(observedValue, 5)
  end,

  ["STATE-001 STATE-003: intent derivation receives a defensive plain snapshot and intents remain plain data"] = function()
    local observed
    local initial = state(1)
    local runtime = Runtime.new({
      initialState = initial,
      reduce = reducer,
      validate = validator,
      deriveIntents = function(committed)
        committed.value = 99
        committed.nested = { changed = true }
        return { { kind = "request", payload = { value = committed.value } } }
      end,
      observeIntents = function(intents)
        observed = intents
      end,
    })

    initial.value = 88
    assert(runtime:submit({ type = "noop" }))
    equal(runtime:state().value, 1)
    equal(observed[1].kind, "request")
    equal(observed[1].payload.value, 99)
  end,

  ["STATE-002: no-op reductions retain the committed version and still derive post-commit intents"] = function()
    local versions = {}
    local runtime = Runtime.new({
      initialState = state(8),
      reduce = reducer,
      validate = validator,
      deriveIntents = function(_, event, version)
        table.insert(versions, event.type .. ":" .. version)
        return {}
      end,
    })

    assert(runtime:submit({ type = "noop" }))
    equal(runtime:version(), 0)
    equal(table.concat(versions, ","), "noop:0")
  end,
}
