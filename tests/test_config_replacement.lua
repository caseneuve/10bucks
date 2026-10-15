local Config = require("lib.config")
local Bindings = require("lib.bindings")

return {
  ["COL-010: public gap defaults to zero, accepts fractional points and rejects invalid values without replacing config"] = function()
    assert(Config.build().columnGap == 0)
    local input = { columnGap = 2.5 }
    local config = Config.build(input); input.columnGap = 99
    assert(config.columnGap == 2.5 and Config.defaults.columnGap == 0)
    local ten = dofile("10bucks.spoon/init.lua"):configure({ columnGap = 2.5 })
    local prior = ten.config
    for _, gap in ipairs({ -1, math.huge, -math.huge, 0/0, "10", false, {} }) do
      local ok, err = pcall(ten.configure, ten, { columnGap = gap })
      assert(not ok and tostring(err):find("config.columnGap", 1, true))
      assert(ten.config == prior and ten.config.columnGap == 2.5)
    end
    assert(Config.build({ columnGap = 0 }).columnGap == 0)
    assert(Config.build({ columnGap = 1e300 }).columnGap == 1e300)
  end,
  ["COL-010 STACK-001 LAY-001: composition snapshots gap per Core through the existing layout owner"] = function()
    local ten = dofile("10bucks.spoon/init.lua"):configure({ columnGap = 10 })
    ten.context = { displayId = "built-in", workArea = { x = 100, y = 132, w = 300, h = 400 } }
    ten.cores = {}
    local core = ten:_coreForSpace("first")
    assert(core.dependencies.layoutConfigs.columns.columnGap == 10)
    assert(core.dependencies.layoutConfigs.stack.columnGap == 10)
    ten.config.columnGap = 20 -- Core configuration is a primitive snapshot, not the public table.
    assert(ten:_coreForSpace("first") == core)
    assert(core.dependencies.layoutConfigs.columns.columnGap == 10)
    local other = ten:_coreForSpace("second")
    assert(other.dependencies.layoutConfigs.columns.columnGap == 20)
    assert(other.dependencies.layoutConfigs.columns ~= core.dependencies.layoutConfigs.columns)
    assert(core:submit({ type = "WindowReady", id = "one", displayId = "built-in", spaceId = "first",
      application = { pid = 1, name = "Example", bundleID = "example.app" } }))
    assert(core.currentFrames.one.x == 110 and core.currentFrames.one.y == 142)
    assert(core.currentFrames.one.w == 280 and core.currentFrames.one.h == 380)
    assert(core:submit({ type = "CycleLayout" }))
    assert(core.currentFrames.one.x == 110 and core.currentFrames.one.y == 142)
    assert(core.currentFrames.one.w == 280 and core.currentFrames.one.h == 380)
    assert(core:submit({ type = "Reflow" }))
    assert(core.currentFrames.one.x == 110)
    assert(core:submit({ type = "CycleLayout" }))
    assert(core.currentFrames.one.x == 110 and core.currentFrames.one.w == 280)
  end,
  ["RULE-001 RULE-003: narrow rules config copies exact matches and rejects unsupported actions/matchers"] = function()
    local input = { rules = { { match = { bundleID = "example.app", title = "" }, action = "exclude" } } }
    local config = Config.build(input)
    input.rules[1].match.title = "changed"
    assert(config.rules[1].match.title == "")
    assert(#Config.build().rules == 0)
    local prefix = { rules = { { match = { titlePrefix = "Utility: " }, action = "exclude" } } }
    assert(Config.build(prefix).rules[1].match.titlePrefix == "Utility: ")
    assert(not pcall(Config.build, { rules = { { match = { titlePrefix = false }, action = "exclude" } } }))
    for _, rule in ipairs({
      { match = {}, action = "nativeFullscreenOnCreate" },
      { match = { titlePattern = "Utility.*" }, action = "exclude" },
      { match = { title = false }, action = "manage" },
      { match = {}, action = "exclude", predicate = function() return true end },
      { action = "exclude" },
      { match = {}, action = "unsupported" },
    }) do assert(not pcall(Config.build, { rules = { rule } })) end
    local rule = { match = {}, action = "manage" }
    assert(not pcall(Config.build, { rules = { [2] = rule } }))
    assert(not pcall(Config.build, { rules = { named = rule } }))
    for _, value in ipairs({
      { rules = setmetatable({}, {}) },
      { rules = { setmetatable({ match = {}, action = "manage" }, {}) } },
      { rules = { { match = setmetatable({}, {}), action = "manage" } } },
    }) do assert(not pcall(Config.build, value)) end
    local cycle = {}; cycle[1] = cycle
    assert(not pcall(Config.build, { rules = cycle }))
  end,
  ["SPACE-001 SPACE-003 SPACE-004 SPACE-005 CMD-001: chooser and desktop defaults preserve existing commands and copy desktop fields"] = function()
    local callbacks, events = {}, {}
    local hs = { hotkey = { bind = function(_, key, callback) callbacks[key] = callback; return { delete = function() end } end } }
    local bound = Bindings.bind(hs, function(event) events[#events + 1] = event end, Config.build().hotkeys)
    local count = 0; for _, binding in pairs(Config.build().hotkeys) do if binding ~= false then count = count + 1 end end
    assert(#bound == count)
    callbacks.w(); assert(events[#events].type == "OpenWindowChooser")
    assert(Config.build({ hotkeys = { chooseWindow = false } }).hotkeys.chooseWindow == false)
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
    local config = Config.build({ hotkeys = { cycleLayout = false, focusLeftGroup = false, focusRightGroup = false, focusPrevious = false, focusNext = { { "cmd" }, "j" }, focusManagedPrevious = false, chooseWindow = false, moveFocusedToOtherGroup = false, swapGroups = false, resizeLeft = false, resizeRight = false, resetRatio = false, reflow = false } })
    for name in pairs(config.hotkeys) do if name:find("Desktop", 1, true) then config.hotkeys[name] = false end end
    local bound = Bindings.bind(hs, function(value) command = value end, config.hotkeys)
    assert(#bound == 1); calls[1](); assert(command.type == "FocusNext"); Bindings.delete(bound); assert(deleted == 1)
  end,
}
