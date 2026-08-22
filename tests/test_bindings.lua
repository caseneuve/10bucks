local Bindings = require("lib.bindings")

local function fakeHs()
  local calls = {}
  local hs = {
    hotkey = {
      bind = function(modifiers, key, callback)
        table.insert(calls, { modifiers = modifiers, key = key, callback = callback })
        return { delete = function() end }
      end,
    },
  }
  return hs, calls
end

return {
  ["valid hotkey bindings install once and dispatch their action"] = function()
    local hs, calls = fakeHs()
    local dispatches = 0
    local engine = {
      toggleLayout = function() dispatches = dispatches + 1 end,
    }

    local bindings = Bindings.bind(hs, engine, {
      toggleLayout = { { "cmd", "alt" }, "space" },
    })

    assert(#calls == 1)
    assert(#bindings == 1)
    assert(calls[1].modifiers[1] == "cmd")
    assert(calls[1].modifiers[2] == "alt")
    assert(calls[1].key == "space")
    calls[1].callback()
    assert(dispatches == 1)
  end,

  ["false hotkey bindings are skipped"] = function()
    local hs, calls = fakeHs()
    local bindings = Bindings.bind(hs, {}, { deleteWorkspace = false })

    assert(#calls == 0)
    assert(#bindings == 0)
  end,

  ["unknown actions are rejected even when disabled"] = function()
    local hs = fakeHs()
    local ok, err = pcall(Bindings.bind, hs, {}, { unknownAction = false })

    assert(not ok)
    assert(tostring(err):find("Unknown 10bucks action: unknownAction", 1, true))
  end,

  ["malformed hotkey values are rejected with actionable paths"] = function()
    local cases = {
      { value = "not a chord", fragment = "must be false or { modifiers, key }" },
      { value = { { "cmd" } }, fragment = "must be false or { modifiers, key }" },
      { value = { "cmd", "w" }, fragment = "modifiers must be a list" },
      { value = { { 1 }, "w" }, fragment = "modifier must be a string" },
      { value = { { "command" }, "w" }, fragment = "unsupported modifier" },
      { value = { { "cmd", "cmd" }, "w" }, fragment = "duplicate modifier" },
      { value = { { "cmd" }, 1 }, fragment = "key must be a string" },
    }

    for _, case in ipairs(cases) do
      local hs, calls = fakeHs()
      local ok, err = pcall(Bindings.bind, hs, {}, { chooseWindow = case.value })
      local message = tostring(err)
      assert(not ok)
      assert(message:find("10bucks config: hotkeys.chooseWindow", 1, true))
      assert(message:find(case.fragment, 1, true))
      assert(#calls == 0)
    end
  end,

  ["empty modifier lists remain valid"] = function()
    local hs, calls = fakeHs()
    local bindings = Bindings.bind(hs, {}, { toggleLayout = { {}, "space" } })

    assert(#calls == 1)
    assert(#bindings == 1)
    assert(calls[1].key == "space")
  end,

  ["invalid entries are rejected before any hotkey is installed"] = function()
    local hs, calls = fakeHs()
    local ok, err = pcall(Bindings.bind, hs, {}, {
      toggleLayout = { { "cmd" }, "space" },
      chooseWindow = { { "cmd" }, 1 },
    })

    assert(not ok)
    assert(tostring(err):find("10bucks config: hotkeys.chooseWindow", 1, true))
    assert(#calls == 0)
  end,

  ["exact duplicate chords are rejected with stable action names"] = function()
    local hs, calls = fakeHs()
    local ok, err = pcall(Bindings.bind, hs, {}, {
      toggleLayout = { { "cmd", "alt" }, "space" },
      chooseWindow = { { "cmd", "alt" }, "space" },
    })
    local message = tostring(err)
    local chooseWindow = message:find("hotkeys.chooseWindow", 1, true)
    local toggleLayout = message:find("hotkeys.toggleLayout", 1, true)

    assert(not ok)
    assert(message:find("10bucks config: duplicate hotkey chord", 1, true))
    assert(chooseWindow and toggleLayout and chooseWindow < toggleLayout)
    assert(#calls == 0)
  end,

  ["reordered modifiers identify the same physical chord"] = function()
    local hs, calls = fakeHs()
    local ok, err = pcall(Bindings.bind, hs, {}, {
      toggleLayout = { { "alt", "cmd" }, "space" },
      chooseWindow = { { "cmd", "alt" }, "space" },
    })

    assert(not ok)
    assert(tostring(err):find("10bucks config: duplicate hotkey chord", 1, true))
    assert(#calls == 0)
  end,

  ["disabled actions do not collide with enabled chords"] = function()
    local hs, calls = fakeHs()
    local bindings = Bindings.bind(hs, {}, {
      toggleLayout = { { "cmd", "alt" }, "space" },
      chooseWindow = false,
    })

    assert(#bindings == 1)
    assert(#calls == 1)
  end,

  ["duplicate rejection happens before any hotkey installation"] = function()
    local hs, calls = fakeHs()
    local ok = pcall(Bindings.bind, hs, {}, {
      toggleLayout = { { "cmd" }, "space" },
      chooseWindow = { { "cmd" }, "space" },
    })

    assert(not ok)
    assert(#calls == 0)
  end,
}
