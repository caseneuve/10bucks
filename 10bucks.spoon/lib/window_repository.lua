local WindowRepository = {}
WindowRepository.__index = WindowRepository

local FOCUS_SPACE_RETRY_DELAY = 0.05
local FOCUS_SPACE_SETTLE_DELAY = 0.15
local MAX_FOCUS_SPACE_RETRIES = 40
local MISSION_CONTROL_RETRY_DELAY = 0.025
local MAX_MISSION_CONTROL_RETRIES = 120

local function attempt(object, method, fallback)
  if not object or type(object[method]) ~= "function" then return fallback end
  local ok, value = pcall(object[method], object)
  return ok and value or fallback
end

local function axAttribute(element, name)
  if not element then return nil end
  local directOk, direct = pcall(function() return element[name] end)
  if directOk and direct ~= nil then return direct end
  if type(element.attributeValue) ~= "function" then return nil end
  local ok, value = pcall(element.attributeValue, element, name)
  return ok and value or nil
end

local function axChild(element, identifier, displayId)
  for _, child in ipairs(axAttribute(element, "AXChildren") or {}) do
    if axAttribute(child, "AXIdentifier") == identifier
      and (displayId == nil or axAttribute(child, "AXDisplayID") == displayId) then
      return child
    end
  end
  return nil
end

local function matchesAny(text, patterns)
  for _, pattern in ipairs(patterns) do
    if text:match(pattern) then return true end
  end
  return false
end

-- Some applications expose modal or fixed-size dialogs as AXStandardWindow.
-- Accessibility capabilities identify them without app-specific or geometric heuristics.
local function isTransientStandardWindow(hs, window)
  if not hs.axuielement or type(hs.axuielement.windowElement) ~= "function" then return false end
  local elementOk, element = pcall(hs.axuielement.windowElement, window)
  if not elementOk or not element then return false end

  if type(element.attributeValue) == "function" then
    local modalOk, modal = pcall(element.attributeValue, element, "AXModal")
    if modalOk and modal == true then return true end
  end

  if type(element.isAttributeSettable) == "function" then
    local sizeOk, sizeSettable = pcall(element.isAttributeSettable, element, "AXSize")
    if sizeOk and sizeSettable == false then return true end
  end
  return false
end

function WindowRepository.new(hs, config)
  assert(hs and hs.window and hs.window.filter and type(hs.window.filter.new) == "function" and hs.screen,
    "10bucks requires hs.window.filter and hs.screen")
  return setmetatable({ hs = hs, config = config, screens = {} }, WindowRepository)
end

function WindowRepository:screenId(screen)
  return tostring(screen:getUUID())
end

function WindowRepository:spaceId(screen)
  if not self.hs.spaces or type(self.hs.spaces.activeSpaceOnScreen) ~= "function" then
    return "current"
  end
  local ok, space = pcall(self.hs.spaces.activeSpaceOnScreen, screen)
  return ok and (space or "current") or "current"
end

function WindowRepository:contextForScreen(screen)
  if not screen then return nil end
  local screenId = self:screenId(screen)
  self.screens[screenId] = screen
  return { screenId = screenId, spaceId = self:spaceId(screen) }
end

function WindowRepository:contextForWindow(window)
  return self:contextForScreen(attempt(window, "screen", nil))
end

function WindowRepository:currentContext()
  local focused = self:focusedWindow()
  return self:contextForWindow(focused)
    or self:contextForScreen(self.hs.screen.mainScreen() or self.hs.screen.primaryScreen())
end

function WindowRepository:screenForContext(context)
  if not context then return nil end
  local screen = self.screens[context.screenId] or self.hs.screen.find(context.screenId)
  if screen then self.screens[context.screenId] = screen end
  return screen
end

function WindowRepository:screenFrame(context)
  return attempt(self:screenForContext(context), "frame", nil)
end

function WindowRepository:activeContexts()
  local contexts = {}
  for _, screen in ipairs(self.hs.screen.allScreens()) do
    local context = self:contextForScreen(screen)
    if context then table.insert(contexts, context) end
  end
  return contexts
end

function WindowRepository:isExcludedByConfiguration(window)
  local application = attempt(window, "application", nil)
  local bundleId = attempt(application, "bundleID", nil)
  for _, excluded in ipairs(self.config.excludedBundleIDs) do
    if excluded == bundleId then return true end
  end
  return matchesAny(attempt(window, "title", "") or "", self.config.excludedWindowTitles)
end

