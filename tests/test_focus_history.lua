local FocusHistory = require("lib.focus_history")
local Rules = require("lib.rules")

local function ids(history)
  local result = {}
  for index, entry in ipairs(history:snapshot()) do result[index] = entry.windowId end
  return table.concat(result, ",")
end

local function fullscreenReady(id, pid, spaceId)
  return assert(Rules.ready({
    id = id, application = { pid = pid, bundleID = "example.app", name = "Example" },
    title = "Fullscreen", displayId = "built-in", spaceId = spaceId or "fullscreen-space",
    role = "AXWindow", subrole = "AXStandardWindow", modal = false,
    movable = false, resizable = true, selfProcess = false, origin = "targetedReadiness",
    spaceType = "fullscreen", nativeFullscreen = true,
  }))
end

return {
  ["SPACE-006 FS-003: retired scopes retain live primitive metadata history order and uncertainty until readiness"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "gone" })
    history:observe({ windowId = "B", spaceId = "live" })
    history:request({ windowId = "A", spaceId = "gone" })
    local window = { id = "A", application = { pid = 44, bundleID = "example" }, title = "A",
      placementSpaceId = "gone", actualSpaceId = "gone", lifecycle = { nativeFullscreen = false } }
    history:invalidateSpace("gone", { window })
    assert(history:pending() == nil and ids(history) == "A,B")
    local record = assert(history:unplacedTarget("A"))
    assert(record.uncertain and record.pid == 44 and record.target.spaceId == "gone")
    assert(record.window.title == "A" and record.window.placementSpaceId == nil and window.placementSpaceId == "gone")
    record.window.title = "corrupt"; assert(history:unplacedTarget("A").window.title == "A")
    assert(#history:unplacedTargets() == 0)
    local calls = 0
    assert(history:previous(function() calls = calls + 1; return true end) == nil)
    assert(calls == 1 and ids(history) == "A,B")
    history:observe({ windowId = "A", spaceId = "elsewhere" }); assert(ids(history) == "A,B")
    history:promote({ windowId = "A", spaceId = "new" })
    assert(not history:unplacedTarget("A") and ids(history) == "A,B" and history:snapshot()[1].spaceId == "new")
    assert(history:previous(function() return true end).spaceId == "new")
  end,
  ["FS-003 SPACE-006: removed saved regular placement retains confirmed fullscreen descriptor"] = function()
    local h = FocusHistory.new(); h:registerUnplaced(fullscreenReady("F", 44, "full"))
    h:observe({ windowId = "F", spaceId = "full" })
    h:invalidateSpace("gone", { { id = "F", application = { pid = 44 }, placementSpaceId = "gone",
      actualSpaceId = "full", lifecycle = { nativeFullscreen = true } } })
    local record = h:unplacedTarget("F")
    assert(record.target.spaceId == "full" and not record.uncertain and record.window.placementSpaceId == nil)
    assert(#h:unplacedTargets() == 1 and h:snapshot()[1].spaceId == "full")
  end,
  ["SPACE-006 WIN-005: orphan relocation fullscreen readiness destruction and app termination keep lifetime semantics"] = function()
    local function orphan()
      local h = FocusHistory.new(); h:observe({ windowId = "A", spaceId = "gone" })
      h:invalidateSpace("gone", { { id = "A", application = { pid = 44 }, placementSpaceId = "gone" } })
      return h
    end
    local h = orphan(); h:relocate({ windowId = "A", spaceId = "new" })
    assert(not h:unplacedTarget("A") and h:snapshot()[1].spaceId == "new")
    h = orphan(); h:registerUnplaced(fullscreenReady("A", 44, "full"))
    assert(not h:unplacedTarget("A").uncertain and #h:unplacedTargets() == 1 and h:snapshot()[1].spaceId == "full")
    h:remove("A"); assert(not h:unplacedTarget("A") and ids(h) == "")
    h = orphan(); h:removeApplication(44); assert(not h:unplacedTarget("A") and ids(h) == "")
  end,
  ["FOCUS-001 FOCUS-005: confirmed managed observations form unique global MRU and toggle naturally"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "two" })
    history:observe({ windowId = "B", spaceId = "two" })
    assert(ids(history) == "A,B")
    local target = history:previous(function() return true end)
    assert(target.windowId == "A" and target.spaceId == "one")
    history:observe(target)
    assert(history:previous(function() return true end).windowId == "B")
  end,

  ["FOCUS-001 FOCUS-005 FS-005: a confirmed unplaced fullscreen target enters MRU only on actual focus and toggles bidirectionally"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "two" })
    history:registerUnplaced(fullscreenReady("F", 44))
    assert(ids(history) == "A,B", "readiness must not fabricate focus history")

    local recorded = assert(history:unplacedTarget("F"))
    assert(recorded.target.windowId == "F" and recorded.target.spaceId == "fullscreen-space" and recorded.pid == 44)
    history:registerUnplaced(fullscreenReady("F", 44))
    assert(history:unplacedTarget("F").pid == 44, "duplicate readiness retains the original managed lifetime")
    recorded.target.spaceId = "corrupt"
    assert(history:unplacedTarget("F").target.spaceId == "fullscreen-space", "returned targets must be defensive copies")

    local fullscreenTarget = history:unplacedTarget("F").target
    history:observe(fullscreenTarget)
    assert(ids(history) == "A,B,F")
    history:request(fullscreenTarget)
    history:registerUnplaced(fullscreenReady("F", 44, "fullscreen-space-2"))
    local reboundRecord = assert(history:unplacedTarget("F"))
    assert(reboundRecord.target.spaceId == "fullscreen-space-2" and reboundRecord.pid == 44)
    assert(history:snapshot()[3].spaceId == "fullscreen-space-2")
    assert(history:pending().spaceId == "fullscreen-space-2")
    history:cancel()

    local first = assert(history:previous(function() return true end))
    assert(first.windowId == "B")
    history:request(first)
    assert(history:pending().windowId == "B")
    local rapid = assert(history:previous(function() return true end))
    assert(rapid.windowId == "B", "unconfirmed previous resolves from unchanged actual history")
    history:request(rapid)
    assert(history:pending().windowId == "B")

    history:observe({ windowId = "B", spaceId = "two" })
    assert(history:pending() == nil and ids(history) == "A,F,B")
    assert(history:previous(function() return true end).windowId == "F")
  end,

  ["FOCUS-005: nonmatching known actual focus preserves a pending global request and its MRU"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "two" })
    history:request({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "two" })
    assert(ids(history) == "A,B")
    assert(history:pending().windowId == "A")
    history:cancel()
    assert(history:pending() == nil)
  end,

  ["FS-004 FS-005 LIFE-003: promotion rebinds an unplaced target in place without MRU insertion"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:registerUnplaced(fullscreenReady("F", 44))
    history:observe({ windowId = "F", spaceId = "fullscreen-space" })
    history:observe({ windowId = "A", spaceId = "one" })
    assert(ids(history) == "F,A")

    history:promote({ windowId = "F", spaceId = "regular-destination" })
    assert(history:unplacedTarget("F") == nil)
    assert(history:snapshot()[1].windowId == "F" and history:snapshot()[1].spaceId == "regular-destination")
    assert(ids(history) == "F,A", "promotion must not reorder MRU")
  end,

  ["WIN-005 FOCUS-005: authoritative removal prunes history and unplaced ownership without resolver-driven registry deletion"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:registerUnplaced(fullscreenReady("F", 44))
    history:observe({ windowId = "F", spaceId = "fullscreen-space" })
    local target = history:previous(function(candidate) return candidate.windowId ~= "F" end)
    assert(target == nil and history:unplacedTarget("F") ~= nil)
    history:removeApplication(44)
    assert(history:unplacedTarget("F") == nil and ids(history) == "A")
    history:remove("A")
    assert(history:previous(function() return true end) == nil)
  end,
  ["LIFE-002 FOCUS-005: regular relocation rebinds MRU and pending target without reordering"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "one" })
    history:request({ windowId = "A", spaceId = "one" })
    history:relocate({ windowId = "A", spaceId = "two" })
    assert(ids(history) == "A,B" and history:snapshot()[1].spaceId == "two")
    assert(history:pending().windowId == "A" and history:pending().spaceId == "two")
  end,
}
