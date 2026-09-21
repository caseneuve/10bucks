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
    assert(history:registerUnplaced(fullscreenReady("F", 44)))
    assert(ids(history) == "A,B", "readiness must not fabricate focus history")

    local recorded = assert(history:unplacedTarget("F"))
    assert(recorded.target.windowId == "F" and recorded.target.spaceId == "fullscreen-space")
    assert(recorded.pid == 44 and recorded.metadata.nativeFullscreen and recorded.decision.action == "manage")
    local duplicate = fullscreenReady("F", 99)
    duplicate.decision.reason = "later-decision"
    assert(not history:registerUnplaced(duplicate), "duplicate readiness must preserve the original decision")
    assert(history:unplacedTarget("F").pid == 44 and history:unplacedTarget("F").decision.reason == nil)
    recorded.metadata.nativeFullscreen = false
    assert(history:unplacedTarget("F").metadata.nativeFullscreen, "returned records must be defensive copies")

    history:observe(recorded.target)
    assert(ids(history) == "A,B,F")
    history:request(recorded.target)
    local rebound = fullscreenReady("F", 99, "fullscreen-space-2")
    rebound.decision.reason = "new-owner-must-not-reclassify"
    assert(history:registerUnplaced(rebound), "a new confirmed fullscreen owner must rebind in place")
    local reboundRecord = assert(history:unplacedTarget("F"))
    assert(reboundRecord.target.spaceId == "fullscreen-space-2")
    assert(reboundRecord.pid == 44 and reboundRecord.metadata.spaceId == "fullscreen-space"
      and reboundRecord.decision.reason == nil, "duplicate readiness retains original metadata/decision")
    assert(history:snapshot()[3].spaceId == "fullscreen-space-2")
    assert(history:pending().target.spaceId == "fullscreen-space-2")
    history:cancel()

    local first = assert(history:previous(function() return true end))
    assert(first.windowId == "B")
    local pending = history:request(first)
    assert(pending.target.windowId == "B" and history:pending().target.windowId == "B")
    local generation = history:pending().generation
    local rapid = assert(history:previous(function() return true end))
    assert(rapid.windowId == "B", "unconfirmed previous resolves from unchanged actual history")
    history:request(rapid)
    assert(history:pending().target.windowId == "B" and history:pending().generation == generation + 1)

    history:observe({ windowId = "B", spaceId = "two" })
    assert(history:pending() == nil and ids(history) == "A,F,B")
    assert(history:previous(function() return true end).windowId == "F")
  end,

  ["STATE-001 STATE-003: pure focus reducer commits defensive plain state"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    local before = history:state()
    assert(FocusHistory.reduce(before, { type = "Observe", target = { windowId = "A", spaceId = "one" } }) == before,
      "duplicate newest observation is a reducer no-op")
    local reduced = FocusHistory.reduce(before, { type = "Request", target = { windowId = "A", spaceId = "one" } })
    assert(before.pending == nil and reduced.pending.target.windowId == "A")
    reduced.pending.target.spaceId = "corrupt"
    assert(history:state().pending == nil and before.pending == nil)
  end,

  ["FOCUS-005: nonmatching known actual focus preserves a pending global request and its MRU"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "two" })
    history:request({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "B", spaceId = "two" })
    assert(ids(history) == "A,B")
    assert(history:pending().target.windowId == "A")
    history:cancel()
    assert(history:pending() == nil)
  end,

  ["FS-004 FS-005 LIFE-003: promotion rebinds an unplaced target in place without MRU insertion or rule replacement"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    assert(history:registerUnplaced(fullscreenReady("F", 44)))
    history:observe({ windowId = "F", spaceId = "fullscreen-space" })
    history:observe({ windowId = "A", spaceId = "one" })
    assert(ids(history) == "F,A")

    assert(history:promote({ windowId = "F", spaceId = "regular-destination" }))
    assert(history:unplacedTarget("F") == nil)
    local state = history:state()
    assert(state.entries[1].windowId == "F" and state.entries[1].spaceId == "regular-destination")
    assert(ids(history) == "F,A", "promotion must not reorder MRU")
    state.entries[1].spaceId = "corrupt"
    assert(history:snapshot()[1].spaceId == "regular-destination")
  end,

  ["WIN-005 FOCUS-005: authoritative removal prunes history and unplaced ownership without resolver-driven registry deletion"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    assert(history:registerUnplaced(fullscreenReady("F", 44)))
    history:observe({ windowId = "F", spaceId = "fullscreen-space" })
    local target = history:previous(function(candidate) return candidate.windowId ~= "F" end)
    assert(target == nil and history:unplacedTarget("F") ~= nil)
    history:removeApplication(44)
    assert(history:unplacedTarget("F") == nil and ids(history) == "A")
    history:remove("A")
    assert(history:previous(function() return true end) == nil)
  end,
}