function WindowRepository:isWorkspaceWindow(window)
  if not window or not attempt(window, "id", nil) or attempt(window, "isFullScreen", false) then
    return false
  end
  if self:isExcludedByConfiguration(window) then return false end

  -- AXStandardWindow excludes sheets, utility palettes, menu-bar items, and most transient UI.
  local isStandardWindow = attempt(window, "role", nil) == "AXWindow"
    and attempt(window, "subrole", nil) == "AXStandardWindow"
  if not isStandardWindow or isTransientStandardWindow(self.hs, window) then return false end

  return not self.config.windowFilter or self.config.windowFilter(window) ~= false
end

function WindowRepository:isEligible(window)
  return self:isWorkspaceWindow(window) and attempt(window, "isVisible", false)
end

-- Fullscreen rules are evaluated independently of normal window eligibility.
-- Callers decide when a matching window should be requested to enter native
-- fullscreen; this repository only provides the matching and safe primitives.
function WindowRepository:shouldSpawnFullscreen(window)
  if not window then return false end
  local rules = self.config and self.config.fullscreenRules
  if type(rules) ~= "table" then return false end

  for _, rule in ipairs(rules) do
    if type(rule) == "table" then
      local application
      local applicationQueried = false
      local function getApplication()
        if not applicationQueried then
          application = attempt(window, "application", nil)
          applicationQueried = true
        end
        return application
      end

      local hasSelector = false
      local matches = true
      if rule.bundleID ~= nil then
        hasSelector = true
        local bundleID = attempt(getApplication(), "bundleID", nil)
        matches = bundleID ~= nil and bundleID == rule.bundleID
      end
      if matches and rule.applicationName ~= nil then
        hasSelector = true
        local applicationName = attempt(getApplication(), "name", nil)
        matches = applicationName ~= nil and applicationName:match(rule.applicationName) ~= nil
      end
      if matches and rule.windowTitle ~= nil then
        hasSelector = true
        local title = attempt(window, "title", nil)
        matches = title ~= nil and title:match(rule.windowTitle) ~= nil
      end
      -- Predicates may be expensive or have side effects, so only invoke them
      -- after every declarative selector in the rule has matched.
      if matches and rule.predicate ~= nil then
        hasSelector = true
        matches = rule.predicate(window) and true or false
      end
      if hasSelector and matches then return true end
    end
  end
  return false
end

-- This only confirms that Hammerspoon accepted the request. Native fullscreen
-- transitions are asynchronous, so it deliberately does not imply completion.
function WindowRepository:requestFullscreen(window)
  if not window then return false end
  local methodAvailable, setFullScreen = pcall(function() return window.setFullScreen end)
  if not methodAvailable or type(setFullScreen) ~= "function" then return false end
  local issued = pcall(setFullScreen, window, true)
  return issued
end

function WindowRepository:isFullscreen(window)
  if not window then return false end
  local methodAvailable, isFullScreen = pcall(function() return window.isFullScreen end)
  if not methodAvailable or type(isFullScreen) ~= "function" then return false end
  local queried, fullscreen = pcall(isFullScreen, window)
  return queried and fullscreen == true
end

function WindowRepository:eligibleWindows()
  local windows = self.hs.window.visibleWindows()
  local eligible = {}
  for _, window in ipairs(windows) do
    if self:isEligible(window) then table.insert(eligible, window) end
  end
  return eligible
end

-- Return a cheap snapshot of window IDs currently composited onscreen. The
-- native ID list avoids hs.window.get(), which performs an Accessibility search
-- and is too expensive for the missed-destroy-event reconciliation timer.
function WindowRepository:onscreenWindowIds()
  local orderedIds = self.hs.window._orderedwinids
  if type(orderedIds) == "function" then
    local ok, values = pcall(orderedIds)
    if ok and type(values) == "table" then
      local ids = {}
      for _, id in ipairs(values) do ids[id] = true end
      return ids
    end
  end

  -- Compatibility fallback for Hammerspoon builds without the native helper.
  local ids = {}
  for _, window in ipairs(self.hs.window.visibleWindows()) do
    local id = attempt(window, "id", nil)
    if id then ids[id] = true end
  end
  return ids
end

-- The chooser should see standard application windows in every native Space,
-- not merely the visible 10bucks scope. hs.window.allWindows() includes many
-- AX helper surfaces (such as app sidebars); use a dedicated window filter to
-- retain its cross-Space tracking while excluding those ghost windows.
-- Focus history shares the chooser's intentionally broad standard-window
-- policy: it includes unmanaged/floating windows and can cross native Spaces.
function WindowRepository:isFocusHistoryWindow(window)
  return self:isPickerWindow(window)
