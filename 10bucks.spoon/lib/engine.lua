local Geometry = require("lib.geometry")
local FocusHistory = require("lib.focus_history")
local WindowChooser = require("lib.window_chooser")

local Engine = {}
Engine.__index = Engine

local function labelFor(scope)
  if scope.layout == "stack" then return "Stack" end
  return string.format("Columns %d/%d", math.floor(scope.ratio * 100 + 0.5), 100 - math.floor(scope.ratio * 100 + 0.5))
end

local function focusedScreenAndContext(engine)
  local _, context = engine:focusedContext()
  return context and engine.repository:screenForContext(context), context
end

function Engine.new(dependencies)
  assert(dependencies.state and dependencies.repository and dependencies.workspaces and dependencies.config,
    "10bucks engine requires state, repository, workspaces, and config")
  dependencies.focusHistory = dependencies.focusHistory or FocusHistory.new()
  return setmetatable(dependencies, Engine)
end

function Engine:notify(message)
  if self.statusDisplay then self.statusDisplay(message) end
end

function Engine:isDesktopContext(context)
  if not context then return false end
  if not self.workspaces:isAvailable() then return true end
  return self.workspaces:isDesktopSpace(context.spaceId)
end

function Engine:reflow(context)
  context = context or self.repository:currentContext()
  if not self:isDesktopContext(context) then return false end

  local scope = self.state:scope(context)
  self.state:prune(context, function(id) return self.repository:windowForId(id) ~= nil end)
  local screenFrame = self.repository:screenFrame(context)
  if not screenFrame then return false end

  -- Keep the columns mode selected, but let its sole non-empty column occupy
  -- the whole usable screen. The next window will enter the empty column and
  -- restore the configured split.
  local useTwoColumns = scope.layout == "columns"
    and #scope.columns[1].windows > 0
    and #scope.columns[2].windows > 0
  local frames = Geometry.frames(screenFrame, useTwoColumns and "columns" or "stack", scope.ratio,
    self.config.outerGap, self.config.columnGap, self.config.topGap)
  local columns = scope.layout == "stack" and 1 or 2
  for columnIndex = 1, columns do
    for _, id in ipairs(scope.columns[columnIndex].windows) do
      local window = self.repository:windowForId(id)
      local frame = useTwoColumns and frames[columnIndex] or frames[1]
      if window then self.repository:setFrame(window, frame, self.config.animationDuration) end
    end
  end
  return true
end

function Engine:reflowAll()
  for _, scope in pairs(self.state.scopes) do self:reflow(scope.context) end
end

function Engine:start()
  for _, window in ipairs(self.repository:eligibleWindows()) do
    local context = self.repository:contextForWindow(window)
    if self:isDesktopContext(context) then
      -- Seed columns evenly so the initial two-column mode is useful immediately.
      self.state:addWindow(context, window:id(), self.state:leastPopulatedColumn(context))
    end
  end
  -- Lifecycle subscriptions start after this initial seed, so explicitly
  -- remember the already focused window. Without this, closing it before a
  -- later focus event leaves its workspace with no useful focus history.
  local focused, focusedContext = self:focusedContext()
  if focused and self:isFocusHistoryWindow(focused) then self:rememberFocus(focused) end
  if focused and focusedContext and self:isDesktopContext(focusedContext)
    and self.repository:isEligible(focused) then
    self.state:selectId(focusedContext, focused:id())
  end
  self:reflowAll()
  for _, context in ipairs(self.repository:activeContexts()) do
    local screen = self.repository:screenForContext(context)
    if screen then self.workspaces:rememberActiveDesktop(screen) end
  end
  self:notify("10bucks ready")
  return self
end

function Engine:focusedContext()
  local window = self.repository:focusedWindow()
  local context = self.repository:contextForWindow(window) or self.repository:currentContext()
  return window, context
end

-- The global history deliberately uses the chooser's broad standard-window
-- policy rather than layout eligibility: it must retain floating windows and
-- windows on other native Spaces without admitting or reflowing them.
function Engine:isFocusHistoryWindow(window)
  return self.repository:isFocusHistoryWindow(window)
end

function Engine:rememberFocus(window)
  local id = window and window:id()
  if id and self:isFocusHistoryWindow(window) then self.focusHistory:remember(id, window) end
  return self
