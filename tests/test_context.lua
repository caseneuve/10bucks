local Context = require("lib.macos.context")
local function screen(frame)
  return { getUUID = function() return "built-in" end, frame = function() return frame end, fullFrame = function() return frame end }
end
local function spaces()
  return { data_managedDisplaySpaces = function() return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = 1 }, Spaces = { { ManagedSpaceID = 1, type = 0 } } } } end }
end
return {
  ["SPACE-004 CMD-006: asynchronous Space adapter invariant sequences"] = function()
    for name, test in pairs(require("tests.test_spaces")) do
      local ok, err = pcall(test); assert(ok, name .. ": " .. tostring(err))
    end
  end,
  ["SPACE-009: owned Dock destruction snapshots once reattaches on replacement and detaches stale callbacks"] = function()
    local calls, boundaries, reads, stopped = 0, 0, 0, 0
    local observers, appCallback = {}, nil
    local app = { pid = function() return 7 end, bundleID = function() return "com.apple.dock" end }
    local selected = screen({ x = 0, y = 0, w = 1, h = 1 })
    local function watcher() return { start = function(self) return self end, stop = function() end } end
    local hs = { screen = { allScreens = function() return { selected } end, watcher = { new = watcher } }, spaces = spaces() }
    local snapshot = hs.spaces.data_managedDisplaySpaces
    hs.spaces.data_managedDisplaySpaces = function() reads = reads + 1; return snapshot() end
    hs.spaces.watcher = { new = watcher }
    hs.application = { applicationsForBundleID = function() return { app } end,
      watcher = { launched = 1, terminated = 2, new = function(cb) appCallback = cb; return watcher() end } }
    hs.axuielement = { applicationElement = function() return {} end, observer = { new = function()
      local observer = { callback = function(self, cb) self.cb = cb end, addWatcher = function(self) return self end,
        start = function(self) return self end, stop = function() stopped = stopped + 1 end }
      observers[#observers + 1] = observer; return observer
    end } }
    local subscription = Context.watch(hs, "built-in", function(context) calls = calls + 1; assert(context.nativeSpaceId == 1) end,
      function(context) boundaries = boundaries + 1; assert(context.nativeSpaceId == 1) end)
    observers[1].cb(nil, nil, "AXUIElementDestroyed"); assert(calls == 1 and boundaries == 1 and reads == 1)
    appCallback(nil, 2, app); appCallback(nil, 1, app)
    assert(#observers == 2 and stopped == 1)
    local before = calls; observers[1].cb(nil, nil, "AXUIElementDestroyed"); assert(calls == before)
    subscription.detach(); observers[2].cb(nil, nil, "AXUIElementDestroyed"); assert(calls == before and stopped == 2)
  end,
  ["ENV-004 FS-005: context distinguishes native fullscreen without inventing a regular Space"] = function()
    local selected = screen({ x = 0, y = 0, w = 1, h = 1 })
    local hs = { screen = { allScreens = function() return { selected } end }, spaces = spaces() }
    local context = Context.snapshot(hs, "built-in"); assert(context.displayId == "built-in")
    assert(context.workArea.x == 0 and context.workArea.y == 32 and context.workArea.w == 1 and context.workArea.h == 0)
    hs.spaces.data_managedDisplaySpaces = function() return { { ["Display Identifier"] = "built-in", ["Current Space"] = { ManagedSpaceID = 2 }, Spaces = { { ManagedSpaceID = 2, type = 4 } } } } end
    local fullscreen = Context.snapshot(hs, "built-in")
    assert(fullscreen.regularSpaceId == nil and fullscreen.displayId == "built-in")
    assert(fullscreen.nativeSpaceId == 2 and fullscreen.nativeSpaceType == "fullscreen" and fullscreen.fullSpaceIds[1] == 2)
    assert(#fullscreen.regularSpaceIds == 0 and fullscreen.revision == nil)
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
