local Config = require("lib.config")
local Bindings = require("lib.bindings")

return {
  ["SPACE-001 SPACE-003 SPACE-004 SPACE-005 CMD-001: 25 defaults preserve existing commands and copy desktop fields"] = function()
    local callbacks, events = {}, {}
    local hs = { hotkey = { bind = function(_, key, callback) callbacks[key] = callback; return { delete = function() end } end } }
    local bound = Bindings.bind(hs, function(event) events[#events + 1] = event end, Config.build().hotkeys)
    assert(#bound == 25)
    assert(callbacks.c == nil) -- reserved by the user's external launcher, not 10bucks
    callbacks.d(); assert(events[#events].type == "CreateRegularDesktop")
    assert(Config.build({ hotkeys = { createDesktop = false } }).hotkeys.createDesktop == false)
    for i = 1, 9 do callbacks[tostring(i)](); assert(events[#events].type == "FocusRegularPosition" and events[#events].position == i) end
    events[#events].position = 999; callbacks["9"](); assert(events[#events].position == 9)
    callbacks["0"](); assert(events[#events].type == "FocusPreviousRegular")
    callbacks.n(); assert(events[#events].type == "FocusRelativeRegular" and events[#events].delta == 1)
    callbacks.p(); assert(events[#events].delta == -1)
    callbacks.j(); assert(events[#events].type == "FocusNext")
    callbacks["["](); assert(events[#events].delta == -0.05)
  end,
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
  ["COL-007 CMD-001: h/l bindings dispatch physical left/right column commands"] = function()
    local callbacks = {}
    local hs = { hotkey = { bind = function(_, key, callback)
      callbacks[key] = callback
      return { delete = function() end }
    end } }
    local commands = {}
    Bindings.bind(hs, function(command) commands[#commands + 1] = command.type end, {
      focusLeftGroup = { { "cmd" }, "h" }, focusRightGroup = { { "cmd" }, "l" },
    })
    callbacks.h(); callbacks.l()
    assert(commands[1] == "FocusLeftGroup" and commands[2] == "FocusRightGroup")
  end,
  ["Canary A bindings dispatch only validated commands and delete every binding"] = function()
    local calls, deleted, command = {}, 0, nil
    local hs = { hotkey = { bind = function(_, _, callback) calls[#calls + 1] = callback; return { delete = function() deleted = deleted + 1 end } end } }
    local config = Config.build({ hotkeys = { cycleLayout = false, focusLeftGroup = false, focusRightGroup = false, focusPrevious = false, focusNext = { { "cmd" }, "j" }, focusManagedPrevious = false, moveFocusedToOtherGroup = false, swapGroups = false, resizeLeft = false, resizeRight = false, resetRatio = false, reflow = false } })
    for name in pairs(config.hotkeys) do if name:find("Desktop", 1, true) then config.hotkeys[name] = false end end
    local bound = Bindings.bind(hs, function(value) command = value end, config.hotkeys)
    assert(#bound == 1); calls[1](); assert(command.type == "FocusNext"); Bindings.delete(bound); assert(deleted == 1)
  end,
}
