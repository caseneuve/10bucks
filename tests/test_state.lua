local State = require("lib.state")

local config = {
  resizeStep = 0.1,
  minimumColumnRatio = 0.2,
  maximumColumnRatio = 0.8,
}
local context = { screenId = "screen-a", spaceId = 42 }

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

return {
  ["state cycles selected window inside the active stack"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:addWindow(context, 20)
    equal(state:selectedId(context), 20)
    equal(state:focusInStack(context, 1), 10)
    equal(state:focusInStack(context, -1), 20)
  end,

  ["state preserves a focused window when columns swap"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:toggleLayout(context)
    state:addWindow(context, 20, 2)
    state:selectId(context, 20)
    state:swapColumns(context)
    equal(state:selectedId(context), 20)
    equal(state:scope(context).activeColumn, 1)
  end,

  ["collapsing columns merges both stacks and keeps the focused window"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:toggleLayout(context)
    state:addWindow(context, 20, 2)
    state:selectId(context, 20)
    equal(state:toggleLayout(context), "stack")
    equal(#state:scope(context).columns[1].windows, 2)
    equal(#state:scope(context).columns[2].windows, 0)
    equal(state:selectedId(context), 20)
  end,

  ["returning from stack restores the prior column membership"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:toggleLayout(context)
    state:addWindow(context, 20, 2)
    state:addWindow(context, 30, 2)
    state:selectId(context, 30)

    equal(state:toggleLayout(context), "stack")
    equal(state:toggleLayout(context), "columns")
    local scope = state:scope(context)
    equal(#scope.columns[1].windows, 1)
    equal(scope.columns[1].windows[1], 10)
    equal(#scope.columns[2].windows, 2)
    equal(scope.columns[2].windows[1], 20)
    equal(scope.columns[2].windows[2], 30)
    equal(state:selectedId(context), 30)
  end,

  ["windows added while stacked are balanced on return to columns"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:toggleLayout(context)
    state:addWindow(context, 20, 2)
    state:toggleLayout(context)
    state:addWindow(context, 30)
    state:addWindow(context, 40)

    equal(state:toggleLayout(context), "columns")
    local scope = state:scope(context)
    equal(#scope.columns[1].windows, 2)
    equal(#scope.columns[2].windows, 2)
  end,

  ["returning from stack preserves the selected window in each column"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:addWindow(context, 20)
    state:toggleLayout(context)
    state:addWindow(context, 30, 1)
    state:selectId(context, 20)

    equal(state:toggleLayout(context), "stack")
    equal(state:toggleLayout(context), "columns")
    equal(state:selectedId(context), 20)
    equal(state:focusColumn(context), 30)
  end,

  ["divider movement remains physical regardless of focused column"] = function()
    local state = State.new(config)
    state:toggleLayout(context)
    state:addWindow(context, 10, 2)
    state:moveDivider(context, 1)
    equal(state:scope(context).ratio, 0.6)
    state:focusColumn(context)
    state:moveDivider(context, 1)
    equal(state:scope(context).ratio, 0.7)
    state:moveDivider(context, -1)
    equal(state:scope(context).ratio, 0.6)
  end,

  ["resetting the divider restores the configured split"] = function()
    local state = State.new(config)
    state:toggleLayout(context)
    state:moveDivider(context, 1)
    equal(state:scope(context).ratio, 0.6)
    equal(state:resetDivider(context), 0.5)
  end,

  ["focus fallback uses workspace history after closing the focused window"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:addWindow(context, 20)
    state:addWindow(context, 30)
    state:selectId(context, 10)
    state:selectId(context, 20)
    state:selectId(context, 30)
    state:forgetWindow(30, true)
    equal(state:selectedId(context), 20)
    equal(state:focusFallback(context), 20)
  end,

  ["focus fallback uses the first stack window when history is empty"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:addWindow(context, 20)
    state:forgetWindow(20, true)
    equal(state:focusFallback(context, 1), 10)
  end,

  ["focus fallback does not borrow history from another workspace"] = function()
    local state = State.new(config)
    local otherContext = { screenId = "screen-a", spaceId = 99 }
    state:addWindow(context, 10)
    state:addWindow(context, 20)
    state:addWindow(otherContext, 30)
    state:selectId(otherContext, 30)

    state:forgetWindow(20, true)
    equal(state:focusFallback(context, 1), 10)
  end,

  ["moving between columns requires at least three managed windows"] = function()
    local state = State.new(config)
    state:toggleLayout(context)
    state:addWindow(context, 10, 1)
    state:addWindow(context, 20, 2)
    local moved, reason = state:moveToOtherColumn(context, 10)
    equal(moved, nil)
    equal(reason, "at-least-three-windows-required")
    equal(#state:scope(context).columns[1].windows, 1)
    equal(#state:scope(context).columns[2].windows, 1)
  end,

  ["moving between columns transfers the selected focused window once three windows are managed"] = function()
    local state = State.new(config)
    state:toggleLayout(context)
    state:addWindow(context, 10, 1)
    state:addWindow(context, 20, 2)
    state:addWindow(context, 30, 1)
    state:selectId(context, 10)
    equal(state:moveToOtherColumn(context, 10), 10)
    equal(#state:scope(context).columns[1].windows, 1)
    equal(state:scope(context).columns[1].windows[1], 30)
    equal(#state:scope(context).columns[2].windows, 2)
    equal(state:selectedId(context), 10)
  end,

  ["a second columns window always opens on the physical right"] = function()
    local state = State.new(config)
    state:toggleLayout(context)
    state:addWindow(context, 10, 1)
    state:swapColumns(context)
    assert(state:addNewWindow(context, 20))

    local scope = state:scope(context)
    equal(scope.columns[1].windows[1], 10)
    equal(scope.columns[2].windows[1], 20)
  end,

  ["later columns windows join the currently focused stack"] = function()
    local state = State.new(config)
    state:toggleLayout(context)
    state:addWindow(context, 10, 1)
    state:addWindow(context, 20, 2)
    state:selectId(context, 20)
    assert(state:addNewWindow(context, 30))

    local scope = state:scope(context)
    equal(#scope.columns[1].windows, 1)
    equal(#scope.columns[2].windows, 2)
    equal(scope.columns[2].windows[2], 30)
  end,

  ["unmanaged windows are not implicitly added again"] = function()
    local state = State.new(config)
    state:addWindow(context, 10)
    state:addWindow(context, 20)
    state:addWindow(context, 30)
    state:selectId(context, 30)
    state:setManaged(context, 10, false)
    assert(not state:contains(context, 10))
    equal(state:selectedId(context), 30)
    assert(not state:addWindow(context, 10))
    assert(state:setManaged(context, 10, true))
    assert(state:contains(context, 10))
  end,
}