end

function Engine:historyWindowForId(id)
  return self.repository:historyWindowForId(id)
end

function Engine:managedFocusedWindow()
  local window, context = self:focusedContext()
  if not window or not self:isDesktopContext(context) or not self.repository:isEligible(window) then return nil, context end

  local scope = self.state:scope(context)
  if scope.unmanaged[window:id()] then return nil, context end
  self.state:addNewWindow(context, window:id())
  self.state:selectId(context, window:id())
  return window, context
end

function Engine:windowCreated(window)
  if not window or not self.repository:isEligible(window) then return false end
  local context = self.repository:contextForWindow(window)
  if not self:isDesktopContext(context) then return false end
  local scope = self.state:scope(context)
  if scope.unmanaged[window:id()] or self.state:contains(context, window:id()) then return false end

  -- A second window always opens on the physical right. Once both columns are
  -- populated, later windows join the stack the user currently has focused.
  self.state:addNewWindow(context, window:id())
  self:reflow(context)
  return true
end

function Engine:windowFocused(window)
  local id = window and window:id()
  local wasPickerFocus = id and self.pickerFocusId == id
  local wasHistoryFocus = id and self.historyFocusId == id
  if wasPickerFocus then self.pickerFocusId = nil end
  if wasHistoryFocus then self.historyFocusId = nil end
  self:rememberFocus(window)
  if not window or not self.repository:isEligible(window) then return false end
  local context = self.repository:contextForWindow(window)
  if not self:isDesktopContext(context) then return false end
  local scope = self.state:scope(context)
  if scope.unmanaged[id] then return false end

  if wasPickerFocus or wasHistoryFocus then
    -- The chooser and global-history actions are focus-only. Do not implicitly
    -- admit an arbitrary target or reflow its scope; either operation can
    -- rearrange stacks and columns merely because focus crossed an app/Space.
    if self.state:contains(context, id) then self.state:selectId(context, id) end
    return true
  end

  self:windowCreated(window)
  self.state:selectId(context, id)
  -- Focus normally changes after a close. Reflow here as a recovery path for
  -- apps that tear down the old Accessibility window before its destroy event
  -- reaches the lifecycle watcher; reflow() prunes that stale window ID.
  self:reflow(context)
  return true
end

-- Reconcile the active scope independently of Accessibility lifecycle events.
-- Chromium can remove its last native window on Cmd-W without emitting any
-- windowNotVisible or windowDestroyed event through hs.window.filter. Polling
-- the small active managed set closes that gap: stale members are pruned and a
-- surviving window is focused when macOS leaves the workspace without one.
function Engine:reconcileActiveWorkspace()
  local context = self.repository:currentContext()
  if not self:isDesktopContext(context) then return false end

  local scope = self.state.scopes[self.state:scopeKey(context)]
  if not scope then return false end

  local onscreenIds = self.repository:onscreenWindowIds()
  local stale = false
  for _, column in ipairs(scope.columns) do
    for _, id in ipairs(column.windows) do
      if not onscreenIds[id] then stale = true break end
    end
    if stale then break end
  end
  if stale then self:reflow(context) end

  -- Layout reconciliation is still useful when macOS already chose a valid
  -- replacement. Never steal focus in that case.
  if self.repository:focusedWindow() then return stale end
  if self.state:windowCount(context) == 0 then return stale end

  local recovery = {
    id = nil,
    context = context,
    fallbackColumn = scope.activeColumn,
  }
  if self:focusRecovery(recovery) then return true, recovery end
  return stale
end

-- A minimized window is temporarily unavailable to layout but remains a live
-- standard window for global focus history. Destruction is permanent, so only
-- that path removes its global-history entry.
function Engine:focusRecovery(recovery)
  -- Only recover focus in the workspace that is active now. A close event from
  -- another Space must never pull focus away from the user's current desktop.
  local active = self.repository:currentContext()
  local sameActiveContext = active
    and active.screenId == recovery.context.screenId
    and active.spaceId == recovery.context.spaceId
  if not sameActiveContext or not self:isDesktopContext(recovery.context) then return false end

  -- Reflow prunes windows that vanished before their lifecycle event. Resolve
  -- the candidate afterwards so a stale history entry cannot swallow the
  -- first-stack fallback and leave this workspace without focus.
  self:reflow(recovery.context)
  local focused = self.repository:focusedWindow()
  local focusedId = focused and focused:id()
  if focused and focusedId ~= recovery.id then return false end

  local candidate = self.state:focusFallback(recovery.context, recovery.fallbackColumn)
  local window = candidate and self.repository:windowForId(candidate)
  if not candidate or not window then return false end

  -- hs.window:focus() only requests focus. The lifecycle may retry this same
  -- recovery if the postcondition is still absent on its next timer tick.
  self:focus(candidate, recovery.context)
  return true
