local State = {}
State.__index = State

local function indexOf(items, value)
  for index, item in ipairs(items) do
    if item == value then return index end
  end
  return nil
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function wrap(index, size)
  if size == 0 then return nil end
  return ((index - 1) % size) + 1
end

local function newColumn()
  return { windows = {}, selected = nil }
end

local function removeFrom(items, value)
  for index = #items, 1, -1 do
    if items[index] == value then table.remove(items, index) end
  end
end

local function removeWindowFromColumns(columns, id)
  for columnIndex, column in ipairs(columns) do
    local index = indexOf(column.windows, id)
    if index then
      table.remove(column.windows, index)
      if #column.windows == 0 then
        column.selected = nil
      elseif column.selected and column.selected > #column.windows then
        column.selected = #column.windows
      elseif column.selected and index < column.selected then
        column.selected = column.selected - 1
      end
      return columnIndex
    end
  end
  return nil
end

local function firstWindow(scope, preferredColumn)
  local preferred = scope.columns[preferredColumn]
  if preferred and preferred.windows[1] then return preferred.windows[1] end
  for columnIndex, column in ipairs(scope.columns) do
    if columnIndex ~= preferredColumn and column.windows[1] then return column.windows[1] end
  end
  return nil
end

local function focusFallback(scope, preferredColumn)
  return scope.focusHistory[1] or firstWindow(scope, preferredColumn)
end

function State.new(config)
  return setmetatable({ config = config, scopes = {} }, State)
end

function State:scopeKey(context)
  return tostring(context.screenId) .. ":" .. tostring(context.spaceId or "unknown")
end

function State:scope(context)
  local key = self:scopeKey(context)
  if not self.scopes[key] then
    self.scopes[key] = {
      context = { screenId = context.screenId, spaceId = context.spaceId },
      layout = self.config.initialLayout or "stack",
      ratio = self.config.initialColumnRatio or 0.5,
      activeColumn = 1,
      columns = { newColumn(), newColumn() },
      -- Captured when columns collapse into a stack so a later return to the
      -- columns layout can restore each window to its prior column.
      columnSnapshot = nil,
      unmanaged = {},
      -- Most-recent-first focus history for this display/Space. It lets a
      -- focused window close return to the last window used in this workspace,
      -- rather than whichever window macOS happens to choose during teardown.
      focusHistory = {},
    }
  end
  return self.scopes[key]
end

function State:contains(context, id)
  local scope = self:scope(context)
  for _, column in ipairs(scope.columns) do
    if indexOf(column.windows, id) then return true end
  end
  return false
end

function State:addWindow(context, id, columnIndex, force)
  local scope = self:scope(context)
  if scope.unmanaged[id] and not force then return false end
  if self:contains(context, id) then return false end

  local column = scope.columns[columnIndex or scope.activeColumn]
  table.insert(column.windows, id)
  column.selected = #column.windows
  return true
end

-- Admission policy for windows that arrive after a scope already exists. The
-- initial startup population is balanced separately by the engine; afterwards
-- new windows belong with the stack the user is working in. A lone window is
-- normalized to the physical left column, so its next neighbor always opens on
-- the right rather than inheriting a prior column swap.
function State:addNewWindow(context, id)
  local scope = self:scope(context)
  if scope.unmanaged[id] or self:contains(context, id) then return false end

  if scope.layout ~= "columns" then return self:addWindow(context, id, 1) end

  local count = self:windowCount(context)
  if count == 1 then
    local left, right = scope.columns[1], scope.columns[2]
    if #left.windows == 0 then
      left.windows, left.selected = right.windows, right.selected
      right.windows, right.selected = {}, nil
      scope.activeColumn = 1
    end
    return self:addWindow(context, id, 2)
  end

  return self:addWindow(context, id, scope.activeColumn)
end

function State:removeWindow(context, id, keepUnmanaged)
  local scope = self:scope(context)
  removeWindowFromColumns(scope.columns, id)
  removeFrom(scope.focusHistory, id)
  if not keepUnmanaged then scope.unmanaged[id] = nil end
end

function State:setManaged(context, id, managed, columnIndex)
  local scope = self:scope(context)
  if managed then
    scope.unmanaged[id] = nil
    return self:addWindow(context, id, columnIndex, true)
  end
  self:removeWindow(context, id, true)
  scope.unmanaged[id] = true
  return true
end

-- Remove a window from every scope. Return the context and fallback column so
-- the engine can resolve a surviving workspace fallback after pruning stale windows.
function State:forgetWindow(id)
  for _, scope in pairs(self.scopes) do
    local columnIndex = removeWindowFromColumns(scope.columns, id)
    if columnIndex then
      scope.unmanaged[id] = nil
      removeFrom(scope.focusHistory, id)

      return {
        context = scope.context,
        fallbackColumn = columnIndex,
      }
    end
  end
  return nil
end

