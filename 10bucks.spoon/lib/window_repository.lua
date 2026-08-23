local WindowRepository = {}
WindowRepository.__index = WindowRepository

local function attempt(object, method, fallback)
  if not object or type(object[method]) ~= "function" then return fallback end
  local ok, value = pcall(object[method], object)
  return ok and value or fallback
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

function WindowRepository:eligibleWindows()
  local windows = self.hs.window.visibleWindows()
  local eligible = {}
  for _, window in ipairs(windows) do
    if self:isEligible(window) then table.insert(eligible, window) end
  end
  return eligible
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

function WindowRepository:focus(window)
  window:focus()
end

function WindowRepository:stop()
  if self.pickerFilter and type(self.pickerFilter.delete) == "function" then self.pickerFilter:delete() end
  self.pickerFilter = nil
  return self
end

return WindowRepository