end

function WindowRepository:isPickerWindow(window)
  if not window or not attempt(window, "id", nil) then return false end
  if self:isExcludedByConfiguration(window) or not attempt(window, "isStandard", false) then return false end
  return not isTransientStandardWindow(self.hs, window)
end

function WindowRepository:allLiveWindows()
  if not self.pickerFilter then
    self.pickerFilter = self.hs.window.filter.new(function(window) return self:isPickerWindow(window) end)
  end
  return self.pickerFilter:getWindows()
end

-- Deletion must be stricter than normal layout eligibility: an ordinary
-- minimized or hidden window still means the desktop is not empty.
function WindowRepository:workspaceWindows()
  local windows = self.hs.window.allWindows()
  local workspaceWindows = {}
  for _, window in ipairs(windows) do
    if self:isWorkspaceWindow(window) then table.insert(workspaceWindows, window) end
  end
  return workspaceWindows
end

function WindowRepository:focusedWindow()
  return self.hs.window.focusedWindow()
end

function WindowRepository:windowForId(id)
  local window = self.hs.window.get(id)
  return self:isEligible(window) and window or nil
end

-- Unlike windowForId(), do not require current-Space visibility or 10bucks
-- layout eligibility. hs.window:focus() performs the native Space transition.
function WindowRepository:historyWindowForId(id)
  -- hs.window.get() is not reliable for a window outside the active Space on
  -- every Hammerspoon/macOS combination. The all-live filter deliberately
  -- tracks standard windows across Spaces, so prefer its object reference.
  for _, window in ipairs(self:allLiveWindows()) do
    if attempt(window, "id", nil) == id then return window end
  end
  local window = self.hs.window.get(id)
  return self:isFocusHistoryWindow(window) and window or nil
end

function WindowRepository:setFrame(window, frame, duration)
  window:setFrame(frame, duration)
end

function WindowRepository:cancelPendingFocus()
  self.focusGeneration = (self.focusGeneration or 0) + 1
  if self.focusTimer and type(self.focusTimer.stop) == "function" then self.focusTimer:stop() end
  self.focusTimer = nil
  if self.focusMissionControlOpen then
    local toggle = self.hs.spaces and self.hs.spaces.toggleMissionControl
    if type(toggle) == "function" then pcall(toggle) end
    self.focusMissionControlOpen = nil
  end
end

function WindowRepository:activeSpaceForWindow(window)
  local spaces = self.hs.spaces
  if not spaces then return nil end
  local screen = attempt(window, "screen", nil)
  if screen and type(spaces.activeSpaceOnScreen) == "function" then
    local ok, active = pcall(spaces.activeSpaceOnScreen, screen)
    if ok then return active end
  end
  if type(spaces.focusedSpace) == "function" then
    local ok, active = pcall(spaces.focusedSpace)
    if ok then return active end
  end
  return nil
end

function WindowRepository:missionControlSpacesList(dockElement, screen)
  local missionControl = axChild(dockElement, "mc")
  local display = axChild(missionControl, "mc.display", attempt(screen, "id", nil))
  local spacesGroup = axChild(display, "mc.spaces")
  return axChild(spacesGroup, "mc.spaces.list")
end

