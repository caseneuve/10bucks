local State = require("lib.state")
local Engine = require("lib.engine")

local context = { screenId = "screen-a", spaceId = "space-a" }

local function equal(actual, expected)
  assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local function fakeWindow(id)
  return {
    id = function() return id end,
    setFrame = function(self, frame) self.lastFrame = frame end,
    focus = function(self) self.focused = true end,
  }
end

local function repositoryWith(ids)
  local windows, order = {}, {}
  for _, id in ipairs(ids) do
    windows[id] = fakeWindow(id)
    table.insert(order, windows[id])
  end
  return {
    windows = windows,
    eligibleWindows = function() return order end,
    workspaceWindows = function() return order end,
    activeContexts = function() return { context } end,
    contextForWindow = function() return context end,
    currentContext = function() return context end,
    screenForContext = function() return { id = "screen-a" } end,
    screenFrame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
    windowForId = function(self, id) return self.windows[id] end,
    onscreenWindowIds = function(self)
      local ids = {}
      for id in pairs(self.windows) do ids[id] = true end
      return ids
    end,
    historyWindowForId = function(self, id) return self.windows[id] end,
    setFrame = function(_, window, frame) window:setFrame(frame) end,
    focus = function(_, window) window:focus() end,
    focusedWindow = function(self) return self.windows[self.focusedId] end,
    isEligible = function(_, window) return window ~= nil end,
    isFocusHistoryWindow = function(_, window) return window ~= nil end,
  }
end

local function workspaceWith(overrides)
  local workspace = {
    isAvailable = function() return false end,
    isDesktopSpace = function() return true end,
    rememberActiveDesktop = function() end,
    previouslyFocusedDesktop = function() return nil end,
    canCreateDesktop = function() return false end,
    canRemoveDesktop = function() return false end,
    closeMissionControl = function() end,
    completePendingRemoval = function() return false end,
    neighboringDesktop = function() return nil end,
    desktopAt = function() return nil end,
    setPendingDesktop = function() end,
    clearPendingDesktop = function() end,
    gotoDesktop = function() return false end,
    activeDesktop = function() return nil end,
    queueDesktopRemoval = function() return false end,
    clearPendingRemoval = function() end,
    addDesktop = function() return false end,
  }
  for name, method in pairs(overrides or {}) do workspace[name] = method end
  return workspace
end

local function build(ids, options)
  local config = {
    animationDuration = 0,
    initialLayout = options and options.initialLayout or "stack",
    outerGap = 10,
    topGap = 10,
    columnGap = 20,
    resizeStep = 0.1,
    minimumColumnRatio = 0.2,
    maximumColumnRatio = 0.8,
  }
  local repository = repositoryWith(ids)
  repository.focusedId = ids[1]
  local engine = Engine.new({
    config = config,
    state = State.new(config),
    repository = repository,
    workspaces = workspaceWith(),
  })
  engine:start()
  return engine, repository
end

local function deletionFixture(options)
  options = options or {}
  local engine, repository = build({})
  local screen = { id = "screen-a" }
  local source = { id = "desktop-2", index = 2 }
  local destination = { id = "desktop-1", index = 1 }
  local destinationContext = { screenId = "screen-a", spaceId = destination.id }
  local currentContext = context
  local observations = { events = {} }

  repository.windows[42] = fakeWindow(42)
  engine.state:addWindow(destinationContext, 42, 1)
  repository.currentContext = function() return currentContext end
  repository.activeContexts = function() return { currentContext } end
  repository.screenForContext = function() return screen end
  repository.setFrame = function(_, window, frame)
    window:setFrame(frame)
    table.insert(observations.events, "reflow")
  end
  repository.focus = function(_, window)
    table.insert(observations.events, "focus:" .. tostring(window:id()))
  end

  engine.workspaces = workspaceWith({
    isAvailable = function() return true end,
    isDesktopSpace = function() return true end,
    canRemoveDesktop = function() return true end,
    activeDesktop = function() return source end,
    previouslyFocusedDesktop = function() return destination end,
    queueDesktopRemoval = function(_, _, queuedSource, queuedDestination)
      observations.queued = { source = queuedSource, destination = queuedDestination }
      return true
    end,
    setPendingDesktop = function() end,
    clearPendingDesktop = function() end,
    clearPendingRemoval = function() end,
    gotoDesktop = function(_, id)
      observations.selected = id
      return options.switchFails ~= true
    end,
    rememberActiveDesktop = function() end,
    completePendingRemoval = function()
      if options.removalFails then return false, "Desktop removal cancelled" end
      return true, source
    end,
  })

  observations.enterDestination = function() currentContext = destinationContext end
  return engine, observations
