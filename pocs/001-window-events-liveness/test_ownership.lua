local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local Ownership = require("ownership")
local function equal(actual, expected) assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual))) end

return {
  ["WIN-006 POC bootstrap confirms one regular owner without a move"] = function()
    local model = Ownership.new()
    local result = model:observe("win-001", { { space = "space-001", kind = "regular" } })
    equal(result.kind, "regular"); equal(result.space, "space-001"); equal(result.move, nil)
  end,
  ["FS-002 POC fullscreen and uncertainty retain prior confirmed regular ownership"] = function()
    local model = Ownership.new()
    model:observe("win-001", { { space = "space-001", kind = "regular" } })
    local fullscreen = model:observe("win-001", { { space = "space-009", kind = "fullscreen" } })
    equal(fullscreen.kind, "fullscreen"); equal(fullscreen.retained_regular, "space-001")
    local unknown = model:observe("win-001", { { space = "space-010", kind = "unknown" } })
    equal(unknown.kind, "unknown"); equal(unknown.retained_regular, "space-001")
  end,
  ["WIN-006 POC emits a move only for distinct uniquely confirmed regular owners"] = function()
    local model = Ownership.new()
    model:observe("win-001", { { space = "space-001", kind = "regular" } })
    local move = model:observe("win-001", { { space = "space-002", kind = "regular" } })
    equal(move.move.from, "space-001"); equal(move.move.to, "space-002")
    equal(model:observe("win-001", { { space = "space-002", kind = "regular" } }).move, nil)
  end,
  ["STATE-005 POC ambiguous memberships defer and never replace confirmed ownership"] = function()
    local model = Ownership.new()
    model:observe("win-001", { { space = "space-001", kind = "regular" } })
    local ambiguous = model:observe("win-001", { { space = "space-002", kind = "regular" }, { space = "space-003", kind = "regular" } })
    equal(ambiguous.kind, "unknown"); equal(ambiguous.retained_regular, "space-001"); equal(ambiguous.move, nil)
  end,
}