function State:prune(context, isLive)
  local scope = self:scope(context)
  for _, column in ipairs(scope.columns) do
    for index = #column.windows, 1, -1 do
      if not isLive(column.windows[index]) then
        table.remove(column.windows, index)
      end
    end
    if #column.windows == 0 then
      column.selected = nil
    else
      column.selected = clamp(column.selected or 1, 1, #column.windows)
    end
  end
  for index = #scope.focusHistory, 1, -1 do
    if not isLive(scope.focusHistory[index]) then table.remove(scope.focusHistory, index) end
  end
end

function State:focusFallback(context, preferredColumn)
  return focusFallback(self:scope(context), preferredColumn)
end

function State:leastPopulatedColumn(context)
  local scope = self:scope(context)
  if scope.layout ~= "columns" then return 1 end
  if #scope.columns[1].windows <= #scope.columns[2].windows then return 1 end
  return 2
end

function State:windowCount(context)
  local scope = self:scope(context)
  return #scope.columns[1].windows + #scope.columns[2].windows
end

function State:toggleLayout(context)
  local scope = self:scope(context)
  if scope.layout == "stack" then
    -- Restore the columns that existed before the stack layout. Windows added
    -- while stacked have no saved column, so distribute only those evenly.
    local focusedId = self:selectedId(context)
    local snapshot = scope.columnSnapshot or { assignments = {}, activeColumn = 1 }
    local restored = { newColumn(), newColumn() }
    for _, source in ipairs(scope.columns) do
      for _, id in ipairs(source.windows) do
        local columnIndex = snapshot.assignments[id]
        if not columnIndex then
          columnIndex = #restored[1].windows <= #restored[2].windows and 1 or 2
        end
        table.insert(restored[columnIndex].windows, id)
      end
    end

    for columnIndex, column in ipairs(restored) do
      local selectedId = snapshot.selectedIds and snapshot.selectedIds[columnIndex]
      column.selected = selectedId and indexOf(column.windows, selectedId)
      if not column.selected and #column.windows > 0 then column.selected = 1 end
    end
    scope.columns = restored
    scope.layout = "columns"
    scope.activeColumn = snapshot.activeColumn
    if focusedId then self:selectId(context, focusedId) end
    scope.columnSnapshot = nil
    return scope.layout
  end

  -- A one-column layout has exactly one stack. Preserve each window's prior
  -- column before merging, so toggling back to columns does not strand every
  -- window in the left column.
  local focusedId = self:selectedId(context)
  local first, second = scope.columns[1], scope.columns[2]
  local assignments, selectedIds = {}, {}
  for columnIndex, column in ipairs(scope.columns) do
    for _, id in ipairs(column.windows) do assignments[id] = columnIndex end
    selectedIds[columnIndex] = column.windows[column.selected]
  end
  scope.columnSnapshot = {
    assignments = assignments,
    selectedIds = selectedIds,
    activeColumn = scope.activeColumn,
  }
  for _, id in ipairs(second.windows) do table.insert(first.windows, id) end
  second.windows, second.selected = {}, nil
  scope.layout, scope.activeColumn = "stack", 1
  if focusedId then first.selected = indexOf(first.windows, focusedId) end
  if not first.selected and #first.windows > 0 then first.selected = 1 end
  return scope.layout
end

function State:selectedId(context, columnIndex)
  local scope = self:scope(context)
  local column = scope.columns[columnIndex or scope.activeColumn]
  return column.windows[column.selected]
end

function State:selectId(context, id)
  local scope = self:scope(context)
  for columnIndex, column in ipairs(scope.columns) do
    local index = indexOf(column.windows, id)
    if index then
      scope.activeColumn = columnIndex
      column.selected = index
      removeFrom(scope.focusHistory, id)
      table.insert(scope.focusHistory, 1, id)
      return id
    end
  end
  return nil
end

function State:focusInStack(context, direction)
  local scope = self:scope(context)
  local column = scope.columns[scope.activeColumn]
  if #column.windows == 0 then return nil end
  column.selected = wrap((column.selected or 1) + direction, #column.windows)
  return column.windows[column.selected]
end

function State:focusColumn(context)
  local scope = self:scope(context)
  if scope.layout ~= "columns" then return self:selectedId(context) end
  local destination = scope.activeColumn == 1 and 2 or 1
  if #scope.columns[destination].windows == 0 then return nil end
  scope.activeColumn = destination
  local column = scope.columns[destination]
  column.selected = clamp(column.selected or 1, 1, #column.windows)
  return column.windows[column.selected]
end

function State:swapColumns(context)
  local scope = self:scope(context)
  scope.columns[1], scope.columns[2] = scope.columns[2], scope.columns[1]
  scope.activeColumn = 3 - scope.activeColumn
end

-- direction is physical: -1 moves the divider left, +1 moves it right.
-- This makes [ and ] directional regardless of which column has focus.
function State:moveDivider(context, direction)
  local scope = self:scope(context)
  if scope.layout ~= "columns" then return scope.ratio end
  scope.ratio = clamp(scope.ratio + (self.config.resizeStep * direction),
    self.config.minimumColumnRatio, self.config.maximumColumnRatio)
  return scope.ratio
end

function State:resetDivider(context)
  local scope = self:scope(context)
  if scope.layout ~= "columns" then return scope.ratio end
  scope.ratio = self.config.initialColumnRatio or 0.5
  return scope.ratio
end

function State:moveToOtherColumn(context, id)
  local scope = self:scope(context)
  if scope.layout ~= "columns" then return nil, "columns-layout-required" end
  if self:windowCount(context) < 3 then return nil, "at-least-three-windows-required" end
  local sourceIndex = scope.activeColumn
  local source = scope.columns[sourceIndex]
  local index = indexOf(source.windows, id)
  if not index then return nil end

  table.remove(source.windows, index)
  if #source.windows == 0 then source.selected = nil
  else source.selected = clamp(source.selected or 1, 1, #source.windows) end

  local destinationIndex = 3 - sourceIndex
  local destination = scope.columns[destinationIndex]
  table.insert(destination.windows, id)
  destination.selected = #destination.windows
  scope.activeColumn = destinationIndex
  return id
end

return State