end

function Engine:windowUnavailable(id, destroyed)
  if destroyed then self.focusHistory:forget(id) end
  local removal = self.state:forgetWindow(id)
  if not removal then return false end
  local recovery = {
    id = id,
    context = removal.context,
    fallbackColumn = removal.fallbackColumn,
  }
  if self:focusRecovery(recovery) then return true, recovery end
  return true
end

function Engine:windowDestroyed(id)
  return self:windowUnavailable(id, true)
end

function Engine:windowMinimized(id)
  return self:windowUnavailable(id, false)
end

function Engine:windowUnminimized(window)
  -- A restored managed window returns through the normal admission path. This
  -- restores the two-column split when it was the missing peer.
  return self:windowCreated(window)
end

function Engine:focus(id, context)
  if not id then return false end
  local window = self.repository:windowForId(id)
  if not window then return false end
  self.state:selectId(context, id)
  self.repository:focus(window)
  return true
end

function Engine:toggleLayout()
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  local layout = self.state:toggleLayout(context)
  self:reflow(context)
  self:notify(labelFor(self.state:scope(context)))
  return layout
end

function Engine:focusStack(direction)
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  return self:focus(self.state:focusInStack(context, direction), context)
end

function Engine:focusColumn()
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  return self:focus(self.state:focusColumn(context), context)
end

function Engine:swapColumns()
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  local scope = self.state:scope(context)
  if scope.layout ~= "columns" then
    self:notify("Columns layout required")
    return false
  end
  self.state:swapColumns(context)
  self:reflow(context)
  self:notify("Columns swapped")
  return true
end

function Engine:moveDivider(direction)
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  local scope = self.state:scope(context)
  if scope.layout ~= "columns" then
    self:notify("Columns layout required")
    return false
  end
  self.state:moveDivider(context, direction)
  self:reflow(context)
  self:notify(labelFor(scope))
  return true
end

function Engine:resetDivider()
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  local scope = self.state:scope(context)
  if scope.layout ~= "columns" then
    self:notify("Columns layout required")
    return false
  end
  self.state:resetDivider(context)
  self:reflow(context)
  self:notify(labelFor(scope))
  return true
end

-- Focus the globally previous standard application window. The history is
-- MRU-based, so pressing this repeatedly toggles between the two most recently
-- focused windows, including floating windows and windows on another Space.
function Engine:focusPreviousWindow()
  local current = self.repository:focusedWindow()
  local currentId = current and current:id()
  local target = self.focusHistory:previous(currentId)
  while target do
    -- hs.window.get() can fail for a window outside the active native Space.
    -- Retain the lifecycle object's reference as the cross-Space fallback;
    -- hs.window:focus() is responsible for making that Space active.
    local window = self:historyWindowForId(target.id) or target.window
    if window and self:isFocusHistoryWindow(window) then
      -- Update immediately as well as on the ensuing lifecycle event, so a
      -- rapid second shortcut reliably toggles even before that event arrives.
      self.focusHistory:remember(target.id, window)
      self.historyFocusId = target.id
      self.repository:focus(window)
      return true
    end
    self.focusHistory:forget(target.id)
    target = self.focusHistory:previous(currentId)
  end
  self:notify("No previously focused window")
  return false
end

function Engine:moveFocusedToOtherColumn()
  local window, context = self:managedFocusedWindow()
  if not window or not context then return false end
  local moved, reason = self.state:moveToOtherColumn(context, window:id())
  if not moved then
    if reason == "at-least-three-windows-required" then
      self:notify("At least 3 windows required")
    else
      self:notify("Columns layout required")
    end
    return false
  end
  self:reflow(context)
  self:focus(window:id(), context)
  return true
end

