local Context = require("lib.macos.context")
local function screen(frame)
  return { getUUID = function() return "built-in" end, frame = function() return frame end, fullFrame = function() return frame end }
end
local function spaces()
  return { data_managedDisplaySpaces = function() return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = 1 }, Spaces = { { ManagedSpaceID = 1, type = 0 } } } } end }
end
return {
  ["ENV-004 FS-005: context distinguishes native fullscreen without inventing a regular Space"] = function()
    local selected = screen({ x = 0, y = 0, w = 1, h = 1 })
    local hs = { screen = { allScreens = function() return { selected } end }, spaces = spaces() }
    local context = Context.snapshot(hs, "built-in"); assert(context.displayId == "built-in")
    assert(context.workArea.x == 0 and context.workArea.y == 32 and context.workArea.w == 1 and context.workArea.h == 0)
    hs.spaces.data_managedDisplaySpaces = function() return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = 2 }, Spaces = { { ManagedSpaceID = 2, type = 4 } } } } end
    local fullscreen = Context.snapshot(hs, "built-in")
    assert(fullscreen.regularSpaceId == nil and fullscreen.displayId == "built-in")
    hs.spaces.data_managedDisplaySpaces = function() return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = 3 }, Spaces = { { ManagedSpaceID = 3, type = 9 } } } } end
    assert(not pcall(Context.snapshot, hs, "built-in"))
    assert(not pcall(Context.snapshot, hs, "missing"))
  end,
  ["context snapshot normalizes hs.geometry public properties before generic copies"] = function()
    local geometry = setmetatable({ _x = 10, _y = 20, _w = 30, _h = 40 }, {
      __index = function(value, key)
        return ({ x = value._x, y = value._y, w = value._w, h = value._h })[key]
      end,
    })
    local rawCopy = {}; for key, value in pairs(geometry) do rawCopy[key] = value end
    assert(rawCopy.x == nil and rawCopy.y == nil and rawCopy.w == nil and rawCopy.h == nil)
    assert(rawCopy._x == 10 and rawCopy._y == 20 and rawCopy._w == 30 and rawCopy._h == 40)
    local selected = screen(geometry)
    local hs = { screen = { allScreens = function() return { selected } end }, spaces = spaces() }
    local context = Context.snapshot(hs, "built-in")
    local copied = {}; for key, value in pairs(context.workArea) do copied[key] = value end
    assert(copied.x == 10 and copied.y == 52 and copied.w == 30 and copied.h == 8)
    assert(not pcall(function()
      selected.frame = function() return setmetatable({}, { __index = function() return "not-a-number" end }) end
      Context.snapshot(hs, "built-in")
    end))
  end,
  ["context watcher stops on start failure and ignores callbacks after detach"] = function()
    local stopped, callback = 0, nil
    local selected = screen({ x = 0, y = 0, w = 1, h = 1 })
    local watcher = { start = function() error("start failed") end, stop = function() stopped = stopped + 1 end }
    local screenWatcher = { start = function() end, stop = function() stopped = stopped + 1 end }
    local hs = { screen = { allScreens = function() return { selected } end, watcher = { new = function() return screenWatcher end } }, spaces = spaces() }
    hs.spaces.watcher = { new = function(cb) callback = cb; return watcher end }
    assert(not pcall(Context.watch, hs, "built-in", function() end)); assert(stopped == 2)
    watcher.start = function() end; local calls = 0; local subscription = Context.watch(hs, "built-in", function() calls = calls + 1 end)
    callback(); assert(calls == 1); subscription.detach(); callback(); assert(calls == 1 and stopped == 4)
  end,
}
