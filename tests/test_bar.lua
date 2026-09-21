local Bar = require("lib.bar")
local NativeBar = require("lib.macos.bar")

local function fake()
  local f = { replaces = 0, shows = 0, hides = 0, frames = 0, deleted = 0, timers = {} }
  local function timer() local t = { stop = function(self) self.stopped = true end }; f.timers[#f.timers + 1] = t; return t end
  local canvas = { level = function(self) return self end, behavior = function(self) return self end, clickActivating = function(self) return self end,
    canvasMouseEvents = function(self) f.mouseEvents = true; return self end, mouseCallback = function(self, cb) f.mouse = cb; return self end,
    frame = function(self) f.frames = f.frames + 1; return self end, replaceElements = function(self) f.replaces = f.replaces + 1; return self end,
    show = function(self) f.shows = f.shows + 1; return self end, hide = function(self) f.hides = f.hides + 1; return self end,
    delete = function() f.deleted = f.deleted + 1 end }
  f.canvas, f.now, f.pointer = canvas, 1, { x = 40, y = 40 }
  return f, { canvas = { new = function() return canvas end }, mouse = { absolutePosition = function() f.pointerReads = (f.pointerReads or 0) + 1; return f.pointer end },
    timer = { secondsSinceEpoch = function() return f.now end, doAfter = function(_, fn) f.deadline = fn; return timer() end, doEvery = function(_, fn) f.every = fn; return timer() end },
    distributednotifications = { new = function(callback) f.appearance = { callback = callback, start = function() end, stop = function() f.appearanceStopped = true end }; return f.appearance end } }
end
return {
  ["BAR-003 BAR-004 BAR-005: semantic view formats actual unmanaged/no-focus presentation and coordinator status"] = function()
    local context = { displayId = "built-in", barFrame = { x = 0, y = 0, w = 400, h = 32 }, regularSpaceId = "b", regularPositions = { "a", "b" } }
    local view = Bar.view({ context = context, layout = "columns", status = { position = 2, count = 3 }, actual = { id = "popup", title = "Popup" }, timestamp = 0.25 })
    local presentation = Bar.format(view)
    assert(presentation.elements[4].text == "1 [2] · Popup  (2/3) ")
    view.actual.applicationPid = 7
    local retained = Bar.reduceActual(view.actual, { type = "ApplicationTerminated", pid = 8 })
    assert(retained.id == "popup")
    assert(Bar.reduceActual(view.actual, { type = "ApplicationTerminated", pid = 7 }).id == nil)
    local entered = Bar.reduceActual(view.actual, { type = "WindowEnteredNativeFullscreen", id = "popup" })
    assert(not Bar.view({ context = context, actual = entered, timestamp = 0 }).visible)
    local exited = Bar.reduceActual(entered, { type = "WindowExitedNativeFullscreen", id = "popup" })
    assert(Bar.view({ context = context, actual = exited, timestamp = 0 }).visible)
    local noFocus = Bar.reduceActual(view.actual, { type = "ActualFocusChanged" })
    assert(Bar.format(Bar.view({ context = context, actual = noFocus, timestamp = 0 })).elements[4].text:find("No focused window", 1, true))
  end,
  ["BAR-002: handoff callback waits grace and stop clears its temporary tracker"] = function()
    local f, hs = fake(); local owner = NativeBar.new(hs, function() end):start()
    owner:present({ displayId = "built-in", frame = { x = 0, y = 0, w = 100, h = 32 }, visible = true, elements = {} })
    f.mouse(f.canvas, "mouseEnter"); assert(f.hides == 1 and f.every)
    f.pointer = { x = 40, y = 40 }; f.every(); f.now = 1.25; f.every()
    assert(f.shows == 2); owner:stop(); assert(f.timers[#f.timers].stopped and f.appearanceStopped)
  end,
  ["BAR-002: initially-inside pointer hands off without showing"] = function()
    local f, hs = fake(); f.pointer = { x = 40, y = 10 }
    local owner = NativeBar.new(hs, function() end):start()
    owner:present({ displayId = "built-in", frame = { x = 0, y = 0, w = 100, h = 32 }, visible = true, elements = {} })
    assert(f.shows == 0 and f.hides == 0 and f.every)
    owner:stop()
  end,
  ["BAR-006: notification-start failure cleans partial clock allocation"] = function()
    local f, hs = fake(); hs.distributednotifications.new = function() return { start = function() error("fail") end, stop = function() f.appearanceStopped = true end } end
    assert(not pcall(function() NativeBar.new(hs, function() end):start() end))
    assert(f.timers[1].stopped and f.appearanceStopped)
  end,
  ["BAR-006 BAR-001 BAR-002: native owner deduplicates presentation and releases timer/canvas resources"] = function()
    local f, hs = fake(); local updates = 0; local owner = NativeBar.new(hs, function() updates = updates + 1 end):start()
    local p = { displayId = "built-in", frame = { x = 0, y = 0, w = 100, h = 32 }, visible = true, elements = { { type = "text", frame = { x = 0, y = 0, w = 1, h = 1 }, text = "x", textFont = "Menlo" } } }
    owner:present(p):present(p)
    assert(f.replaces == 1 and f.shows == 1 and f.mouseEvents and f.pointerReads == 1)
    f.deadline(); assert(updates == 1 and f.every)
    owner:stop(); assert(f.deleted == 1 and f.timers[2].stopped)
  end,
}