-- Show a fresh searchable list of every live Hammerspoon window. Selection
-- deliberately focuses the chosen window directly: managed eligible windows
-- are then admitted/selected through the normal focus lifecycle path.
function Engine:cancelWindowSelection()
  if self.windowChooser then self.windowChooser:hide() end
  self.windowChooser = nil
  self.pickerFocusId = nil
  return self
end

function Engine:focusPickedWindow(window)
  local id = window and window:id()
  if not id then return false end
  -- The next lifecycle focus event is intentionally handled as focus-only.
  self.pickerFocusId = id
  self.repository:focus(window)
  return true
end

function Engine:chooseWindow(hs)
  if not hs or not hs.chooser or type(hs.chooser.new) ~= "function" then
    self:notify("Window chooser is unavailable")
    return false
  end
  self:cancelWindowSelection()
  self.windowChooser = WindowChooser.new(hs, self.repository, function(window)
    self:focusPickedWindow(window)
  end)
  local shown, err = self.windowChooser:show()
  if not shown then self:notify(err or "Window chooser is unavailable") end
  return shown
end

function Engine:toggleManaged()
  local window, context = self:focusedContext()
  if not window or not self:isDesktopContext(context) or not self.repository:isEligible(window) then
    self:notify("Focused window cannot be managed")
    return false
  end

  if self.state:contains(context, window:id()) then
    self.state:setManaged(context, window:id(), false)
    self:reflow(context)
    self:notify("Window floating")
  else
    self.state:setManaged(context, window:id(), true)
    self:reflow(context)
    self:notify("Window managed")
  end
  return true
end

function Engine:switchWorkspace(screen, destination)
  if not destination then
    self:notify("No mapped desktop workspace")
    return false
  end
  self.workspaces:setPendingDesktop(screen, destination)
  local ok, err = self.workspaces:gotoDesktop(destination.id)
  if not ok then
    self.workspaces:clearPendingDesktop(screen)
    self:notify(err or "Unable to switch workspace")
    return false
  end
  self:notify(string.format("Desktop %d", destination.index))
  return true
end

function Engine:focusWorkspace(direction)
  local screen = focusedScreenAndContext(self)
  if not screen or not self.workspaces:isAvailable() then
    self:notify("Desktop workspace support is unavailable")
    return false
  end
  return self:switchWorkspace(screen, self.workspaces:neighboringDesktop(screen, direction))
end

function Engine:focusOrCreateWorkspaceNumber(index)
  local screen = focusedScreenAndContext(self)
  if not screen or not self.workspaces:isAvailable() then
    self:notify("Desktop workspace support is unavailable")
    return false
  end
  local destination = self.workspaces:desktopAt(screen, index)
  if destination then return self:switchWorkspace(screen, destination) end
  return self:newWorkspace(index)
end

function Engine:focusPreviouslyFocusedWorkspace()
  local screen = focusedScreenAndContext(self)
  if not screen or not self.workspaces:isAvailable() then
    self:notify("Desktop workspace support is unavailable")
    return false
  end
  local destination = self.workspaces:previouslyFocusedDesktop(screen)
  if not destination then
    self:notify("No previously focused desktop workspace")
    return false
  end
  return self:switchWorkspace(screen, destination)
end

function Engine:workspaceWindowsInContext(context)
  local windows = self.repository:workspaceWindows()
  local matching = {}
  for _, window in ipairs(windows) do
    local windowContext = self.repository:contextForWindow(window)
    if windowContext and windowContext.screenId == context.screenId and windowContext.spaceId == context.spaceId then
      table.insert(matching, window)
    end
  end
  return matching
end