-- Perform the same Mission Control AXPress as hs.spaces.gotoSpace(), but poll
-- with timers for up to three seconds instead of blocking Hammerspoon's main
-- thread. Retain Hammerspoon's stabilization delay before pressing the Space.
function WindowRepository:startAsyncSpaceSwitch(window, destination, generation, switched)
  local hs = self.hs
  local spaces = hs.spaces
  local timer = hs.timer
  local screen = attempt(window, "screen", nil)
  if not screen or not spaces or type(spaces.toggleMissionControl) ~= "function"
    or type(spaces.spacesForScreen) ~= "function" or not timer
    or type(timer.doAfter) ~= "function" or not hs.application or not hs.axuielement
    or type(hs.application.applicationsForBundleID) ~= "function"
    or type(hs.axuielement.applicationElement) ~= "function" then return false end

  local orderOk, orderedSpaces = pcall(spaces.spacesForScreen, screen)
  if not orderOk or type(orderedSpaces) ~= "table" then return false end
  local targetIndex
  for index, spaceId in ipairs(orderedSpaces) do
    if spaceId == destination then targetIndex = index break end
  end
  if not targetIndex then return false end

  local appsOk, dockApps = pcall(hs.application.applicationsForBundleID, "com.apple.dock")
  local dock = appsOk and type(dockApps) == "table" and dockApps[1]
  if not dock then return false end
  local elementOk, dockElement = pcall(hs.axuielement.applicationElement, dock)
  if not elementOk or not dockElement then return false end

  -- Chooser selection starts from the normal desktop UI. Calling
  -- openMissionControl() would first synchronously scan Dock's AX tree and can
  -- block for seconds after Space creation/removal; the core toggle is instant.
  if not pcall(spaces.toggleMissionControl) then return false end
  self.focusMissionControlOpen = true

  local attempts = 0
  local stabilized = false
  local function pollMissionControl()
    if generation ~= self.focusGeneration then return end
    attempts = attempts + 1
    local spacesList = self:missionControlSpacesList(dockElement, screen)
    if spacesList and not stabilized then
      stabilized = true
      local delay = type(spaces.MCwaitTime) == "number" and spaces.MCwaitTime or 0.3
      self.focusTimer = timer.doAfter(delay, pollMissionControl)
      return
    end

    if spacesList and stabilized then
      local button = (axAttribute(spacesList, "AXChildren") or {})[targetIndex]
      if button and type(button.performAction) == "function" then
        local actionOk, pressed = pcall(button.performAction, button, "AXPress")
        if actionOk and pressed then
          self.focusMissionControlOpen = nil -- AXPress closes Mission Control.
          self.focusTimer = nil
          switched()
          return
        end
      end
    end

    if attempts >= MAX_MISSION_CONTROL_RETRIES then
      if type(spaces.toggleMissionControl) == "function" then pcall(spaces.toggleMissionControl) end
      self.focusMissionControlOpen = nil
      self.focusTimer = nil
      if type(hs.printf) == "function" then hs.printf("10bucks: timed out switching Spaces") end
      return
    end
    self.focusTimer = timer.doAfter(MISSION_CONTROL_RETRY_DELAY, pollMissionControl)
  end
  self.focusTimer = timer.doAfter(MISSION_CONTROL_RETRY_DELAY, pollMissionControl)
  return true
end

function WindowRepository:focus(window)
  if not window or type(window.focus) ~= "function" then return false end
  self:cancelPendingFocus()

  local spaces = self.hs.spaces
  local timer = self.hs.timer
  if not spaces or type(spaces.windowSpaces) ~= "function"
    or not timer or type(timer.doAfter) ~= "function" then
    window:focus()
    return true
  end

  local spacesOk, targetSpaces = pcall(spaces.windowSpaces, window)
  local destination = spacesOk and type(targetSpaces) == "table" and targetSpaces[1]
  local activeSpace = self:activeSpaceForWindow(window)
  if type(targetSpaces) == "table" then
    for _, targetSpace in ipairs(targetSpaces) do
      if targetSpace == activeSpace then
        window:focus()
        return true
      end
    end
  end
  if not destination then
    window:focus()
    return true
  end

  -- A cross-Space target is never focused until its Space is confirmed active
  -- and remains active through a short settle period. There is deliberately no
  -- direct-focus fallback: that is the path Contexts can steal and reverse.
  local generation = self.focusGeneration
  local function waitForDestination()
    local attempts = 0
    local function pollDestination()
      if generation ~= self.focusGeneration then return end
      attempts = attempts + 1
      if self:activeSpaceForWindow(window) == destination then
        self.focusTimer = timer.doAfter(FOCUS_SPACE_SETTLE_DELAY, function()
          if generation ~= self.focusGeneration then return end
          self.focusTimer = nil
          if self:activeSpaceForWindow(window) == destination then window:focus() end
        end)
        return
      end
      if attempts >= MAX_FOCUS_SPACE_RETRIES then
        self.focusTimer = nil
        if type(self.hs.printf) == "function" then self.hs.printf("10bucks: destination Space did not activate") end
        return
      end
      self.focusTimer = timer.doAfter(FOCUS_SPACE_RETRY_DELAY, pollDestination)
    end
    self.focusTimer = timer.doAfter(FOCUS_SPACE_RETRY_DELAY, pollDestination)
  end

  if not self:startAsyncSpaceSwitch(window, destination, generation, waitForDestination)
    and type(self.hs.printf) == "function" then
    self.hs.printf("10bucks: asynchronous Space switching is unavailable")
  end
  return true
end

function WindowRepository:stop()
  self:cancelPendingFocus()
  if self.pickerFilter and type(self.pickerFilter.delete) == "function" then self.pickerFilter:delete() end
  self.pickerFilter = nil
  return self
end

return WindowRepository
