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
}
