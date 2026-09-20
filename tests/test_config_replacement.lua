local Config = require("lib.config")
local Bindings = require("lib.bindings")

return {
  ["Canary A config rejects unknown keys/actions, cycles, malformed modifiers, and duplicate reordered chords"] = function()
    assert(not pcall(Config.build, { unsupported = true }))
    assert(not pcall(Config.build, { hotkeys = false }))
    assert(not pcall(Config.build, { hotkeys = { workspace = false } }))
    assert(not pcall(Config.build, { hotkeys = { focusNext = { { "cmd", "cmd" }, "j" } } }))
    assert(not pcall(Config.build, { hotkeys = { focusNext = { { "command" }, "j" } } }))
    assert(not pcall(Config.build, { hotkeys = { focusNext = { { "cmd", "alt" }, "j" }, focusPrevious = { { "alt", "cmd" }, "j" } } }))
    local cyclic = {}; cyclic.self = cyclic; assert(not pcall(Config.build, cyclic))
  end,
  ["checked-in example builds after switch-preflight UUID substitution and legacy keys fail early"] = function()
    local example = assert(loadfile("10bucks.spoon/config.example.lua"))()
    example.builtInDisplayUUID = "fake-built-in"
    assert(Config.build(example).builtInDisplayUUID == "fake-built-in")
    local ok, err = pcall(Config.build, { initialLayout = "stack" })
    assert(not ok and tostring(err):find("config.initialLayout", 1, true))
  end,
  ["configureFile(nil) ignores empty XDG_CONFIG_HOME and uses HOME without real files"] = function()
    package.loaded["init"] = nil
    local ten = dofile("10bucks.spoon/init.lua")
    ten.getenv = function(name) return name == "XDG_CONFIG_HOME" and "" or "/controlled-home" end
    local loaded
    local original = Config.loadFile
    Config.loadFile = function(path) loaded = path; return { builtInDisplayUUID = "built-in" } end
    ten:configureFile(nil)
    Config.loadFile = original
    assert(loaded == "/controlled-home/.config/10bucks/config.lua")
  end,
  ["binding installation rolls back already-created hotkeys when a later bind fails"] = function()
    local created, deleted = 0, 0
    local hs = { hotkey = { bind = function() created = created + 1; if created == 2 then error("bind failed") end; return { delete = function() deleted = deleted + 1 end } end } }
    local config = Config.build({ hotkeys = { focusPrevious = false } })
    assert(not pcall(Bindings.bind, hs, function() end, config.hotkeys))
    assert(created == 2 and deleted == 1)
  end,
  ["Canary A bindings dispatch only validated commands and delete every binding"] = function()
    local calls, deleted, command = {}, 0, nil
    local hs = { hotkey = { bind = function(_, _, callback) calls[#calls + 1] = callback; return { delete = function() deleted = deleted + 1 end } end } }
    local config = Config.build({ hotkeys = { cycleLayout = false, focusPrevious = false, focusNext = { { "cmd" }, "j" }, reflow = false } })
    local bound = Bindings.bind(hs, function(value) command = value end, config.hotkeys)
    assert(#bound == 1); calls[1](); assert(command.type == "FocusNext"); Bindings.delete(bound); assert(deleted == 1)
  end,
}
