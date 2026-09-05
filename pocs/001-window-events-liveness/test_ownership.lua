local source = debug.getinfo(1, "S").source:sub(2)
local root = source:match("(.*/)pocs/") or "./"
package.path = root .. "pocs/001-window-events-liveness/?.lua;" .. package.path

local Ownership = require("ownership")
local function equal(actual, expected) assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual))) end

return {
  ["WIN-006 POC bootstrap confirms one regular owner without a move"] = function()
    local model = Ownership.new()
    local result = model:observe("win-001", { { space = "space-001", kind = "regular", reciprocal = true } })
    equal(result.kind, "regular"); equal(result.space, "space-001"); equal(result.move, nil)
  end,
  ["FS-002 POC fullscreen and uncertainty retain prior confirmed regular ownership"] = function()
    local model = Ownership.new()
    model:observe("win-001", { { space = "space-001", kind = "regular", reciprocal = true } })
    local fullscreen = model:observe("win-001", { { space = "space-009", kind = "fullscreen", reciprocal = true } })
    equal(fullscreen.kind, "fullscreen"); equal(fullscreen.retained_regular, "space-001")
    local unknown = model:observe("win-001", { { space = "space-010", kind = "unknown" } })
    equal(unknown.kind, "unknown"); equal(unknown.retained_regular, "space-001")
  end,
  ["WIN-006 POC emits a move only for distinct uniquely reciprocal regular owners"] = function()
    local model = Ownership.new()
    model:observe("win-001", { { space = "space-001", kind = "regular", reciprocal = true } })
    local move = model:observe("win-001", { { space = "space-002", kind = "regular", reciprocal = true } })
    equal(move.reason, "unique_regular"); equal(move.membership_count, 1); equal(move.reciprocal_confirmed_count, 1)
    equal(move.move.from, "space-001"); equal(move.move.to, "space-002")
    local same = model:observe("win-001", { { space = "space-002", kind = "regular", reciprocal = true } })
    equal(same.move, nil); equal(same.no_regular_move, true); equal(same.reason, "same_regular")
  end,
  ["STATE-005 POC reciprocal reasons defer fullscreen unknown and ambiguous ownership without a move"] = function()
    local model = Ownership.new()
    model:observe("win-001", { { space = "space-001", kind = "regular", reciprocal = true } })
    local fullscreen = model:observe("win-001", { { space = "space-009", kind = "fullscreen", reciprocal = true } })
    equal(fullscreen.reason, "fullscreen"); equal(fullscreen.no_regular_move, true); equal(fullscreen.retained_regular, "space-001")
    local ambiguous = model:observe("win-001", { { space = "space-002", kind = "regular", reciprocal = true }, { space = "space-003", kind = "regular", reciprocal = true } })
    equal(ambiguous.kind, "unknown"); equal(ambiguous.reason, "ambiguous"); equal(ambiguous.retained_regular, "space-001"); equal(ambiguous.move, nil)
    local missing = model:observe("win-001", {})
    equal(missing.reason, "missing"); equal(missing.no_regular_move, true); equal(missing.retained_regular, "space-001")
  end,
}
