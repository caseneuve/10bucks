-- Searchable all-window picker backed by hs.chooser. It intentionally uses
-- the repository's live-window enumeration rather than the managed-window
-- filter: the picker is a way to reach every currently live app window.
local WindowChooser = {}
WindowChooser.__index = WindowChooser

local function attempt(object, method, fallback)
  if not object or type(object[method]) ~= "function" then return fallback end
  local ok, value = pcall(object[method], object)
  return ok and value or fallback
end

local function appIcon(hs, bundleId)
  if hs and hs.image and type(hs.image.imageFromAppBundle) == "function" and bundleId then
    local ok, icon = pcall(hs.image.imageFromAppBundle, bundleId)
    if ok and icon then return icon end
  end
  return nil
end

local function choiceFor(hs, window)
  local application = attempt(window, "application", nil)
  local title = attempt(window, "title", "")
  if not title or title == "" then title = "Untitled window" end
  local bundleId = attempt(application, "bundleID", nil)
  local applicationName = attempt(application, "name", nil) or bundleId or "Unknown application"
  local pid = attempt(application, "pid", nil)
  local details = { applicationName }
  if bundleId and bundleId ~= applicationName then table.insert(details, bundleId) end
  if pid then table.insert(details, "pid " .. tostring(pid)) end
  local choice = {
    text = title,
    -- hs.chooser fuzzy-searches this field when searchSubText is enabled.
    -- It gives direct lookup by owning GUI process name, bundle identifier,
    -- and PID in addition to the window title.
    subText = table.concat(details, " · "),
    windowId = attempt(window, "id", nil),
  }
  local icon = appIcon(hs, bundleId)
  if icon then choice.image = icon end
  return choice
end

function WindowChooser.new(hs, repository, selectWindow)
  return setmetatable({ hs = hs, repository = repository, selectWindow = selectWindow }, WindowChooser)
end

function WindowChooser:hide()
  if self.chooser and type(self.chooser.hide) == "function" then self.chooser:hide() end
  self.chooser = nil
  return self
end

function WindowChooser:show()
  if not self.hs or not self.hs.chooser or type(self.hs.chooser.new) ~= "function" then
    return false, "Window chooser is unavailable"
  end

  self.windows = {}
  local choices = {}
  for _, window in ipairs(self.repository:allLiveWindows()) do
    local choice = choiceFor(self.hs, window)
    if choice.windowId then
      self.windows[choice.windowId] = window
      table.insert(choices, choice)
    end
  end
  table.sort(choices, function(left, right)
    local leftName = string.lower(left.subText .. "\0" .. left.text)
    local rightName = string.lower(right.subText .. "\0" .. right.text)
    return leftName < rightName
  end)

  self.chooser = self.hs.chooser.new(function(choice)
    if not choice then return end -- Escape/cancel.
    local window = self.windows[choice.windowId]
    if window then self.selectWindow(window) end
  end)
  -- hs.chooser's matcher is fuzzy by default. Explicitly search subText too,
  -- so both the title (text) and owning application are searchable.
  if type(self.chooser.searchSubText) == "function" then self.chooser:searchSubText(true) end
  self.chooser:choices(choices)
  self.chooser:show()
  return true
end

return WindowChooser
