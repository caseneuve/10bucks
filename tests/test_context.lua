local Context = require("lib.macos.context")
return {
  ["context selects only explicit built-in UUID and rejects non-user active Space"] = function()
    local screen = { getUUID = function() return "built-in" end, frame = function() return { x = 0, y = 0, w = 1, h = 1 } end }
    local hs = { screen = { allScreens = function() return { screen } end }, spaces = { activeSpaceOnScreen = function() return "space" end, spaceType = function() return "user" end } }
    local context = Context.snapshot(hs, "built-in"); assert(context.displayId == "built-in")
    hs.spaces.spaceType = function() return "fullscreen" end
    assert(not pcall(Context.snapshot, hs, "built-in"))
    assert(not pcall(Context.snapshot, hs, "missing"))
  end,
  ["context watcher stops on start failure and ignores callbacks after detach"] = function()
    local stopped, callback = 0, nil
    local screen = { getUUID = function() return "built-in" end, frame = function() return {} end }
    local watcher = { start = function() error("start failed") end, stop = function() stopped = stopped + 1 end }
    local hs = { screen = { allScreens = function() return { screen } end }, spaces = { activeSpaceOnScreen = function() return "space" end,
      spaceType = function() return "user" end, watcher = { new = function(cb) callback = cb; return watcher end } } }
    assert(not pcall(Context.watch, hs, "built-in", function() end)); assert(stopped == 1)
    watcher.start = function() end; local calls = 0; local subscription = Context.watch(hs, "built-in", function() calls = calls + 1 end)
    callback(); assert(calls == 1); subscription.detach(); callback(); assert(calls == 1 and stopped == 2)
  end,
}