end

return {
  ["engine initially overlaps all managed windows in the stack"] = function()
    local _, repository = build({ 1, 2 })
    equal(repository.windows[1].lastFrame.w, 980)
    equal(repository.windows[2].lastFrame.w, 980)
    equal(repository.windows[1].lastFrame.x, repository.windows[2].lastFrame.x)
  end,

  ["engine distributes startup windows across initial columns"] = function()
    local _, repository = build({ 1, 2 }, { initialLayout = "columns" })
    equal(repository.windows[1].lastFrame.w, 480)
    equal(repository.windows[2].lastFrame.w, 480)
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[2].lastFrame.x, 510)
  end,

  ["engine refuses to move a focused window between columns when fewer than three windows are managed"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    assert(not engine:moveFocusedToOtherColumn())
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[2].lastFrame.x, 510)
  end,

  ["engine moves a focused window to the other stack when three windows are managed"] = function()
    local engine, repository = build({ 1, 2, 3 }, { initialLayout = "columns" })
    assert(engine:moveFocusedToOtherColumn())
    local scope = engine.state:scope(context)
    equal(#scope.columns[1].windows, 1)
    equal(scope.columns[1].windows[1], 3)
    equal(#scope.columns[2].windows, 2)
    equal(scope.columns[2].windows[1], 2)
    equal(scope.columns[2].windows[2], 1)
    assert(repository.windows[1].focused)
  end,

  ["engine restores both columns after a stack round trip"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    engine:toggleLayout()
    engine:toggleLayout()
    equal(repository.windows[1].lastFrame.w, 480)
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[2].lastFrame.w, 480)
    equal(repository.windows[2].lastFrame.x, 510)
  end,

  ["engine focuses the next item in the selected stack"] = function()
    local engine, repository = build({ 1, 2 })
    engine:focusStack(1)
    assert(repository.windows[2].focused)
  end,

  ["global previous-window focus uses the cross-workspace window lookup"] = function()
    local engine, repository = build({ 1 })
    local otherWorkspaceWindow = fakeWindow(99)
    -- Simulate hs.window.get() not resolving a window in another Space. The
    -- lifecycle reference in global history must still be focusable.
    repository.historyWindowForId = function(_, id)
      return id == 99 and nil or repository.windows[id]
    end
    engine.focusHistory:remember(99, otherWorkspaceWindow)
    engine.focusHistory:remember(1, repository.windows[1])

    assert(engine:focusPreviousWindow())
    assert(otherWorkspaceWindow.focused)
  end,

  ["global previous-window focus includes floating windows without reflowing them"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    engine.state:setManaged(context, 2, false)

    -- Focus history is global rather than layout-scoped, so a floating window
    -- is retained even though its normal focus event cannot manage it.
    repository.focusedId = 2
    assert(not engine:windowFocused(repository.windows[2]))
    repository.focusedId = 1
    assert(engine:windowFocused(repository.windows[1]))
    local firstFrame, secondFrame = repository.windows[1].lastFrame, repository.windows[2].lastFrame
    assert(engine:focusPreviousWindow())
    assert(repository.windows[2].focused)

    -- Its subsequent lifecycle focus event remains focus-only too.
    assert(not engine:windowFocused(repository.windows[2]))
    equal(engine.state:windowCount(context), 1)
    assert(repository.windows[1].lastFrame == firstFrame)
    assert(repository.windows[2].lastFrame == secondFrame)
  end,

  ["picker focus does not admit or reflow an arbitrary window"] = function()
    local engine, repository = build({ 1 }, { initialLayout = "columns" })
    local originalFrame = repository.windows[1].lastFrame
    repository.windows[2] = fakeWindow(2)

    assert(engine:focusPickedWindow(repository.windows[2]))
    assert(engine:windowFocused(repository.windows[2]))
    equal(engine.state:windowCount(context), 1)
    assert(not engine.state:contains(context, 2))
    assert(repository.windows[2].focused)
    assert(repository.windows[1].lastFrame == originalFrame)
  end,

  ["picker focus selects an existing member without rearranging columns"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    local firstFrame, secondFrame = repository.windows[1].lastFrame, repository.windows[2].lastFrame

    assert(engine:focusPickedWindow(repository.windows[2]))
    assert(engine:windowFocused(repository.windows[2]))
    local scope = engine.state:scope(context)
    equal(scope.activeColumn, 2)
    equal(engine.state:selectedId(context), 2)
    assert(repository.windows[1].lastFrame == firstFrame)
    assert(repository.windows[2].lastFrame == secondFrame)
  end,

  ["closing a focused window returns to the last focused window in its workspace"] = function()
    local engine, repository = build({ 1, 2, 3 }, { initialLayout = "columns" })
    repository.focusedId = 2
    assert(engine:windowFocused(repository.windows[2]))
    repository.focusedId = 3
    assert(engine:windowFocused(repository.windows[3]))
    repository.windows[3] = nil
    assert(engine:windowDestroyed(3))
    -- Window 2 is in the other column, proving the replacement is workspace
    -- focus history rather than merely the closing window's stack sibling.
    assert(repository.windows[2].focused)
  end,

  ["closing a focused window with no history focuses the first stack window"] = function()
    local engine, repository = build({ 1, 2 })
    repository.focusedId = 2
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    assert(repository.windows[1].focused)
  end,

  ["closing a background window does not steal focus"] = function()
    local engine, repository = build({ 1, 2 })
    repository.windows[1].focused = true
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    assert(repository.windows[1].focused)
  end,

  ["closing with no focused application restores the active workspace fallback"] = function()
    local engine, repository = build({ 1, 2 })
    repository.focusedId = nil
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    assert(repository.windows[1].focused)
  end,

  ["active reconciliation recovers when Chromium emits no close lifecycle event"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    repository.focusedId = nil
    repository.windows[2] = nil

    local changed, recovery = engine:reconcileActiveWorkspace()

    assert(changed and recovery)
    equal(engine.state:windowCount(context), 1)
    assert(repository.windows[1].focused)
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[1].lastFrame.w, 980)
  end,

  ["active reconciliation prunes a stale peer without stealing existing focus"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    repository.focusedId = 1
    repository.windows[2] = nil

    local changed, recovery = engine:reconcileActiveWorkspace()

    assert(changed and not recovery)
    equal(engine.state:windowCount(context), 1)
    assert(not repository.windows[1].focused)
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[1].lastFrame.w, 980)
  end,

  ["active reconciliation uses one ID snapshot without per-window lookups when nothing changed"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    local snapshots, lookups = 0, 0
    repository.focusedId = 1
    repository.onscreenWindowIds = function()
      snapshots = snapshots + 1
      return { [1] = true, [2] = true }
    end
    repository.windowForId = function()
      lookups = lookups + 1
      error("unchanged reconciliation must not resolve Accessibility windows")
    end

    assert(not engine:reconcileActiveWorkspace())
    equal(snapshots, 1)
    equal(lookups, 0)
  end,

  ["engine exposes fallback recovery after an initial focus request"] = function()
    local engine, repository = build({ 1, 2 })
    repository.focusedId = nil
    repository.windows[2] = nil
    local handled, recovery = engine:windowDestroyed(2)
    assert(handled and recovery)
    repository.focusedId = 1
    assert(not engine:focusRecovery(recovery))
  end,

  ["inactive recovery does not reflow or prune its workspace scope"] = function()
    local engine, repository = build({ 1, 2 })
    local inactive = { screenId = "screen-b", spaceId = "space-b" }
    repository.windows[99] = fakeWindow(99)
    engine.state:addWindow(inactive, 99)
    engine.state:addWindow(inactive, 100)
    local scope = engine.state:scope(inactive)
    assert(engine.state:contains(inactive, 100))
    assert(not repository.windows[99].lastFrame)

    assert(engine:windowDestroyed(99))
    assert(engine.state:contains(inactive, 100))
    assert(not repository.windows[99].lastFrame)
    assert(scope.columns[1].windows[1] == 100)
  end,

  ["closing preserves an actually focused live window despite a stale hint"] = function()
    local engine, repository = build({ 1, 2, 3 })
    repository.focusedId = 3
    assert(engine:windowFocused(repository.windows[3]))
    repository.focusedId = 1
    repository.windows[1].focused = true
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    assert(repository.windows[1].focused)
    assert(not repository.windows[3].focused)
  end,

  ["closing preserves a focused modal-like window outside history"] = function()
    local engine, repository = build({ 1, 2, 3 })
    repository.isFocusHistoryWindow = function(_, window)
      return window and window:id() ~= 1
    end
    repository.focusedId = 3
    assert(engine:windowFocused(repository.windows[3]))
    repository.focusedId = 1
    repository.windows[1].focused = true
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    assert(repository.windows[1].focused)
    assert(not repository.windows[3].focused)
  end,

  ["closing never focuses a fallback in an inactive workspace"] = function()
    local engine, repository = build({ 1, 2 })
    repository.currentContext = function()
      return { screenId = "screen-a", spaceId = "space-b" }
    end
    repository.focusedId = nil
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    assert(not repository.windows[1].focused)
  end,

  ["closing skips stale history and falls back after reflow pruning"] = function()
    local engine, repository = build({ 1, 2, 3 })
    repository.focusedId = 2
    assert(engine:windowFocused(repository.windows[2]))
    repository.focusedId = 3
    assert(engine:windowFocused(repository.windows[3]))
    -- Window 2 has already vanished but its destroy event has not arrived.
    repository.windows[2] = nil
    repository.windows[3] = nil
    assert(engine:windowDestroyed(3))
    assert(repository.windows[1].focused)
  end,

  ["engine expands the remaining column after its peer closes"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    repository.windows[2] = nil
    assert(engine:windowDestroyed(2))
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[1].lastFrame.w, 980)
  end,

  ["minimizing the focused window focuses and expands its remaining peer"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    -- A minimized window is no longer layout-eligible, but it is not destroyed.
    repository.windows[1] = nil
    assert(engine:windowMinimized(1))

    assert(repository.windows[2].focused)
    equal(repository.windows[2].lastFrame.x, 10)
    equal(repository.windows[2].lastFrame.w, 980)
    assert(engine.focusHistory:previous(nil).id == 1)
  end,

  ["restoring a minimized window restores the two-column layout"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    repository.windows[1] = nil
    assert(engine:windowMinimized(1))
    repository.windows[1] = fakeWindow(1)

    assert(engine:windowUnminimized(repository.windows[1]))
    equal(repository.windows[2].lastFrame.x, 10)
    equal(repository.windows[2].lastFrame.w, 480)
    equal(repository.windows[1].lastFrame.x, 510)
    equal(repository.windows[1].lastFrame.w, 480)
  end,

  ["a new window restores the empty column beside a sole stack"] = function()
    local engine, repository = build({ 1 }, { initialLayout = "columns" })
    repository.windows[2] = fakeWindow(2)
    assert(engine:windowCreated(repository.windows[2]))
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[1].lastFrame.w, 480)
    equal(repository.windows[2].lastFrame.x, 510)
    equal(repository.windows[2].lastFrame.w, 480)
  end,

  ["a later new window joins the focused column stack"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    assert(engine:windowFocused(repository.windows[2]))
    repository.windows[3] = fakeWindow(3)
    assert(engine:windowCreated(repository.windows[3]))

    local scope = engine.state:scope(context)
    equal(#scope.columns[1].windows, 1)
    equal(#scope.columns[2].windows, 2)
    equal(scope.columns[2].windows[2], 3)
  end,

  ["focusing the remaining window prunes a peer closed before its destroy event"] = function()
    local engine, repository = build({ 1, 2 }, { initialLayout = "columns" })
    repository.windows[2] = nil
    repository.focusedId = 1
    assert(engine:windowFocused(repository.windows[1]))
    equal(repository.windows[1].lastFrame.x, 10)
    equal(repository.windows[1].lastFrame.w, 980)
  end,

  ["recovery works when no application window is focused"] = function()
    local engine, repository = build({ 1, 2 })
    repository.focusedId = nil
    assert(engine:recover())
  end,

  ["engine switches through the mapped desktop workspace service"] = function()
    local engine, repository = build({ 1 })
    local switchedTo
    repository.screenForContext = function() return { id = "screen-a" } end
    engine.workspaces = workspaceWith({
      isAvailable = function() return true end,
      isDesktopSpace = function() return true end,
      neighboringDesktop = function(_, _, direction)
        assert(direction == 1)
        return { id = "desktop-2", index = 2 }
      end,
      setPendingDesktop = function() end,
      clearPendingDesktop = function() end,
      gotoDesktop = function(_, id) switchedTo = id return true end,
    })
    assert(engine:focusWorkspace(1))
    equal(switchedTo, "desktop-2")
  end,

  ["engine returns to the previously focused desktop instead of an adjacent one"] = function()
    local engine, repository = build({ 1 })
    local selected
    repository.screenForContext = function() return { id = "screen-a" } end
    engine.workspaces = workspaceWith({
      isAvailable = function() return true end,
      isDesktopSpace = function() return true end,
      previouslyFocusedDesktop = function() return { id = "desktop-3", index = 3 } end,
      setPendingDesktop = function() end,
      clearPendingDesktop = function() end,
      gotoDesktop = function(_, id) selected = id return true end,
    })
    assert(engine:focusPreviouslyFocusedWorkspace())
    equal(selected, "desktop-3")
  end,

  ["workspace selector waits for a number and exits after selection"] = function()
    local engine = build({ 1 })
    local modal = { bindings = {} }
    function modal:bind(_, key, callback) self.bindings[key] = callback end
    function modal:enter() self.entered = true end
    function modal:exit() self.exited = true end
    local hs = { hotkey = { modal = { new = function() return modal end } } }
    local selected
    engine.focusOrCreateWorkspaceNumber = function(_, index) selected = index return true end

    assert(engine:chooseWorkspace(hs))
    assert(modal.entered)
    assert(type(modal.bindings.escape) == "function")
    modal.bindings["2"]()
    equal(selected, 2)
    assert(modal.exited)
    assert(engine.workspaceSelectionModal == nil)
  end,

  ["engine creates a missing desktop with the requested label"] = function()
    local engine, repository = build({ 1 })
    local requestedLabel, selected
    repository.screenForContext = function() return { id = "screen-a" } end
    engine.workspaces = workspaceWith({
      isAvailable = function() return true end,
      isDesktopSpace = function() return true end,
      desktopAt = function() return nil end,
      canCreateDesktop = function() return true end,
      addDesktop = function(_, _, label)
        requestedLabel = label
        return true, { id = "desktop-7", index = 7 }
      end,
      setPendingDesktop = function() end,
      clearPendingDesktop = function() end,
      gotoDesktop = function(_, id) selected = id return true end,
    })
    assert(engine:focusOrCreateWorkspaceNumber(7))
    equal(requestedLabel, 7)
    equal(selected, "desktop-7")
  end,

  ["engine creates and enters a new desktop workspace"] = function()
    local engine, repository = build({ 1 })
    local addedOn, selected
    repository.screenForContext = function() return { id = "screen-a" } end
    engine.workspaces = workspaceWith({
      isAvailable = function() return true end,
      isDesktopSpace = function() return true end,
      canCreateDesktop = function() return true end,
      addDesktop = function(_, screen)
        addedOn = screen
        return true, { id = "desktop-2", index = 2 }
      end,
      setPendingDesktop = function() end,
      clearPendingDesktop = function() end,
      gotoDesktop = function(_, id) selected = id return true end,
    })
    assert(engine:newWorkspace())
    equal(addedOn.id, "screen-a")
    equal(selected, "desktop-2")
  end,

  ["desktop deletion restores destination focus after reflow"] = function()
    local engine, observations = deletionFixture()

    assert(engine:deleteWorkspace())
    equal(observations.queued.source.id, "desktop-2")
    equal(observations.queued.destination.id, "desktop-1")
    equal(observations.selected, "desktop-1")

    observations.enterDestination()
    assert(engine:workspaceChanged())
    equal(observations.events[1], "reflow")
    equal(observations.events[2], "focus:42")
    assert(engine.pendingWorkspaceRemovalFocus["screen-a"] == nil)
  end,

  ["failed desktop removal does not restore destination focus"] = function()
    local engine, observations = deletionFixture({ removalFails = true })

    assert(engine:deleteWorkspace())
    observations.enterDestination()
    assert(engine:workspaceChanged())
    equal(observations.events[1], "reflow")
    assert(observations.events[2] == nil)
    assert(engine.pendingWorkspaceRemovalFocus["screen-a"] == nil)
  end,

  ["failed desktop switch clears pending focus restoration"] = function()
    local engine, observations = deletionFixture({ switchFails = true })

    assert(not engine:deleteWorkspace())
    equal(observations.selected, "desktop-1")
    assert(#observations.events == 0)
    assert(engine.pendingWorkspaceRemovalFocus["screen-a"] == nil)
  end,

  ["engine refuses to delete a desktop that contains a hidden workspace window"] = function()
    local engine, repository = build({ 1 })
    local queued = false
    -- This window is absent from the normal eligible list but remains part of
    -- the workspace, as minimized or hidden windows do in WindowRepository.
    repository.eligibleWindows = function() return {} end
    repository.screenForContext = function() return { id = "screen-a" } end
    engine.workspaces = workspaceWith({
      isAvailable = function() return true end,
      isDesktopSpace = function() return true end,
      canRemoveDesktop = function() return true end,
      activeDesktop = function() return { id = "desktop-1", index = 1 } end,
      previouslyFocusedDesktop = function() return { id = "desktop-2", index = 2 } end,
      queueDesktopRemoval = function() queued = true return true end,
    })
    assert(not engine:deleteWorkspace())
    assert(not queued)
  end,

  ["engine never reflows a fullscreen scratchpad scope"] = function()
    local engine = build({ 1 })
    engine.workspaces = workspaceWith({
      isAvailable = function() return true end,
      isDesktopSpace = function(_, spaceId) return spaceId ~= "scratchpad" end,
    })
    assert(not engine:reflow({ screenId = "screen-a", spaceId = "scratchpad" }))
  end,
}
