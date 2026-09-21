local FocusHistory = require("lib.focus_history")

local function ids(history)
  local result = {}
  for index, entry in ipairs(history:snapshot()) do result[index] = entry.windowId end
  return table.concat(result, ",")
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
  ["WIN-005 FOCUS-005: dead targets are pruned without a scan and unmanaged focus cannot enter history"] = function()
    local history = FocusHistory.new()
    history:observe({ windowId = "A", spaceId = "one" })
    history:observe({ windowId = "dead", spaceId = "two" })
    history:observe({ windowId = "B", spaceId = "three" })
    local target = history:previous(function(candidate) return candidate.windowId ~= "dead" end)
    assert(target.windowId == "A" and ids(history) == "A,B")
    history:remove("A")
    assert(history:previous(function() return true end) == nil)
  end,
}
