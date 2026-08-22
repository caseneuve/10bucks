local FocusHistory = require("lib.focus_history")

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

return {
  ["global focus history returns the immediately previous window"] = function()
    local history = FocusHistory.new()
    local one, two, three = {}, {}, {}
    history:remember(1, one)
    history:remember(2, two)
    history:remember(3, three)

    local previous = history:previous(3)
    equal(previous.id, 2)
    equal(previous.window, two)
  end,

  ["global focus history keeps one entry per window and toggles when refocused"] = function()
    local history = FocusHistory.new()
    local one, two = {}, {}
    history:remember(1, one)
    history:remember(2, two)
    history:remember(1, one)

    equal(history:previous(1).id, 2)
    assert(history:previous(2) == nil)
  end,

  ["untracked current focus returns the latest tracked application window"] = function()
    local history = FocusHistory.new()
    local window = {}
    history:remember(42, window)
    equal(history:previous(999).id, 42)
    history:forget(42)
    assert(history:previous(999) == nil)
  end,
}