function Engine:deleteWorkspace()
  local screen, context = focusedScreenAndContext(self)
  if not screen or not self.workspaces:isAvailable() or not self.workspaces:canRemoveDesktop() then
    self:notify("Desktop workspace removal is unavailable")
    return false
  end

  local source = self.workspaces:activeDesktop(screen)
  if not source then
    self:notify("Current Space is not a desktop workspace")
    return false
  end

  local windows = self:workspaceWindowsInContext(context)
  if #windows > 0 then
    self:notify(string.format("Cannot remove desktop: it contains %d window%s", #windows, #windows == 1 and "" or "s"))
    return false
  end

  local destination = self.workspaces:previouslyFocusedDesktop(screen)
  if not destination then
    self:notify("No previously focused desktop workspace")
    return false
  end

  local queued, err = self.workspaces:queueDesktopRemoval(screen, source, destination)
  if not queued then
    self:notify(err or "Unable to remove desktop workspace")
    return false
  end

  self.workspaces:setPendingDesktop(screen, destination)
  local switched, switchErr = self.workspaces:gotoDesktop(destination.id)
  if not switched then
    self.workspaces:clearPendingDesktop(screen)
    self.workspaces:clearPendingRemoval(screen)
    self:notify(switchErr or "Unable to switch workspace")
    return false
  end
  self:notify(string.format("Removing empty desktop %d", source.index))
  return true
end

function Engine:cancelWorkspaceSelection()
  local modal = self.workspaceSelectionModal
  self.workspaceSelectionModal = nil
  if modal then modal:exit() end
  return self
end

-- Enter a Hammerspoon-only modal for direct mapped-desktop selection. This
-- intentionally does not involve skhd or an external IPC command: desktop
-- selection is 10bucks behavior.
function Engine:chooseWorkspace(hs)
  if not hs or not hs.hotkey or not hs.hotkey.modal or type(hs.hotkey.modal.new) ~= "function" then
    self:notify("Desktop workspace selection is unavailable")
    return false
  end

  self:cancelWorkspaceSelection()
  local modal = hs.hotkey.modal.new()
  self.workspaceSelectionModal = modal
  local function dismiss()
    if self.workspaceSelectionModal == modal then self.workspaceSelectionModal = nil end
    modal:exit()
  end

  modal:bind({}, "escape", dismiss)
  for index = 1, 9 do
    local selectedIndex = index
    modal:bind({}, tostring(selectedIndex), function()
      self:focusOrCreateWorkspaceNumber(selectedIndex)
      dismiss()
    end)
  end
  modal:enter()
  self:notify("Desktop: 1-9 (Esc cancels)")
  return true
end

-- Create a native macOS desktop and immediately enter it. macOS creates a
-- blank user Space; 10bucks initializes its scoped layout lazily when the
-- Space-change watcher reports the transition.
function Engine:newWorkspace(label)
  local screen = focusedScreenAndContext(self)
  if not screen or not self.workspaces:canCreateDesktop() then
    self:notify("Desktop workspace creation is unavailable")
    return false
  end

  local added, destination = self.workspaces:addDesktop(screen, label)
  if not added then
    self:notify(destination or "Unable to create desktop workspace")
    return false
  end

  self.workspaces:setPendingDesktop(screen, destination)
  local switched, err = self.workspaces:gotoDesktop(destination.id)
  if not switched then
    self.workspaces:clearPendingDesktop(screen)
    self.workspaces:closeMissionControl()
    self:notify(err or "Unable to switch workspace")
    return false
  end
  self:notify(string.format("New desktop %d", destination.index))
  return true
end

function Engine:workspaceChanged()
  -- A native Space switch exposes a different set of Accessibility windows.
  -- Seed only the currently visible regular-desktop scopes and never reflow a
  -- fullscreen/tiled scratchpad.
  local contexts = {}
  for _, context in ipairs(self.repository:activeContexts()) do
    local screen = self.repository:screenForContext(context)
    if screen then self.workspaces:rememberActiveDesktop(screen) end
    if screen then
      local removed, result = self.workspaces:completePendingRemoval(screen)
      if removed then self:notify(string.format("Removed empty desktop %d", result.index))
      elseif result then self:notify(result) end
    end
    if self:isDesktopContext(context) then contexts[self.state:scopeKey(context)] = context end
  end
  for _, window in ipairs(self.repository:eligibleWindows()) do
    local context = self.repository:contextForWindow(window)
    if self:isDesktopContext(context) then
      self.state:addNewWindow(context, window:id())
      contexts[self.state:scopeKey(context)] = context
    end
  end
  for _, context in pairs(contexts) do self:reflow(context) end
  return next(contexts) ~= nil
end

function Engine:recover()
  -- Recovery must work even after a close leaves no focused application window.
  local _, context = self:focusedContext()
  if not self:isDesktopContext(context) then return false end
  self:reflow(context)
  self:notify("10bucks reflowed")
  return true
end

return Engine
